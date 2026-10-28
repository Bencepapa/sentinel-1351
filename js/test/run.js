// Headless checks for the JS runtime (node js/test/run.js [outdir]).
//
// 1. flight: runs with the 1351 moving, ports in verify mode
// 2. map: runs the grid sweep and icons, compares the grid cells of the
//    bitmap with the original game's bitmap (c128-map/ref/map-bitmap-6000.bin),
//    exercises the cursor, the fast ticks and the second display
// Writes PNG snapshots of both screens to outdir.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const zlib = require('zlib');

const ROOT = path.join(__dirname, '..');
global.CPU6502 = require(path.join(ROOT, 'src/cpu6502.js'));
global.SentinelFont = require(path.join(ROOT, 'src/font.js'));
const C128 = require(path.join(ROOT, 'src/machine.js'));
const Video = require(path.join(ROOT, 'src/video.js'));
const Hooks = require(path.join(ROOT, 'src/hooks.js'));
const Native = require(path.join(ROOT, 'src/native.js'));
const ctx = {};
vm.runInNewContext(fs.readFileSync(path.join(ROOT, 'programs.js'), 'utf8'), ctx);
const PROGRAMS = ctx.SENTINEL_PROGRAMS;
const OUT = process.argv[2] || path.join(__dirname, 'out');
fs.mkdirSync(OUT, { recursive: true });

let failures = 0;
function check(cond, msg) { console.log((cond ? 'ok   ' : 'FAIL ') + msg); if (!cond) failures++; }

function boot(name, mode) {
  const p = PROGRAMS[name];
  const m = new C128();
  m.loadPrg(new Uint8Array(Buffer.from(p.prg, 'base64')));
  const hooks = new Hooks(m, p.symbols);
  const ported = Native.install(hooks, mode);
  m.start(p.entry);
  return { m, hooks, ported, p };
}

function run(m, hooks, frames, each) {
  for (let i = 0; i < frames; i++) {
    if (each) each(i);
    if (!m.runFrame()) return false;
    hooks.endFrame();
  }
  return true;
}

function png(file, w, h, px) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    for (let x = 0; x < w; x++) {
      const c = px[y * w + x], o = y * (w * 4 + 1) + 1 + x * 4;
      raw[o] = c & 255; raw[o + 1] = (c >> 8) & 255; raw[o + 2] = (c >> 16) & 255; raw[o + 3] = 255;
    }
  }
  const crcT = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; crcT[n] = c >>> 0; }
  const crc = b => { let c = 0xFFFFFFFF; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; };
  const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
}

function snap(m, name) {
  const vic = new Uint32Array(Video.VIC_W * Video.VIC_H);
  Video.renderVic(m, vic);
  png(path.join(OUT, name + '-vic.png'), Video.VIC_W, Video.VIC_H, vic);
  const vdc = new Uint32Array(Video.VDC_W * Video.VDC_H);
  Video.renderVdc(m, vdc, true);
  png(path.join(OUT, name + '-vdc.png'), Video.VDC_W, Video.VDC_H, vdc);
}

function report(hooks, label) {
  for (const a in hooks.handlers) {
    const h = hooks.handlers[a];
    if (h.fn) check(h.failed === 0 && h.verified > 0, `${label}: ${h.name} verified ${h.verified} calls, ${h.failed} mismatches`);
  }
  hooks.mismatches.slice(0, 3).forEach(r => console.log('     ', r.name, 'frame', r.frame, r.diffs.join('; ')));
}

// ---- flight ----------------------------------------------------------------
{
  const { m, hooks } = boot('flight', 'verify');
  const alive = run(m, hooks, 300, i => { if (i > 30) m.moveMouse(i % 60 < 30 ? 3 : -3, i % 80 < 40 ? 2 : -2); });
  check(alive, 'flight runs 300 frames' + (m.stopped ? ' (' + m.stopped + ')' : ''));
  check(m.vic[0x11] === 0x3B && (m.vic[0x16] & 0x10), 'flight: multicolor bitmap mode set');
  report(hooks, 'flight');
  snap(m, 'flight');
  // both buttons: exit back to BASIC
  m.mouse.left = m.mouse.right = true;
  run(m, hooks, 5);
  check(m.stopped === 'returned to BASIC', 'flight: both buttons return to BASIC');
}

// ---- map -------------------------------------------------------------------
{
  const { m, hooks, p } = boot('map', 'verify');
  run(m, hooks, 400);
  check(!m.stopped, 'map runs 400 frames' + (m.stopped ? ' (' + m.stopped + ')' : ''));
  // grid cells compared with the original game's bitmap
  const ref = fs.readFileSync(path.join(ROOT, '..', 'c128-map', 'ref', 'map-bitmap-6000.bin')).subarray(2);
  let same = 0, diff = 0;
  for (let cy = 4; cy <= 16; cy++) for (let cx = 0; cx < 40; cx++) {
    const o = cy * 320 + cx * 8;
    let notGrid = false;
    for (let i = 0; i < 8; i++) for (let k = 0; k < 8; k += 2) { if (((ref[o + i] >> k) & 3) === 1 || ((ref[o + i] >> k) & 3) === 2 || ((m.ram[0x6000 + o + i] >> k) & 3) === 2) notGrid = true; }
    if (notGrid) continue;
    let eq = true;
    for (let i = 0; i < 8; i++) if (ref[o + i] !== m.ram[0x6000 + o + i]) eq = false;
    if (eq) same++; else { diff++; if (diff <= 12) console.log('      cell', cx, cy, [...ref.subarray(o, o + 8)].map(v => v.toString(16)).join(' '), '|', [...m.ram.subarray(0x6000 + o, 0x6008 + o)].map(v => v.toString(16)).join(' ')); }
  }
  check(diff === 0 && same > 400, `map: ${same} grid cells match the original bitmap, ${diff} differ`);
  snap(m, 'map');
  // cursor: move right with the mouse, fire with the left button
  const s = p.symbols;
  const curx0 = m.ram[s.CURX];
  run(m, hooks, 40, i => { if (i < 10) m.moveMouse(4, 0); });
  run(m, hooks, 6, i => { m.mouse.left = i < 3; });
  check(m.ram[s.CURX] !== curx0, `map: mouse moves the cursor (CURX ${curx0} -> ${m.ram[s.CURX]})`);
  // T held: fast ticks
  const before = Buffer.from(m.ram.subarray(s.STATE, s.STATE + 60));
  m.setKey(2, 6, true);
  run(m, hooks, 2500);
  m.setKey(2, 6, false);
  const moved = Buffer.compare(before, Buffer.from(m.ram.subarray(s.STATE, s.STATE + 60))) !== 0;
  check(moved, 'map: squadrons move with T held');
  report(hooks, 'map');
  snap(m, 'map-later');
  check(m.vic[0x15] & 2, 'map: planet sprite enabled');
  // SPACE exits
  m.setKey(7, 4, true);
  run(m, hooks, 3);
  check(m.stopped === 'returned to BASIC', 'map: SPACE returns to BASIC');
}

// ---- cockpit -------------------------------------------------------------
{
  const { m, hooks, p } = boot('cockpit', 'verify');
  const s = p.symbols;
  run(m, hooks, 60);
  check(!m.stopped, 'cockpit runs' + (m.stopped ? ' (' + m.stopped + ')' : ''));
  check(m.vicLog.length / 4 > 20, `cockpit: ${m.vicLog.length / 4} VIC writes per frame (raster splits logged)`);
  const cx = m.ram[s.CURX], cy = m.ram[s.CURY];
  run(m, hooks, 30, () => m.moveMouse(3, 2));
  check(m.ram[s.CURX] > cx && m.ram[s.CURY] < cy, `cockpit: mouse moves the crosshair (${cx},${cy} -> ${m.ram[s.CURX]},${m.ram[s.CURY]})`);
  run(m, hooks, 10, i => { m.mouse.left = i < 8; });
  snap(m, 'cockpit');
  check(m.ram[s.OVRUN] === 0, 'cockpit: frame work fits in the vertical blank (OVRUN = 0)');
  report(hooks, 'cockpit');
  m.mouse.left = false;
  m.setKey(7, 4, true);
  run(m, hooks, 3);
  check(m.stopped === 'returned to BASIC', 'cockpit: SPACE returns to BASIC');
}

console.log(failures ? failures + ' check(s) failed' : 'all checks passed');
process.exit(failures ? 1 : 0);
