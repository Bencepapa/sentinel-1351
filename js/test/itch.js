'use strict';
// The minimal itch.io page: the hi-score logic (the rating against the original $F440, the end of
// a game found by the hooks in the C64 original and in the C128 port, the score store) and the
// audio start fallbacks (issue #14). The DOM part of the page (js/src/itch.js) is checked by
// building it and, by hand, in a browser (js/README.md).
module.exports = function ({ boot, run, check, fs, path, ROOT }) {
  const vm = require('vm');
  const HI = require('../src/hiscore.js');
  const SentinelAudio = require('../src/audio.js');
  const state = n => JSON.parse(fs.readFileSync(path.join(__dirname, '../../briefs/ref/' + n), 'utf8')).state;
  const call = (m, a) => {
    const c = m.cpu, saved = [c.pc, c.sp, c.p];
    c.push(255); c.push(243); c.pc = a; c.p |= 4;
    let n = 0; while (c.pc !== 0xfff4 && n++ < 2e6) { c.step(); if (c.jam) throw Error(c.jam); }
    const r = { a: c.a, x: c.x, y: c.y }; [c.pc, c.sp, c.p] = saved; return r;
  };

  const hudAt = (m, at = 0x544a) => {
    const d = i => m.ram[at + i] - 0x70;
    return (d(0) * 10 + d(1)) * 60 + d(3) * 10 + d(4);
  };
  const clockState = ({ m, p: { symbols: s } }) =>
    [m.ram[s.CLOCKDIV], m.ram[s.CLOCKHOURS], ...m.ram.subarray(s.HUDTIME, s.HUDTIME + 5)].join();
  const zeroClock = [60, 0, 0x70, 0x70, 0x6e, 0x70, 0x70].join();
  const setClock = ({ m, p: { symbols: s } }, digits, hours, div) => {
    const colon = div <= 30 ? 0x60 : 0x6e;
    m.ram.set([...digits].map(c => c === ':' ? colon : 0x70 + Number(c)), s.HUDTIME);
    m.ram[s.CLOCKHOURS] = hours;
    m.ram[s.CLOCKDIV] = div;
  };
  // the statistics as the C64 game holds them just before JSR $F440 (read here independently of hiscore.js)
  const c64Raw = (m, secs) => {
    const R = m.ram;
    let mothers = 0, bases = 0;
    for (const a of [0, 9, 50, 59]) if (R[0x33c + a] !== 0x80) mothers++;
    for (const a of [12, 17, 42, 47]) if (R[0x33c + a] === 0xff) bases++;
    return { diff: R[0xe0], kills: (R[0xf434] | R[0xf435] << 8) - 1, mothers, bases, elapsed: secs };
  };

  // ---- the rating: the port of $F440 against the original, and rate() against its registers ----
  {
    const o = boot('c64game', 'trace'), R = o.m.ram;
    o.m.loadState(o.m.stateFromText(JSON.stringify(state('c64-minefield.state.json'))));
    let seed = 12345, rnd = n => { seed = (Math.imul(seed, 1103515245) + 12345) >>> 0; return (seed >>> 8) % n; };
    let cases = 0, bad = null;
    const put = (a, v, n) => { for (let i = 0; i < n; i++) R[a + i] = (v >>> (8 * i)) & 255; };
    for (let t = 0; t < 4000 && !bad; t++) {
      const i = {
        diff: rnd(5), victory: rnd(2), planet: rnd(2), hits: rnd(t % 3 ? 40 : 65536), kills: rnd(t % 4 ? 60 : 65536),
        energy: rnd(t % 5 ? 300000 : 0x1000000), protons: rnd(t % 3 ? 12 : 65536), shots: rnd(t % 2 ? 400 : 65536),
      };
      const orange = [0, 9, 50, 59], blue = [12, 17, 42, 47];
      i.mothers = 0; i.bases = 0;
      orange.forEach(a => { const v = rnd(3) ? 0x80 : 0; R[0x33c + a] = v; if (v !== 0x80) i.mothers++; });
      blue.forEach(a => { const v = rnd(3) ? 0xff : 0; R[0x33c + a] = v; if (v !== 0xff) i.bases++; });
      R[0xe0] = i.diff; R[0xf34b] = i.victory ? 4 : 0; R[0xf431] = i.planet;
      put(0xf432, i.hits, 2); put(0xf434, i.kills, 2); put(0xf436, i.energy, 3); put(0xf439, i.protons, 2); put(0xf43b, i.shots, 2);
      const r = call(o.m, 0xf440), mine = HI.rating(i), rated = HI.rate(R[0xf43d], R[0xf43e], i.diff), again = HI.rate(mine.lo, mine.hi, i.diff);
      cases++;
      // the original's registers: A = class, X = rank; its clamped low byte stays in $F43D
      if (r.x !== rated.x || r.a !== rated.cls || rated.lo !== R[0xf43d] || again.x !== r.x || again.lo !== R[0xf43d] || again.cls !== r.a)
        bad = JSON.stringify({ i, orig: r, f43d: R[0xf43d], f43e: R[0xf43e], mine, rated, again });
    }
    check(!bad, `itch: ${cases} random games: the JS rating, rank and class equal the original $F440's${bad ? ' ' + bad : ''}`);
  }

  // ---- the point score, result, names, the store ---------------------------------------------
  {
    const S = HI.score;
    check(S({ victory: true, diff: 0, kills: 0, mothers: 0, bases: 0, elapsed: 6000 }).points === 0, 'itch: nothing done and no time left is 0 points');
    check(S({ victory: true, diff: 2, kills: 7, mothers: 3, bases: 4, elapsed: 600 }).points === 300 + 400 + 5400 + 7 * 30 &&
      S({ victory: true, diff: 4, kills: 7, mothers: 0, bases: 0, elapsed: null }).points === 7 * 50 && S({ victory: true, diff: 0, kills: 7, mothers: 0, bases: 0 }).points === 70,
      'itch: a victory scores 100 per mothership destroyed + 100 per base left + (6000 - seconds) + 10 (difficulty + 1) per fighter; with no clock, no time term');
    const lost = S({ victory: false, diff: 2, kills: 7, mothers: 3, bases: 4, elapsed: 20 });
    check(lost.points === 300 + 7 * 30 && lost.parts.bases === 0 && lost.parts.time === 0 && S({ diff: 0, kills: 0, mothers: 0, bases: 4, elapsed: 5 }).points === 0,
      'itch: a loss keeps the kills and the motherships but not the bases left nor the time (dying at once with nothing done is 0)');
    const d = [0, 1, 2, 3, 4].map(k => S({ diff: k, kills: 10 }).points);   // (lost or won: the kills count always)
    check(d.join() === '100,200,300,400,500', 'itch: a fighter is worth 10, 20, 30, 40, 50 by difficulty 0-4 (' + d + ')');
    check(S({ victory: true, diff: 0, kills: 0, mothers: 0, bases: 0, elapsed: 99999 }).parts.time === 0 && S({ victory: true, diff: 9, kills: -4, mothers: -1, bases: -1, elapsed: -5 }).points === 6000,
      'itch: the time term is never negative (past 6000 s) and nonsense inputs are clamped');
    check(S({ victory: true, diff: 4, kills: 99999, mothers: 4, bases: 4, elapsed: 0 }).points === 999999, 'itch: the score is capped at 999999');
    const cells = new Uint8Array(60); [0, 9, 50, 59].forEach((a, i) => { cells[a] = i < 3 ? 0x80 : 0; }); [12, 17, 42, 47].forEach((a, i) => { cells[a] = i < 3 ? 0xFF : 0; });
    const mc = HI.mapCounts(a => cells[a]);
    check(mc.mothers === 1 && mc.bases === 3, 'itch: the map\'s corner cells give the motherships destroyed ($80 = still there) and the bases left ($FF)');
    const hud = str => { const R = new Uint8Array(0x10000); R[0x544A] = 0x70 + +str[0]; R[0x544B] = 0x70 + +str[1]; R[0x544C] = 0x6E; R[0x544D] = 0x70 + +str[3]; R[0x544E] = 0x70 + +str[4]; return HI.hudSeconds(R); };
    check(hud('01:04') === 64 && hud('59:59') === 3599 && hud('00:00') === 0 && hud('12:34') === 754 && HI.hudSeconds(new Uint8Array(0x10000)) === null,
      'itch: the C64 HUD clock MM:SS reads as seconds, null when the HUD text is not there');
    const a = HI.result(0xff, 0x80 + 7, 4, true, undefined, { diff: 4, kills: 20, mothers: 4, bases: 4, elapsed: 1000 }), b = HI.result(0, 0x10, 2, false), c = HI.result(0x40, 0x84, 2, false);
    const lose = HI.result(0, 0x10, 2, false, undefined, { diff: 2, kills: 4, mothers: 1, bases: 3, elapsed: 30 });
    check(lose.points === 100 + 4 * 30 && lose.text === '000220', `itch: result() of a loss has no base or time bonus (${lose.text})`);
    check(a.points === 400 + 400 + 5000 + 20 * 50 && a.text === '006800' && a.name === 'STAR SENTINEL' && a.cls === 1 && a.rank === 7,
      `itch: result() takes the points from the statistics and the name and class from the rating (${a.text} ${a.name} ${a.cls})`);
    check(b.points === 0 && b.text === '000000' && b.rank === 0 && b.name === 'SPACE DROID' && b.cls === 8,
      `itch: without statistics the score is 000000, the lowest rating SPACE DROID class 8 (${b.text} ${b.name} ${b.cls})`);
    check(c.rank === 0 && HI.result(0x40, 0x84, 3, false).rank === 4,
      'itch: after a defeat at difficulty 0-2 the name is the original\'s four-name subset (rank and 3), at 3-4 the full table');
    check(HI.pad6(7) === '000007' && HI.pad6(1234567) === '999999' && HI.pad6(-3) === '000000', 'itch: scores print as six digits');
    let mem = {}; const ok = { getItem: k => (k in mem ? mem[k] : null), setItem: (k, v) => { mem[k] = String(v); } };
    const s1 = new HI.Store(ok);
    const r1 = s1.submit('game', 500), r2 = s1.submit('game', 300), r3 = s1.submit('game', 900), r4 = s1.submit('c64game', 20);
    check(r1.isNew && r1.best === 500 && !r2.isNew && r2.best === 500 && r3.isNew && r3.best === 900 && r4.best === 20 &&
      s1.get('game') === 900 && s1.get('c64game') === 20 && new HI.Store(ok).get('game') === 900 && new HI.Store(ok).get('none') === 0,
      'itch: the store keeps the best score per program, also for a new store on the same storage');
    const broken = { getItem() { throw new Error('denied'); }, setItem() { throw new Error('denied'); } };
    const s2 = new HI.Store(broken); s2.submit('game', 70);
    const s3 = new HI.Store(null); s3.submit('game', 80);
    mem = { 'sentinel-itch-hi-game': 'garbage' };
    check(s2.get('game') === 70 && s3.get('game') === 80 && new HI.Store(ok).get('game') === 0,
      'itch: storage that throws, is missing or holds garbage keeps scores in memory / reads 0 and never throws');
  }

  // ---- the C128 clock against raster IRQ ticks in the C64 original --------------------------
  {
    const o = boot('c64game', 'trace'), k = boot('game', 'trace');
    const m = k.m, s = k.p.symbols, B = m.ram;
    o.m.dma = m.dma = true;
    o.hooks.fixC64Original();   // keep the C64's IRQ chain alive through startup
    let originalTicks = 0;
    const original = [], originalBlinks = [];
    o.hooks.on('$FAD7', () => { originalTicks++; });
    o.hooks.on('$FAE9', () => original.push([o.m.frame, originalTicks]));
    o.hooks.on('$FB36', () => originalBlinks.push([originalTicks, o.m.ram[0x544c] ^ 0x0e]));
    run(o.m, o.hooks, 745, f => { o.m.mouse.left = (f >= 300 && f < 310) || (f >= 450 && f < 460); });

    const port = [], portBlinks = [];
    let portTicks = 0, initial, previous = 0, previousColon = 0x6e, late = 0, mapSecond = false;
    k.hooks.on('CLOCKTICK', () => {
      if (++portTicks === 1) initial = clockState(k);
    });
    const frame = () => {
      m.runFrame();
      const log = m.vicLog;
      for (let i = 0; i < log.length; i += 4) {
        const line = log[i], cycle = log[i + 1], reg = log[i + 2];
        if ((reg === 32 || reg === 33) && ((line >= 50 && line <= 76) || (line >= 230 && line <= 245)) &&
            cycle >= 16 && cycle <= 55) late++;
      }
    };
    for (let f = 0; f < 320; f++) {
      m.setKey(7, 5, f >= 125 && f < 129);
      frame();
      if (!portTicks) continue;
      const secs = hudAt(m, s.HUDTIME);
      if (secs !== previous) {
        port.push([m.frame, portTicks, secs]);
        previous = secs;
        mapSecond ||= !!B[s.MAPSHOWN];
      }
      const colon = B[s.HUDTIME + 2];
      if (colon !== previousColon) {
        portBlinks.push([portTicks, colon]);
        previousColon = colon;
      }
    }
    const gaps = samples => samples.slice(1).map(([f], i) => f - samples[i][0]);
    check(initial === zeroClock && s.HUDTIME === 0x484a,
      'itch: the C128 HUD starts at 00:00 in the original TIME field');
    check(original.length >= 4 && port.length >= 4 && gaps(original).every(n => n === 60) &&
      gaps(port).every(n => n === 60) && original.every(([, n], i) => n === (i + 1) * 60) &&
      port.every(([, n, secs], i) => n === (i + 1) * 60 && secs === i + 1) && mapSecond,
      `itch: C128 clock matches the C64 IRQ cadence in flight and runs with the map open (${gaps(original)} vs ${gaps(port)} frames)`);
    check(portBlinks.length >= 8 && portBlinks.every(([n, colon], i) =>
      originalBlinks[i]?.[0] === n && originalBlinks[i][1] === colon),
      'itch: the C128 colon blinks on the same 30-frame ticks as the original');
    setClock(k, '09:59', 0, 1); frame();
    const ten = hudAt(m, s.HUDTIME) === 600 && B[s.HUDTIME + 2] === 0x6e;
    setClock(k, '59:59', 0, 1); frame();
    check(ten && hudAt(m, s.HUDTIME) === 0 && B[s.CLOCKHOURS] === 1 && B[s.CLOCKDIV] === 60 && B[s.HUDTIME + 2] === 0x6e,
      'itch: 09:59 carries to 10:00 and 59:59 wraps to 00:00, preserving the elapsed hour and colon');
    check(!m.stopped && late === 0 && B[s.OVRUN] === 0,
      `itch: the C128 clock and worst-case carry fit the DMA raster budget (${late} late splits, ${B[s.OVRUN]} OVRUN)`);
  }

  // ---- the end of a game, seen by the hooks -------------------------------------------------
  {   // C64 original, death: the supplied minefield save, shields lost
    const k = boot('c64game', 'trace'), m = k.m;
    m.loadState(m.stateFromText(JSON.stringify(state('c64-minefield.state.json')))); m.dma = true; m.ram[0x8300] = 255;
    const got = []; let regs = null, raw = null, secs = hudAt(m), hudAtEnd = null;   // (the clock has no variable: the test counts the HUD's seconds itself)
    k.hooks.on('$FAE9', () => { secs++; });
    k.hooks.on('$F3CE', () => { raw = c64Raw(m, secs); hudAtEnd = hudAt(m); });   // (registered first: runs before the watcher's)
    k.hooks.on('$F3D1', () => { regs = { a: m.cpu.a, x: m.cpu.x }; });
    const w = HI.watch(m, k.hooks, 'c64game', k.p.symbols, r => got.push(r)); w.rearm();   // (as after a quick load: the clock starts from the HUD)
    for (let f = 0; f < 900 && !got.length; f++) m.runFrame();
    run(m, k.hooks, 5);
    const r = got[0];
    check(got.length === 1 && regs && raw && r.cls === (regs.a ^ 7) + 1 && r.points === HI.score(Object.assign({ victory: false }, raw)).points && r.points === 10 * (raw.diff + 1) * raw.kills + 100 * raw.mothers && !r.victory && r.name.length > 0 && r.rank === HI.rankIndex(regs.x, raw.diff, false) && r.parts.time === 0 && r.parts.bases === 0 && raw.elapsed >= 18 && !(hudAtEnd >= 0) && raw.bases === 4 && raw.kills === 0 && r.text === '000000',
      `itch: the C64 original's death is found once (the death scene has cleared the HUD digits, the counted clock still gives the time): ${r && r.text} ${r && r.name} class ${r && r.cls} (original A=${regs && regs.a} X=${regs && regs.x}; ${JSON.stringify(raw)})`);
  }
  {   // C64 original, victory: the last enemy mothership save
    const k = boot('c64game', 'trace'), m = k.m;
    m.loadState(m.stateFromText(JSON.stringify(state('c64-last-enemy-map-then-win.state.json')))); m.dma = true;
    const got = []; let regs = null, raw = null, hudAtEnd = null;
    k.hooks.on('$F3CE', () => { hudAtEnd = hudAt(m); raw = c64Raw(m, hudAtEnd); });   // here the HUD still shows the time: the page's count must equal it
    k.hooks.on('$F3D1', () => { regs = { a: m.cpu.a, x: m.cpu.x }; });
    const w = HI.watch(m, k.hooks, 'c64game', k.p.symbols, r => got.push(r)); w.rearm();
    for (let f = 0; f < 400 && !got.length; f++) m.runFrame();
    run(m, k.hooks, 5);
    const r = got[0];
    check(got.length === 1 && regs && raw && r.victory && r.cls === (regs.a ^ 7) + 1 && r.points === HI.score(Object.assign({ victory: true }, raw)).points && r.name === HI.RANKS[regs.x] && raw.mothers === 4 && raw.elapsed > 0 && raw.elapsed < 600 && r.parts.time === 6000 - hudAtEnd,
      `itch: the C64 original's victory is found once: ${r && r.text} ${r && r.name} class ${r && r.cls} (original A=${regs && regs.a} X=${regs && regs.x}; ${JSON.stringify(raw)})`);
  }
  {   // C128 port: death by the ship's loss, and victory with the map cleared
    const ready = () => { const k = boot('game', 'trace'); k.m.dma = true; run(k.m, k.hooks, 80); return k; };
    const k = ready(), m = k.m, B = m.ram, T = k.p.symbols, got = [];
    HI.watch(m, k.hooks, 'game', T, r => got.push(r));
    B[T.KILLS] = 3; B[T.KILLS + 1] = 0; B[T.DIFF] = 4;
    [0, 9, 50, 59].forEach((a, i) => { B[T.M_STATE + a] = i < 2 ? 0x80 : 0; }); [12, 17, 42, 47].forEach((a, i) => { B[T.M_STATE + a] = i < 3 ? 0xFF : 0; });
    let deathClock;
    k.hooks.on('ENDSTOPXY', () => {
      setClock(k, '12:34', 1, 1);
      deathClock = clockState(k);
    });
    B[T.SHIPLOST] = 1; call(m, T.ENDARM);
    for (let f = 0; f < 900 && !got.length; f++) m.runFrame();
    run(m, k.hooks, 5);
    const r = got[0];
    check(got.length === 1 && r && !r.victory && r.rank === B[T.ENDRANK] && r.cls === (B[T.ENDCLASS] ^ 7) + 1 && r.name === HI.RANKS[B[T.ENDRANK]],
      `itch: the C128 port's death is found once: ${r && r.text} ${r && r.name} class ${r && r.cls}`);
    check(r && r.points === 2 * 100 + 3 * 50 && r.parts.time === 0 && r.parts.bases === 0,
      `itch: the C128 port's lost game: 2 motherships destroyed, 3 kills at difficulty 4, the 3 bases left do not count = 350 (${r && r.text})`);
    check(clockState(k) === deathClock, 'itch: the C128 clock and its frame divider freeze through the death scene');
    B[T.ENDTIME] = 1; B[T.ENDTIME + 1] = 0;
    m.setBreak(T.CLOCKTICK, true);
    for (let f = 0; f < 100 && !m.breakInfo; f++) m.runFrame();
    check(m.cpu.pc === T.CLOCKTICK && B[T.ENDMODE] === 0 && clockState(k) === zeroClock,
      'itch: the C128 game-over reset clears the HUD, hours and frame divider before the first gameplay tick');
    // the rating stays the same for the same statistics, in the original and in the port
    const j = ready(), jm = j.m, JB = jm.ram, got2 = [];
    HI.watch(jm, j.hooks, 'game', j.p.symbols, x => got2.push(x));
    JB.fill(0, T.M_STATE, T.M_STATE + 60); JB.fill(0, T.M_FLG, T.M_FLG + 4); JB[T.ENDQUAL] = 1; JB[T.KILLS] = 5; JB[T.KILLS + 1] = 0; JB[T.DIFF] = 2;
    let winClock;
    j.hooks.on('ENDSTOPXY', () => {
      setClock(j, '01:37', 1, 1);
      winClock = clockState(j);
    });
    JB[T.M_STATE + 12] = 0xFF; JB[T.M_STATE + 17] = 0xFF; call(jm, T.ENDTRYWIN);
    for (let f = 0; f < 700 && !got2.length; f++) jm.runFrame();
    run(jm, j.hooks, 80);
    const w = got2[0];
    check(got2.length === 1 && w && w.victory && w.rank === JB[T.ENDRANK] && w.cls === (JB[T.ENDCLASS] ^ 7) + 1 &&
      w.parts.time === 6000 - 3697 && w.points === 400 + 200 + 5 * 30 + w.parts.time,
      `itch: the C128 port's victory scores 750 combat/base points plus the bonus for 3697 seconds: ${w && w.text} ${w && w.name} class ${w && w.cls}`);
    check(clockState(j) === winClock, 'itch: the C128 clock and its frame divider freeze through the victory screen');
  }

  // ---- frame pacing: the C64 unpack at full speed ends inside a tick (a 10+ s stall at the title) ---------
  {
    const Pacing = require('../src/pacing.js');
    const sim = (unpackEnd, speed) => {          // 60 Hz display ticks, 2 ms of CPU per emulated frame
      let T = 0, frame = 0, fast = unpackEnd > 0, endT = -1, worstTick = 0, firstAfter = -1;
      const p = new Pacing.Pacer(), times = [];
      for (let k = 0; k < 60 * 30; k++) {
        const t0 = T, c = { speed, budgetMs: 14, now: () => T, isFast: () => fast,
          frame: () => { T += 2; frame++; times.push(T); if (fast && frame >= unpackEnd) { fast = false; endT = T; } return true; } };
        const r = p.tick(1000 / 60, c);
        worstTick = Math.max(worstTick, T - t0);
        if (endT >= 0 && firstAfter < 0 && frame > unpackEnd) firstAfter = times[unpackEnd] - endT;
        T = Math.max(T, (k + 1) * 1000 / 60);
      }
      return { frame, endT, worstTick, firstAfter, T, times };
    };
    const r = sim(175, 1), afterFrames = r.times.filter(t => t > r.endT).length, afterSecs = (r.T - r.endT) / 1000;
    check(r.endT > 0 && r.endT < 600 && r.firstAfter >= 0 && r.firstAfter < 60,
      `itch: the unpacker's fast frames end in under 0.6 s and the first frame at normal speed follows within 60 ms (end ${r.endT.toFixed(0)} ms, next ${r.firstAfter.toFixed(0)} ms)`);
    check(Math.abs(afterFrames / afterSecs - 50) < 3, `itch: after the unpack the game runs at 50 frames a second, with no debt of the fast frames (${(afterFrames / afterSecs).toFixed(1)} a second)`);
    check(r.worstTick < 20, `itch: no tick runs the rest of its 1000 frames unthrottled after the unpack ends (longest tick ${r.worstTick} ms)`);
    const n = sim(0, 1), f5 = sim(0, 5);
    check(Math.abs(n.frame / (n.T / 1000) - 50) < 3, `itch: normal speed is 50 frames a second (${(n.frame / (n.T / 1000)).toFixed(1)})`);
    check(f5.frame / (f5.T / 1000) > 150 && f5.worstTick < 20, `itch: 5x speed runs as many frames as the 14 ms budget allows (${(f5.frame / (f5.T / 1000)).toFixed(0)} a second, longest tick ${f5.worstTick} ms)`);
  }

  // ---- audio: the synth in the worklet, and the start fallbacks (issue #14) ----------------------
  {
    const noise = (e, n) => { let peak = 0; for (let i = 0; i < n; i += 128) { const out = new Float32Array(128); e.render(out); for (const v of out) peak = Math.max(peak, Math.abs(v)); } return peak; };
    const e = SentinelAudio.createEngine(48000);
    const play = (e2) => {   // volume 15, voice 1: sawtooth ~440 Hz, instant attack, full sustain, gate on
      const log = [0, 24, 15, 0, 0, 0x1d, 0, 1, 0x45, 0, 5, 0x00, 0, 6, 0xf0, 0, 4, 0x21];
      e2.message({ frameStart: 0, log });
    };
    play(e);
    check(noise(e, 4800) > 0.05, 'itch: the SID engine plays a note from a register log');
    e.message({ reset: true, cycle: 0 });
    check(noise(e, 2400) < 1e-6, 'itch: a reset silences the engine');
    // the worklet module text runs as an AudioWorklet module would and registers its processor
    let registered = null;
    const sandbox = { AudioWorkletProcessor: class { constructor() { this.port = {}; } }, registerProcessor: (n, c) => { registered = [n, c]; }, sampleRate: 48000 };
    vm.runInNewContext(SentinelAudio.moduleSource(), sandbox);
    const proc = registered && new registered[1]();
    if (proc) { proc.port.onmessage({ data: { frameStart: 0, log: [0, 24, 15, 0, 0, 0x1d, 0, 1, 0x45, 0, 5, 0, 0, 6, 0xf0, 0, 4, 0x21] } }); }
    const block = [[new Float32Array(128)]];
    let peak = 0; if (proc) for (let i = 0; i < 40; i++) { proc.process([], block); for (const v of block[0][0]) peak = Math.max(peak, Math.abs(v)); }
    check(registered && registered[0] === 'sid-processor' && peak > 0.05, 'itch: the worklet module text registers "sid-processor" and plays');

    // start(): blob URL worklet, then data URL, then ScriptProcessor; each only after the one before failed
    const attempt = (blobWorks, dataWorks, hasWorklet) => new Promise(resolve => {
      const urls = [];
      const mkCtx = () => ({
        state: 'suspended', sampleRate: 48000, destination: {},
        resume() { this.state = 'running'; return Promise.resolve(); },
        audioWorklet: hasWorklet ? { addModule(u) { urls.push(u.split(':')[0]); return (u.startsWith('blob:') ? blobWorks : dataWorks) ? Promise.resolve() : Promise.reject(new Error('blocked')); } } : undefined,
        createScriptProcessor() { return { connect() {}, port: null }; },
      });
      global.window = { AudioContext: function () { return mkCtx(); }, AudioWorkletNode: hasWorklet ? function () { this.connect = () => {}; this.port = { postMessage() {} }; } : undefined };
      global.document = { addEventListener() {}, hidden: false };
      const a = new SentinelAudio();
      a.start().then(() => resolve({ kind: a.kind, urls }));
    });
    const prevWarn = console.warn;
    const rs = [];   // (one after the other: each sets its own fake window)
    return attempt(true, true, true).then(r => { rs.push(r); return attempt(false, true, true); }).then(r => { rs.push(r); return attempt(false, false, true); })
      .then(r => { rs.push(r); return attempt(true, true, false); }).then(r => { rs.push(r);
      const [r1, r2, r3, r4] = rs;
      check(r1.kind === 'worklet-blob' && r2.kind === 'worklet-data' && r2.urls.join() === 'blob,data' && r3.kind === 'script' && r4.kind === 'script',
        `itch: audio starts by blob worklet, else data-URL worklet, else ScriptProcessor (${rs.map(r => r.kind).join(', ')})`);
      delete global.window; delete global.document; console.warn = prevWarn;
    });
  }
};
