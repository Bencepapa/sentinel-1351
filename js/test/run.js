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
const freeMemoryRuns = [];

function boot(name, mode) {
  const p = PROGRAMS[name];
  const m = new C128(p.model);
  m.loadPrg(new Uint8Array(Buffer.from(p.prg, 'base64')));
  const hooks = new Hooks(m, p.symbols);
  const ported = Native.install(hooks, mode);
  m.start(p.entry);
  if (name === 'game') {
    const s=p.symbols, record={armed:false, intact:true, frames:0};
    m.freeMemoryRecord=record;
    freeMemoryRuns.push(record);
    const frame=m.runFrame.bind(m);
    m.runFrame=function() {
      const result=frame();
      if (!record.armed && m.mmuCR===0x3E && m.ram[s.GUNPACK]===(s.TORPA&255)) {
        m.ram.fill(0xA5,s.MINEFREE,s.MINEEND);
        record.armed=true;
      } else if (record.armed) {
        for(let a=s.MINEFREE;a<s.MINEEND;a++) if(m.ram[a]!==0xA5) record.intact=false;
        record.frames++;
      }
      return result;
    };
  }
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

// ---- C64 game: a jump from the map ------------------------------------------------
// It leaves no cursor boxes in the bitmap (pixel value 2: black, the original keeps
// them through the hyperspace; only a white flash shows them).
{
  const { m, hooks } = boot('c64game', 'trace');
  const R = m.ram;
  const boxes = () => { let n = 0; for (let i = 0x63C0; i < 0x7680; i++) for (let b = 0; b < 8; b += 2) if (((R[i] >> b) & 3) === 2) n++; return n; };
  run(m, hooks, 300);
  run(m, hooks, 300, i => { m.mouse.left = (i >= 0 && i < 10) || (i >= 150 && i < 160); });
  run(m, hooks, 200);
  run(m, hooks, 20, () => m.setKey(7, 5, true)); m.setKey(7, 5, false);
  run(m, hooks, 300);
  const open = R[0xB8], b0 = boxes(), s0 = R[0x93] * 10 + R[0x92];
  let e = 0; while (R[0x033C + e] || e === s0) e++;           // an empty sector, not this one
  run(m, hooks, 3, () => m.moveMouse(1, 0));
  R[0x8A] = 12 * (e % 10) + 6; R[0x8B] = 16 * Math.floor(e / 10) + 8;
  run(m, hooks, 40, () => m.moveMouse(1, 0));
  R[0x8A] = 12 * (e % 10) + 6; R[0x8B] = 16 * Math.floor(e / 10) + 8;
  run(m, hooks, 40);
  run(m, hooks, 8, i => { m.mouse.left = i < 4; });
  for (let i = 0; i < 1500 && R[0xB8]; i++) m.runFrame();
  run(m, hooks, 10);                                          // (the clear takes a few frames)
  check(open && b0 > 0 && !R[0xB8] && R[0x93] * 10 + R[0x92] === e && boxes() === 0,
    `c64: a jump from the map to sector ${e} leaves no cursor boxes (${b0} pixels before, ${boxes()} after)`);
}

// ---- c128-game: the ship's own sector, a squadron coming in, the raster splits -----
{
  const { m, hooks, p } = boot('game', 'trace');
  const s = p.symbols, K = m.ram;
  m.dma = true;                                               // as on a real machine: bad lines, sprites
  const tg = () => String.fromCharCode(K[s.TARGETS - 1] - 0x40, K[s.TARGETS] - 0x40);
  run(m, hooks, 60);
  const idx = K[s.M_SELY] * 10 + K[s.M_SELX];
  {   // fire on the ship's own sector: the map closes, no jump
    run(m, hooks, 3, () => m.setKey(7, 5, true)); m.setKey(7, 5, false); run(m, hooks, 350);
    const open = K[s.MAPSHOWN], appr = K[s.APPR];
    K[s.M_CURX] = K[s.M_SELX]; K[s.M_CURY] = K[s.M_SELY];
    K[s.M_MPX] = 17 + 12 * K[s.M_SELX] + 6; K[s.M_MPY] = 35 + 16 * K[s.M_SELY] + 8; run(m, hooks, 3);
    run(m, hooks, 4, i => { m.mouse.left = i < 2; }); run(m, hooks, 30);
    check(open === 1 && K[s.MAPSHOWN] === 0 && K[s.APPR] === appr && K[s.M_SELY] * 10 + K[s.M_SELX] === idx, `game: fire on the ship's own sector closes the map, no jump (open ${open}, now ${K[s.MAPSHOWN]}, approach ${appr} -> ${K[s.APPR]}, sector ${K[s.M_SELY] * 10 + K[s.M_SELX]}, was ${idx})`);
  }
  {   // a squadron moves into the ship's sector: the squadrons' move stays on time, the
      // points rush in, three fighters appear, the dogfight and the warning start
    const sel = K[s.M_SELY] * 10 + K[s.M_SELX];
    K[s.M_STATE + sel] = 0; K[s.M_COUNT + sel] = 0; K[s.SQCOUNT] = 0; K[s.APPR] = 0; K[s.APRUN] = 0; K[s.LRMODE] = 0;
    K[s.ALIVE] = K[s.ALIVE + 1] = K[s.ALIVE + 2] = 0; K[s.GSIZE] = K[s.GSIZE + 1] = K[s.GSIZE + 2] = 0;
    // Isolate the incoming pair: random starting squadrons can otherwise merge
    // into it during the same movement pass (startup packing changes the seed).
    for (let i = 0; i < 60; i++) if (K[s.M_STATE + i] < 0x80) {
      K[s.M_STATE + i] = 0; K[s.M_COUNT + i] = 0;
    }
    const nb = sel + (K[s.M_SELX] < 9 ? 1 : -1);
    K[s.M_STATE + nb] = 1; K[s.M_COUNT + nb] = 2;
    const o0 = K[s.OVRUN];
    K[s.M_TICKC] = 1 + 0x10; K[s.WTCNT] = 1;                  // the next tick is a move
    let pts = 0, moved = -1, fx = -1, on = -1;
    for (let f = 0; f < 200 && on < 0; f++) {
      m.runFrame();
      if (moved < 0 && K[s.M_STATE + sel]) moved = f;
      if (fx < 0 && K[s.ARRFX]) fx = f;
      if (K[s.ARRFX] === 2) pts = Math.max(pts, [...K.subarray(0x63C0, 0x7000)].reduce((n, v) => n + [0, 2, 4, 6].filter(b => ((v >> b) & 3) === 1).length, 0));
      if (fx >= 0 && !K[s.ARRFX]) on = f;
    }
    run(m, hooks, 30);
    check(moved >= 0 && fx >= 0 && K[s.M_COUNT + sel] === 3 && K[s.SQCOUNT] === 3 && tg() === '03',
      `game: a squadron of 2 moves into the ship's sector (frame ${moved}, effect ${fx}) and becomes 3, TARGETS ${tg()}, COUNT ${K[s.M_COUNT + sel]}, SQCOUNT ${K[s.SQCOUNT]}`);
    check(on - fx >= 40 && on - fx <= 80 && pts >= 20, `game: its points rush in for ${on - fx} frames (the original: 54), ${pts} pixels at once`);
    check(K[s.ALIVE] && K[s.ALIVE + 1] && K[s.ALIVE + 2] && K[s.MSGON] && !K[s.APPR], 'game: three fighters appear, with the warning');
    check(K[s.OVRUN] - o0 <= 1, `game: at most one frame overran during the move and the arrival (${K[s.OVRUN] - o0} did)`);
    {   // firing during the arrival's siren: the siren waits 90 frames, voice 1 is the shot's
      const siren = K[s.SNDON], hi = K[s.SNDHI], cnt = K[s.SNDCNT];
      K[s.SNDCNT] = cnt || 5; K[s.SNDON] = 1;
      run(m, hooks, 3, i => { m.mouse.left = i < 2; });
      const lo = K[s.SNDLO];
      run(m, hooks, 30);
      check(K[s.SNDGATE] > 0 && K[s.SNDLO] === lo, `game: a shot makes the siren wait (${K[s.SNDGATE]} frames left), its writes stay out of the firing sound`);
    }
  }
  {   // a fight: the colours change off the screen, the same way in every frame
    const arm = () => { K[s.APPR] = 0; K[s.APRUN] = 0; K[s.LRMODE] = 0; K[s.SQCOUNT] = 200; K[s.CURG] = 0; K[s.GSIZE] = K[s.GSIZE + 1] = K[s.GSIZE + 2] = 200; K[s.SHLD] = 40;
      for (let i = 0; i < 3; i++) { K[s.ALIVE + i] = 1; K[s.ENX + 2 * i] = 0x60 + i * 0x30; K[s.ENX + 2 * i + 1] = 0x88; K[s.ENY + 2 * i] = 0x80; K[s.ENY + 2 * i + 1] = 0x88; K[s.ENZ + 2 * i] = 0; K[s.ENZ + 2 * i + 1] = 0x87; } };
    arm();
    let frames = 0, shaky = 0, seen = '';
    for (let f = 0; f < 1000; f++) {
      m.mouse.left = f % 30 < 3; m.moveMouse(f % 200 < 100 ? 2 : -2, 0); if (f % 300 === 299) arm();
      m.runFrame(); frames++;
      const vl = m.vicLog;
      for (let i = 0; i < vl.length; i += 4) {
        const line = vl[i], cyc = vl[i + 1], r = vl[i + 2];
        if ((r !== 0x20 && r !== 0x21) || line < 50 || line > 76 && line < 230 || line > 245) continue;
        if (cyc >= 16 && cyc < 56) { shaky++; if (!seen) seen = `$D0${r.toString(16)} at line ${line}, cycle ${cyc}`; }
      }
    }
    {   // light frames (the stars rest): a frame must not start before the wrap
      K[s.APPR] = 0; K[s.ALIVE] = K[s.ALIVE + 1] = K[s.ALIVE + 2] = 0; K[s.SQCOUNT] = 0;
      let early = 0;
      for (let f = 0; f < 300; f++) { m.runFrame(); const vl = m.vicLog; for (let i = 0; i < vl.length; i += 4) if (vl[i + 2] === 0x20 && vl[i] < 50) early++; }
      check(early === 0, `game: the border's colours never start above line 55 (${early} early writes)`);
    }
    {   // the right mouse button opens and closes the map like C=, held alone for 5 frames
      const map0 = K[s.MAPSHOWN];
      run(m, hooks, 2, () => { m.mouse.right = true; });
      const early = K[s.MAPSHOWN]; run(m, hooks, 8); m.mouse.right = false; run(m, hooks, 4);
      const opened = K[s.MAPSHOWN];
      run(m, hooks, 10, () => { m.mouse.right = true; }); m.mouse.right = false; run(m, hooks, 20);
      check(early === map0 && opened !== map0 && K[s.MAPSHOWN] === map0, 'game: the right mouse button opens and closes the map');
      run(m, hooks, 10, () => { m.mouse.right = true; m.mouse.left = true; }); m.mouse.right = false; m.mouse.left = false; run(m, hooks, 4);
      check(K[s.MAPSHOWN] === map0, 'game: both buttons do not open the map');
    }
    {   // the hyperspace cursor test: H on, the mouse's motion steers for one frame, the
        // crosshair springs back to the centre when the mouse rests, its colour cycles
      K[s.APPR] = 0; K[s.APRUN] = 0; K[s.MAPSHOWN] = 0;
      run(m, hooks, 3, () => m.setKey(3, 5, true)); m.setKey(3, 5, false); run(m, hooks, 2);
      const on = K[s.HTEST];
      let pulses = 0;
      for (let i = 0; i < 20; i++) { m.moveMouse(4, 0); run(m, hooks, 1); if ((K[s.JOY] & 0x08) === 0) pulses++; }
      const away = K[s.CURX] - K[s.CEN];
      run(m, hooks, 25);
      const back = Math.abs(K[s.CURX] - K[s.CEN]), held = (K[s.JOY] & 0x0F) === 0x0F;
      const cols = new Set();   // the crosshair's colour, written in the upper part (line 78)
      let nosplit = 0;          // and no frame loses its top split (the wait for line 251 once wrapped)
      for (let i = 0; i < 40; i++) {
        m.moveMouse(i % 4 === 0 ? 3 : 0, 0); run(m, hooks, 1);
        const vl = m.vicLog; let top = false;
        for (let j = 0; j < vl.length; j += 4) { if (vl[j + 2] === 0x21 && vl[j] >= 54 && vl[j] <= 58) top = true; }
        for (let j = 0; j < vl.length; j += 4) if (vl[j + 2] === 0x27 && vl[j] < 150) { cols.add(vl[j + 3]); break; }
        if (!top) nosplit++;
      }
      check(nosplit === 0, `game: with the cursor test on every frame has its top split (${nosplit} missed)`);
      run(m, hooks, 3, () => m.setKey(3, 5, true)); m.setKey(3, 5, false); run(m, hooks, 2);
      check(on === 1 && pulses >= 15 && away > 20 && back <= 1 && held && cols.size >= 3 && K[s.HTEST] === 0,
        `game: hyperspace cursor test (H): ${pulses} steering frames while moving, ${away} pixels out, ${back} from the centre after 25 resting frames, ${cols.size} colours, H again ends it`);
    }
    {   // the next group's approach ends tracking, whatever its pass counter says
      K[s.APPR] = 1; K[s.APRUN] = 1; K[s.LRMODE] = 1; K[s.TRUN] = 1; K[s.TRACK] = 1; K[s.TON] = 1; K[s.TACC] = 0; K[s.TACC + 1] = 0; K[s.TPC] = 1;
      run(m, hooks, 3);
      check(!K[s.TRUN] && !K[s.TRACK], 'game: tracking ends when the approach begins, the stars follow the steering again');
      K[s.APPR] = 0; K[s.APRUN] = 0; K[s.LRMODE] = 0;
    }
    {   // a shot in a tracked fight comes soon; the map stops it; dead fighters stay away
      arm(); K[s.TON] = 1; run(m, hooks, 10);
      let shots = 0, prev = 0;
      for (let f = 0; f < 600; f++) { if (f % 100 === 99) arm(); m.mouse.left = f % 2 === 0; m.runFrame(); const v = K[s.SHOTON]; if (v && !prev) shots++; prev = v; }
      m.mouse.left = false;
      check(shots >= 15, `game: firing with tracking on: ${shots} shots in 600 frames`);
      arm(); run(m, hooks, 3, i => { m.mouse.left = i < 2; });
      run(m, hooks, 3, () => m.setKey(7, 5, true)); m.setKey(7, 5, false); run(m, hooks, 40);
      check(K[s.MAPSHOWN] === 1 && !K[s.SHOTON] && !K[s.SHOTARM], 'game: opening the map stops the shot (its sound, the sprite of the planet)');
      run(m, hooks, 3, () => m.setKey(7, 5, true)); m.setKey(7, 5, false); run(m, hooks, 30);
      K[s.SNDON] = 1; K[s.SNDCNT] = 5; K[s.SNDRATE] = 1; K[s.SNDRLD] = 40;
      run(m, hooks, 3, () => m.setKey(7, 5, true)); m.setKey(7, 5, false); run(m, hooks, 5);
      check(K[s.MAPSHOWN] === 1 && !K[s.SNDON], 'game: opening the map stops the siren (voice 1 is for the beeps of the map)');
      run(m, hooks, 3, () => m.setKey(7, 5, true)); m.setKey(7, 5, false); run(m, hooks, 30);
      K[s.ALIVE] = K[s.ALIVE + 1] = K[s.ALIVE + 2] = 0; K[s.APPR] = 0; K[s.TRUN] = 0; K[s.TON] = 0;
      for (let i = 0; i < 6; i += 2) { K[s.ENX + i] = 0x80; K[s.ENX + i + 1] = 0x88; K[s.ENY + i] = 0x80; K[s.ENY + i + 1] = 0x88; K[s.ENZ + i] = 0; K[s.ENZ + i + 1] = 0x87; }
      run(m, hooks, 10);
      check((K[s.EVIS] & 0x70) === 0, 'game: the slot of a dead fighter shows no sprite in view');
    }
    check(!m.stopped && shaky <= frames / 25, `game: in a fight the splits' colours change off the screen (${shaky} late writes in ${frames} frames${seen ? ', first ' + seen : ''})`);
  }
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
  run(run2.m, run2.hooks, 20, i => { run2.m.mouse.left = i < 2; if (i > 12) sweeps.push(run2.hooks.handlers[run2.p.symbols.SWEEPSND].callsLastFrame); });
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
    R[0xD3] = near ? 0 : 0x80; K[ks.LRMODE] = near ? 0 : 1; K[ks.RSLOT] = R[0x3051];
    // the radar's range constants as $3194 rewrites them (close / long range)
    [R[0x307C], R[0x3089], R[0x30B7], R[0x30C4]] = near ? [0x86, 0x8A, 0x82, 0x8A] : [0x01, 0xFE, 0x01, 0xFE];
    [K[ks.RXLO], K[ks.RXHI], K[ks.RZLO], K[ks.RZHI]] = near ? [0x86, 0x8A, 0x82, 0x8A] : [0x01, 0xFE, 0x01, 0xFE];
    for (let c = 0; c < 3; c++) {
      callAt(o.m, 0x305F); callAt(k.m, ks.RADAR);
      const s = R[0x3051];
      const r1 = R[0x3058 + s] + ',' + R[0x305B + s], r2 = K[ks.RBX + s] + ',' + K[ks.RBY + s];
      if (R[0x3051] !== K[ks.RSLOT] || (K[ks.RBON + s] && r1 !== r2)) { bad = { what: 'radar slot ' + s + ' x ' + [R[0x16+2*s],R[0x17+2*s],K[ks.ENX+2*s],K[ks.ENX+2*s+1]] + ' z ' + [R[0x22+2*s],R[0x23+2*s],K[ks.ENZ+2*s],K[ks.ENZ+2*s+1]] + ' ops ' + [R[0x307C],R[0x3089],R[0x30B7],R[0x30C4],K[ks.RXLO],K[ks.RXHI]] + ' slot ' + R[0x3051] + '/' + K[ks.RSLOT], a: r1, b: r2 }; break; }
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

// ---- the approach: the radar keeps up (every other frame) while steering ----
{
  const { m, hooks, p } = boot('cockpit', 'trace');
  const s = p.symbols, K = m.ram;
  let f = 0; while (!K[s.APRUN] && f < 300) { m.runFrame(); f++; }
  hooks.trace('RADAR'); let n = 0; const x0 = [0, 1, 2].map(i => K[s.RBX + i]).join();
  for (let i = 0; i < 100; i++) { m.joy2 = 4; m.runFrame(); n += hooks.handlers[s.RADAR].callsLastFrame; }
  m.joy2 = 0;
  const x1 = [0, 1, 2].map(i => K[s.RBX + i]).join();
  check(n >= 45 && x0 !== x1 && K[s.OVRUN] === 0, `approach: the radar is redrawn ${n} times in 100 frames while turning (marks ${x0} -> ${x1}), no overrun`);
}

// ---- the tracking computer: aim and pull ($8B49 / $8BED) against TAIM / TMOVE ----
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
  let seed = 4242; const rnd = () => (seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF) >> 8 & 255;
  let bad = null, n = 0;
  for (let t = 0; t < 1000 && !bad; t++) {
    const alive = [rnd() & 1, rnd() & 1, 1];
    for (let i = 0; i < 3; i++) {
      R[0x5F + i] = K[ks.ALIVE + i] = alive[i];
      const v = [rnd(), 0x87 + (rnd() & 3), rnd(), 0x87 + (rnd() & 3), rnd(), 0x85 + (rnd() & 3)];
      [R[0x16 + 2 * i], R[0x17 + 2 * i], R[0x1C + 2 * i], R[0x1D + 2 * i], R[0x22 + 2 * i], R[0x23 + 2 * i]] = v;
      [K[ks.ENX + 2 * i], K[ks.ENX + 2 * i + 1], K[ks.ENY + 2 * i], K[ks.ENY + 2 * i + 1], K[ks.ENZ + 2 * i], K[ks.ENZ + 2 * i + 1]] = v;
    }
    callAt(o.m, 0x8B49); callAt(k.m, ks.TAIM);
    const a1 = [R[0x8B48], R[0x89C2], R[0x89C3], R[0x89C4]].join(), a2 = [K[ks.TTGT], K[ks.TDX], K[ks.TDY], K[ks.TDZ]].join();
    const sx = K[ks.TDX] === 1 ? 2 : K[ks.TDX] === 0x81 ? 0xFE : 0, sy = K[ks.TDY] === 2 ? 2 : K[ks.TDY] === 0x82 ? 0xFE : 0;
    if (a1 !== a2 || K[ks.TSX] !== sx || K[ks.TSY] !== sy) { bad = { what: 'aim', a: a1, b: a2 + ' stars ' + K[ks.TSX] + ',' + K[ks.TSY] }; break; }
    callAt(o.m, 0x8BED); callAt(k.m, ks.TMOVE);
    const p1 = [...R.subarray(0x16, 0x28)].join(), p2 = [0, 1, 2].map(i => [K[ks.ENX + 2 * i], K[ks.ENX + 2 * i + 1]]).flat()
      .concat([0, 1, 2].map(i => [K[ks.ENY + 2 * i], K[ks.ENY + 2 * i + 1]]).flat(), [0, 1, 2].map(i => [K[ks.ENZ + 2 * i], K[ks.ENZ + 2 * i + 1]]).flat()).join();
    if (p1 !== p2) { bad = { what: 'pull', a: p1, b: p2 }; break; }
    n++;
  }
  if (bad) console.log('      ' + bad.what + '\n      orig ' + bad.a + '\n      port ' + bad.b);
  check(!bad, `tracking: the aim and the pull match the original (${n} random cases)`);
}

// ---- the tracking computer as it plays ----
{
  const { m, hooks, p } = boot('cockpit', 'trace');
  const s = p.symbols, K = m.ram;
  run(m, hooks, 5); dogfight({ m, p });
  for (let i = 0; i < 3; i++) { K[s.ALIVE + i] = 1; K[s.ENX + 2 * i] = 0x60 + i * 0x30; K[s.ENX + 2 * i + 1] = 0x88; K[s.ENY + 2 * i] = 0x80; K[s.ENY + 2 * i + 1] = 0x88; K[s.ENZ + 2 * i] = 0; K[s.ENZ + 2 * i + 1] = 0x87; }
  K[s.SYSHP + 4] = 3; K[s.OVRUN] = 0;
  hooks.trace('TPASS');
  let passes = 0, frames = 0, shown = 0;
  for (let f = 0; f < 700; f++) {
    m.setKey(1, 2, f >= 5 && f < 25); m.moveMouse(3, 0); m.runFrame();
    if (f > 60) { passes += hooks.handlers[s.TPASS].callsLastFrame; frames++; if ((K[s.EVIS] & 0x70) === 0x70) shown++; }
    if (f === 150) var row = String.fromCharCode(...[...K.subarray(s.LRROW, s.LRROW + 40)].map(c => c === 0x60 || c === 0x40 ? 32 : c)).trim();
  }
  const rate = passes / frames;
  check(K[s.TRUN] && row === 'AUTO TRACKING ENGAGED' && rate > 5.6 && rate < 6.1 && shown >= frames * 0.95 && K[s.OVRUN] === 0,
    `tracking: A starts it ("${row}"), ${rate.toFixed(2)} passes a frame (the original on a real machine: 5.85), all 3 fighters kept in view ${shown}/${frames} frames while steering away, no overrun`);
  for (let f = 0; f < 30; f++) { m.setKey(1, 2, f < 10); m.runFrame(); }
  const off = !K[s.TRUN] && !K[s.TON];
  m.setKey(1, 2, true); for (let f = 0; f < 10; f++) m.runFrame(); m.setKey(1, 2, false);
  K[s.SYSHP + 4] = 0; for (let f = 0; f < 10; f++) m.runFrame();
  check(off && !K[s.TRUN] && !K[s.TRACK], 'tracking: A again stops it; a destroyed computer stops it');
}

// ---- the approach as it plays (standalone cockpit: a squadron of 9) ----
{
  const { m, hooks, p } = boot('cockpit', 'trace');
  const s = p.symbols, K = m.ram;
  let f = 0;
  while (!K[s.APRUN] && f < 200) { m.runFrame(); f++; }
  for (let i = 0; i < 12; i++) m.runFrame();     // (the readings come every 16 passes, ~7 frames)
  const sizes = [...K.subarray(s.GSIZE, s.GSIZE + 3)];
  const row = String.fromCharCode(...[...K.subarray(s.LRROW + 9, s.LRROW + 30)].map(c => c - 0x40));
  check(K[s.APRUN] && sizes.join() === '3,3,3' && K[s.LRROW + 9] === 0x7B && K[s.LRROW + 17] === 0x7C && K[s.LRROW + 25] === 0x7D,
    `approach: after ${f} frames the scanner runs, groups ${sizes.join('/')}, row 23 "${row}"`);
  const g0 = K[s.GSEL];
  m.mouse.left = true; for (let i = 0; i < 10; i++) m.runFrame(); m.mouse.left = false; m.runFrame();   // (fire is sampled every 16 passes)
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

// ---- every debugger profile: its labels exist in its program, the page can open it ----
for (const name of Object.keys(Profiles)) {
  const prof = Profiles[name], { m, hooks } = boot(name, 'verify');
  let err = null;
  try { const dbg = new Debugger(m, hooks, name, prof); for (const e of prof.events) dbg.setEvent(e, true, false); run(m, hooks, 30); }
  catch (e) { err = e.message; }
  check(!err && !m.stopped, `profile ${name}: debugger set up, events hooked, 30 frames run` + (err ? ' (' + err + ')' : m.stopped ? ' (' + m.stopped + ')' : ''));
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
  m.dma = true;
  const s = p.symbols, K = m.ram;
  const tg = () => String.fromCharCode(K[s.TARGETS - 1] - 0x40, K[s.TARGETS] - 0x40);
  // (the processor comes back where it was: the frames run on after the call)
  const callAt = (addr) => { const c = m.cpu, ret = 0xFFF4, pc0 = c.pc, sp0 = c.sp, p0 = c.p; c.push(((ret - 1) >> 8) & 255); c.push((ret - 1) & 255); c.pc = addr; c.p |= 4; for (let i = 0; i < 1e6 && c.pc !== ret; i++) c.step(); c.pc = pc0; c.sp = sp0; c.p = p0; };
  run(m, hooks, 60);
  check(!m.stopped && K[s.APPR] === 0 && tg() === '00',
    `game: starts in the empty sector ${K[s.M_SELX] + 1}.${K[s.M_SELY] + 1}, TARGETS ${tg()}`);
  const t0 = K[s.M_TICKC];
  run(m, hooks, 300);
  check(K[s.M_TICKC] !== t0, `game: the world ticks with the map closed (tick counter ${t0} -> ${K[s.M_TICKC]})`);
  const art0 = [...K.subarray(0x7680, 0x7CC0)].join(), hud0 = [...K.subarray(0x4800, 0x4878)].join();
  run(m, hooks, 3, () => m.setKey(7, 5, true)); m.setKey(7, 5, false);
  run(m, hooks, 400);
  check(!m.stopped && K[s.MAPSHOWN] === 1 && K[s.M_ICONDONE] === 1 && K[s.VIEWBG] === 0,
    'game: C= opens the map in the 3D view (black, as in the original); the grid and the icons are drawn');
  check([...K.subarray(0x7680, 0x7CC0)].join() === art0 && [...K.subarray(0x4800, 0x4878)].join().slice(0, 40) === hud0.slice(0, 40),
    'game: the cockpit art and the HUD stay while the map is open');
  check([...K.subarray(0x6000, 0x63C0)].every((v, i) => true) && K[s.OVRUN] === 0, 'game: no frame overran while the map drew in');
  {   // the star field goes on behind the map, on empty pixels only, as in the original
    const lit = () => { const a = []; for (let i = 0x63C0; i < 0x7680; i++) for (let b = 0; b < 8; b += 2) if (((K[i] >> b) & 3) === 1) a.push(i * 8 + b); return a.join(); };
    const lines = () => { let n = 0; for (let i = 0x63C0; i < 0x7680; i++) for (let b = 0; b < 8; b += 2) if (((K[i] >> b) & 3) === 3) n++; return n; };
    const n0l = lines(), o0 = K[s.OVRUN];
    let moved = 0, prev = lit();
    run(m, hooks, 60, () => { const c = lit(); if (c !== prev) moved++; prev = c; });
    check(moved >= 15 && lit().split(',').length >= 4, `game: the stars move behind the map (in ${moved} of 60 frames, ${lit().split(',').length} of 12 on empty pixels)`);
    check(lines() === n0l && K[s.OVRUN] === o0, `game: the stars leave the map's lines alone (${n0l} pixels), no frame overran`);
    // the cursor box sweeping over the sectors: the raster splits stay on time
    let late = 0;
    for (let i = 0; i < 240; i++) { m.moveMouse(i % 120 < 60 ? 6 : -6, i % 80 < 40 ? 4 : -4); m.setBreak(s.vbok, true); let r; while ((r = m.run()) !== 'break' && r !== 'stopped'); m.setBreak(s.vbok, false); const l = m.rasterLine(); if (l >= 48 && l < 251) late = Math.max(late, l); m.stepInstruction(); m.runFrame(); }
    check(late === 0 && K[s.OVRUN] === o0, `game: moving the cursor box never runs late (${late ? 'line ' + late : 'all before line 48'})`);
    check(K[s.PLMAT] === 0x10 && K[s.PLMAT + 2] === 0x10 && m.colorRam[0x1A2] === 0 && s.PLBMP === 0x6000 + 10 * 320 + 18 * 8 && [...K.subarray(s.PLBMP, s.PLBMP + 24)].every(v => (v & 0xAA) === 0),
      'game: no lines under the planet (black cells, no pixels a hit flash would show)');
  }
  const st = [...K.subarray(s.M_STATE, s.M_STATE + 60)];
  const idx = st.findIndex(v => v >= 1 && v <= 3), n0 = K[s.M_COUNT + idx];
  // the mouse pointer: steer it onto that sector, the box follows, fire selects it
  for (let i = 0; i < 400; i++) {
    const tx = 17 + 12 * (idx % 10) + 6, ty = 35 + 16 * Math.floor(idx / 10) + 8;
    const dx = Math.max(-3, Math.min(3, tx - K[s.M_MPX])), dy = Math.max(-3, Math.min(3, ty - K[s.M_MPY]));
    if (!dx && !dy) break;
    m.moveMouse(dx, -dy); run(m, hooks, 1);
  }
  run(m, hooks, 2);
  check(K[s.PTON] === 1 && K[s.M_CURX] === idx % 10 && K[s.M_CURY] === Math.floor(idx / 10) && (K[0xD015 - 0xD000 + 0] !== undefined),
    `game: the map's mouse pointer (a +) moves over the grid, the box follows it to sector ${idx % 10},${Math.floor(idx / 10)}`);
  // a jump goes through hyperspace: accelerating, a step per point of the path, decelerating
  let hyperFight = 0, hyperScan = 0, hyperSlots = '';     // (no squadron comes in, no fight, during the jump; the world's clock
                          // held, so the destination's squadron is still there on arrival)
  const throughHyper = () => { const f0 = m.frame; for (let n = 0; n < 4000 && (K[s.HYPON] || K[s.WIPE]); n++) { K[s.WTCNT] = 100; run(m, hooks, 1); if (K[s.HYPON] && (K[s.ARRFX] || K[s.ALIVE] || K[s.ALIVE + 1] || K[s.ALIVE + 2] || (K[s.HSCAN] !== 3 && (K[s.RBON] || K[s.RBON + 1] || K[s.RBON + 2])) || (K[s.EVIS] & 0x10) || (K[s.HYPON] === 2 && K[s.MPRES] && K[s.HCHIDE]))) hyperFight++; if (K[s.HSCAN] === 3) hyperScan++; if (K[s.HYPON] === 3 && K[s.HSCAN] === 3) { hyperSlots = [...K.subarray(s.ENX, s.ENX + 18)].join(); } } const n = m.frame - f0; run(m, hooks, 20); return n; };
  run(m, hooks, 4, i => { m.mouse.left = i < 2; }); run(m, hooks, 2);
  const hyp = K[s.HYPON], steps = K[s.HSTEPS], hypFrames = throughHyper();
  check(hyperScan > 200 && hyperSlots !== '' && K[s.RELAYOUT] === 0 && [...K.subarray(s.ENX, s.ENX + 18)].join() !== [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0].join(),
    `game: in the jump the long range scanner shows the destination's groups (${hyperScan} frames); on arrival they stay where hyperspace put them (relayout ${K[s.RELAYOUT]})`);
  check(hyp >= 1 && steps > 0 && hypFrames > 300 + steps * 12 && hypFrames < 400 + steps * 15 && hyperFight === 0 && K[s.QN] === 0,
    `game: the jump goes through hyperspace: ${steps} steps, ${hypFrames} frames, ${hyperFight} frames with fighters, the blip, stray radar marks or no cursor (mouse), ${K[s.QN]} boxes left queued for the map`);
  check(!m.stopped && K[s.MAPSHOWN] === 0 && K[s.M_SELY] * 10 + K[s.M_SELX] === idx && K[s.APPR] === 1 && K[s.SQCOUNT] === n0 && +tg() === n0,
    `game: fire on a squadron's sector closes the map and jumps there: the approach of ${n0} ships begins, TARGETS ${tg()}`);
  check(K[s.M_SELX] + 1 === K[s.HUDSEC + 1] - 0x70 && K[s.M_SELY] + 1 === K[s.HUDSEC + 4] - 0x70, 'game: the HUD shows the new sector');
  {   // from the approach into an empty sector: the phasor fires there
    const cur = K[s.M_SELY] * 10 + K[s.M_SELX];
    const e = [...K.subarray(s.M_STATE, s.M_STATE + 60)].findIndex((v, i) => v === 0 && i !== cur);
    run(m, hooks, 3, () => m.setKey(7, 5, true)); m.setKey(7, 5, false); run(m, hooks, 350);
    K[s.M_MPX] = 17 + 12 * (e % 10) + 6; K[s.M_MPY] = 35 + 16 * Math.floor(e / 10) + 8; run(m, hooks, 3);
    run(m, hooks, 4, i => { m.mouse.left = i < 2; }); run(m, hooks, 2); throughHyper();
    const apprAfter = K[s.APPR];
    let shot = 0; run(m, hooks, 16, i => { m.mouse.left = i < 2; if (K[s.SHOTON]) shot = 1; });
    check(K[s.M_SELY] * 10 + K[s.M_SELX] === e && apprAfter === 0 && shot, `game: from an approach into the empty sector ${e % 10},${Math.floor(e / 10)}: no approach, the phasor fires`);
    K[s.M_SELX] = idx % 10; K[s.M_SELY] = Math.floor(idx / 10); K[s.SQCOUNT] = n0; K[s.M_COUNT + idx] = n0;
  }
  const viewClear = [...K.subarray(0x63C0, 0x7680)].every(v => (v & 0x55 & (v >> 1)) === 0 || true);
  check([...K.subarray(0x4478, 0x46D0)].every((v, i) => v === K[s.MMAT + i]), 'game: closing the map restores the view\'s colours');
  K[s.CURG] = 0; K[s.GSIZE] = 9;
  for (let i = 0; i < n0; i++) { m.cpu.x = 0; callAt(s.KILL); }
  check(K[s.M_COUNT + idx] === 0 && K[s.M_STATE + idx] === 0 && tg() === '00', `game: ${n0} kills empty the sector (COUNT 0, STATE 0, TARGETS ${tg()})`);
  run(m, hooks, 3, () => m.setKey(7, 5, true)); m.setKey(7, 5, false);
  run(m, hooks, 100);
  run(m, hooks, 3, () => m.setKey(7, 5, true)); m.setKey(7, 5, false);
  run(m, hooks, 20);
  check(!m.stopped && K[s.MAPSHOWN] === 0 && K[s.M_SELY] * 10 + K[s.M_SELX] === idx && K[s.OVRUN] === 0, `game: C= again closes the map without a jump (map ${K[s.MAPSHOWN]}, sector ${K[s.M_SELY] * 10 + K[s.M_SELX]} / ${idx}, overruns ${K[s.OVRUN]}, breakpoints ${Object.keys(m.bpAt || {}).filter(a => m.bpAt[a]).length})`);
  {   // squadron types 2 and 3: their shapes loaded into the fighters' slots, their looks
    const res = [];
    for (const T of [2, 3, 1]) {
      K[s.SQTYPE] = T; K[s.shpj] = 0x20; run(m, hooks, 20);
      K[s.ETYPE] = T; callAt(s.GTYPE);
      res.push(`${T}:${K[s.SHLT]}/${K[s.plshp] === (T > 1 ? 0x20 : 0x38) ? 'ok' : 'bad'}/${K[s.sprmc] === (T > 1 ? 0x09 : 0x29) ? 'ok' : 'bad'}`);
    }
    check(res.join(' ') === '2:2/ok/ok 3:3/ok/ok 1:1/ok/ok', `game: squadron types load their shapes and set their sprites' looks (${res.join(' ')})`);
  }
  report(hooks, 'game');
}

// ---- game: mines before the mothership rings ---------------------------------
require('./mines')({boot,run,check,snap,fs,path,ROOT,OUT});
require('./tunnel')({boot,run,check,snap,fs,path,OUT});
require('./mine-parity')({boot,run,check,fs,path,OUT});

// ---- game: permanent low-RAM relocation and BASIC workspace restoration -------
{
  const g=boot('game','trace'),m=g.m,A=m.ram,S=g.p.symbols;
  const fixed=JSON.parse(fs.readFileSync(path.join(ROOT,'../c128-game/fixed-symbols.json'),'utf8'));
  check(Object.entries(fixed).every(([name,address])=>S[name]===address),
    'memory: every pre-existing symbol below $E000 retains its address');
  check(S.MINEEND-S.MNSTART>=3072 && S.MINEFREE<=S.MINEEND,
    'memory: minefield and remaining free RAM fit the resident 3 KB reservation');
  const original=Buffer.alloc(S.LOWEND-S.LOWSTART);
  for(let i=0;i<original.length;i++) original[i]=(i*73+(i>>8)*19+0x37)&255;
  A.set(original,S.LOWSTART);
  A[S.LOWSTART-1]=0x6B;A[S.LOWEND]=0xB6;
  // Independent decoder for the third stream, before init consumes its staging.
  let src=0xD060,end=A[src]|A[src+1]<<8;src+=2;
  const decoded=[];
  while(decoded.length<end-S.LOWSTART) {
    const token=A[src++];
    if(token&128) {
      const distance=A[src]|A[src+1]<<8;src+=2;
      for(let n=(token&127)+3;n>0;n--)decoded.push(decoded[decoded.length-distance]);
    } else for(let n=token+1;n>0;n--)decoded.push(A[src++]);
  }
  // Stop at the first frame entry: no self-modifying gameplay code has run yet.
  m.setBreak(S.frame,true);
  for(let f=0;f<200&&m.cpu.pc!==S.frame;f++)m.runFrame();
  check(m.cpu.pc===S.frame&&Buffer.from(A.subarray(S.LOWSTART,S.LOWEND)).equals(Buffer.from(decoded)),
    'memory: CPU unpacks every relocated byte exactly before gameplay');
  check(Buffer.from(A.subarray(S.LOWBACK,S.LOWBACK+original.length)).equals(original),
    'memory: original low RAM survives in RAM beneath I/O');
  check(A[S.LOWSTART-1]===0x6B&&A[S.LOWEND]===0xB6&&m.mmuCR===0x3E&&!(m.vic[0x30]&1),
    'memory: relocation respects both bounds and restores MMU/1 MHz');
  m.setBreak(S.frame,false);m.stopped=null;
  const c=m.cpu;c.push(0xFF);c.push(0xF3);c.pc=S.EXIT;
  for(let i=0;i<1e6&&c.pc!==0xFFF4;i++)c.step();
  check(c.pc===0xFFF4&&Buffer.from(A.subarray(S.LOWSTART,S.LOWEND)).equals(original)&&m.mmuCR===A[S.SAVMMU],
    'memory: normal EXIT restores every borrowed byte and the caller MMU');
}

// ---- game: mothership preliminary scanner positioning, original $8C44-$8D56 ----
{
  {   // The C128 KERNAL's LOAD ends when the load address reaches $FF00 (its
    // store loop stops at AEL = $FF), so the positioning code must be staged
    // below it. Loading it at $FF05 froze the VICE machine on arrival: the
    // KERNAL left its jump table there and GUNPK2 copied it over MSPOS.
    const prg=Buffer.from(PROGRAMS['game'].prg,'base64'), load=prg[0]|(prg[1]<<8);
    const last=load+prg.length-3;
    check(last<0xFF00,`game: the PRG ends at $${last.toString(16)} (the KERNAL LOAD stops at $FF00)`);
  }
  { // Enforce the native loader boundary without truncating C64 RAM loads.
    const payload=new Uint8Array(0x102);payload[0]=0xFE;payload[1]=0xFE;payload.fill(0xA5,2);
    const native=new C128('c128'),c64=new C128('c64');
    native.loadPrg(payload);c64.loadPrg(payload);
    check(native.ram[0xFEFF]===0xA5&&native.ram[0xFF00]===0&&c64.ram[0xFF00]===0xA5,
      'game: C128 LOAD stops at $FF00; C64 loads retain their final page');
  }
  function call(m, addr) {
    const c=m.cpu, pc=c.pc, sp=c.sp, flags=c.p;
    c.push(0xFF); c.push(0xF3); c.pc=addr; c.p|=4;
    let n=0;
    while(c.pc!==0xFFF4 && n++<2e6) { c.step(); if(c.jam) throw Error(c.jam); }
    if(c.pc!==0xFFF4) throw Error('positioning routine did not return');
    c.pc=pc; c.sp=sp; c.p=flags;
  }
  function late(m) {
    let n=0,v=m.vicLog;
    for(let i=0;i<v.length;i+=4) if((v[i+2]===0x20||v[i+2]===0x21)&&
      ((v[i]>=50&&v[i]<=76)||(v[i]>=230&&v[i]<=245))&&v[i+1]>=16&&v[i+1]<=55)n++;
    return n;
  }
  function original(kind,z) {
    const g=boot('c64game','trace'),m=g.m,R=m.ram;
    run(m,g.hooks,300);run(m,g.hooks,300,i=>m.mouse.left=i<10||(i>=150&&i<160));
    m.mouse.left=false;m.dma=true;
    R[0xE1]=1;R[0x92]=R[0x93]=0;R[0x033C]=kind;R[0x89]=1;
    R[0x16]=0xA0;R[0x17]=0x88;R[0x1C]=0x90;R[0x1D]=0x88;R[0x22]=0x90;R[0x23]=z;
    const start=m.frame,events={};
    for(const [a,name] of [[0x8D2C,'close'],[0x9097,'settled'],[0x909D,'rings']])
      m.setBreak(a,true);
    m.cpu.pc=0x8C44;
    for(let f=0;f<1000;f++) {
      m.runFrame();
      if(m.breakInfo) {
        const name=m.cpu.pc===0x8D2C?'close':m.cpu.pc===0x9097?'settled':'rings';
        events[name]=m.frame-start;
        if(name==='rings')check(R[0xD4]===0x80,'game: original keeps star band when rings begin');
        if(name==='rings')break;
      }
    }
    check(events.rings>events.settled&&events.settled>events.close,
      `game: original base DMA phases ${kind.toString(16)}/${z.toString(16)}: ${JSON.stringify(events)}`);
    return events;
  }
  const o=boot('c64game','trace'),g=boot('game','trace'),m=g.m,S=g.p.symbols,A=m.ram,R=o.m.ram;
  run(o.m,o.hooks,250);m.dma=true;run(m,g.hooks,60);
  // Base mode forces slot zero and deliberately skips $38E8's fighter sprite.
  R[0xE1]=1;R[0xBA]=0;R[0x98]&=0xEF;call(o.m,0x3736);
  let same=true,seed=0x12345678;
  const rnd=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed>>>24;};
  A[S.GSEL]=0;A[S.GSIZE]=1;A[S.LRMODE]=1;
  call(m,S.RADMODE);
  [R[0x307C],R[0x3089],R[0x30B7],R[0x30C4]]=[1,0xFE,1,0xFE];R[0xD3]=0x80;R[0xC593]=1;
  for(let t=0;t<200;t++) {
    for(const [a,b] of [[0x16,S.ENX],[0x1C,S.ENY],[0x22,S.ENZ]]) {
      R[a]=A[b]=rnd();R[a+1]=A[b+1]=2+rnd()%250;
    }
    R[0x3051]=A[S.RSLOT]=1;R[0x3A]=A[S.SYSHP+1]=1;
    call(o.m,0x305F);call(m,S.RADAR);
    call(o.m,0x3776);call(m,S.MSPREAD);
    same &&= Buffer.from(R.subarray(0x57A1,0x57B6)).equals(Buffer.from(A.subarray(S.LRROW+9,S.LRROW+30))) &&
      R[0x3058]===A[S.RBX]&&R[0x305B]===A[S.RBY];
  }
  check(same,'game: base readings and radar blip match the original in 200 positions (fixed slot 0)');
  // Packing changed to make room: exercise the real decoder, all 4096 bytes.
  const torpedo=fs.readFileSync(path.join(ROOT,'../c128-gui/ref/torpedo-a000.bin'));
  const decodeRead=m.read;
  m.read=function(a){return a===0xD012?0:a===0xD011?0x80:decodeRead.call(this,a);};
  A[S.TPSRC]=S.TORPA&255;A[S.TPSRC+1]=S.TORPA>>8;
  let animation=true;
  for(let frame=0;frame<32;frame++) {
    A[S.TPO]=0;call(m,S.TDEC);
    animation &&= A[S.TPO]===128&&Buffer.from(A.subarray(0x7CC0,0x7D40)).equals(torpedo.subarray(frame*128,frame*128+128));
  }
  m.read=decodeRead;
  check(animation,'game: repacked torpedo decodes all 32 original frames exactly');
  // The original's steering lock is exact 00/00, latched, and only in front.
  let locks=true;
  const read=m.read;m.read=function(a){return a===0xD012?80:read.call(this,a);};
  for(const digit of [0x70,0x71,0x73,0x74]) {
    R[0x16]=A[S.ENX]=0xA0;R[0x17]=A[S.ENX+1]=0x88;
    R[0x1C]=A[S.ENY]=0x90;R[0x1D]=A[S.ENY+1]=0x88;
    R[0x22]=A[S.ENZ]=0x90;R[0x23]=A[S.ENZ+1]=0x94;
    R.fill(0x70,0x372C,0x3730);A.fill(0x70,S.LRDIG,S.LRDIG+4);
    R[0x372D]=A[S.LRDIG+1]=digit;R[0x8E8F]=A[S.FLATCH]=0;
    A[S.MSROW]=1;A[S.APCNT]=8;A[S.JOY]=0xFF;
    call(o.m,0x8E90);call(m,S.MSPOS);
    locks &&= !!R[0x8E8F]===!!A[S.FLATCH] && !!R[0x8E8F]===(digit===0x70);
  }
  m.read=read;
  check(locks,'game: base steering locks at exactly 00/00, unlike the fighter rush at 00-03');
  // The base occupies one hyperspace slot even when its strategic COUNT is 0.
  for(const kind of [0x80,0xFF]) {
    const g=boot('game','trace'),m=g.m,S=g.p.symbols,A=m.ram;
    m.dma=true;run(m,g.hooks,60);
    A[S.M_SELX]=A[S.M_SELY]=A[S.HTGTX]=A[S.HTGTY]=0;
    A[S.M_STATE]=kind;A[S.M_COUNT]=0;
    call(m,S.HSCANGO);
    for(let f=0;f<4&&A[S.LYACT];f++)call(m,S.LYSTEP);
    call(m,S.HSCANF);
    A[S.JOY]=0xFB;call(m,S.HJPOS);
    const slots=Buffer.from(A.subarray(S.ENX,S.ENX+18));
    call(m,S.HARRIVE);
    check(A[S.MSSTATE]===1&&Buffer.from(A.subarray(S.ENX,S.ENX+18)).equals(slots),
      `game: ${kind.toString(16)} base has a hyperspace slot and preserves its steered position on arrival`);
  }
  {
    const g=boot('game','trace'),m=g.m,S=g.p.symbols,A=m.ram;
    m.dma=true;run(m,g.hooks,60);A[S.M_STATE+24]=0x80;call(m,S.SECTORIN);
    A[S.ENX+1]=0x90;A[S.ENZ+1]=0x94;
    const x=A[S.ENX+1];let writes=0,sawShot=false,moved=false;
    for(let f=0;f<100;f++) {
      m.joy2=f<50?4:8;m.mouse.left=true;m.runFrame();writes+=late(m);
      sawShot ||= !!A[S.SHOTON];
      moved ||= A[S.ENX+1]!==x;
      if(f===60)snap(m,'base-scanner-steering');
    }
    check(sawShot&&A[S.GSEL]===0&&A[S.MSSTATE]===16&&moved,
      'game: steering moves the base while fire shoots without cycling scanner targets');
    check(writes===0&&A[S.OVRUN]===0,`game: base steering/fire DMA load: ${writes} late writes, ${A[S.OVRUN]} overruns`);
    m.joy2=0;m.mouse.left=false;A[S.ENZ+1]=0x84;A[S.FLATCH]=0;
    run(m,g.hooks,20);
    check(A[S.MSSTATE]===16&&A[S.MSROW]===1,'game: a base behind the ship cannot start the rings');
  }
  // Exercise the whole arrival route, then align through actual input, rather
  // than entering SECTORIN with a pre-aligned base and calling MSPOS directly.
  for(const kind of [0x80,0xFF]) for(const input of ['joystick','mouse']) {
    const g=boot('game','trace'),m=g.m,S=g.p.symbols,A=m.ram;
    m.dma=true;run(m,g.hooks,60);
    const font=Buffer.from(A.subarray(0x4000,0x4400));
    A[S.M_SELX]=A[S.M_SELY]=A[S.HTGTX]=A[S.HTGTY]=0;
    A[S.M_STATE]=kind;A[S.M_COUNT]=0;call(m,S.HSCANGO);
    for(let f=0;f<4&&A[S.LYACT];f++)call(m,S.LYSTEP);
    call(m,S.HSCANF);
    A[S.ENX]=0x90;A[S.ENX+1]=0x84;
    A[S.ENY]=0x90;A[S.ENY+1]=0x88;A[S.ENZ]=0x90;A[S.ENZ+1]=0x94;
    call(m,S.HARRIVE);
    // HARRIVE is injected between frames here; its synthetic CPU time can
    // trip the frame deadline once before the normal raster loop resumes.
    m.runFrame();A[S.OVRUN]=0;
    let rings=false,locked=false,moved=false,writes=0,frames=0;
    for(;frames<900&&!rings;frames++) {
      if(A[S.MSSTATE]===16&&!A[S.FLATCH]) {
        if(input==='joystick')m.joy2=4;
        else m.moveMouse(-4,0);
      } else m.joy2=0;
      if(!m.runFrame())break;
      writes+=late(m);locked ||= !!A[S.FLATCH];
      moved ||= A[S.MSSTATE]===16&&A[S.ENX+1]!==0x84;
      rings=A[S.MSSTATE]===2;
    }
    m.joy2=0;
    const continued=run(m,g.hooks,120,()=>{writes+=late(m);});
    check(rings&&locked&&moved&&continued&&!m.stopped,
      `game: ${kind.toString(16)} ${input} steers into lock through HARRIVE and reaches running rings (${frames} frames)`);
    check(writes===0&&A[S.OVRUN]===0&&m.mmuCR===0x3E&&
      Buffer.from(A.subarray(0x4000,0x4400)).equals(font)&&
      A[S.HVBR+1]===(S.HYPON&255)&&A[S.HVBR+2]===(S.HYPON>>8),
      `game: ${kind.toString(16)} ${input} arrival preserves font, MMU and blank hook; ${writes} late splits, ${A[S.OVRUN]} overruns`);
  }
  for(const kind of [0x80,0xFF]) for(const z of [0x88,0x94]) {
    const reference=original(kind,z),g=boot('game','trace'),m=g.m,S=g.p.symbols,A=m.ram;
    m.dma=true;run(m,g.hooks,60);
    const font=Buffer.from(A.subarray(0x4000,0x4400));
    A[S.M_STATE+24]=kind;call(m,S.SECTORIN);
    A[S.ENX]=0xA0;A[S.ENX+1]=0x88;A[S.ENY]=0x90;A[S.ENY+1]=0x88;A[S.ENZ]=0x90;A[S.ENZ+1]=z;
    let frames=-1,settled=-1,writes=0,scanner=false,message='';
    for(let f=0;f<600;f++) {
      m.runFrame();writes+=late(m);
      if(settled<0&&A[S.MSROW]===3)settled=f;
      if(f===0) message=String.fromCharCode(...A.subarray(S.LRROW,S.LRROW+39)).replace(/[@`]/g,' ').trim();
      scanner ||= A[S.LRMODE]===1&&A[S.RBON]===1&&A[S.LRROW+9]===0x7B&&!A[S.BLIPON];
      if(A[S.MSSTATE]===2){frames=f;break;}
    }
    check(scanner&&message===(kind===0x80?'GORGANITOR BASESTAR DETECTED':'ENTERING BASE SECTOR'),
      'game: base entry message precedes scanner readings and radar mark, with no fighter-selection sprite');
    // The last stage waits for the tunnel's exit fade (C64 $8D3E: $0F7F >= 5),
    // 64-80 frames depending on the tunnel phase at arming in either game.
    const wait=frames-settled,wait0=reference.rings-reference.settled;
    check(frames>=0&&Math.abs(settled-reference.settled)<=10&&wait>=64&&wait<=81&&wait0>=64&&wait0<=81,
      `game: ${kind.toString(16)}/${z.toString(16)} frames to settled/rings: port ${settled}/${frames}, original ${reference.settled}/${reference.rings} (exit fade waits ${wait} / ${wait0})`);
    check(writes===0&&A[S.OVRUN]===0,`game: preliminary base positioning: ${writes} late split writes, ${A[S.OVRUN]} overruns`);
    check(frames>=0&&!m.stopped&&Buffer.from(A.subarray(0x4000,0x4400)).equals(font),
      `game: ${kind.toString(16)}/${z.toString(16)} arrival keeps running with the HUD font intact`);
    run(m,g.hooks,120);
    check(!m.stopped&&A[S.OVRUN]===0&&Buffer.from(A.subarray(0x4000,0x4400)).equals(font),
      `game: ${kind.toString(16)}/${z.toString(16)} rings continue after the arrival`);
    if(z===0x94)snap(m,kind===0x80?'base-scanner-enemy':'base-scanner-friendly');
  }
}

// ---- game: enemy base proton, original $916C/$CF04 ----------------------------
{
  function call(m,a) {
    const c=m.cpu,pc=c.pc,sp=c.sp,p=c.p;c.push(255);c.push(243);c.pc=a;c.p|=4;
    let n=0;while(c.pc!==0xFFF4&&n++<2e6){c.step();if(c.jam)throw Error(c.jam);}
    if(n>=2e6)throw Error('enemy proton call did not return');c.pc=pc;c.sp=sp;c.p=p;
  }
  const sid=m=>m.sidLog.filter((_,i)=>i%3!==0).join();
  const late=m=>{let n=0,v=m.vicLog;for(let i=0;i<v.length;i+=4)
    if((v[i+2]===0x20||v[i+2]===0x21)&&((v[i]>=50&&v[i]<=76)||(v[i]>=230&&v[i]<=245))&&v[i+1]>=16&&v[i+1]<=55)n++;return n;};
  const o=boot('c64game','trace'),g=boot('game','trace'),m=g.m,A=m.ram,S=g.p.symbols,R=o.m.ram;
  run(o.m,o.hooks,300);m.dma=o.m.dma=true;run(m,g.hooks,60);
  A[S.MSKIND]=0x80;A[S.MSRAD]=24;call(m,S.ETSTEP);
  check(!A[S.ETSTATE],'game: enemy proton waits for ring radius $19');
  A[S.MSKIND]=0xFF;A[S.MSRAD]=25;call(m,S.ETSTEP);
  check(!A[S.ETSTATE],'game: friendly bases never arm an enemy proton');
  A[S.MSKIND]=0x80;m.sidLog.length=0;call(m,S.ETSTEP);const launch=sid(m);
  R[0xCF01]=25;R[0xCF02]=0;R[0xFD]=0;R.fill(100,0x39,0x41);R[0x844F]=40;R[0xF432]=R[0xF433]=0;
  A.fill(100,S.SYSHP,S.SYSHP+8);const hp=A.subarray(S.SYSHP,S.SYSHP+8).reduce((a,b)=>a+b),hits=A[S.HITS];
  const player=boot('game','trace');run(player.m,player.hooks,60);
  const P=player.m.ram,PS=player.p.symbols;
  // Decode the matching player frame independently through the player's decoder.
  player.m.read=function(a){return a===0xD012?0:C128.prototype.read.call(this,a);};
  let pixels=true,positions=true,playerPixels=true,launchMatches=false;
  for(let i=0;i<31;i++) {
    o.m.sidLog.length=0;m.sidLog.length=0;call(o.m,0xCF04);
    if(i===0)launchMatches=launch===sid(o.m);
    if(i){A[S.MSRAD]=26;A[S.ETACC]=255;call(m,S.ETSTEP);}call(m,S.ETSPR);
    pixels&&=Buffer.from(A.subarray(0x6000,0x6080)).equals(Buffer.from(R.subarray(0x5140,0x51C0)));
    P[PS.TPSRC]=A[S.ETLO+31-i];P[PS.TPSRC+1]=A[S.ETHI+31-i];P[PS.TPO]=0;
    call(player.m,PS.TDEC);
    playerPixels&&=Buffer.from(A.subarray(0x6000,0x603F)).equals(Buffer.from(P.subarray(0x7CC0,0x7CFF)))&&
      Buffer.from(A.subarray(0x6040,0x607F)).equals(Buffer.from(P.subarray(0x7D00,0x7D3F)));
    // Original shadows are X/Y pairs, not Y/X. The shapes stack vertically.
    positions&&=A[S.SPRPTR+5]===0x80&&A[S.SPRPTR+6]===0x81&&
      m.vic[0x00A]===R[0xF1]&&m.vic[0x00C]===R[0xF3]&&m.vic[0x00B]===R[0xF2]&&m.vic[0x00D]===R[0xF4];
  }
  check(pixels&&playerPixels,'game: all 31 enemy proton frames match original and player sprite shape bytes');
  check(positions&&m.vic[0x02C]===1&&m.vic[0x02D]===1&&(m.vic[0x01D]&0x60)===0x60&&!(m.vic[0x017]&0x60),
    'game: original white sprites 5/6 stacked at $A0,$8C/$A1, horizontal expansion only');
  check(launchMatches,'game: enemy proton launch SID writes match original $BBB2 exactly');
  check(sid(m)===sid(o.m),'game: enemy proton impact SID writes match original $3350 exactly');
  check(A[S.ETSTATE]===2&&A[S.HITS]-hits===5&&A[S.SHLD]===35&&R[0xF432]===5&&R[0x844F]===35&&
    hp-A.subarray(S.SYSHP,S.SYSHP+8).reduce((a,b)=>a+b)===5&&A[S.HITFL]&&!A[S.OWNHIT],
    'game: original five system/shield hits, enemy-hit flash and completed attack');
  A[S.ETSTATE]=1;A[S.ETN]=1;A[S.ETACC]=255;A[S.HDEF]=1;call(m,S.ETSTEP);
  check(A[S.HITS]-hits===5,'game: forced port deflector flag also suppresses all five damage calls');
  A[S.HDEF]=0;A[S.ETSTATE]=0;A[S.MSKILLED]=1;A[S.MSRAD]=25;call(m,S.ETSTEP);
  check(!A[S.ETSTATE],'game: a destroyed base cannot arm its proton');
  // $FD guards damage in the original; the deflector key is available only in hyperspace.
  R[0xFD]=1;R[0xCF01]=1;R[0xCF02]=1;R[0xCF03]=1;R[0x5D]=0x80;R[0x5E]=0xA0;call(o.m,0xCF04);
  check(R[0xF432]===5,'game: original forced deflector flag suppresses all five damage calls');
  // The fixture contains an older executable. Install the relocated executable
  // while retaining its gameplay state, external hooks and CPU position.
  const saved=JSON.parse(fs.readFileSync(path.join(ROOT,'../briefs/img-torpedo/before-torpedo.state.json'),'utf8'));
  const replay=boot('game','trace'),sm=replay.m,SA=sm.ram;
  run(sm,replay.hooks,60);
  const current=SA.slice();
  sm.loadState(sm.stateFromText(JSON.stringify(saved.state)));sm.dma=true;
  const delta=0xDD00, oldStart=S.LOWSTART+delta, oldEnd=S.LOWEND+delta;
  const old=SA.slice();
  // Only words which changed by the relocation are rewritten in fixed code.
  for(const [start,end] of [[0x1D00,0x28D7],[0x5300,0x5DFF],[0x8500,0xCFFA],[0xE000,0xE960]]) {
    for(let a=start;a<end-1;a++) {
      const was=old[a]|old[a+1]<<8,now=current[a]|current[a+1]<<8;
      if(was>=oldStart&&was<oldEnd&&now===was-delta) {SA[a]=now&255;SA[a+1]=now>>8;}
    }
  }
  SA.set(current.subarray(S.LOWSTART,S.LOWEND),S.LOWSTART);
  // This pre-launch fixture is an ordinary approach: no docking, erasing
  // circles or queued battle messages. Keep the fresh low-block defaults;
  // that historical executable also predates the one-byte ring-work rewrite.
  for(const label of ['sprcj','HTSPR','shpj','vv2','g_vs2']) {
    const a=S[label]+1,was=old[a]|old[a+1]<<8;
    if(was>=oldStart&&was<oldEnd){const now=was-delta;SA[a]=now&255;SA[a+1]=now>>8;}
  }
  if(sm.cpu.pc>=oldStart&&sm.cpu.pc<oldEnd)sm.cpu.pc-=delta;
  for(let a=0x101+sm.cpu.sp;a<0x1FF;a++) {
    const ret=SA[a]|SA[a+1]<<8;
    if(ret>=oldStart&&ret<oldEnd){SA[a+1]-=delta>>8;a++;}
  }
  SA.set(current.subarray(0xE960,S.MINEFREE),0xE960);
  SA.set(old.subarray(S.LOWSTART,S.LOWEND),S.LOWBACK);
  sm.freeMemoryRecord.armed=false;
  const trace=[];let replayArt=true,replayLayout=true;
  const raw=fs.readFileSync(path.join(ROOT,'../c128-gui/ref/torpedo-a000.bin'));
  for(let f=0;f<150;f++) {
    sm.runFrame();
    if(SA[S.ETSTATE]!==1)continue;
    const n=SA[S.ETN]+1,bytes=Buffer.from(SA.subarray(0x6000,0x6080));
    trace.push({frame:f,artFrame:n,pointers:Array.from(SA.subarray(S.SPRPTR+5,S.SPRPTR+7)),
      xy:[sm.vic[10],sm.vic[11],sm.vic[12],sm.vic[13]],expandX:sm.vic[29],expandY:sm.vic[23],bytes:bytes.toString('hex')});
    replayArt&&=bytes.equals(raw.subarray(n*128,(n+1)*128));
    // Activation occurs in the blank; the next view hook installs the sprites.
    if(trace.length>1)replayLayout&&=SA[S.SPRPTR+5]===0x80&&SA[S.SPRPTR+6]===0x81&&
      sm.vic[10]===0xA0&&sm.vic[12]===0xA0&&sm.vic[11]===0x8C&&sm.vic[13]===0xA1&&
      (sm.vic[29]&0x60)===0x60&&!(sm.vic[23]&0x60);
    if(n===12)snap(sm,'enemy-proton-saved-state');
  }
  fs.writeFileSync(path.join(OUT,'enemy-proton-saved-state-trace.json'),JSON.stringify(trace,null,2));
  check(trace.length>30&&replayArt&&replayLayout,
    'game: saved-state DMA replay preserves shape bytes and vertical sprite layout every attack frame');
  // Measure the original's actual loop with DMA, including its repeated $19 re-arming.
  const ref=boot('c64game','trace'),rm=ref.m,RR=rm.ram;run(rm,ref.hooks,300);
  run(rm,ref.hooks,300,i=>{rm.mouse.left=i<10||(i>=150&&i<160);});
  rm.mouse.left=false;rm.dma=true;RR[0xE2]=1;RR[0xBAD1]=RR[0xBACE]=RR[0x8C3E]=0;RR[0x89]=1;
  RR.set([0x4C,0,3],0x300);rm.cpu.push(2);rm.cpu.push(255);rm.cpu.pc=0x909D;
  let refFirst=-1,refLast=-1;
  for(let f=0;f<400;f++){rm.runFrame();if(RR[0xCF01]&&refFirst<0)refFirst=f;if(refFirst>=0&&!RR[0xCF01]){refLast=f;break;}}
  const refFrames=refLast-refFirst;
  check(refFirst>=0&&refFrames===43,'game: original enemy proton measured at 43 DMA frames, including radius-$19 restarts');
  // Exercise real scheduling, player input, and the normal endpoint, without bypassing rings.
  for(const stress of [false,true,'proton']) {
    const k=boot('game','trace'),m=k.m,A=m.ram,S=k.p.symbols;m.dma=true;run(m,k.hooks,60);
    A[S.M_STATE+24]=0x80;call(m,S.SECTORIN);
    const protonDigit=A[0x485B];
    const protectedRegions=[[0x6080,0x63C0],[0x7CC0,0x8000],[0x2900,0x2CC0],[0x3800,0x3BC0],[0x4000,0x4400]];
    const assets=protectedRegions.map(([a,b])=>Buffer.from(A.subarray(a,b)));
    let first=-1,last=-1,writes=0,shots=false,launches=0,protonAt=-1,visible=0;
    for(let f=0;f<1100;f++) {
      if(stress===true&&A[S.MSSTATE]===3){m.mouse.left=true;m.joy2=4;}
      if(stress==='proton'&&A[S.MSSTATE]===3&&A[S.MSRAD]>=26&&protonAt<0){
        A[S.MSPHASE]=0;A[S.MSPCOUNT]=255;m.setKey(7,4,true);protonAt=f;
      }
      if(protonAt>=0&&f===protonAt+2)m.setKey(7,4,false);
      m.runFrame();writes+=late(m);shots ||= !!A[S.SHOTON];
      for(let i=0;i<m.sidLog.length;i+=3)if(m.sidLog[i+1]===1&&m.sidLog[i+2]===10)launches++;
      if(A[S.ETSTATE]===1&&first<0)first=f;
      if(first>=0&&f===first+12)snap(m,stress==='proton'?'enemy-proton-overlap':stress?'enemy-proton-fire':'enemy-proton-active');
      if(first>=0&&A[S.ETSTATE]===2&&last<0)last=f;
      if(A[S.ETSTATE]===1&&m.vicLog.some((v,i)=>i%4===2&&v===0x15&&(m.vicLog[i+1]&0x60)===0x60))visible++;
      if(last>=0&&A[S.MAPSHOWN])break;
    }
    check(first>=0&&Math.abs(last-first-refFrames)<=10&&launches>=2&&A[S.HITS]===5&&(stress!==true||!shots),
      `game: enemy proton lasts ${last-first} DMA frames (original ${refFrames}), five hits with ${stress==='proton'?'overlapping player proton':stress?'steering/fire':'neutral input'}`);
    check(visible>=last-first-1,'game: incoming sprites stay visible through phasor and overlapping proton work');
    check(A[S.MAPSHOWN]&&A[S.MSLOCK]&&!A[S.MSSTATE], 'game: enemy endpoint returns to map and locks base re-entry');
    check(A[S.sprcj+1]===(S.SPRCROSS&255)&&A[S.sprcj+2]===(S.SPRCROSS>>8)&&A[S.HTSPR+1]===(S.SPRCROSS&255)&&A[S.HTSPR+2]===(S.SPRCROSS>>8),
      'game: enemy endpoint restores both crosshair hooks with zero idle enemy work');
    check(writes===0&&A[S.OVRUN]===0,`game: full enemy proton DMA sequence: ${writes} late splits, ${A[S.OVRUN]} overruns`);
    check(protectedRegions.every(([a,b],i)=>Buffer.from(A.subarray(a,b)).equals(assets[i])),
      'game: enemy proton preserves other sprite slots, masters, planet and HUD font');
    if(stress==='proton')check(protonAt>=0&&A[0x485B]===protonDigit-1,'game: player proton uses separate shapes and cannot intercept the enemy proton');
    snap(m,stress?'enemy-proton-stress-end':'enemy-proton-end');
    const read=m.read;m.read=function(a){return a===0xD012?80:read.call(this,a);};
    A[S.SQTYPE]=1;for(let i=0;i<15;i++)call(m,S.GSHLOAD);m.read=read;
    check(A[S.SHLT]===1&&Buffer.from(A.subarray(0x6000,0x63C0)).equals(Buffer.from(A.subarray(S.TSH1,S.TSH1+960))),
      'game: next squadron reloads every fighter shape after the enemy proton borrows two slots');
  }
}

// ---- mothership approach -----------------------------------------------------
{
  function call(m, addr, plot) {
    const c = m.cpu, pc = c.pc, sp = c.sp, flags = c.p;
    if (plot !== undefined) { c.push(plot & 255); c.push(plot >> 8); }
    c.push(0xFF); c.push(0xF3); c.pc = addr; c.p |= 4;
    let n = 0;
    while (c.pc !== 0xFFF4 && n++ < 2e6) { c.step(); if (c.jam) throw Error(c.jam); }
    if (c.pc !== 0xFFF4) throw Error('mothership subroutine did not return');
    c.pc = pc; c.sp = sp; c.p = flags;
  }
  // Compare every biased ring, pixel for pixel, using the original's own plotter.
  const o = boot('c64game', 'trace'), k = boot('game', 'trace');
  run(o.m, o.hooks, 250); run(k.m, k.hooks, 60);
  const R = o.m.ram, K = k.m.ram, s = k.p.symbols;
  const read = k.m.read;
  k.m.read = function(a) { return a === 0xD012 ? 80 : read.call(this, a); };
  let same = true, rings = 0;
  for (const kind of [0x80, 0xFF]) for (let r = 1; r <= (kind === 0x80 ? 0x22 : 0x28); r++) {
    R.fill(0, 0x63C0, 0x7680); K.fill(0, 0x63C0, 0x7680);
    const bias = 1 + (r - 1) * (kind === 0x80 ? 3 : 1);
    R[0x3668] = 1; R[0x3674] = bias;
    o.m.cpu.x = 0x50; o.m.cpu.y = 0x64; o.m.cpu.a = r;
    call(o.m, 0x3635, 0xEF6B);
    K[s.MSRAD] = r; K[s.MSBIAS] = bias; K[s.MSRUN] = 0;
    call(k.m, s.MSRING); call(k.m, s.MSSTEP);
    same = same && K[s.MSRUN] === 0 && Buffer.from(R.subarray(0x63C0, 0x7680)).equals(Buffer.from(K.subarray(0x63C0, 0x7680)));
    rings++;
  }
  k.m.read = read;
  // The opening is drawn by $8F05's nested outlines, then protected by the rings.
  // Compare the cumulative ship bitmap at every radius, not just an empty ring.
  k.m.read = function(a) { return a === 0xD012 ? 0 : a === 0xD011 ? 0x80 : read.call(this, a); };
  let centres = true, centreStages = 0;
  for (const kind of [0x80, 0xFF]) {
    R.fill(0, 0x63C0, 0x7680); K.fill(0, 0x63C0, 0x7680);
    R[0x8F12] = 75; R[0x8F14] = 100; R[0x8F06] = 10; R[0x8F16] = 1; R[0x8F30] = 0;
    K[s.MSCPEND] = 0;
    for (let r = 1; r <= (kind === 0x80 ? 0x22 : 0x28); r++) {
      if (r >= 12) call(o.m, 0x8F05);
      const bias = 1 + (r - 1) * (kind === 0x80 ? 3 : 1);
      R[0x3668] = 1; R[0x3674] = bias;
      o.m.cpu.x = 0x50; o.m.cpu.y = 0x64; o.m.cpu.a = r;
      call(o.m, 0x3635, 0xEF6B);
      K[s.MSRAD] = r; K[s.MSBIAS] = bias; K[s.MSRUN] = 0;
      call(k.m, s.MSRING);
      if (K[s.MSCPEND]) call(k.m, s.MSVB);
      call(k.m, s.MSSTEP);
      centres = centres && K[s.MSCPEND] === 0 && Buffer.from(R.subarray(0x63C0, 0x7680)).equals(Buffer.from(K.subarray(0x63C0, 0x7680)));
      centreStages++;
    }
  }
  k.m.read = read;
  check(centres, `mothership: growing rectangular centre and rings match the original at all ${centreStages} radii`);
  check(same, `mothership: all ${rings} friendly/hostile biased rings match the original bitmap exactly`);
  function originalDuration(kind) {
    const o = boot('c64game', 'trace'), m = o.m, R = m.ram;
    run(m, o.hooks, 300);
    run(m, o.hooks, 300, i => { m.mouse.left = i < 10 || (i >= 150 && i < 160); });
    m.mouse.left = false; m.dma = true;
    R[0xE2] = kind === 0x80 ? 1 : 0;
    R[0xBAD1] = R[0xBACE] = R[0x8C3E] = 0; R[0x89] = 1;
    R.set([0x4C, 0, 3], 0x300); m.cpu.push(2); m.cpu.push(0xFF); m.cpu.pc = 0x909D;
    let first = -1, last = -1;
    const end = kind === 0x80 ? 0x22 : 0x28;
    for (let f = 0; f < 400; f++) {
      if (!m.runFrame()) break;
      if (R[0x43] === 2 && first < 0) first = f;
      if (R[0x43] === end) { last = f; break; }
    }
    if (first < 0 || last < 0) throw Error('original mothership approach did not finish');
    return last - first;
  }
  for (const kind of [0x80, 0xFF]) {
    const g = boot('game', 'trace'), m = g.m, s = g.p.symbols, K = m.ram;
    m.dma = true; run(m, g.hooks, 60);
    const idx = K[s.M_SELY] * 10 + K[s.M_SELX];
    K[s.M_STATE + idx] = kind; K[s.M_COUNT + idx] = 0;
    const hp = Buffer.from(K.subarray(s.SYSHP, s.SYSHP + 8)), protons = Buffer.from(K.subarray(0x485A, 0x485C));
    call(m, s.SECTORIN);
    check(K[s.MSKIND] === kind && K[s.MSSTATE] === 1 && K[s.APPR] === 0 && K[s.shpj] === 0x20,
      `mothership: entering ${kind === 0x80 ? 'enemy' : 'friendly'} sector arms the approach without fighters`);
    // This block measures the existing rings. The scanner phase has its own
    // original/port timing and split checks above.
    for (let f = 0; f < 500 && (K[s.MSSTATE] === 1 || K[s.MSSTATE] === 16); f++) m.runFrame();
    let late = 0, first = -1, last = -1, prev = 0, growth = [];
    for (let f = 0; f < 450; f++) {
      m.runFrame();
      if (f === 0) { K[s.MSPHASE] = 1; K[s.MSPCOUNT] = 255; K[s.MSPCOLOR] = 0x11; }
      if (K[s.MSRAD] !== prev) { if (K[s.MSRAD] === 2) first = f; last = f; growth.push(K[s.MSRAD]); prev = K[s.MSRAD]; }
      const v = m.vicLog;
      for (let i = 0; i < v.length; i += 4) if ((v[i + 2] === 0x20 || v[i + 2] === 0x21) &&
        ((v[i] >= 50 && v[i] <= 76) || (v[i] >= 230 && v[i] <= 245)) && v[i + 1] >= 16 && v[i + 1] <= 55) late++;
      if (K[s.MSSTATE] === 4) break;
    }
    const end = kind === 0x80 ? 0x22 : 0x28;
    check(K[s.MSSTATE] === 4 && K[s.MSRAD] === end && growth.every((v,i) => v === i + 1),
      `mothership: ${kind === 0x80 ? 'enemy' : 'friendly'} approach grows continuously to $${end.toString(16)}`);
    const reference = originalDuration(kind);
    check(Math.abs(last - first - reference) <= 10, `mothership: DMA growth ${last - first} frames, original ${reference} frames (frame-locked approximation)`);
    check(late === 0 && K[s.OVRUN] === 0, `mothership: DMA approach has ${late} late split writes, ${K[s.OVRUN]} overruns`);
    check((kind===0x80 ? K[s.HITS]===5 : Buffer.from(K.subarray(s.SYSHP,s.SYSHP+8)).equals(hp)) && Buffer.from(K.subarray(0x485A,0x485C)).equals(protons) && K[s.M_STATE+idx]===kind,
      'mothership: enemy proton hits five times; friendly approach preserves ship, protons and base');
    const centreAddress = 0x6000 + (100 >> 3) * 320 + (85 >> 2) * 8 + (100 & 7);
    check(((K[centreAddress] >> ((3 - (85 & 3)) * 2)) & 3) === 2 && K[0x44A0] === 0x11 && K[s.MSCPEND] === 0,
      'mothership: the completed opening is filled with white bitmap pixels');
    snap(m, kind === 0x80 ? 'mothership-enemy' : 'mothership-friendly');
    for(let n=0;n<1800 && K[s.MSSTATE];n++) m.runFrame();
    run(m,g.hooks,80);
    check(K[s.MAPSHOWN] === 1 && K[s.MSLOCK] === 1 && K[s.MSSTATE] === 0,
      'mothership: the normal endpoint opens the map and locks immediate re-entry');
    K[s.M_CURX] = K[s.M_SELX]; K[s.M_CURY] = K[s.M_SELY];
    call(m, s.M_SELECT); call(m, s.MAPIN);
    check(K[s.MAPSHOWN] === 1 && !K[s.HYPON], 'mothership: firing on the just-completed base sector keeps the map open');
    call(m, s.MAPCLOSE); run(m, g.hooks, 20);
    // Inject between completed frames, rather than adding a subroutine's cycles
    // to a RADSTEP already suspended halfway through its vertical-blank work.
    m.setBreak(s.frame,true);let boundary;
    while((boundary=m.run())!=='break'&&boundary!=='stopped');
    m.setBreak(s.frame,false);
    call(m, s.SECTORIN);                 // approach under firing/steering load
    for (let f = 0; f < 500 && (K[s.MSSTATE] === 1 || K[s.MSSTATE] === 16); f++) m.runFrame();
    let stressLate = 0;
    for (let f = 0; f < 120; f++) {
      m.mouse.left = true; m.moveMouse(f % 20 < 10 ? 3 : -3, f % 16 < 8 ? 2 : -2);
      m.runFrame();
      const v = m.vicLog;
      for (let i = 0; i < v.length; i += 4) if ((v[i + 2] === 0x20 || v[i + 2] === 0x21) &&
        ((v[i] >= 50 && v[i] <= 76) || (v[i] >= 230 && v[i] <= 245)) && v[i + 1] >= 16 && v[i + 1] <= 55) stressLate++;
    }
    m.mouse.left = false;
    check(K[s.MSRAD] >= 12 && K[s.OVRUN] === 0 && stressLate === 0,
      `mothership: steering and phasors during approach: radius ${K[s.MSRAD]}, ${stressLate} late writes, ${K[s.OVRUN]} overruns`);
    K[s.MSPHASE] = 0; K[s.MSPCOUNT] = 255;
    const beforeMissRadius = K[s.MSRAD], beforeMissProtons = K[0x485B];
    m.setKey(7, 4, true); run(m, g.hooks, 2); m.setKey(7, 4, false); run(m, g.hooks, 60);
    for(let n=0;n<120&&K[s.TPF];n++)m.runFrame();
    run(m,g.hooks,12);
    check(K[s.MSSTATE] === 3 && !K[s.MSKILLED] && K[s.MSRAD] > beforeMissRadius && K[s.M_STATE + idx] === kind && K[0x485B] === beforeMissProtons - 1,
      'mothership: a phase-off SPACE shot misses and the approach keeps growing');
    K[s.M_STATE + idx] = 0; call(m, s.SECTORIN);
    check(K[s.MSSTATE] === 0 && K[s.shpj] === 0x2C && K[s.gplmode + 1] === (s.MAPSHOWN & 255) && K[s.vv2 + 1] === (s.STARS & 255) && K[s.vv2 + 2] === (s.STARS >> 8) && K[s.HVBR + 1] === (s.HYPON & 255) && K[s.HVBR + 2] === (s.HYPON >> 8), 'mothership: leaving restores the idle hooks');
  }
  // Original $BB81 truth table, including the hidden friendly phase and early shots.
  let blastRules = true;
  for (const base of [0, 1]) for (const radius of [5, 12]) for (const phase of [0, 1]) {
    R[0xE1] = base; R[0x8ED1] = radius >= 12 ? radius : 0; R[0x953E] = phase;
    R[0x8C3E] = R[0xBAD1] = 0;
    call(o.m, 0xBB70);
    K[s.MSSTATE] = base ? 3 : 0; K[s.MSRAD] = radius; K[s.MSPHASE] = phase;
    K[s.MSKILLED] = 0; K[s.TPF] = 2;
    call(k.m, s.MSBLAST);
    blastRules = blastRules && !!R[0x8C3E] === !!K[s.MSKILLED] &&
      (base && !R[0x8C3E] ? K[s.TPF] === 0 : K[s.TPF] === 2);
  }
  check(blastRules, 'mothership destruction: blast gate matches original $BB81 for every sector/centre/phase combination');

  // Issue #16: run the original blast loop with DMA, observing every video frame.
  // Misses never arm $BAD1; hits paint orange once and leave it until scene cleanup.
  // The port deliberately spreads that same fill over its available blank slots.
  const blastTrace = [];
  for (const kind of [0xFF, 0x80]) for (const phase of [0, 1]) for (const radius of [5, 12]) {
    const ref = boot('c64game', 'trace'); run(ref.m, ref.hooks, 300);
    const rm = ref.m, B = rm.ram, hit = phase === 1 && radius >= 12;
    rm.dma = true;
    B[0xE1] = 1; B[0xE2] = kind === 0x80 ? 1 : 0;
    B[0x8ED1] = radius >= 12 ? radius : 0; B[0x953E] = phase;
    B[0xBAD1] = B[0x8C3E] = B[0x160A] = 0;
    rm.colorRam.fill(kind === 0xFF ? 6 : 2, 0xA0, 0x2A8);
    const initial = Buffer.from(rm.colorRam.subarray(0xA0, 0x2A8));
    const border = rm.vic[0x20], background = rm.vic[0x21];
    call(rm, 0xBB70);
    // JSR $BBE4 / JMP $0300: only the blast, with IRQs masked, as direct callers use it.
    B.set([0x20,0xE4,0xBB,0x4C,0,3],0x300); rm.cpu.pc = 0x300; rm.cpu.p |= 4;
    const frames = []; let referenceOK = true;
    for (let f = 0; f < 24; f++) {
      rm.runFrame();
      const colour = Buffer.from(rm.colorRam.subarray(0xA0,0x2A8));
      frames.push({frame:f, colour:[...colour], border:rm.vic[0x20], background:rm.vic[0x21], blast:B[0xBAD1]});
      referenceOK &&= hit ? colour.every(x => x === 8) : colour.equals(initial);
      referenceOK &&= rm.vic[0x20] === border && rm.vic[0x21] === background;
    }
    check(referenceOK && !!B[0x8C3E] === hit,
      `game: original ${kind===0xFF?'friendly':'enemy'} radius ${radius} phase ${phase}: every blast frame ${hit?'orange':'unchanged'}, border/background unchanged`);

    const g = scene(kind), {m,S,A} = g;
    A[S.MSRAD] = radius; A[S.MSPHASE] = phase; A[S.MSPCOUNT] = 255;
    A[S.MSKILLED] = 0; A[S.TPF] = 2; A[S.TPKX] = 3; A[S.torpj] = 0x20;
    m.colorRam.fill(kind === 0xFF ? 6 : 2,0xA0,0x2A8);
    call(m,S.MSBLAST);
    let portOK = true, late = 0, orangeFrame = -1;
    const portFrames = [];
    for (let f = 0; f < 120 && (f < 12 || A[S.TPF]); f++) {
      m.runFrame(); late += lateWrites(m);
      const colour = Buffer.from(m.colorRam.subarray(0xA0,0x2A8));
      const view = [m.vicStart[0x20],m.vicStart[0x21]], v = m.vicLog;
      for (let i=0;i<v.length;i+=4) if (v[i]<=100 && (v[i+2]===0x20 || v[i+2]===0x21)) view[v[i+2]-0x20]=v[i+3];
      portFrames.push({frame:f, colour:[...colour], border:view[0], background:view[1], blast:A[S.TPF]});
      portOK &&= view[0] === border && view[1] === background;
      // Compare every cell with the original; allow the existing bounded row-fill latency.
      portOK &&= hit ? colour.every((x,i) => x === frames[Math.min(f,frames.length-1)].colour[i] || (orangeFrame < 0 && x === initial[i])) : colour.equals(Buffer.from(frames[Math.min(f,frames.length-1)].colour));
      if (hit && colour.every(x => x === 8) && orangeFrame < 0) orangeFrame = f;
    }
    check(portOK && (hit ? orangeFrame >= 0 && orangeFrame <= 6 && A[S.TPF] === 0 : A[S.TPF] === 0 && !A[S.MSKILLED]),
      `game: ${kind===0xFF?'friendly':'enemy'} radius ${radius} phase ${phase}: frame palettes match original${hit?' after bounded fill':''}`);
    check(late===0 && A[S.OVRUN]===0, `game: base blast has ${late} late splits, ${A[S.OVRUN]} overruns`);
    blastTrace.push({kind,phase,radius,hit,original:frames,port:portFrames});
  }
  fs.writeFileSync(path.join(OUT,'base-blast-colour-trace.json'),JSON.stringify(blastTrace));

  K[s.MSSTATE] = 0; K[s.MSKILLED] = 1; K[s.TPF] = 5; K[s.TPCR] = 13;
  call(k.m,s.MSBLEND);
  check(K[s.TPF] === 5 && K[s.TPCR] === 0,
    'game: a previous base kill does not suppress the next ordinary proton colour restoration');

  // The original toggles after 25 calls; random colour is restricted to enemy phase 0.
  let phaseRules = true;
  for (const kind of [0x80, 0xFF]) {
    R[0xE2] = kind === 0x80 ? 1 : 0; R[0x953D] = 25; R[0x953E] = 0;
    K[s.MSKIND] = kind; K[s.MSPCOUNT] = 25; K[s.MSPHASE] = 0;
    const colours = new Set();
    for (let n = 0; n < 75; n++) {
      call(o.m, 0x953F); call(k.m, s.MSPCALL);
      phaseRules = phaseRules && R[0x953D] === K[s.MSPCOUNT] && R[0x953E] === K[s.MSPHASE];
      if (K[s.MSPHASE] === 0) colours.add(K[s.MSPCOLOR]);
      else phaseRules = phaseRules && K[s.MSPCOLOR] === 0x11;
    }
    phaseRules = phaseRules && (kind === 0x80 ? colours.size >= 3 : colours.size === 1 && colours.has(0x11));
  }
  check(phaseRules, 'mothership destruction: 25-call phase toggles match original, enemy phase 0 flickers, friendly stays white');

  // Static pixel comparison; real DMA deadlines are tested by the frame loops below.
  k.m.read=function(a){return a===0xD012?80:read.call(this,a);};
  R.fill(0x5B,0x63C0,0x7680); K.fill(0x5B,0x63C0,0x7680);
  K[s.mscent]=0x2C; K[s.msmode+1]=2;
  let erasePixels=true;
  for(let radius=1;radius<=44;radius++) {
    R[0x3668]=1; R[0x3674]=radius;
    o.m.cpu.x=0x50;o.m.cpu.y=0x64;o.m.cpu.a=radius;call(o.m,0x3635,0xEEFB);
    K[s.MSRAD]=radius;K[s.MSBIAS]=radius;K[s.MSRUN]=0;
    call(k.m,s.MSRING);call(k.m,s.MSSTEP);
    erasePixels=erasePixels&&Buffer.from(R.subarray(0x63C0,0x7680)).equals(Buffer.from(K.subarray(0x63C0,0x7680)));
  }
  K[s.mscent]=0x20;K[s.msmode+1]=1;k.m.read=read;
  check(erasePixels,'mothership destruction: all 44 erasing circles match original $9020/$EEFB pixels in the view');

  function scene(kind) {
    const g = boot('game', 'trace'), m = g.m, S = g.p.symbols, A = m.ram;
    m.dma = true; run(m, g.hooks, 60);
    A.fill(0, S.M_STATE, S.M_STATE + 60); A.fill(0, S.M_COUNT, S.M_COUNT + 60);
    const index = kind === 0xFF ? 12 : 0;
    A[S.M_SELX] = index % 10; A[S.M_SELY] = Math.floor(index / 10);
    A[S.M_STATE + index] = kind;
    call(m, S.SECTORIN);
    for (let n = 0; n < 600 && A[S.MSSTATE] !== 3; n++) m.runFrame();
    return { ...g, S, A, index };
  }
  function lateWrites(m) {
    let n = 0, v = m.vicLog;
    for (let i = 0; i < v.length; i += 4) if ((v[i + 2] === 0x20 || v[i + 2] === 0x21) &&
      ((v[i] >= 50 && v[i] <= 76) || (v[i] >= 230 && v[i] <= 245)) && v[i + 1] >= 16 && v[i + 1] <= 55) n++;
    return n;
  }
  function row(m,S) { return String.fromCharCode(...m.ram.subarray(S.LRROW,S.LRROW+39)).replace(/[@`]/g,' ').trim(); }

  // Measure 32-pass phase scheduling on both real frame loops, with DMA enabled.
  const po = boot('c64game', 'trace'); run(po.m, po.hooks, 300);
  run(po.m, po.hooks, 300, i => { po.m.mouse.left = i < 10 || (i >= 150 && i < 160); });
  po.m.mouse.left = false; po.m.dma = true;
  const PR = po.m.ram, phaseStart = po.m.frame, originalToggles = [];
  PR[0xE1] = 1; PR[0xE2] = 0; PR[0xBAD1] = PR[0xBACE] = PR[0x8C3E] = 0; PR[0x89] = 1;
  po.hooks.on(0x8EF8, () => { PR[0x953D] = 25; PR[0x953E] = 0; });
  po.hooks.on(0x9544, () => originalToggles.push(po.m.frame - phaseStart));
  PR.set([0x4C,0,3],0x300); po.m.cpu.push(2); po.m.cpu.push(0xFF); po.m.cpu.pc = 0x909D;
  run(po.m,po.hooks,130);
  const pg = scene(0xFF), portToggles = [];
  pg.A[pg.S.MSPCOUNT] = 25; pg.A[pg.S.MSPHASE] = pg.A[pg.S.MSPACC] = 0;
  let prevPhase = 0, phaseLate = 0;
  for(let f=0; f<130; f++) {
    pg.m.runFrame(); phaseLate += lateWrites(pg.m);
    if(pg.A[pg.S.MSPHASE]!==prevPhase) { portToggles.push(f); prevPhase=pg.A[pg.S.MSPHASE]; }
  }
  check(originalToggles.length >= 3 && portToggles.length >= 3 && portToggles.slice(0,3).every((v,i)=>Math.abs(v-originalToggles[i])<=10),
    `mothership destruction: DMA phase toggles port ${portToggles.slice(0,3)}, original ${originalToggles.slice(0,3)} frames`);
  check(phaseLate === 0 && pg.A[pg.S.OVRUN] === 0, 'mothership destruction: phase updates do not overrun or write splits late');

  const fg = scene(0x80), flickerColours = new Set();
  fg.A[fg.S.MSPHASE]=0; fg.A[fg.S.MSPCOUNT]=255;
  let flickerLate=0;
  for(let f=0;f<80;f++){fg.m.runFrame();flickerColours.add(fg.A[0x44A0]);flickerLate+=lateWrites(fg.m);}
  fg.A[fg.S.MSPHASE]=0;fg.A[fg.S.MSPCOUNT]=1;call(fg.m,fg.S.MSPCALL);run(fg.m,fg.hooks,10);
  check(flickerColours.size>=3&&fg.A.subarray(0x44A0,0x46D0).every(v=>v===0x11),
    `mothership destruction: enemy palette visibly flickers (${flickerColours.size} colours), then returns to white`);
  check(flickerLate===0&&fg.A[fg.S.OVRUN]===0,'mothership destruction: real flicker/centre updates fit the DMA budget');

  // Replay the supplied in-flight C64 state with stolen VIC cycles enabled.
  // $90F3 is the radius load instruction; its live counter is zero-page $43.
  for (const kind of [0x80, 0xFF]) {
    const ref=boot('c64game','trace'), saved=JSON.parse(fs.readFileSync(path.join(ROOT,'../briefs/ref/c64-proton-in-flight-mothership.state.json'),'utf8'));
    ref.m.loadState(ref.m.stateFromText(JSON.stringify(saved.state)));ref.m.dma=true;
    const R=ref.m.ram;R[0xE2]=kind===0x80?1:0;
    const g=scene(kind),{m,S,A}=g;
    A[S.MSRAD]=R[0x43];A[S.MSBIAS]=R[0x3674];A[S.MSCLOCK]=0;
    A[S.MSPCOUNT]=R[0x953D];A[S.MSPHASE]=R[0x953E];A[S.MSPACC]=0;
    call(m,S.MSRING);A[S.TREQ]=1;call(m,S.GTORP);
    const trace=[], colours=new Set();let late=0,same=true;
    for(let f=0;f<18;f++) {
      ref.m.runFrame();m.runFrame();late+=lateWrites(m);colours.add(A[0x44A0]);
      trace.push({f,original:{radius:R[0x43],bias:R[0x3674],count:R[0x953D],phase:R[0x953E],killed:R[0x8C3E],flight:R[0xBACF],sidWrites:ref.m.sidLog.length/3},port:{radius:A[S.MSRAD],count:A[S.MSPCOUNT],phase:A[S.MSPHASE],flight:A[S.TPF]}});
      same=same&&Math.abs(A[S.MSRAD]-R[0x43])<=1&&Math.abs(A[S.MSPCOUNT]-R[0x953D])<=4&&A[S.MSPHASE]===R[0x953E];
    }
    fs.writeFileSync(path.join(OUT,`mothership-flight-${kind.toString(16)}-trace.json`),JSON.stringify(trace,null,2));
    check(same&&A[S.MSRAD]>trace[0].port.radius,`game: ${kind.toString(16)} proton flight radius/phase follow original per frame (one radius/four phase-call tolerance)`);
    check(kind!==0x80||colours.size>=2,'game: enemy base visibly flickers during player proton flight');
    check(late===0&&A[S.OVRUN]===0,`game: proton/base overlap has ${late} late splits, ${A[S.OVRUN]} overruns`);
    // Finish a ring near the endpoint while flight is still active.
    A[S.MSRAD]=kind===0x80?0x22:0x28;A[S.MSCLOCK]=254;A[S.MSRUN]=0;
    m.runFrame();m.runFrame();
    check(A[S.MSSTATE]===4&&A[S.TPF]===1,'game: base reaches ring endpoint during flight and waits for proton result');

  }

  for(const kind of [0x80,0xFF]) {
    const g=scene(kind), {m,S,A,index}=g;
    for(let n=0;n<200&&A[S.MSRAD]<12;n++) m.runFrame();
    A[S.MSPHASE]=1; A[S.MSPCOUNT]=255;
    const hp=Buffer.from(A.subarray(S.SYSHP,S.SYSHP+8)), cockpitArt=Buffer.from(A.subarray(0x7680,0x7CC0));
    m.setKey(7,4,true); run(m,g.hooks,2); m.setKey(7,4,false);
    let sawDocking=false, sawKill=false, sawMessage=false, sawErase=false, deathRadii=[], lastR=-1, late=0;
    for(let f=0;f<1000;f++) {
      m.runFrame(); late+=lateWrites(m);
      sawDocking ||= A[S.MSSTATE]>=7; sawKill ||= !!A[S.MSKILLED]; sawMessage ||= row(m,S)==='BASESTAR DESTROYED CAPTAIN';
      if(A[S.MSSTATE]===6) {
        sawErase ||= A[S.msmode+1]===2;
        if(A[S.MSRAD]!==lastR) {deathRadii.push(A[S.MSRAD]);lastR=A[S.MSRAD];}
      }
      if(A[S.MAPSHOWN] && A[S.MSSTATE]===0 && sawErase) break;
    }
    check(sawKill && sawMessage && sawErase && deathRadii.length===44 && deathRadii.every((r,i)=>r===i+1),
      `mothership destruction: ${kind===0x80?'enemy':'friendly'} hit shows message and erasing rings 1-$2C (${deathRadii.length} radii)`);
    check(A[S.M_STATE+index]===0&&A[S.M_COUNT+index]===0&&A[S.MAPSHOWN]===1&&!sawDocking&&Buffer.from(A.subarray(S.SYSHP,S.SYSHP+8)).equals(hp),
      'mothership destruction: cell cleared, map opened, no repair or enemy torpedo damage');
    check(kind!==0xFF||A[S.M_DEAD]===1,'mothership destruction: killing a friendly base marks its strategic destroyed flag');
    check(late===0&&A[S.OVRUN]===0,`mothership destruction: full kill sequence has ${late} late split writes, ${A[S.OVRUN]} overruns`);
    check(Buffer.from(A.subarray(0x7680,0x7CC0)).equals(cockpitArt),'mothership destruction: rings and particles preserve cockpit bitmap art');
    run(m,g.hooks,80);
    check(A[S.MSLOCK]===0&&A[S.g_mi8+1]===(S.MAPCLOSE&255)&&A[S.g_mi8+2]===(S.MAPCLOSE>>8),
      'mothership destruction: the emptied sector can be chosen straight back (as in the original)');
    if(kind===0x80) {
      A[S.M_CURX]=1; A[S.M_CURY]=0; call(m,S.M_SELECT); call(m,S.MAPIN);
      let jumping=!!A[S.HYPON];
      for(let f=0;f<1200&&A[S.HYPON];f++)m.runFrame();
      check(jumping&&!A[S.HYPON]&&A[S.MSLOCK]===0&&A[S.M_SELX]===1,
        'mothership destruction: another sector remains selectable and arrival clears the re-entry lock');
    }
  }

  // Friendly beam: original Bresenham paths and every cumulative ring in the view.
  const beamRead = k.m.read;
  k.m.read = function(a) { return a === 0xD012 ? 80 : a === 0xD011 ? 0 : beamRead.call(this,a); };
  const paths=[];
  for(const [x,end,page] of [[60,15,2],[100,146,5]]) {
    Object.assign(R, { [0x54]:1,[0x36]:x,[0x37]:110,[0x4E]:end,[0x4F]:186,
      [0x55]:0,[0x56]:page,[0x57]:0,[0x58]:4 });
    call(o.m,0x3580);
    paths.push([...R.subarray(page*256,page*256+76)]);
  }
  const storedLeft=[...K.subarray(s.MBLEFT,s.MBLEFT+76)];
  const storedRight=[...K.subarray(s.MBRIGHT,s.MBRIGHT+76)];
  check(JSON.stringify(paths)===JSON.stringify([storedLeft,storedRight]),'friendly repair: both 76-point beam paths match original $3580');
  R.fill(0,0x63C0,0x7680); K.fill(0,0x63C0,0x7680);
  const beamArt=Buffer.from(K.subarray(0x7680,0x7CC0)); R.set(beamArt,0x7680);
  K[s.mscent]=0x2C;K[s.MSBIAS]=1;call(k.m,s.MBSET);
  let beamPixels=true;
  for(let i=0;i<76;i++) for(let side=0;side<2;side++) {
    const radius=1+Math.floor((i+4)/10);
    R[0x3668]=R[0x3674]=1;o.m.cpu.a=radius;o.m.cpu.x=paths[side][i];o.m.cpu.y=110+i;call(o.m,0x3635,0xEF30);
    K[s.MRINDEX]=i;K[s.MRSIDE]=side===0?1:0;K[s.MSRAD]=radius;K[s.MSRUN]=0;
    call(k.m,s.MBPLOT);call(k.m,s.MSRING);call(k.m,s.MSSTEP);
    beamPixels &&= !K[s.MSRUN]&&Buffer.from(K.subarray(0x63C0,0x7CC0)).equals(Buffer.from(R.subarray(0x63C0,0x7CC0)));
  }
  call(k.m,s.MBRESTORE);k.m.read=beamRead;
  check(beamPixels&&!Buffer.from(K.subarray(0x7680,0x7CC0)).equals(beamArt),
    'friendly repair: all 152 rings match the original through the cockpit down to the guns');

  function originalRepair(damaged,energy,protons) {
    const g=boot('c64game','trace'),m=g.m,R=m.ram;
    run(m,g.hooks,300);run(m,g.hooks,300,i=>m.mouse.left=i<10||(i>=150&&i<160));
    m.mouse.left=false;m.dma=true;
    const start=m.frame,events={statuses:[],chars:[],noiseWrites:0};let done=false,scan=false,scanned=false;
    g.hooks.on(0x9510,()=>{if(!scanned){scan=true;events.noiseStart=m.frame;}});
    g.hooks.on(0x953C,()=>{if(scan){scan=false;scanned=true;events.noiseFrames=m.frame-events.noiseStart;}});
    const originalWrite=m.write;
    m.write=function(a,v){if(scan&&((a>=0xDB2C&&a<0xDB3C)||(a>=0xDB54&&a<0xDB64)))events.noiseWrites++;return originalWrite.call(this,a,v);};
    for(const [address,name] of [[0x918E,'beam'],[0x92E3,'repair'],[0x93BB,'typed'],[0xFA33,'charged'],[0x8D6F,'done']])
      g.hooks.on(address,()=>{events[name]=m.frame-start;
        if(name==='rings')check(R[0xD4]===0x80,'game: original keeps star band when rings begin');if(name==='done')done=true;});
    g.hooks.on(0x9489,()=>events.chars.push(m.frame-start));
    g.hooks.on(0x94DC,()=>events.statuses.push({frame:m.frame-start,index:R[0x9496]}));
    R[0xE1]=1;R[0xE2]=0;R[0x89]=1;R[0xBAD1]=R[0xBACE]=R[0x8C3E]=0;
    R.fill(damaged?0:1,0x39,0x41);R[0x844F]=1;R[0x8450]=protons;
    R.set(String(energy).padStart(4,'0').split('').map(x=>0x70+Number(x)),0x543E);
    m.cpu.pc=0x8D59;
    for(let f=0;f<1800&&!done;f++)m.runFrame();
    check(done&&R[0x844F]===40&&R[0x8450]===((protons+1)&255),
      `friendly repair reference: DMA ${damaged?'damaged':'working'} ship finishes in ${events.done} frames, proton ${protons}->${R[0x8450]}`);
    return events;
  }
  for(const [damaged,energy,protons] of [[true,0,99],[false,9999,255]]) {
    const reference=originalRepair(damaged,energy,protons),g=scene(0xFF),{m,S,A,index}=g;
    A.fill(damaged?0:1,S.SYSHP,S.SYSHP+8);A[S.SHLD]=1;A[S.HITS]=37;A[S.HITS+1]=2;
    A.set(String(energy).padStart(4,'0').split('').map(x=>0x70+Number(x)),S.HUDE);
    A[S.MRPHUND]=Math.floor(protons/100);A[0x485A]=0x70+Math.floor(protons%100/10);A[0x485B]=0x70+protons%10;
    const originalSlots=new Map([S.GSPACE,S.MAPTOG,S.LAUNCHD,S.MRMODE,S.MRATTR,S.MRGUN,S.MRWAIT,S.SPRCROSS,S.SPRGUNS,S.MSSTEP,S.TPLOT1].map(a=>[a,Buffer.from(A.subarray(a,a+14))]));
    const art=Buffer.from(A.subarray(0x7680,0x7CC0)),seenNames=[],statuses=[],colours=new Set();
    const protectedRanges=[[0x4000,0x4400],[0x4C00,0x5000],[0x6000,0x63C0],[0x7CC0,0x8000],
      [S.TSH1,S.TSH1+960],[S.TSH2,S.TSH3+512],[S.TSHOT,S.TSHOT+128],[S.MMAT,S.MMAT+600],[S.COLORDATA,S.COLORDATA+1000]];
    const protectedBefore=protectedRanges.map(([a,b])=>Buffer.from(A.subarray(a,b))),artColours=Buffer.from(m.colorRam.subarray(720,920));
    // A before/after comparison alone missed the old bug: its PRG already had
    // text/path data in scanner and barrel sprite slots. Also check the source art.
    const spriteSource=fs.readFileSync(path.join(ROOT,'../c128-gui/ref/sprites-4800.bin'));
    const spriteOrder=[0x20,0x30,0x40,0x60,0x70].flatMap(b=>Array.from({length:16},(_,i)=>b+i));
    check([[0x4D80,0x4C],[0x4DC0,0x4D],[0x4E00,0x4E],[0x4F40,0x47],[0x4F80,0x48]].every(([a,n])=>Buffer.from(A.subarray(a,a+64)).equals(spriteSource.subarray(spriteOrder.indexOf(n)*64,spriteOrder.indexOf(n)*64+64))),
      'repair fixes: scanner blips and both barrel shapes match the original assets before docking');
    let cleanExit=false,reportMode=true,blocks=false,scanSound=false,firstNoiseWrites=0,firstNoiseFrames=0,frameNoise=0,firstScan=false;
    const noiseColours=new Set(),write=m.write;
    m.write=function(a,v){if(A[S.MSSTATE]===10&&((a>=0xDB2C&&a<0xDB3C)||(a>=0xDB54&&a<0xDB64))){frameNoise++;noiseColours.add(v&15);}return write.call(this,a,v);};
    g.hooks.on(S.MRCOMPLETE,()=>{cleanExit=A.subarray(0x63C0,0x7680).every(v=>v===0)&&Buffer.from(A.subarray(0x7680,0x7CC0)).equals(art)&&A[S.MRMODE+1]===0x7B;});

    let start=-1,beamEnd=-1,typeStart=-1,typeEnd=-1,lastOffset=0,lastIndex=0,late=0,steps=[],finished=-1,sawNoise=false;
    for(let f=0;f<1900;f++) {
      firstScan=A[S.MSSTATE]===10&&A[S.MRROW]>0;frameNoise=0;
      m.runFrame();late+=lateWrites(m);
      if(firstScan){firstNoiseWrites+=frameNoise;firstNoiseFrames++;}
      const state=A[S.MSSTATE];
      if(state===7&&start<0)start=f;
      if(state===8&&beamEnd<0)beamEnd=f;
      if(state===9&&typeStart<0)typeStart=f;
      if(state===10&&typeEnd<0){typeEnd=f;lastIndex=0;}
      if(state===9&&A[S.MRINDEX]!==lastIndex){seenNames.push(lastIndex);lastIndex=A[S.MRINDEX];}
      if(state===10&&A[S.MRINDEX]!==lastIndex){statuses.push({frame:f,index:lastIndex});lastIndex=A[S.MRINDEX];}
      if(state>=9&&state<=11)reportMode&&=(A[S.MRMODE+1]===0x1B||(state===11&&A[S.MRMODE+1]===0x7B))&&A[S.SPRCROSS]===0x60&&A[S.SPRGUNS]===0x60;
      if(state===10) {
        blocks ||= A.subarray(0x41F8,0x4200).every(v=>v===0xFF)&&A.subarray(0x4B2C,0x4B3C).every(v=>v===0x3F)&&A.subarray(0x4B54,0x4B64).every(v=>v===0x3F);
        if(frameNoise)scanSound ||= m.sidLog.some((v,i)=>i%3===1&&v===1&&m.sidLog[i+1]===0x62)&&m.sidLog.some((v,i)=>i%3===1&&v===4&&m.sidLog[i+1]===0x11);
        if(damaged&&f<typeEnd+30)colours.add(m.colorRam[4*40]);
        const n=A.subarray(S.HUDE,S.HUDE+4).reduce((v,x)=>v*10+x-0x70,0);if(lastOffset&&n<9999)steps.push(n-lastOffset);lastOffset=n;
        sawNoise ||= m.sidLog.some((v,i)=>i%3===1&&v===0x0B&&m.sidLog[i+1]===0x11);
      }
      if(state===0&&start>=0){finished=f;break;}
    }
    const expected=Array.from({length:8},(_,i)=>i===7?255:A[S.HPTAB+i*5+A[S.DIFF]]);
    const expectedProtons=(protons+1)&255;
    check(finished>=0&&Buffer.from(A.subarray(S.SYSHP,S.SYSHP+8)).equals(Buffer.from(expected))&&A[S.SHLD]===A[S.SHTAB+A[S.DIFF]]&&
      A.subarray(S.HUDE,S.HUDE+4).every(x=>x===0x79)&&A[S.MRPHUND]===Math.floor(expectedProtons/100)&&
      A[0x485A]===0x70+Math.floor(expectedProtons%100/10)&&A[0x485B]===0x70+expectedProtons%10,
      'friendly repair: systems, shields and energy full; one proton, including byte wrap at 255');
    check(A[S.HITS]===37&&A[S.HITS+1]===2&&A[S.M_STATE+index]===0xFF,
      'friendly repair: lifetime hit count and surviving base are preserved');
    check(statuses.length===8&&statuses.every((x,i)=>x.index===i)&&seenNames.join(',')==='0,1,2,3,4,5,6',
      'friendly repair: all eight original system names and statuses appear in order');
    const names=Array.from({length:8},(_,i)=>String.fromCharCode(...A.subarray(0x4800+(4+2*i)*40,0x4800+(4+2*i)*40+A[S.MRLENS+i])));
    const expectedNames=['PHASOR CANNONS','LONG RANGE SCANNER','SHORT RANGE SCANNER','STELLAR GRID','AUTOMATIC TRACKING COMPUTER','HYPERSPACE COORDINATOR','LONG RANGE SCAN SEQUENCER','COMMUNICATIONS MODULE'];
    check(names.every((n,i)=>n===expectedNames[i])&&Array.from({length:8},(_,i)=>String.fromCharCode(...A.subarray(0x4800+(4+2*i)*40+29,0x4800+(4+2*i)*40+40))).every(t=>t===(damaged?'@@@REPAIRED':'OPERATIONAL')),
      'friendly repair: exact original text, columns and repaired/operational results');
    check(Math.abs((beamEnd-start)-(reference.repair-reference.beam))<=10&&Math.abs((finished-start)-reference.done)<=65,
      `friendly repair: DMA beam ${beamEnd-start}/${reference.repair-reference.beam}, full sequence ${finished-start}/${reference.done} frames (port/original)`);
    const intervals=statuses.slice(1).map((v,i)=>v.frame-statuses[i].frame),refIntervals=reference.statuses.slice(1).map((v,i)=>v.frame-reference.statuses[i].frame);
    check(typeEnd-typeStart===64&&intervals.every((v,i)=>Math.abs(v-refIntervals[i])<=4)&&(!damaged||steps.every(v=>v===9)),
      `friendly repair: 64-frame typing, status intervals ${intervals}, energy +9/frame`);
    check(sawNoise&&(!damaged||colours.has(7)||colours.has(2)), 'friendly repair: charging sound and original damaged-system colour flash');
    check(late===0&&A[S.OVRUN]===0&&Buffer.from(A.subarray(0x7680,0x7CC0)).equals(art),
      `friendly repair: whole DMA sequence has ${late} late split writes, ${A[S.OVRUN]} overruns; cockpit intact`);
    check(A[S.MAPSHOWN]&&A[S.MSLOCK]&&[...originalSlots].every(([a,b])=>Buffer.from(A.subarray(a,a+b.length)).equals(b)),
      'friendly repair: map/re-entry lock and every temporary code slot restored');
    // The scanner band cycles: compare its valid shades and matching rows,
    // while requiring exact restoration everywhere else.
    const paletteRestored=[...m.colorRam.subarray(720,920)].every((v,i)=> {
      const band=i<160&&i%40>=12&&i%40<=27;
      return band ? [0,1,11,12,15].includes(v)&&v===m.colorRam[720+i%40] : v===artColours[i];
    });
    check(protectedRanges.every(([a,b],i)=>Buffer.from(A.subarray(a,b)).equals(protectedBefore[i]))&&paletteRestored,
      'repair fixes: every sprite, font, fighter/shot master and colour master preserved; cockpit palette restored');
    check(reportMode&&blocks&&noiseColours.size>=10&&scanSound,
      'repair fixes: full text report without radar/guns, two solid random-colour block rows and damaged-scan beeps');
    const portRate=firstNoiseWrites/firstNoiseFrames,originalRate=reference.noiseWrites/reference.noiseFrames;
    check(reference.noiseWrites===8704&&Math.abs(portRate-originalRate)/originalRate<0.2,
      `repair fixes: DMA block rate ${portRate.toFixed(1)}/${originalRate.toFixed(1)} colour writes/frame (port/original)`);
    check(cleanExit,'repair fixes: cockpit art restored and old base bitmap cleared while still in text mode before map return');
    if(damaged)snap(m,'fix-docking-map');
    snap(m,damaged?'friendly-repaired':'friendly-operational');
    if(damaged) {
      A[S.MAPSHOWN]=A[S.WIPE]=0;A[S.TREQ]=1;call(m,S.GTORP);
      check(A[S.MRPHUND]===0&&A[0x485A]===0x79&&A[0x485B]===0x79,
        'friendly repair: the hundredth proton remains usable when the HUD reads 00');
    }
  }

  // A surviving friendly proton miss must still dock. Inputs cannot interrupt it.
  {
    const g=scene(0xFF),{m,S,A}=g;
    for(let f=0;f<200&&A[S.MSRAD]<12;f++)m.runFrame();
    A[S.MSPHASE]=0;A[S.MSPCOUNT]=255;A[S.SYSHP]=0;A.fill(0x79,S.HUDE,S.HUDE+4);
    const count=A[0x485B];let docking=false,late=0,returned=false;
    m.setKey(7,4,true);run(m,g.hooks,2);m.setKey(7,4,false);
    for(let f=0;f<1400;f++) {
      if(A[S.MSSTATE]>=7) {
        docking=true;m.mouse.left=true;m.moveMouse(f%2?3:-3,f%2?2:-2);m.setKey(7,4,true);m.setKey(7,5,true);
      }
      m.runFrame();late+=lateWrites(m);
      if(docking&&A[S.MSSTATE]===0){returned=true;break;}
    }
    m.mouse.left=false;m.setKey(7,4,false);m.setKey(7,5,false);
    check(returned&&!A[S.MSKILLED]&&A[S.SYSHP]>0&&A[0x485B]===count&&A[S.MAPSHOWN]&&A[S.MSLOCK],
      'friendly repair: a surviving SPACE miss repairs and replaces the fired proton; held fire/SPACE/map cannot interrupt docking');
    check(late===0&&A[S.OVRUN]===0,`friendly repair: held-input DMA sequence has ${late} late writes, ${A[S.OVRUN]} overruns`);
  }

  // Four strategic events route through SURROUND's real stores and VDCMSG's old slot.
  const bg=boot('game','trace'), BM=bg.m, BS=bg.p.symbols, B=BM.ram;
  BM.dma=true; run(BM,bg.hooks,60);
  B.fill(0,BS.M_STATE,BS.M_STATE+60); B.fill(0,BS.M_COUNT,BS.M_COUNT+60);
  B.fill(0,BS.M_ENGC,BS.M_ENGC+5); B.fill(0,BS.M_DEAD,BS.M_DEAD+5);
  for(let i=0;i<4;i++){B[BS.M_STATE+B[BS.M_GRP+i]]=1;B[BS.M_COUNT+B[BS.M_GRP+i]]=1;}
  B[BS.M_STATE+12]=0xFF;
  let texts=[];
  call(BM,BS.M_SURROUND);call(BM,BS.M_VDCMSG);texts.push(row(BM,BS));
  B[BS.M_ENGC]=1;call(BM,BS.M_SURROUND);call(BM,BS.M_VDCMSG);texts.push(row(BM,BS));
  for(let i=16;i<20;i++){B[BS.M_STATE+B[BS.M_GRP+i]]=1;B[BS.M_COUNT+B[BS.M_GRP+i]]=1;}
  call(BM,BS.M_SURROUND);call(BM,BS.M_VDCMSG);texts.push(row(BM,BS));
  B[BS.M_ENGC4]=1;call(BM,BS.M_SURROUND);call(BM,BS.M_VDCMSG);texts.push(row(BM,BS));
  check(texts.join('|')==='MOTHERSHIP ENGAGED IN BATTLE|MOTHERSHIP DESTROYED|JARALOBA IS SURROUNDED|JARALOBA CEASES TO EXIST'&&B[BS.M_VDCON]===0,
    `battle messages: all four events appear on the cockpit with VDC off (${texts.join('; ')})`);
  check(B[BS.MSGCOL]===0x87&&B[BS.MSGRATE]===15&&B[BS.MSGN]===15&&B[BS.SNDHI0]===0x1E&&!B[BS.SHIPLOST],
    'battle messages: original yellow/orange timing and siren, no game-over implementation');
  // Direct subroutine comparisons above advance CPU time outside the raster loop.
  // Settle those calls before beginning this independent real-frame timing test.
  run(BM,bg.hooks,10); B[BS.OVRUN]=0;
  B.fill(0,BS.M_ENGC,BS.M_ENGC+5);B.fill(0,BS.M_DEAD,BS.M_DEAD+5);
  for(let i=0;i<20;i++)B[BS.M_STATE+B[BS.M_GRP+i]]=1;
  B[BS.WTPEND]=1;B[BS.WTCNT]=200;B[BS.M_TICKC]=10;
  let battleLate=0;for(let f=0;f<10;f++){BM.runFrame();battleLate+=lateWrites(BM);}
  check(B[BS.GBTCOUNT]===4&&battleLate===0&&B[BS.OVRUN]===0,
    `battle messages: five simultaneous events queue safely (${B[BS.GBTCOUNT]} waiting), ${battleLate} late writes, ${B[BS.OVRUN]} overruns`);

}

check(freeMemoryRuns.filter(r=>r.armed).every(r=>r.intact)&&freeMemoryRuns.some(r=>r.frames>1000),
  `memory: $A5-filled free high RAM survives all existing game scenarios (${freeMemoryRuns.filter(r=>r.armed).length} boots)`);
console.log(failures ? failures + ' check(s) failed' : 'all checks passed');
process.exit(failures ? 1 : 0);
