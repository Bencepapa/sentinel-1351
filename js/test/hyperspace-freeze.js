'use strict';
// Issue #13: the fighters seen on the long range scanner during a jump must be there on arrival.
//
// The C64 original does NOT freeze the world in hyperspace: its jump loop ($B55D-$B6CE) calls the map's
// tick $BE29 every 128 passes (about every 44 frames, none in the acceleration $B3F6-$B55C and none in
// the deceleration $B6CF), and every 16th tick moves all squadrons: a type 1 hunter heads for the ship's
// sector, so it leaves a far destination. Its scanner then blanks the blips at once ($B696-$B6A6); the port
// used to keep the blips of the jump's start while the table moved on, so the sector was empty on arrival.
// The port now holds the whole world (no tick, none pending) from the path plot to the arrival.
module.exports = function ({boot, run, check}) {
  // the table both sides start with: the ship at 4,2 (index 24); a hunter (type 1, five ships) at 8,3 (38)
  const TABLE = {1: [1, 3], 6: [1, 3], 21: [2, 4], 28: [3, 6], 38: [1, 5], 55: [2, 3]};
  const HUNTER = 38;

  function original() {
    const k = boot('c64game', 'trace'), m = k.m, R = m.ram;
    run(m, k.hooks, 300);
    run(m, k.hooks, 300, i => { m.mouse.left = (i >= 0 && i < 10) || (i >= 150 && i < 160); });
    m.mouse.left = false;
    run(m, k.hooks, 200);
    m.setKey(7, 5, true); run(m, k.hooks, 4); m.setKey(7, 5, false);
    run(m, k.hooks, 20);
    R.fill(0, 0x33C, 0x33C + 120);
    for (const b of [12, 17, 42, 47]) R[0x33C + b] = 0xFF;
    for (const b of [0, 9, 50, 59]) { R[0x33C + b] = 0x80; R[0x378 + b] = 1; }
    for (const [i, [t, n]] of Object.entries(TABLE)) { R[0x33C + +i] = t; R[0x378 + +i] = n; }
    R[0x20E2] = R[0xDF] = HUNTER % 10; R[0x20E1] = R[0xDE] = Math.floor(HUNTER / 10);
    const cell = () => R[0x33C + HUNTER] + '/' + R[0x378 + HUNTER];
    const ev = {phase: '', ticks: {accel: 0, jump: 0, decel: 0}, passes: 0, start: '', frames: {}};
    let t0 = 0;
    k.hooks.on(0xB3E0, () => { ev.phase = 'accel'; t0 = m.frame; R[0xBDAF] = 17; R[0xBDB0] = 1; });   // the first tick of the jump moves the squadrons
    k.hooks.on(0xB55D, () => { ev.phase = 'jump'; ev.start = cell(); ev.frames.jump = m.frame - t0; });
    k.hooks.on(0xB6CF, () => { ev.phase = 'decel'; ev.frames.decel = m.frame - t0; });
    k.hooks.on(0xFC9D, () => { ev.phase = 'done'; ev.end = cell(); });
    k.hooks.on(0xBE29, () => { if (ev.ticks[ev.phase] !== undefined) ev.ticks[ev.phase]++; });
    k.hooks.on(0xBEC1, () => { if (ev.phase === 'jump') ev.passes++; });
    m.joy2 = 16;
    for (let f = 0; f < 4000 && ev.phase !== 'done'; f++) m.runFrame();
    m.joy2 = 0;
    return ev;
  }

  {
    const ev = original();
    check(ev.phase === 'done' && ev.ticks.accel === 0 && ev.ticks.decel === 0 && ev.ticks.jump >= 8 &&
      ev.frames.decel - ev.frames.jump > 33 * ev.ticks.jump && ev.frames.decel - ev.frames.jump < 55 * ev.ticks.jump,
      `c64 original: the jump loop ticks the world every ${((ev.frames.decel - ev.frames.jump) / ev.ticks.jump).toFixed(0)} frames ` +
      `(${ev.ticks.jump} ticks), the acceleration (${ev.ticks.accel}) and the deceleration (${ev.ticks.decel}) none`);
    check(ev.passes === 1 && ev.start === '1/5' && ev.end === '0/0',
      `c64 original: a squadron move runs in the jump (${ev.passes}): the destination's hunter ${ev.start} is ${ev.end} on arrival`);
  }

  function lateWrites(m) {
    let late = 0;
    for (let i = 0; i < m.vicLog.length; i += 4) {
      const [line, cycle, register] = m.vicLog.slice(i, i + 3);
      if ((register === 32 || register === 33) && cycle >= 16 && cycle <= 55 &&
          ((line >= 50 && line <= 76) || (line >= 230 && line <= 245))) late++;
    }
    return late;
  }

  {
    const g = boot('game', 'trace'), {m, hooks, p} = g, s = p.symbols, K = m.ram;
    m.dma = true;
    run(m, hooks, 60);
    K.fill(0, s.M_STATE, s.M_STATE + 60); K.fill(0, s.M_COUNT, s.M_COUNT + 60);
    for (const b of [12, 17, 42, 47]) K[s.M_STATE + b] = 0xFF;
    for (const b of [0, 9, 50, 59]) { K[s.M_STATE + b] = 0x80; K[s.M_COUNT + b] = 1; }
    for (const [i, [t, n]] of Object.entries(TABLE)) { K[s.M_STATE + +i] = t; K[s.M_COUNT + +i] = n; }
    K.fill(1, s.M_DIRTY, s.M_DIRTY + 60);
    const table = () => Array.from(K.subarray(s.M_STATE, s.M_STATE + 60)).join() + '|' + Array.from(K.subarray(s.M_COUNT, s.M_COUNT + 60)).join();
    const reference = table();
    run(m, hooks, 3, () => { m.setKey(7, 5, true); K[s.WTCNT] = 200; }); m.setKey(7, 5, false);
    run(m, hooks, 400, () => { K[s.WTCNT] = 200; });      // (no tick while the map is opened: the table stays as installed)
    for (let i = 0; i < 400; i++) {
      const tx = 17 + 12 * (HUNTER % 10) + 6, ty = 35 + 16 * Math.floor(HUNTER / 10) + 8;
      const dx = Math.max(-3, Math.min(3, tx - K[s.M_MPX])), dy = Math.max(-3, Math.min(3, ty - K[s.M_MPY]));
      if (!dx && !dy) break;
      m.moveMouse(dx, -dy);
      K[s.WTCNT] = 200;
      run(m, hooks, 1);
    }
    run(m, hooks, 2);
    const onMap = table();
    const ticks = {}, passes = {};
    hooks.on('M_TICK', () => { ticks[K[s.HYPON]] = (ticks[K[s.HYPON]] || 0) + 1; });
    hooks.on('M_MVCOMMIT', () => { passes[K[s.HYPON]] = (passes[K[s.HYPON]] || 0) + 1; });
    // the fire click; at the start of each hyperspace phase the world is made to want a tick at once, and it
    // would be a squadron move (like the first tick of the jump in the original)
    let moved = 0, late = 0, hyper = 0, arrival = '';
    const phases = new Set();
    run(m, hooks, 4, i => { m.mouse.left = i < 2; });
    for (let f = 0; f < 5000 && (K[s.HYPON] || K[s.WIPE] || !f); f++) {
      if (K[s.HYPON]) {
        if (!phases.has(K[s.HYPON])) { K[s.WTCNT] = 1; K[s.M_TICKC] = 17; }   // a tick due at once, the squadrons move with it
        phases.add(K[s.HYPON]); hyper++;
      }
      run(m, hooks, 1);
      late += lateWrites(m);
      if (K[s.HYPON]) {
        if (table() !== onMap) moved++;
      } else if (!arrival) arrival = table();
    }
    run(m, hooks, 30);
    late += lateWrites(m);
    check(hyper > 600 && [1, 2, 3, 4].every(h => phases.has(h)),
      `hyperspace freeze: a ${hyper}-frame jump through the path, acceleration, jump and deceleration phases`);
    check(Object.keys(ticks).filter(h => +h).length === 0 && Object.keys(passes).filter(h => +h).length === 0 && !K[s.MVON] && !moved,
      `hyperspace freeze: no world tick or squadron move in any hyperspace phase although one was due at the start of every phase (${JSON.stringify(ticks)}), the table never changed (${moved} frames)`);
    check(onMap === reference && arrival === reference && K[s.APPR] === 1 && K[s.SQCOUNT] === TABLE[HUNTER][1] && K[s.M_SELX] + 10 * K[s.M_SELY] === HUNTER,
      `hyperspace freeze: the destination's hunter group (${TABLE[HUNTER][1]} ships) is there on arrival, the squadron table is the one the map showed`);
    check(late === 0 && K[s.OVRUN] === 0, `hyperspace freeze: ${late} late split writes, ${K[s.OVRUN]} overruns through the jump`);
    const t0 = K[s.M_TICKC];
    K[s.WTCNT] = 1;
    run(m, hooks, 70);
    check(K[s.M_TICKC] !== t0, `hyperspace freeze: the world ticks again after the arrival (tick counter ${t0} -> ${K[s.M_TICKC]})`);
  }
};
