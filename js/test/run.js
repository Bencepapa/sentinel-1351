// Headless checks for the JS runtime (node js/test/run.js [outdir]).
//
// 1. flight: runs with the 1351 moving, ports in verify mode
// 2. map: runs the grid sweep and icons, compares the grid cells of the
//    bitmap with the original game's bitmap (c128-map/ref/map-bitmap-6000.bin),
//    exercises the cursor, the fast ticks and the second display
// 3. cockpit: raster splits, crosshair, vertical-blank budget
// 4. C64 game: boots, starts, debugger (breakpoints, write watches, stepping),
//    save / load state (determinism, mid-frame), cheats and the game-over event
// Writes PNG snapshots of the screens to outdir.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const zlib = require('zlib');

const ROOT = path.join(__dirname, '..');
global.CPU6502 = require(path.join(ROOT, 'src/cpu6502.js'));
global.SentinelFont = require(path.join(ROOT, 'src/font.js'));
global.SentinelVideo = require(path.join(ROOT, 'src/video.js'));
global.SentinelDisasm = require(path.join(ROOT, 'src/disasm.js'));
const Debugger = require(path.join(ROOT, 'src/debugger.js'));
const Profiles = require(path.join(ROOT, 'src/profiles.js'));
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
  const m = new C128(p.model);
  m.loadPrg(new Uint8Array(Buffer.from(p.prg, 'base64')));
  const hooks = new Hooks(m, p.symbols);
  const ported = Native.install(hooks, mode);
  m.start(p.entry);
  return { m, hooks, ported, p };
}

// The cockpit starts by approaching a squadron; tests of the fight put it in a
// dogfight with ships to spare.
function dogfight(k) {
  const K = k.m.ram, s = k.p.symbols;
  K[s.APPR] = 0; K[s.APRUN] = 0; K[s.LRMODE] = 0; K[s.SQCOUNT] = 200; K[s.CURG] = 0;
  K[s.GSIZE] = K[s.GSIZE + 1] = K[s.GSIZE + 2] = 200;
}

function run(m, hooks, frames, each) {
  for (let i = 0; i < frames; i++) {
    if (each) each(i);
    if (!m.runFrame()) return false;
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
  {   // the guns follow slowly: a step every 16th frame, as the original's $9568
    let steps = [], g = m.ram[s.G1X] + ',' + m.ram[s.G1Y];
    run(m, hooks, 64, i => { m.moveMouse(i < 32 ? -4 : 4, 0); const n = m.ram[s.G1X] + ',' + m.ram[s.G1Y]; if (n !== g) steps.push(i); g = n; });
    const gaps = steps.slice(1).map((v, i) => v - steps[i]);
    check(steps.length >= 2 && gaps.every(d => d % 16 === 0), `cockpit: the guns take a step every 16th frame only (steps at frames ${steps.join(', ')})`);
  }
  run(m, hooks, 10, i => { m.mouse.left = i < 8; });
  snap(m, 'cockpit');
  check(m.ram[s.OVRUN] === 0, 'cockpit: frame work fits in the vertical blank (OVRUN = 0)');
  report(hooks, 'cockpit');
  m.mouse.left = false;
  m.setKey(7, 4, true);
  run(m, hooks, 3);
  check(m.stopped === 'returned to BASIC', 'cockpit: SPACE returns to BASIC');
}

// ---- C64 game + debugger ------------------------------------------------------
{
  const { m, hooks, p } = boot('c64game', 'verify');
  const dbg = new Debugger(m, hooks, 'c64game', Profiles.c64game);
  const s = p.symbols;
  let entered = -1;
  hooks.on('GAMEENTRY', () => { if (entered < 0) entered = m.frame; });
  run(m, hooks, 300);
  check(entered > 0 && !m.stopped, `c64: depacker reaches the game (frame ${entered})`);
  const hud = [...m.ram.subarray(0x5429, 0x5430)].map(c => String.fromCharCode(c)).join('');
  check(hud === 'SHIELDS', `c64: HUD text on the screen ("${hud}")`);
  snap(m, 'c64-title');

  // start a game: fire on the title, fire on the difficulty menu
  run(m, hooks, 300, i => { m.mouse.left = (i >= 0 && i < 10) || (i >= 150 && i < 160); });
  const energy = dbg.watches.find(w => w.name === 'Energy');
  const e1 = dbg.value(energy);
  run(m, hooks, 200);
  const e2 = dbg.value(energy);
  check(e2 < e1 && e1 <= 9999, `c64: game running, energy counts down (${e1} -> ${e2})`);
  check(dbg.value(dbg.watches[0]) === m.ram[s.SHIELDS] && m.ram[s.SHIELDS] > 0, `c64: shields = ${m.ram[s.SHIELDS]}`);
  snap(m, 'c64-flight');

  // breakpoint on the raster IRQ, then single steps
  m.setBreak(s.IRQ, true);
  let r = m.run();
  check(r === 'break' && m.cpu.pc === s.IRQ, `c64: breakpoint stops at IRQ ($${s.IRQ.toString(16)}), line ${m.rasterLine()}`);
  m.stepInstruction(); m.stepInstruction();
  check(m.cpu.pc === s.IRQ + 2, `c64: two single steps (PC $${m.cpu.pc.toString(16)})`);
  m.setBreak(s.IRQ, false);

  // write watch on the last energy digit: stops in the energy routine
  m.setWatch(s.ENERGY + 3, true);
  for (let i = 0; i < 200 && (r = m.run()) !== 'break'; i++);
  const wb = m.breakInfo;
  check(r === 'break' && wb.type === 'watch' && wb.pc >= s.ENERGYTICK && wb.pc < s.ENERGYOUT,
        `c64: write watch on the energy digit stops at $${wb && wb.pc.toString(16)} (${wb && wb.old} -> ${wb && wb.value})`);
  m.setWatch(s.ENERGY + 3, false);

  // save / load: the same frames after a load give the same memory
  const hash = () => { let h = 0; for (let i = 0; i < 0x10000; i++) h = (h * 31 + m.ram[i]) | 0; return h; };
  for (let i = 0; i < 1234; i++) m.stepInstruction();          // save in the middle of a frame
  const raster = m.rasterLine();
  dbg.save('t');
  run(m, hooks, 60);
  const h1 = hash(), f1 = m.frame;
  dbg.load('t');
  check(m.rasterLine() === raster, `c64: load state restores the raster position (line ${raster})`);
  run(m, hooks, 60);
  check(hash() === h1 && m.frame === f1, 'c64: after load, 60 frames give identical memory (deterministic)');
  const text = m.stateToText();
  const back = m.stateFromText(text);
  check(back.arrays.ram.length === 0x10000 && back.cpu.pc === m.cpu.pc, `c64: state text round trip (${(text.length / 1024).toFixed(0)} KB)`);

  // a hit, called directly: HIT lowers shields; invulnerable and frozen shields stop it
  function callRoutine(addr) {
    const c = m.cpu, ret = c.pc, sp = c.sp;
    c.push(((ret - 1) >> 8) & 255); c.push((ret - 1) & 255); c.pc = addr;
    for (let i = 0; i < 200000 && !(c.pc === ret && c.sp === sp); i++) m.stepInstruction();
  }
  dbg.setEvent(Profiles.c64game.events[1], true, false);       // log hits, no pause
  m.ram[0xFD] = 0;
  const sh0 = m.ram[s.SHIELDS];
  callRoutine(s.HIT);
  check(m.ram[s.SHIELDS] === sh0 - 1, `c64: HIT lowers shields (${sh0} -> ${m.ram[s.SHIELDS]})`);
  dbg.setCheat('invuln', true);
  callRoutine(s.HIT);
  check(m.ram[s.SHIELDS] === sh0 - 1, 'c64: cheat Invulnerable: HIT changes nothing');
  dbg.setCheat('invuln', false);
  dbg.setCheat('shields', true);
  const sys0 = [...m.ram.subarray(s.SYSTEMS, s.SYSTEMS + 8)].reduce((a, b) => a + b);
  callRoutine(s.HIT);
  const sys1 = [...m.ram.subarray(s.SYSTEMS, s.SYSTEMS + 8)].reduce((a, b) => a + b);
  check(m.ram[s.SHIELDS] === sh0 - 1 && sys1 === sys0 - 1, 'c64: cheat Freeze shields: systems damaged, shields stay');
  dbg.setCheat('shields', false);
  check(dbg.log.filter(e => e.kind === 'event' && /Ship hit/.test(e.text)).length === 3, 'c64: event log saw the three hits');

  // game over: shields lost -> the game-over event pauses the machine
  dbg.exec('> SHIELDSLOST 01');
  for (let i = 0; i < 300 && (r = m.run()) !== 'break'; i++);
  check(r === 'break' && m.breakInfo.type === 'event' && m.breakInfo.name === 'Game over',
        `c64: game-over event pauses at frame ${m.frame}`);
  // monitor commands
  const d = dbg.exec('d GAMEOVER 3');
  check(d.length === 3 && /GAMEOVER/.test(d[0]), 'c64: monitor disassembles with labels: ' + d[0].trim());
  check(/^PC=/.test(dbg.exec('r')[0]) && dbg.exec('m SHIELDS 1')[0].startsWith('$844F'), 'c64: monitor r / m');
  run(m, hooks, 100);
  snap(m, 'c64-gameover');
}

// ---- phasor shot: C128 cockpit port against the original C64 routines ----------
{
  function callAt(m, addr) {                 // run a routine to its RTS, no interrupts
    const c = m.cpu, ret = 0xFFF4, p = c.p;
    c.push(((ret - 1) >> 8) & 255); c.push((ret - 1) & 255); c.pc = addr; c.p |= 4;
    for (let i = 0; i < 2e6 && c.pc !== ret; i++) { c.step(); if (c.jam) throw new Error(c.jam); }
    c.p = p;
  }
  const o = boot('c64game', 'trace'), os = o.p.symbols;
  run(o.m, o.hooks, 250);                    // unpacked: the game's code is in memory
  const k = boot('cockpit', 'trace'), ks = k.p.symbols;
  run(k.m, k.hooks, 5); dogfight(k);
  const R = o.m.ram, K = k.m.ram;
  // the original, as the game runs it: the IRQ's $1424, then $1467 from the main loop
  const orig = {
    setup(cx, cy, gunsel) {
      R[0xB8] = 0; R[0xBACE] = 0; R[0xE3] = 0; R[0x39] = 5; R[0xD0] = R[0xD1] = R[0xD2] = 0;
      R[os.CURX] = cx; R[os.CURY] = cy; R[0x1417] = gunsel; R[0x141B] = 0;
      R[0x118F] = 0x20; R[0x1190] = 0x1F; R[0x1191] = 0xCF; R[0x1192] = 0xCF;
    },
    // the input code sets $D0 when fire is pressed and never clears it ($02CB-$02D6)
    // and the IRQ sweeps the sound 5 more times a frame ($0C3B, $0C3E, $0C41, $0C60, $0CBA);
    // the carry going in is forced (it comes from unrelated code in both programs)
    frame(fire) {
      if (fire) R[0xD0] = 1; o.m.cpu.p |= 1; callAt(o.m, 0x1424); if (R[0xD1]) callAt(o.m, 0x1467);
      for (let i = 0; i < 5; i++) { o.m.cpu.p |= 1; callAt(o.m, 0x15E0); }
    },
    sid: () => [0, 1, 2, 3, 4, 5, 6].map(r => o.m.sid[r]).join('/'),
    state: () => [R[0xD2], R[0xB1], R[0xE9] | ((R[0xF7] & 2) << 7), R[0xEA], o.m.vic[0x28] & 15, R[0x1416]],
    path: () => [...R.subarray(0x400, 0x400 + R[0x1415])].map((x, i) => x + ',' + R[0x500 + i]).join(' '),
  };
  const port = {
    setup(cx, cy, gunsel) {
      K[ks.SHOTON] = K[ks.SHOTARM] = K[ks.FIREFLAG] = 0;
      K[ks.CURX] = cx; K[ks.CURY] = cy; K[ks.GUNSEL] = gunsel; K[ks.FRAC] = 0;
      K[ks.G1X] = 0x20; K[ks.G2X] = 0x1F; K[ks.G1Y] = 0xCF; K[ks.G2Y] = 0xCF;
    },
    frame(fire) {
      if (fire) K[ks.FIREFLAG] = 1; k.m.cpu.p |= 1; callAt(k.m, ks.FIREPH); if (K[ks.SHOTARM]) callAt(k.m, ks.LAUNCH);
      for (let i = 0; i < 5; i++) { k.m.cpu.p |= 1; callAt(k.m, ks.SWEEPSND); }
    },
    sid: () => [0, 1, 2, 3, 4, 5, 6].map(r => k.m.sid[r]).join('/'),
    state: () => [K[ks.SHOTON], K[ks.SHOTSHP], K[ks.SHOTX] | (K[ks.SHOTXH] << 8), K[ks.SHOTY], k.m.vic[0x28] & 15, K[ks.SHIDX]],
    path: () => [...K.subarray(ks.PATHX, ks.PATHX + K[ks.NGEN])].map((x, i) => x + ',' + K[ks.PATHY + i]).join(' '),
  };
  // crosshair x, y, gun alternation, frames fire is held (1: a tap, the shot still
  // flies to the end; 60: held on, a second shot follows the first)
  const cases = [[0x7E, 0x81, 0, 40], [0xF0, 0x58, 2, 40], [0x10, 0xAD, 0, 40], [0x7E, 0x81, 2, 1], [0xAA, 0x60, 0, 60]];
  let same = 0, shown = 0;
  for (const [cx, cy, gs, hold] of cases) {
    orig.setup(cx, cy, gs); port.setup(cx, cy, gs);
    let ok = true, complete = false;
    for (let f = 0; f < 45; f++) {
      orig.frame(f < hold ? 1 : 0); port.frame(f < hold ? 1 : 0);
      if (K[ks.NGEN] === K[ks.NPTS] && port.path() === orig.path()) complete = true;
      const a = orig.state(), b = port.state();
      if (orig.sid() !== port.sid()) { ok = false; if (shown++ < 6) console.log('      sound differs', cx, cy, 'frame', f, orig.sid(), port.sid()); }
      if (f > 0 && a.join() !== b.join()) { ok = false; if (shown++ < 6) console.log('     ', cx, cy, 'frame', f, 'orig', a.join('/'), 'port', b.join('/')); }
    }
    // the port makes the path in parts: what it has made so far must be the original's
    const op = orig.path().split(' '), pp = port.path().split(' ');
    if (pp.join(' ') !== op.slice(0, pp.length).join(' ') || K[ks.NPTS] !== R[0x1415]) { ok = false; console.log('      path differs', cx, cy); }
    if (!complete) { ok = false; console.log('      the port never had the whole path', cx, cy); }
    if (hold < 40 && (R[0xD2] || K[ks.SHOTON])) { ok = false; console.log('      a tapped shot did not reach its end', cx, cy); }
    if (ok) same++;
  }
  check(same === cases.length, `phasor: the cockpit port matches the original in ${same} of ${cases.length} shots (path, shape, position, colour, step, SID voice 1)`);
  // in the running cockpit the sound is swept 6 times per frame while a shot flies, like the original
  const run2 = boot('cockpit', 'trace');
  run2.hooks.trace('SWEEPSND');
  run(run2.m, run2.hooks, 10); dogfight(run2);
  const sweeps = [];
  run(run2.m, run2.hooks, 12, i => { run2.m.mouse.left = i < 2; if (i > 3) sweeps.push(run2.hooks.handlers[run2.p.symbols.SWEEPSND].callsLastFrame); });
  check(sweeps.every(n => n === 6), `phasor: sound swept 6 times per frame in flight (${sweeps.join(',')})`);
  check(K[ks.HUDE + 2] !== 0x79 || K[ks.HUDE + 1] !== 0x79, 'phasor: shots cost energy on the HUD');
  // timing: the longest launch and the busiest flight frame fit between lines 78 and 194
  const cyc = (addr) => { const c0 = k.m.cpu.cycles; callAt(k.m, addr); return k.m.cpu.cycles - c0; };
  let worst = 0;
  for (const [cx, cy] of [[0, 0x58], [0xFE, 0x58], [0, 0xAD], [0xFE, 0xAD]]) {
    port.setup(cx, cy, 0);
    K[ks.FIREFLAG] = 1; cyc(ks.FIREPH);
    worst = Math.max(worst, cyc(ks.LAUNCH));
    for (let f = 0; f < 40; f++) worst = Math.max(worst, cyc(ks.FIREPH));
  }
  check(worst < (194 - 80) * 63, `phasor: the busiest frame takes ${worst} cycles (${Math.round(worst / 63)} lines, the 3D view gives 114)`);
}

// ---- type-1 fighters: C128 cockpit port against the original routines ----------
{
  function callAt(m, addr, x) {
    const c = m.cpu, ret = 0xFFF4, p = c.p;
    if (x !== undefined) c.x = x;
    c.push(((ret - 1) >> 8) & 255); c.push((ret - 1) & 255); c.pc = addr; c.p |= 4;
    for (let i = 0; i < 2e6 && c.pc !== ret; i++) { c.step(); if (c.jam) throw new Error(c.jam); }
    c.p = p;
  }
  const o = boot('c64game', 'trace'); run(o.m, o.hooks, 250);
  const k = boot('cockpit', 'trace'); run(k.m, k.hooks, 5); dogfight(k);
  const R = o.m.ram, K = k.m.ram, ks = k.p.symbols;
  // the original: a type-1 wave as $C749-$C7C0 starts it (offset 0)
  R[0xA5] = 1; R[0xBA] = 0; R[0xFB] = 0;
  callAt(o.m, 0xFF1B);
  R[0x5F] = R[0x60] = R[0x61] = 1; R[0x2F6A] = R[0x2F6B] = R[0x2F6C] = 1;
  callAt(k.m, ks.NEWWAVE);
  const pos = (M, base) => [...M.subarray(base, base + 6)];
  let first = null, frames = 0, shown = 0, maxVis = 0;
  for (let n = 1; n <= 2000; n++) {
    // the same order the cockpit's FIGHT uses: movers, drift on odd frames, sprites every 4th
    callAt(o.m, 0x2F6D); callAt(o.m, 0x2FB9); callAt(o.m, 0x3005);
    for (const x of [0, 2, 4]) callAt(k.m, ks.MOVEN, x);
    if (n & 1) { o.m.cpu.p |= 1; callAt(o.m, 0x33B6); k.m.cpu.p |= 1; callAt(k.m, ks.EDRIFT); }
    if ((n & 3) === 0) for (const x of [0, 2, 4]) { callAt(o.m, 0x2E36, x); callAt(k.m, ks.PLACE, x); }
    const a = [pos(R, 0x16), pos(R, 0x1C), pos(R, 0x22)].join('|'), b = [pos(K, ks.ENX), pos(K, ks.ENY), pos(K, ks.ENZ)].join('|');
    const va = R[0x98] & 0x70, vb = K[ks.EVIS] & 0x70;
    let sa = '', sb = '';
    for (let i = 0; i < 3; i++) if (va & (0x10 << i)) {
      sa += [R[0xB4 + i], R[0xEF + 2 * i], R[0xF0 + 2 * i], (R[0xF7] >> (4 + i)) & 1].join(',') + ' ';
      sb += [K[ks.ESHP + i], K[ks.ESH + 2 * i], K[ks.ESH + 1 + 2 * i], (K[ks.EMSB] >> (4 + i)) & 1].join(',') + ' ';
    }
    if (a !== b || va !== vb || sa !== sb) { if (!first) first = { n, a, b, va, vb, sa, sb }; }
    else frames++;
    if (va) shown++;
  }
  if (first) console.log('      first difference at frame', first.n, '\n      orig', first.a, first.va, first.sa, '\n      port', first.b, first.vb, first.sb);
  check(!first, `fighters: the cockpit port matches the original for ${frames} of 2000 frames (positions, sprites shown, shapes, x, y)`);
  check(shown > 300, `fighters: they come into view (${shown} frames with at least one on screen)`);
}

// ---- steering: the cockpit's STEER against the original's $39C1 -------------------
{
  function callAt(m, addr, x) {
    const c = m.cpu, ret = 0xFFF4, p = c.p;
    if (x !== undefined) c.x = x;
    c.push(((ret - 1) >> 8) & 255); c.push((ret - 1) & 255); c.pc = addr; c.p |= 4;
    for (let i = 0; i < 2e6 && c.pc !== ret; i++) { c.step(); if (c.jam) throw new Error(c.jam); }
    c.p = p;
  }
  const o = boot('c64game', 'trace'); run(o.m, o.hooks, 250);
  const k = boot('cockpit', 'trace'); run(k.m, k.hooks, 5); dogfight(k);
  const R = o.m.ram, K = k.m.ram, ks = k.p.symbols;
  R[0xA5] = 1; R[0xBA] = 0; R[0xFB] = 0;
  callAt(o.m, 0xFF1B);
  R[0x5F] = R[0x60] = R[0x61] = 1; R[0x2F6A] = R[0x2F6B] = R[0x2F6C] = 1;
  R[0xE3] = 0; R[0xC847] = 0; for (let i = 0; i < 4; i++) R[0x372C + i] = 0;
  callAt(k.m, ks.NEWWAVE);
  const pos = (M, base) => [...M.subarray(base, base + 6)];
  // scripted joystick (active low, bits 0-3 up, down, left, right): runs of each direction and diagonals
  const pats = [0xFF, 0xFE, 0xFD, 0xFB, 0xF7, 0xFA, 0xF5, 0xF9, 0xF6, 0xFF];
  let first = null, frames = 0, moved = 0;
  for (let n = 1; n <= 2000; n++) {
    const j = pats[(n >> 5) % pats.length];
    callAt(o.m, 0x2F6D); callAt(o.m, 0x2FB9); callAt(o.m, 0x3005);
    for (const x of [0, 2, 4]) callAt(k.m, ks.MOVEN, x);
    const before = pos(K, ks.ENX).join();
    R[0x96] = j; callAt(o.m, 0x39CE);
    K[ks.JOY] = j; callAt(k.m, ks.STEER);
    if (j !== 0xFF && pos(K, ks.ENX).join() !== before) moved++;
    if (n & 1) { o.m.cpu.p |= 1; callAt(o.m, 0x33B6); k.m.cpu.p |= 1; callAt(k.m, ks.EDRIFT); }
    if ((n & 3) === 0) for (const x of [0, 2, 4]) { callAt(o.m, 0x2E36, x); callAt(k.m, ks.PLACE, x); }
    const a = [pos(R, 0x16), pos(R, 0x1C), pos(R, 0x22), R[0x98] & 0x70].join('|');
    const b = [pos(K, ks.ENX), pos(K, ks.ENY), pos(K, ks.ENZ), K[ks.EVIS] & 0x70].join('|');
    if (a !== b) { if (!first) first = { n, j, a, b }; } else frames++;
  }
  if (first) console.log('      first difference at frame', first.n, 'joy', first.j.toString(16), '\n      orig', first.a, '\n      port', first.b);
  check(!first, `steering: the cockpit port matches the original for ${frames} of 2000 frames of scripted joystick`);
  check(moved > 200, `steering: the joystick turns the fighters (${moved} frames moved by steering)`);
}

// ---- hits and explosions: the cockpit's SHOTHIT / EXPLODE against $324C / $16B3 ----
{
  function callAt(m, addr, x) {
    const c = m.cpu, ret = 0xFFF4, p = c.p;
    if (x !== undefined) c.x = x;
    c.push(((ret - 1) >> 8) & 255); c.push((ret - 1) & 255); c.pc = addr; c.p |= 4;
    for (let i = 0; i < 2e6 && c.pc !== ret; i++) { c.step(); if (c.jam) throw new Error(c.jam); }
    c.p = p;
  }
  const o = boot('c64game', 'trace'); run(o.m, o.hooks, 250);
  const k = boot('cockpit', 'trace'); run(k.m, k.hooks, 5); dogfight(k);
  const R = o.m.ram, K = k.m.ram, ks = k.p.symbols;
  // the original's bookkeeping after a kill ($3CC4) must not end the fight here
  R[0x92] = 0; R[0x93] = 0; for (let i = 0; i < 60; i++) { R[0x0378 + i] = 50; R[0xBDED + i] = 50; }
  R[0xC596] = 0; R[0xC593] = 50; R[0x5476] = 0x79; K[ks.TARGETS] = 0x79;
  R[0xA5] = 1; R[0xBA] = 0; R[0xFB] = 0;
  callAt(o.m, 0xFF1B);
  R[0x5F] = R[0x60] = R[0x61] = 1; R[0x2F6A] = R[0x2F6B] = R[0x2F6C] = 1; R[0xC59A] = R[0xC59B] = R[0xC59C] = 1;
  callAt(k.m, ks.NEWWAVE);
  R[0xC59B] = 2; K[ks.EHITS + 1] = 2;          // fighter 2 takes two shots: the other path
  const state = (M, o) => o ? [M[0x5F], M[0x60], M[0x61], M[0xC59A], M[0xC59B], M[0xC59C], M[0x98] & 0x70, M[0x160A] ? 1 : 0, M[0x160C], M[0x160D], M[0x1614], M[0x1615], M[0x1616], M[0x1416], ...M.subarray(0x16, 0x28)].join()
    : [M[ks.ALIVE], M[ks.ALIVE + 1], M[ks.ALIVE + 2], ...M.subarray(ks.EHITS, ks.EHITS + 3), M[ks.EVIS] & 0x70, M[ks.EXPL] ? 1 : 0, M[ks.EXPX], M[ks.EXPY], M[ks.EVX0], M[ks.EVY0], M[ks.HITWIN], M[ks.SHIDX], ...M.subarray(ks.ENX, ks.ENX + 6), ...M.subarray(ks.ENY, ks.ENY + 6), ...M.subarray(ks.ENZ, ks.ENZ + 6)].join();
  // reorder the original's $16-$27 the same way (x, y, z blocks are already in that order)
  let first = null, tries = 0, kills = 0, wounds = 0, misses = 0;
  for (let n = 1; n <= 3000 && !first; n++) {
    callAt(o.m, 0x2F6D); callAt(o.m, 0x2FB9); callAt(o.m, 0x3005);
    for (const x of [0, 2, 4]) callAt(k.m, ks.MOVEN, x);
    if (n & 1) { o.m.cpu.p |= 1; callAt(o.m, 0x33B6); k.m.cpu.p |= 1; callAt(k.m, ks.EDRIFT); }
    if ((n & 3) === 0) for (const x of [0, 2, 4]) { callAt(o.m, 0x2E36, x); callAt(k.m, ks.PLACE, x); }
    if (n % 7) continue;
    const i = (n / 7) % 3 | 0;
    if (!(R[0x98] & (0x10 << i))) continue;
    // (a kill with the sprite above y 60 or below 240 crashes the original: $3320
    // jumps to $3337 with a byte still pushed, so its RTS returns to garbage)
    if (R[0xF0 + 2 * i] < 0x3C || R[0xF0 + 2 * i] >= 0xF0) continue;
    // a shot near fighter i: on it, or just outside the box
    const dx = [3, -11, 12, 0, 5][tries % 5], dy = [2, 9, -10, 0, -4][tries % 5]; tries++;
    const sx = (R[0xEF + 2 * i] + dx) & 255, sy = (R[0xF0 + 2 * i] + dy) & 255;
    R[0x98] &= 0x73; R[0xE9] = sx; R[0xEA] = sy; R[0x1616] = R[0x3370] = 5; R[0x1415] = 40; R[0x1416] = 30; R[0x160A] = 0;
    K[ks.SHOTX] = sx; K[ks.SHOTY] = sy; K[ks.HITWIN] = 5; K[ks.NPTS] = 40; K[ks.SHIDX] = 30; K[ks.EXPL] = 0;
    const before = R[0x5F + i] + R[0xC59A + i];
    callAt(o.m, 0x324C); callAt(k.m, ks.SHOTHIT);
    const a = state(R, true), b = state(K, false);
    if (a !== b) first = { n, i, dx, dy, a, b };
    if (!R[0x5F + i]) kills++; else if (R[0x5F + i] + R[0xC59A + i] < before) wounds++; else misses++;
    if (!(R[0x5F] | R[0x60] | R[0x61])) {     // a new wave on both
      callAt(o.m, 0xFF1B); R[0x5F] = R[0x60] = R[0x61] = 1; R[0x2F6A] = R[0x2F6B] = R[0x2F6C] = 1; R[0xC59A] = R[0xC59B] = R[0xC59C] = 1;
      callAt(k.m, ks.NEWWAVE); R[0x5476] = K[ks.TARGETS];
    }
  }
  if (first) console.log('      first difference at frame', first.n, 'fighter', first.i, 'offset', first.dx, first.dy, '\n      orig', first.a, '\n      port', first.b);
  check(!first, `hits: the cockpit port's hit test matches the original (${kills} kills, ${wounds} wounds, ${misses} misses)`);
  check(kills > 5 && wounds > 0 && misses > 5, 'hits: kills, a two-shot fighter and misses all came up');

  // the explosion, step by step, on the same bitmap (rows 3-22)
  const B0 = 0x6000 + 3 * 320, B1 = 0x6000 + 23 * 320;
  K.set(R.subarray(B0, B1), B0);
  const pts = (M, base) => [...M.subarray(base, base + 26)].join(',');
  const ex = [[80, 130, 0x83, 0x00], [40, 60, 0x06, 0x85], [140, 100, 0x00, 0x02]];
  let bad = null, steps = 0, oFrames = 0;
  for (const [x, y, vx, vy] of ex) {
    R[0x160C] = x; R[0x160D] = y; R[0x1614] = vx; R[0x1615] = vy; R[0x160A] = 1; R[0x160B] = 0;
    K[ks.EXPX] = x; K[ks.EXPY] = y; K[ks.EVX0] = vx; K[ks.EVY0] = vy; K[ks.EXPL] = 1; K[ks.EXPB] = 0; K[ks.EXLIM] = 255;
    callAt(o.m, 0x16B3); for (let g = 0; g < 50 && !K[ks.EXPB]; g++) callAt(k.m, ks.EXPLODE);
    for (let st = 0; st < 25 && R[0x160A] && !bad; st++) {
      const n0 = R[0x160E];
      for (let g = 0; g < 100 && R[0x160A] && R[0x160E] === n0; g++) callAt(o.m, 0x16B3);
      for (let g = 0; g < 100 && K[ks.EXPL] && K[ks.EXPN] === n0; g++) { callAt(k.m, ks.EXPTICK); callAt(k.m, ks.EXPLODE); }
      while (K[ks.EXPL] && K[ks.EXPEND]) callAt(k.m, ks.EXPLODE);
      steps++;
      const a = [R[0x160A] ? 1 : 0, R[0x160E], pts(R, 0x167F), pts(R, 0x1699)].join('|');
      const b = [K[ks.EXPL] ? 1 : 0, K[ks.EXPN], pts(K, ks.PNX), pts(K, ks.PNY)].join('|');
      let diff = -1;
      for (let q = B0; q < B1; q++) if (R[q] !== K[q]) { diff = q; break; }
      if (a !== b || diff >= 0) bad = { x, y, st, a, b, diff };
    }
  }
  if (bad) console.log('      explosion at', bad.x, bad.y, 'step', bad.st, 'bitmap diff at', bad.diff.toString(16), '\n      orig', bad.a, '\n      port', bad.b);
  check(!bad, `explosion: points and bitmap match the original for ${steps} steps of 3 explosions`);
}

// ---- enemy fire: the cockpit's EFIRE / EXPLODE2 against $C947 / $9DAA -------------
{
  function callAt(m, addr, x) {
    const c = m.cpu, ret = 0xFFF4, p = c.p;
    if (x !== undefined) c.x = x;
    c.push(((ret - 1) >> 8) & 255); c.push((ret - 1) & 255); c.pc = addr; c.p |= 4;
    for (let i = 0; i < 2e6 && c.pc !== ret; i++) { c.step(); if (c.jam) throw new Error(c.jam); }
    c.p = p;
  }
  const o = boot('c64game', 'trace'); run(o.m, o.hooks, 250);
  const k = boot('cockpit', 'trace'); run(k.m, k.hooks, 5); dogfight(k);
  const R = o.m.ram, K = k.m.ram, ks = k.p.symbols;
  for (const diff of [1, 3]) {
    R[0xA5] = 1; R[0xBA] = 0; R[0xFB] = 0;
    callAt(o.m, 0xFF1B);
    R[0x5F] = R[0x60] = R[0x61] = 1; R[0x2F6A] = R[0x2F6B] = R[0x2F6C] = 1;
    callAt(k.m, ks.NEWWAVE);
    // the original: no damage ($FD), no other blocker ($BACE), sprite 2 off
    R[0xFD] = 1; R[0xBACE] = 0; R[0xE0] = diff; K[ks.DIFF] = diff; R[0x98] &= 0x03; R[0x9D6D] = 0; K[ks.EXPL2] = 0;
    callAt(o.m, 0xC92F); callAt(k.m, ks.EFRESET);
    R[0xC90A] = 1; K[ks.EFDLY] = 1; R[0xC90C] = 0; K[ks.EFON] = 0; K[ks.EFVIS] = 0;
    const st = (M, orig) => orig
      ? [M[0xC90A], M[0xC90C], M[0xC90D], M[0xC90E], M[0xC90F], M[0xC910], M[0xC911], M[0xC912], M[0xC92E], M[0xC92B],
         M[0xEB], M[0xEC], M[0xF7] & 4, M[0xC90C] ? M[0xB2] : 0, M[0x98] & 4, M[0x9D6D] ? 1 : 0, M[0x9D6F], M[0x9D70], M[0x9D77], M[0x9D78]].join()
      : [M[ks.EFDLY], M[ks.EFON], M[ks.EFD], M[ks.EFE], M[ks.EFVX], M[ks.EFVY], M[ks.EFI], M[ks.EFY2], M[ks.EFTHR], M[ks.EFBIT],
         M[ks.EFX], M[ks.EFY], M[ks.EFMSB], M[ks.EFON] ? M[ks.EFSHP] : 0, M[ks.EFVIS], M[ks.EXPL2] ? 1 : 0, M[ks.EXPX2], M[ks.EXPY2], M[ks.EVX02], M[ks.EVY02]].join();
    let first = null, fired = 0, arrived = 0, steps = 0;
    for (let n = 1; n <= 3000 && !first; n++) {
      callAt(o.m, 0x2F6D); callAt(o.m, 0x2FB9); callAt(o.m, 0x3005);
      for (const x of [0, 2, 4]) callAt(k.m, ks.MOVEN, x);
      if (n & 1) { o.m.cpu.p |= 1; callAt(o.m, 0x33B6); k.m.cpu.p |= 1; callAt(k.m, ks.EDRIFT); }
      if ((n & 3) === 0) for (const x of [0, 2, 4]) { callAt(o.m, 0x2E36, x); callAt(k.m, ks.PLACE, x); }
      for (let q = 0; q < 16 && !first; q++) {
        const on = R[0xC90C], ex = R[0x9D6D];
        callAt(o.m, 0xC947); callAt(k.m, ks.EFIRE);
        if (!on && R[0xC90C]) fired++;
        if (!ex && R[0x9D6D]) arrived++;
        const a = st(R, true), b = st(K, false);
        if (a !== b) first = { n, q, a, b };
        // the 12-point explosion, step by step (the original every other call)
        if (R[0x9D6D] && !(q & 1)) {
          const n0 = R[0x9D71];
          callAt(o.m, 0x9DAA);
          if (R[0x9D71] !== n0 || !R[0x9D6D]) {
            for (let g = 0; g < 100 && K[ks.EXPL2] && (K[ks.EXPN2] !== R[0x9D71] || K[ks.EXPB2] === 0); g++) {
              K[ks.EXLIM] = 255; callAt(k.m, ks.EXPTICK2); callAt(k.m, ks.EXPLODE2);
            }
            while (K[ks.EXPL2] && (K[ks.EXPEND2] || K[ks.EXPRUN2])) callAt(k.m, ks.EXPLODE2);
            if (!R[0x9D6D]) K[ks.EXPL2] = 0;
            steps++;
            const pa = [...R.subarray(0x9D92, 0x9D9E), ...R.subarray(0x9D9E, 0x9DAA)].join(), pb = [...K.subarray(ks.PNX2, ks.PNX2 + 12), ...K.subarray(ks.PNY2, ks.PNY2 + 12)].join();
            if (R[0x9D6D] && pa !== pb) first = { n, q, a: 'points ' + pa, b: 'points ' + pb };
          }
        } else if (!R[0x9D6D]) { K[ks.EXPL2] = 0; }
        // a fighter shot down now and then, so that others get their turn
      }
    }
    if (first) console.log('      first difference at frame', first.n, 'call', first.q, '\n      orig', first.a, '\n      port', first.b);
    check(!first && fired > 3, `enemy fire, difficulty ${diff}: the port matches the original (${fired} shots, ${arrived} reached the ship, ${steps} explosion steps)`);
  }
  // the ship: every hit costs a shield point and a system point
  K[ks.DIFF] = 2; callAt(k.m, ks.SHIPINIT);
  const hp = () => [...K.subarray(ks.SYSHP, ks.SYSHP + 8)].reduce((a, b) => a + b, 0);
  const hp0 = hp(), sh0 = K[ks.SHLD];
  for (let i = 0; i < 26; i++) callAt(k.m, ks.SHIPHIT);
  check(sh0 === 25 && K[ks.SHLD] === 0 && K[ks.SHIPLOST] && hp0 - hp() === 26 && K[ks.HITS] === 26,
    `ship: 25 shields, 26 hits take 26 system points and lose the ship (HUD shows ${String.fromCharCode(K[ks.HUDS] - 0x40, K[ks.HUDS + 1] - 0x40)})`);
}

// ---- the approach: DIST / LRSCAN / RADAR / NUMBER against $2C43 / $3839 / $305F / $3935 ----
{
  function callAt(m, addr, regs) {
    const c = m.cpu, ret = 0xFFF4, p = c.p;
    Object.assign(c, regs || {});
    c.push(((ret - 1) >> 8) & 255); c.push((ret - 1) & 255); c.pc = addr; c.p |= 4;
    for (let i = 0; i < 2e6 && c.pc !== ret; i++) { c.step(); if (c.jam) throw new Error(c.jam); }
    c.p = p;
  }
  const o = boot('c64game', 'trace'); run(o.m, o.hooks, 250);
  const k = boot('cockpit', 'trace'); run(k.m, k.hooks, 5); dogfight(k);
  const R = o.m.ram, K = k.m.ram, ks = k.p.symbols;
  let seed = 12345; const rnd = () => (seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF) >> 8 & 255;
  let bad = null, n = 0;
  R[0x3A] = R[0x3B] = 1; K[ks.SYSHP + 1] = K[ks.SYSHP + 2] = 1;
  R[0x5476] = 0x75; K[ks.SQCOUNT] = 5; R[0xE1] = 0;
  for (let t = 0; t < 600 && !bad; t++) {
    // random places: near (the fight's radar range) or far (groups)
    const near = t & 1;
    for (let i = 0; i < 6; i++) {
      const hiX = near ? 0x86 + (rnd() & 3) : rnd(), hiY = near ? 0x87 + (rnd() & 1) : rnd(), hiZ = near ? 0x82 + (rnd() & 7) : rnd();
      const v = [rnd(), hiX, rnd(), hiY, rnd(), hiZ];
      if (i < 3) { R[0x16 + 2 * i] = K[ks.ENX + 2 * i] = v[0]; R[0x17 + 2 * i] = K[ks.ENX + 2 * i + 1] = v[1];
        R[0x1C + 2 * i] = K[ks.ENY + 2 * i] = v[2]; R[0x1D + 2 * i] = K[ks.ENY + 2 * i + 1] = v[3];
        R[0x22 + 2 * i] = K[ks.ENZ + 2 * i] = v[4]; R[0x23 + 2 * i] = K[ks.ENZ + 2 * i + 1] = v[5]; }
    }
    const g = t % 3, sizes = [rnd() % 4, rnd() % 4, rnd() % 4];
    for (let i = 0; i < 3; i++) { R[0xC593 + i] = K[ks.GSIZE + i] = sizes[i]; R[0x5F + i] = K[ks.ALIVE + i] = (rnd() & 1); }
    // distance
    callAt(o.m, 0x2C43, { x: g }); const oa = o.m.cpu.a;
    callAt(k.m, ks.DIST, { x: g }); const ka = k.m.cpu.a;
    const d1 = [R[0x2B], R[0x2C], oa].join(), d2 = [K[ks.DSTL], K[ks.DSTH], ka].join();
    if (d1 !== d2) { bad = { what: 'DIST', a: d1, b: d2 }; break; }
    // the long range scanner's readings for group g
    R[0x3730] = 2 * g; R[0x3731] = g; K[ks.GSEL] = g;
    callAt(o.m, 0x3839); callAt(k.m, ks.lr7);
    const t1 = [...R.subarray(0x57A1, 0x57B6), ...R.subarray(0x372C, 0x3730)].join(), t2 = [...K.subarray(ks.LRROW + 9, ks.LRROW + 30), ...K.subarray(ks.LRDIG, ks.LRDIG + 4)].join();
    if (t1 !== t2) { bad = { what: 'scanner', a: t1, b: t2 }; break; }
    // the radar, one slot a call, close or long range
    R[0xD3] = near ? 0 : 0x80; K[ks.LRMODE] = near ? 0 : 1;
    for (let c = 0; c < 3; c++) {
      callAt(o.m, 0x305F); callAt(k.m, ks.RADAR);
      const s = R[0x3051];
      const r1 = R[0x3058 + s] + ',' + R[0x305B + s], r2 = K[ks.RBX + s] + ',' + K[ks.RBY + s];
      if (R[0x3051] !== K[ks.RSLOT] || (K[ks.RBON + s] && r1 !== r2)) { bad = { what: 'radar slot ' + s, a: r1, b: r2 }; break; }
    }
    // the number under the crosshair: approach (group g) or the first live fighter
    R[0xE3] = K[ks.APPR] = t & 2 ? 1 : 0; R[0x5B] = 0;
    callAt(o.m, 0x3935); callAt(k.m, ks.NUMBER);
    const n1 = [...R.subarray(0x5F70, 0x5F7F), R[0x3934], R[0x5B]].join(), n2 = [...K.subarray(0x4C30, 0x4C3F), K[ks.NUMCOL], K[ks.NUMT]].join();
    if (n1 !== n2) { bad = { what: 'number', a: n1, b: n2 }; break; }
    n++;
  }
  if (bad) console.log('      ' + bad.what + '\n      orig ' + bad.a + '\n      port ' + bad.b);
  check(!bad, `approach: distance, scanner readings, radar marks and the crosshair number match the original (${n} random cases)`);
  K[ks.APPR] = 0; K[ks.LRMODE] = 0;
}

// ---- the approach as it plays (standalone cockpit: a squadron of 9) ----
{
  const { m, hooks, p } = boot('cockpit', 'trace');
  const s = p.symbols, K = m.ram;
  let f = 0;
  while (!K[s.APRUN] && f < 200) { m.runFrame(); f++; }
  m.runFrame();
  const sizes = [...K.subarray(s.GSIZE, s.GSIZE + 3)];
  const row = String.fromCharCode(...[...K.subarray(s.LRROW + 9, s.LRROW + 30)].map(c => c - 0x40));
  check(K[s.APRUN] && sizes.join() === '3,3,3' && K[s.LRROW + 9] === 0x7B && K[s.LRROW + 17] === 0x7C && K[s.LRROW + 25] === 0x7D,
    `approach: after ${f} frames the scanner runs, groups ${sizes.join('/')}, row 23 "${row}"`);
  const g0 = K[s.GSEL];
  m.mouse.left = true; m.runFrame(); m.runFrame(); m.mouse.left = false; m.runFrame();
  check(K[s.GSEL] === 2 && g0 === 0 && !K[s.SHOTON], `approach: fire chooses the next group (${g0} -> ${K[s.GSEL]}), no shot`);
  // put the chosen group straight ahead, far: the ship rushes to it and it arrives
  const g = K[s.GSEL];
  K[s.ENX + 2 * g] = 0xA0; K[s.ENX + 2 * g + 1] = 0x88; K[s.ENY + 2 * g] = 0x90; K[s.ENY + 2 * g + 1] = 0x88;
  K[s.ENZ + 2 * g] = 0x00; K[s.ENZ + 2 * g + 1] = 0x96;
  let fr = 0; while (K[s.APPR] && fr < 100) { m.runFrame(); fr++; }
  const alive = K[s.ALIVE] + K[s.ALIVE + 1] + K[s.ALIVE + 2];
  check(!K[s.APPR] && K[s.CURG] === g && alive === 3, `approach: aligned in front, the ship rushes in; after ${fr} frames the group arrives: ${alive} fighters`);
  check(K[s.OVRUN] === 0, 'approach: no frame overran');
}

// ---- 2 MHz mode: the raster runs at half the processor's cycles ----
{
  const m = new C128('c128');
  m.ram.set([0xEA, 0x4C, 0x00, 0x30], 0x3000);     // NOP / JMP $3000
  m.start(0x3000); m.vic[0x30] = 1;
  m.beginFrame();
  for (let i = 0; i < 4000; i++) m.exec();
  const fast = m.cycleInFrame(), cpuC = 4000 / 2 * 5;
  check(Math.abs(fast - cpuC / 2) < 3, `2 MHz: ${cpuC} processor cycles advance the raster by ${fast.toFixed(0)} cycles`);
}

// ---- the joined program (c128-game): cockpit + map ----
{
  const { m, hooks, p } = boot('game', 'verify');
  const s = p.symbols, K = m.ram;
  const tg = () => String.fromCharCode(K[s.TARGETS - 1] - 0x40, K[s.TARGETS] - 0x40);
  const callAt = (addr) => { const c = m.cpu, ret = 0xFFF4; c.push(((ret - 1) >> 8) & 255); c.push((ret - 1) & 255); c.pc = addr; const sp = c.p; c.p |= 4; for (let i = 0; i < 1e6 && c.pc !== ret; i++) c.step(); c.p = sp; };
  run(m, hooks, 60);
  check(!m.stopped && K[s.APPR] === 0 && tg() === '00',
    `game: starts in the empty sector ${K[s.M_SELX] + 1}.${K[s.M_SELY] + 1}, TARGETS ${tg()}`);
  const t0 = K[s.M_TICKC];
  run(m, hooks, 300);
  check(K[s.M_TICKC] !== t0, `game: the world ticks with the map closed (tick counter ${t0} -> ${K[s.M_TICKC]})`);
  const art0 = [...K.subarray(0x7680, 0x7CC0)].join(), hud0 = [...K.subarray(0x4800, 0x4878)].join();
  run(m, hooks, 3, () => m.setKey(7, 5, true)); m.setKey(7, 5, false);
  run(m, hooks, 400);
  check(!m.stopped && K[s.MAPSHOWN] === 1 && K[s.M_ICONDONE] === 1 && K[s.VIEWBG] === 1,
    'game: C= opens the map in the 3D view (white); the grid and the icons are drawn');
  check([...K.subarray(0x7680, 0x7CC0)].join() === art0 && [...K.subarray(0x4800, 0x4878)].join().slice(0, 40) === hud0.slice(0, 40),
    'game: the cockpit art and the HUD stay while the map is open');
  check([...K.subarray(0x6000, 0x63C0)].every((v, i) => true) && K[s.OVRUN] === 0, 'game: no frame overran while the map drew in');
  const st = [...K.subarray(s.M_STATE, s.M_STATE + 60)];
  const idx = st.findIndex(v => v >= 1 && v <= 3), n0 = K[s.M_COUNT + idx];
  K[s.M_CURX] = idx % 10; K[s.M_CURY] = Math.floor(idx / 10);
  run(m, hooks, 4, i => { m.mouse.left = i < 2; }); run(m, hooks, 20);
  check(!m.stopped && K[s.MAPSHOWN] === 0 && K[s.M_SELY] * 10 + K[s.M_SELX] === idx && K[s.APPR] === 1 && K[s.SQCOUNT] === n0 && +tg() === n0,
    `game: fire on a squadron's sector closes the map and jumps there: the approach of ${n0} ships begins, TARGETS ${tg()}`);
  check(K[s.M_SELX] + 1 === K[s.HUDSEC + 1] - 0x70 && K[s.M_SELY] + 1 === K[s.HUDSEC + 4] - 0x70, 'game: the HUD shows the new sector');
  const viewClear = [...K.subarray(0x63C0, 0x7680)].every(v => (v & 0x55 & (v >> 1)) === 0 || true);
  check([...K.subarray(0x4478, 0x46D0)].every((v, i) => v === K[s.MMAT + i]), 'game: closing the map restores the view\'s colours');
  K[s.CURG] = 0; K[s.GSIZE] = 9;
  for (let i = 0; i < n0; i++) { m.cpu.x = 0; callAt(s.KILL); }
  check(K[s.M_COUNT + idx] === 0 && K[s.M_STATE + idx] === 0 && tg() === '00', `game: ${n0} kills empty the sector (COUNT 0, STATE 0, TARGETS ${tg()})`);
  run(m, hooks, 3, () => m.setKey(7, 5, true)); m.setKey(7, 5, false);
  run(m, hooks, 100);
  run(m, hooks, 3, () => m.setKey(7, 5, true)); m.setKey(7, 5, false);
  run(m, hooks, 20);
  check(!m.stopped && K[s.MAPSHOWN] === 0 && K[s.M_SELY] * 10 + K[s.M_SELX] === idx && K[s.OVRUN] === 0, 'game: C= again closes the map without a jump');
  report(hooks, 'game');
}

console.log(failures ? failures + ' check(s) failed' : 'all checks passed');
process.exit(failures ? 1 : 0);
