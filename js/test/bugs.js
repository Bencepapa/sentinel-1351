'use strict';
// Issues #18-#21 (2026-11-17): warp-in timing under fire, the map key in a base's
// sequence, the crosshair on the victory screen, the fighter slots after a reset.
module.exports = function ({boot, run, check, snap, fs, path, OUT}) {
  const REF = path.join(__dirname, '../../briefs/ref');
  const call = (m, a) => {
    const c = m.cpu, saved = [c.pc, c.sp, c.p];
    c.push(255); c.push(243); c.pc = a; c.p |= 4;
    let n = 0; while (c.pc !== 0xfff4 && n++ < 2e6) { c.step(); if (c.jam) throw Error(c.jam); }
    if (n >= 2e6) throw Error('call did not return: ' + a.toString(16));
    [c.pc, c.sp, c.p] = saved;
  };
  const late = m => { let n = 0; for (let i = 0; i < m.vicLog.length; i += 4) { const [l, c, r] = m.vicLog.slice(i, i + 3);
    if ((r === 32 || r === 33) && ((l >= 50 && l <= 76) || (l >= 230 && l <= 245)) && c >= 16 && c <= 55) n++; } return n; };
  const line = m => m.read(0xd012) + (m.read(0xd011) & 0x80 ? 256 : 0);
  // A browser save state embeds the code of the build that saved it. Code ranges
  // changed since are copied from a fresh boot of this build (pure code only).
  // (States from before the bank-1 store also get this build's bank 1: old-state.js.)
  let freshRam = null, freshBanks = null;
  const fresh = () => { if (!freshRam) { const g = boot('game', 'trace'); run(g.m, g.hooks, 80); freshRam = g.m.ram.slice();
    freshBanks = {ram: freshRam, ram1: g.m.ram1.slice(), mmu: g.m.mmu.slice()}; } return freshRam; };
  const load = (name, ranges) => {
    const saved = JSON.parse(fs.readFileSync(path.join(REF, name), 'utf8'));
    const k = boot(saved.program, 'trace');
    k.m.loadState(k.m.stateFromText(JSON.stringify(saved.state))); k.m.dma = true;
    if (k.m.freeMemoryRecord) k.m.freeMemoryRecord.armed = false;
    const F = fresh();
    if (saved.program === 'game') require('./old-state')(k.m, freshBanks, k.p.symbols);
    for (const [s, e] of ranges || []) k.m.ram.set(F.subarray(s, e), s);
    return k;
  };
  // Per frame: where the squadron's points ran (ARRSTEP), the guns' sprites (line
  // 194 at the latest before their sprites at 207) and the gray strip's split (233).
  const watch = (m, S) => {
    const step = m.cpu.step.bind(m.cpu), f = {};
    let depth = -1;
    m.cpu.step = function () {
      const pc = this.pc;
      if (pc === S.ARRSTEP) { f.arr0 = line(m); depth = this.sp; }
      if (pc === S.ARDRAW && this.a === 0xff) f.point = Math.max(f.point || 0, line(m));
      if (pc === S.SPRGUNS) f.guns = line(m);
      if (pc === S.WAITST && this.a === 233) f.split = line(m);
      if (pc === S.FIREPH) f.fire = line(m);
      if (pc === S.VIEWWORK) f.view = line(m);
      const r = step();
      if (depth >= 0 && this.sp > depth + 1) { f.arr1 = line(m); depth = -1; }
      return r;
    };
    return f;
  };

  // ---- #18: a squadron warping in while the player fires ----------------------
  {
    const trace = (k, fire, frames) => {
      const m = k.m, A = m.ram, S = k.p.symbols, f = watch(m, S), out = [];
      for (let i = 0; i < frames && (A[S.ARRFX] || i < 2); i++) {
        m.mouse.left = fire && i % 6 === 0;
        for (const key in f) delete f[key];
        m.runFrame();
        out.push({...f, late: late(m), fx: A[S.ARRFX], step: A[S.ARSTP]});
      }
      m.mouse.left = false;
      return out;
    };
    const summary = t => ({frames: t.length, late: t.reduce((n, f) => n + f.late, 0),
      split: Math.max(...t.map(f => f.split || 0)), lastPoint: Math.max(...t.map(f => f.point || 0)),
      overGuns: t.filter(f => f.arr0 < 200 && f.arr1 > 200).length});   // (after a launch the phasor alone runs to ~205: pre-existing)
    // The user's save: the squadron starts coming in 199 frames later.
    const arrive = k => { const A = k.m.ram, S = k.p.symbols; for (let i = 0; i < 400 && !A[S.ARRFX]; i++) k.m.runFrame(); return A[S.ARRFX]; };
    const old = load('warping_in.state.json');
    arrive(old);
    const before = summary(trace(old, true, 150));
    const runs = {};
    for (const fire of [true, false]) {
      const S = old.p.symbols;
      const k = load('warping_in.state.json', [[S.ARRSTEP, S.ARREND], [0x5258, S.ENDHELPEND]]);
      const at = arrive(k), o0 = k.m.ram[S.OVRUN];
      const t = trace(k, fire, 150);
      runs[fire ? 'fire' : 'still'] = {...summary(t), overrun: k.m.ram[S.OVRUN] - o0, at,
        fighters: !!(k.m.ram[S.ALIVE] && k.m.ram[S.ALIVE + 1] && k.m.ram[S.ALIVE + 2])};
      if (fire) fs.writeFileSync(path.join(OUT, 'warp-in-fire-trace.json'), JSON.stringify(t));
    }
    const {fire, still} = runs;
    console.log(`     (the save's own code: ${before.late} late split writes, the points ran past line 200 in ${before.overGuns} of ${before.frames} frames)`);
    check(fire.at && fire.late === 0 && fire.overrun === 0 && fire.split <= 230 && fire.fighters,
      `warp-in (#18): the saved squadron comes in under fire with ${fire.late} late splits, ${fire.overrun} OVRUN, the gray strip's split entered by line ${fire.split}, three fighters after ${fire.frames} frames`);
    check(fire.lastPoint <= 184 && still.lastPoint <= 184 && fire.overGuns === 0 && still.overGuns === 0,
      `warp-in (#18): no point begins after line 184 (fire ${fire.lastPoint}, still ${still.lastPoint}) and the points never run past line 200 (the guns' sprites)`);
    check(still.late === 0 && still.overrun === 0 && still.frames <= 62 && still.fighters,
      `warp-in (#18): without fire the points keep 8 a frame: ${still.frames} frames from the start to the fighters (the old code: 60)`);
  }
  {   // A fresh game: a squadron of 2 moves into the ship's sector, fire held now and then.
    const k = boot('game', 'trace'), m = k.m, K = m.ram, s = k.p.symbols;
    m.dma = true; run(m, k.hooks, 60);
    const sel = K[s.M_SELY] * 10 + K[s.M_SELX];
    for (let i = 0; i < 60; i++) if (K[s.M_STATE + i] < 0x80) { K[s.M_STATE + i] = 0; K[s.M_COUNT + i] = 0; }
    K[s.M_STATE + sel + (K[s.M_SELX] < 9 ? 1 : -1)] = 1; K[s.M_COUNT + sel + (K[s.M_SELX] < 9 ? 1 : -1)] = 2;
    K[s.M_TICKC] = 1 + 0x10; K[s.WTCNT] = 1;
    for (let i = 0; i < 300 && !K[s.ARRFX]; i++) m.runFrame();
    const f = watch(m, s); let lateN = 0, frames = 0, over = 0, maxPoint = 0; const o0 = K[s.OVRUN];
    for (let i = 0; i < 200 && K[s.ARRFX]; i++) {
      m.mouse.left = i % 5 < 2; for (const key in f) delete f[key];
      m.runFrame(); frames++; lateN += late(m); if (f.arr0 < 200 && f.arr1 > 200) over++; maxPoint = Math.max(maxPoint, f.point || 0);
    }
    m.mouse.left = false;
    check(frames > 40 && !K[s.ARRFX] && K[s.ALIVE] && lateN === 0 && K[s.OVRUN] === o0 && over === 0 && maxPoint <= 184,
      `warp-in (#18): a fresh squadron coming in under rapid fire: ${frames} frames, ${lateN} late splits, ${K[s.OVRUN] - o0} OVRUN, last point begun at line ${maxPoint}`);
  }

  // ---- #19: no map in a base's sequence (the original never reads C= there) ----
  {
    const o = load('c64-minefield.state.json'), om = o.m, R = om.ram;
    let polls = 0; const step = om.cpu.step.bind(om.cpu);
    om.cpu.step = function () { if (this.pc === 0xfb43) polls++; return step(); };
    let opened = 0;
    for (let f = 0; f < 200; f++) { om.setKey(7, 5, f % 40 < 20); om.runFrame(); if (R[0xb8]) opened++; }
    om.setKey(7, 5, false);
    check(polls === 0 && opened === 0, `map (#19): C64 minefield ($8C44 loop): the map key routine $FB43 runs ${polls} times, the map opens in ${opened} frames`);

    const k = boot('game', 'trace'), m = k.m, A = m.ram, S = k.p.symbols;
    m.dma = true; run(m, k.hooks, 60);
    A[S.M_STATE + 24] = 0xFF; call(m, S.SECTORIN);
    for (let f = 0; f < 400 && A[S.MSSTATE] !== 16; f++) m.runFrame();
    run(m, k.hooks, 40);
    const states = new Set(); let shown = 0, lateN = 0;
    for (let f = 0; f < 400 && A[S.MSSTATE]; f++) {
      m.setKey(7, 5, f % 40 < 10); m.mouse.right = f % 40 >= 20 && f % 40 < 32;
      m.runFrame(); lateN += late(m); states.add(A[S.MSSTATE]); if (A[S.MAPSHOWN] || A[S.WIPE]) shown++;
    }
    m.setKey(7, 5, false); m.mouse.right = false;
    check(states.has(16) && shown === 0 && lateN === 0,
      `map (#19): port base sequence (states ${[...states].join(',')}): C= and the right button open no map (${shown} frames), ${lateN} late splits`);
    // In flight the key works as before.
    const g = boot('game', 'trace'); run(g.m, g.hooks, 60);
    run(g.m, g.hooks, 3, () => g.m.setKey(7, 5, true)); g.m.setKey(7, 5, false); run(g.m, g.hooks, 5);
    check(g.m.ram[S.MAPSHOWN] === 1, 'map (#19): in flight C= still opens the map');
    // The original refuses the map while a proton torpedo is pending or flying ($FB43, $BACE/$BAD1).
    for (const [name, flag] of [['pending', S.TREQ], ['flying', S.TPF]]) {
      const t = boot('game', 'trace'); t.m.dma = true; run(t.m, t.hooks, 60);
      const TA = t.m.ram; TA[flag] = 1;
      t.m.setKey(7, 5, true); run(t.m, t.hooks, 1); call(t.m, S.GMAPTOG); t.m.setKey(7, 5, false);
      const opened = TA[S.MAPSHOWN] || TA[S.WIPE];
      TA[flag] = 0; call(t.m, S.GMAPTOG); run(t.m, t.hooks, 5);
      check(!opened && TA[S.MAPSHOWN] === 1, `map (torpedo ${name}): GMAPTOG refuses the map while the flag is set, opens it when clear`);
    }
    // The user's save: the map was open over the minefield; closed, it stays closed.
    const u = load('minefield_map.state.json', [[S.nosp2, S.nomap], [0x5258, S.ENDHELPEND]]), um = u.m, U = um.ram;
    const wasOpen = U[S.MAPSHOWN] === 1 && U[S.MSSTATE] === 16;
    call(um, S.MAPCLOSE); run(um, u.hooks, 30);
    let reopened = 0;
    for (let f = 0; f < 120; f++) { um.setKey(7, 5, f % 30 < 10); um.mouse.right = f >= 80 && f < 100; um.runFrame(); if (U[S.MAPSHOWN] || U[S.WIPE]) reopened++; }
    um.setKey(7, 5, false); um.mouse.right = false;
    check(wasOpen && reopened === 0 && U[S.MSSTATE], `map (#19): the supplied minefield save cannot reopen the map (${reopened} frames)`);
  }

  // ---- #20: the crosshair on the victory screen --------------------------------
  {
    // The original: its interrupt moves the crosshair ($B2D8) during the wait ($F606).
    const o = load('c64-last-enemy-map-then-win.state.json'), om = o.m, R = om.ram;
    om.setBreak(0xf606, true);
    for (let f = 0; f < 800 && !om.breakInfo; f++) om.runFrame();
    om.setBreak(0xf606, false); om.breakInfo = null;
    const c64 = [];
    const path64 = (m, X, Y, dx, dy, out) => {
      for (let f = 0; f < 30; f++) { if (f < 15) m.moveMouse(dx, dy); m.runFrame(); out.push([m.ram[X], m.ram[Y]]); }
    };
    run(om, o.hooks, 5);
    const start = [R[0xb2d7], R[0x120a]];
    path64(om, 0xb2d7, 0x120a, 3, 2, c64);
    for (let f = 0; f < 200; f++) om.runFrame();
    const rest64 = [R[0xb2d7], R[0x120a]];
    // The port: the same mouse path in its victory wait.
    const k = boot('game', 'trace'), m = k.m, B = m.ram, T = k.p.symbols;
    m.dma = true; run(m, k.hooks, 80);
    B.fill(0, T.M_STATE, T.M_STATE + 60); B.fill(0, T.M_FLG, T.M_FLG + 4); B[T.ENDQUAL] = 1; call(m, T.ENDTRYWIN);
    for (let f = 0; f < 400 && B[T.ENDPHASE] < 3; f++) m.runFrame();
    run(m, k.hooks, 5);
    B[T.CURX] = start[0]; B[T.CURY] = start[1];
    const port = []; let lateN = 0, fired = 0;
    const sx0 = B[T.XPOS];
    let sx14 = sx0;
    for (let f = 0; f < 30; f++) { if (f < 15) m.moveMouse(3, 2); m.runFrame(); lateN += late(m); port.push([B[T.CURX], B[T.CURY]]); if (f === 14) sx14 = B[T.XPOS]; }
    for (let f = 0; f < 200; f++) { m.runFrame(); lateN += late(m); }
    const rest = [B[T.CURX], B[T.CURY]];
    // Frame-to-frame steps (the first frame depends on where the motion falls in
    // the original's interrupt), and the rest position: x 126, y the centre (the
    // C64 save's centre is the base sequence's 145, the port's flight one YCEN).
    const steps = p => [...new Set(p.slice(1).map((v, i) => [v[0] - p[i][0], v[1] - p[i][1]].join()))].sort().join(' ');
    fs.writeFileSync(path.join(OUT, 'win-crosshair-path.json'), JSON.stringify({start, c64, port, rest64, rest}));
    check(steps(port) === steps(c64) && sx14 === ((port[14][0] + 0x2D) & 255) && sx14 !== sx0 && rest[0] === rest64[0] && rest[0] === 126 && rest[1] === B[T.YCEN],
      `victory (#20): the mouse moves the crosshair step for step as the original's interrupt does (${start} -> ${port[29]}, C64 ${c64[29]}); at rest it glides back to ${rest} (C64 ${rest64})`);
    // Fire and the A key: no shot, no tracking; held fire still restarts.
    const stars = Buffer.from(B.subarray(0x63c0, 0x7680)); const joy = [];
    for (let f = 0; f < 20; f++) { m.mouse.left = f < 10; m.setKey(1, 2, f >= 10); m.runFrame(); lateN += late(m);
      if (B[T.SHOTON] || B[T.FIREFLAG] || B[T.TRUN] || B[T.TON]) fired++; joy.push(B[T.JOY]); }
    m.mouse.left = false; m.setKey(1, 2, false);
    check(fired === 0 && joy.every(v => v === 0xff) && lateN === 0 && B[T.OVRUN] === 0 && B[T.ENDMODE] === 2,
      `victory (#20): fire and A launch nothing (${fired} frames), no steering, ${lateN} late splits, ${B[T.OVRUN]} OVRUN`);
    // Without a mouse the joystick moves it too (the original's $B2D8 joystick path).
    m.mouse.present = false; const x0 = B[T.CURX];
    for (let f = 0; f < 10; f++) { m.joy2 = 8; m.runFrame(); }
    m.joy2 = 0;
    check(B[T.CURX] > x0, `victory (#20): the joystick moves the crosshair (x ${x0} -> ${B[T.CURX]})`);
    m.mouse.present = true;
    snap(m, 'win-crosshair');
    // The reset restores the normal input hook (snapshot of iv1).
    B[T.ENDTIME] = 1; B[T.ENDTIME + 1] = 0; run(m, k.hooks, 100);
    const F = fresh();
    check(!B[T.ENDMODE] && B[T.iv1 + 1] === F[T.iv1 + 1] && B[T.iv1 + 2] === F[T.iv1 + 2], 'victory (#20): restart restores the normal input hook');
  }

  // ---- #21: the fighter slots after a reset ------------------------------------
  {
    const F = fresh();
    for (const [kind, fill] of [['enemy proton', 'proton'], ['type 3 fight', 'type3']]) {
      const k = boot('game', 'trace'), m = k.m, B = m.ram, T = k.p.symbols;
      m.dma = true; run(m, k.hooks, 80);
      if (fill === 'proton') for (let i = 0; i < 128; i++) B[0x6000 + i] = (i * 37 + 11) & 255;   // the borrowed $6000-$607F
      else { for (let i = 0; i < 8 * 64; i++) B[0x6000 + i] = B[T.TSH3 + i]; B[T.SHLT] = B[T.SQTYPE] = B[T.ETYPE] = 3; call(m, T.GTYPE); }
      B[T.SHIPLOST] = 1; call(m, T.ENDARM);
      run(m, k.hooks, 330);            // the 255 frames of flashing, then the death's scene
      B[T.ENDTIME] = 1; B[T.ENDTIME + 1] = 0; run(m, k.hooks, 100);
      const slots = Buffer.from(B.subarray(0x6000, 0x63c0)).equals(Buffer.from(F.subarray(0x6000, 0x63c0)));
      const shots = Buffer.from(B.subarray(0x7cc0, 0x8000)).equals(Buffer.from(F.subarray(0x7cc0, 0x8000)));
      const looks = ['SHLT', 'SQTYPE', 'ETYPE', 'SHLK', 'shpj'].every(n => B[T[n]] === F[T[n]]) &&
        [['sprmc', 2], ['sprxe', 2]].every(([n, c]) => Buffer.from(B.subarray(T[n], T[n] + c)).equals(Buffer.from(F.subarray(T[n], T[n] + c))));
      check(!B[T.ENDMODE] && slots && shots && looks,
        `reset (#21): after a death with ${kind} shapes in the fighter slots, the slots ($6000-$63BF), shot shapes ($7CC0-$7FFF) and sprite looks equal a fresh boot's`);
    }
    // The supplied save after a reset: the slots it shows are not the type 1 masters.
    const u = load('after_reset_enemy_shot.state.json'), U = u.m.ram, T = u.p.symbols;
    let bad = 0; for (let i = 0; i < 128; i++) if (U[0x6000 + i] !== U[T.TSH1 + i]) bad++;
    check(bad > 0 && U[T.SHLT] === 1, `reset (#21): the supplied save shows ${bad} bytes of fighter shapes $80/$81 not restored after its reset (the cause: g_gi2 entered with X = $FF)`);
  }
};
