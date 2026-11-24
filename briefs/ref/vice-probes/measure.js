// Spare processor cycles per frame in the game's wait loops (m.dma = true), by scenario.
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const ROOT = 'C:/dev/c64/sentinel/js';
global.CPU6502 = require(ROOT + '/src/cpu6502.js');
global.SentinelFont = require(ROOT + '/src/font.js');
global.SentinelVideo = require(ROOT + '/src/video.js');
global.SentinelDisasm = require(ROOT + '/src/disasm.js');
const C128 = require(ROOT + '/src/machine.js');
const Hooks = require(ROOT + '/src/hooks.js');
const Native = require(ROOT + '/src/native.js');
const ctx = {};
vm.runInNewContext(fs.readFileSync(ROOT + '/programs.js', 'utf8'), ctx);
const P = ctx.SENTINEL_PROGRAMS.game;

function boot() {
  const m = new C128(P.model);
  m.loadPrg(new Uint8Array(Buffer.from(P.prg, 'base64')));
  const hooks = new Hooks(m, P.symbols);
  Native.install(hooks, 'trace');
  m.start(P.entry);
  m.dma = true;
  return { m, hooks, s: P.symbols, K: m.ram };
}

// wait loops of the frame: [from, to) byte ranges
function ranges(s) {
  const r = (a, n) => [a, a + n];
  return [r(s.frame, 7), r(s.wl1, 7), r(s.wst1, 5), r(s.w251, s.w251ok - s.w251), r(s.vbw, 14)];
}

function instrument(g) {
  const m = g.m, c = m.cpu, s = g.s, R = ranges(s);
  const win = (pc) => { for (const [a, b] of R) if (pc >= a && pc < b) return true; return false; };
  const vbwA = s.vbw, vbwB = s.vbw + 14;
  const rec = { frames: [], cur: null };
  g.rec = rec;
  const reset = () => { rec.cur = { wait1: 0, wait2: 0, vbw: 0, cpu: 0, tag: null }; };
  reset();
  const step = c.step.bind(c);
  c.step = function () {
    const pc = this.pc, c0 = this.cycles, mhz = m.clockMHz();
    const r = step();
    const d = this.cycles - c0;
    rec.cur.cpu += d;
    if (win(pc)) { if (mhz === 2) rec.cur.wait2 += d; else rec.cur.wait1 += d; if (pc >= vbwA && pc < vbwB) rec.cur.vbw += d; }
    return r;
  };
  const onF = m.onFrame;
  m.onFrame = function (mm) {
    rec.cur.tag = g.tag ? g.tag() : null;
    rec.frames.push(rec.cur);
    reset();
    if (onF) onF(mm);
  };
}

const med = a => { const b = [...a].sort((x, y) => x - y); return b.length ? b[b.length >> 1] : NaN; };
function stat(frames, label) {
  if (!frames.length) { console.log(label.padEnd(44), 'no frames'); return; }
  const sp = frames.map(f => f.wait1 + f.wait2);
  const sp2 = frames.map(f => f.wait2), vb = frames.map(f => f.vbw);
  const mn = Math.min(...sp), mx = Math.max(...sp), avg = sp.reduce((x, y) => x + y, 0) / sp.length;
  console.log(label.padEnd(44), String(frames.length).padStart(5), 'frames; spare cpu cycles/frame min', String(mn).padStart(6), 'median', String(med(sp)).padStart(6),
    'mean', String(Math.round(avg)).padStart(6), 'max', String(mx).padStart(6), '| 2MHz part (border) median', String(med(sp2)).padStart(6), '| vbw median', String(med(vb)).padStart(6), 'min', Math.min(...vb));
}

function run(g, n, each) { for (let i = 0; i < n; i++) { if (each) each(i); if (!g.m.runFrame()) throw Error('stopped ' + g.m.stopped); } }
function mark(g) { return g.rec.frames.length; }
function since(g, i) { return g.rec.frames.slice(i); }
function dogfight(g) {
  const K = g.K, s = g.s;
  K[s.APPR] = 0; K[s.APRUN] = 0; K[s.LRMODE] = 0; K[s.SQCOUNT] = 200; K[s.CURG] = 0;
  K[s.GSIZE] = K[s.GSIZE + 1] = K[s.GSIZE + 2] = 200;
}
function call(m, a) {
  const c = m.cpu, pc = c.pc, sp = c.sp, p = c.p, ax = c.a, xx = c.x, yx = c.y;
  c.push(255); c.push(243); c.pc = a; c.p |= 4;
  let n = 0; const step = c.step; while (c.pc !== 0xFFF4 && n++ < 2e6) { c.step(); if (c.jam) throw Error(c.jam); }
  c.pc = pc; c.sp = sp; c.p = p; c.a = ax; c.x = xx; c.y = yx;
}

module.exports = { boot, run, instrument, dogfight, call, mark, since, stat, ranges };
if (require.main !== module) return;
const which = process.argv[2] || 'all';
const out = {};

if (which === 'all' || which === 'flight') {
  const g = boot(); instrument(g); const { m, K, s } = g;
  run(g, 60);
  let i = mark(g);
  run(g, 400, k => { if (k > 30) m.moveMouse(k % 60 < 30 ? 3 : -3, k % 80 < 40 ? 2 : -2); });
  stat(since(g, i), 'flight, empty sector (mouse moving)');
  i = mark(g); run(g, 300);
  stat(since(g, i), 'flight, empty sector (mouse still)');
  // map opening and open
  i = mark(g);
  run(g, 3, k => m.setKey(7, 5, true)); m.setKey(7, 5, false);
  let n = 0; while (!K[s.M_ICONDONE] && n++ < 600) run(g, 1);
  stat(since(g, i), 'map opening (until icons drawn)');
  i = mark(g); run(g, 300);
  stat(since(g, i), 'map open');
}

if (which === 'all' || which === 'fight') {
  const g = boot(); instrument(g); const { m, K, s } = g;
  run(g, 60);
  dogfight(g);
  run(g, 20);
  let i = mark(g);
  g.tag = () => (K[s.ALIVE] ? 1 : 0) + (K[s.ALIVE + 1] ? 1 : 0) + (K[s.ALIVE + 2] ? 1 : 0);
  run(g, 600, k => { m.moveMouse(k % 50 < 25 ? 3 : -3, k % 70 < 35 ? 2 : -2); m.mouse.left = (k % 10) < 5; });
  stat(since(g, i), 'fight, mouse moving + firing (all frames)');
  const fr = since(g, i);
  for (let a = 0; a <= 3; a++) stat(fr.filter(f => f.tag === a), `  ... with ${a} fighters alive`);
  i = mark(g);
  run(g, 300, k => { m.mouse.left = false; m.moveMouse(2, 1); });
  stat(since(g, i), 'fight, no firing');
}

if (which === 'all' || which === 'hyper') {
  const g = boot(); instrument(g); const { m, K, s } = g;
  run(g, 60);
  run(g, 300);
  run(g, 3, k => m.setKey(7, 5, true)); m.setKey(7, 5, false);
  run(g, 400);
  const st = [...K.subarray(s.M_STATE, s.M_STATE + 60)];
  const idx = st.findIndex(v => v >= 1 && v <= 3);
  for (let i = 0; i < 400; i++) {
    const tx = 17 + 12 * (idx % 10) + 6, ty = 35 + 16 * Math.floor(idx / 10) + 8;
    const dx = Math.max(-3, Math.min(3, tx - K[s.M_MPX])), dy = Math.max(-3, Math.min(3, ty - K[s.M_MPY]));
    if (!dx && !dy) break;
    m.moveMouse(dx, -dy); run(g, 1);
  }
  run(g, 2);
  g.tag = () => K[s.HYPON] * 10 + (K[s.WIPE] ? 1 : 0);
  const i0 = mark(g);
  run(g, 4, k => { m.mouse.left = k < 2; }); run(g, 2);
  let n = 0; for (; n < 4000 && (K[s.HYPON] || K[s.WIPE]); n++) { K[s.WTCNT] = 100; run(g, 1); }
  const fr = since(g, i0);
  stat(fr, `hyperspace jump (whole, ${n} frames)`);
  const tags = [...new Set(fr.map(f => f.tag))].sort((a, b) => a - b);
  for (const t of tags) stat(fr.filter(f => f.tag === t), `  ... HYPON=${Math.floor(t / 10)} WIPE=${t % 10}`);
  // after the arrival: the fight in the destination sector
  run(g, 60);
  g.tag = () => (K[s.ALIVE] ? 1 : 0) + (K[s.ALIVE + 1] ? 1 : 0) + (K[s.ALIVE + 2] ? 1 : 0);
  let j = mark(g);
  run(g, 900, k => { m.moveMouse(k % 50 < 25 ? 3 : -3, k % 70 < 35 ? 2 : -2); m.mouse.left = (k % 10) < 5; });
  const fr2 = since(g, j);
  stat(fr2, 'fight after the jump (moving + firing)');
  for (let q = 0; q <= 3; q++) stat(fr2.filter(f => f.tag === q), `  ... with ${q} fighters alive`);
  console.log('   hits taken', K[s.HITS], 'shields', K[s.SHLD], 'fgdone', K[s.FGDONE], 'OVRUN', K[s.OVRUN]);
}

if (which === 'all' || which === 'base') {
  for (const kind of [0x80, 0xFF]) {
    const g = boot(); instrument(g); const { m, K, s } = g;
    run(g, 60);
    const idx = K[s.M_SELY] * 10 + K[s.M_SELX];
    K[s.M_STATE + idx] = kind; K[s.M_COUNT + idx] = 0;
    call(m, s.SECTORIN);
    g.tag = () => K[s.MSSTATE] * 1000 + (m.vic[0x1A] & 1) * 100 + (K[s.MTAGE] ? 10 : 0);
    const i0 = mark(g);
    let n = 0;
    for (; n < 4000; n++) { run(g, 1, k => { if (n > 300) m.moveMouse(n % 60 < 30 ? 2 : -2, 1); }); if (!K[s.MSSTATE] && n > 50) break; }
    const fr = since(g, i0);
    stat(fr, `base sector kind $${kind.toString(16)}: whole sequence (${n} frames)`);
    const tags = [...new Set(fr.map(f => f.tag))].sort((a, b) => a - b);
    for (const t of tags) stat(fr.filter(f => f.tag === t), `  ... MSSTATE=${Math.floor(t / 1000)} IRQ=${Math.floor(t / 100) % 10} tunnel=${Math.floor(t / 10) % 10}`);
  }
}
