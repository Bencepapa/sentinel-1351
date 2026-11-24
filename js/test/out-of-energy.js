'use strict';
// Issue #28: out of energy. The C64 original (briefs/out-of-energy.md): -1 every 110 frames (flight, the map
// open, bases; not in a jump), the digits flash below 2000, the decrement that finds 0000 wraps into $F8E0
// (digits 0000, OUT OF ENERGY, a tone, the flag $F865); then $F927 never returns: the stars slow down for
// about 400 frames and stop, no phasor, proton, map, thrust or steering, the world's clock stops; the
// crosshair, the enemies, their fire, the warp-ins and the TIME clock run; in a jump the steps and the
// acceleration take a frame each. Only a new game clears the flag (the original's init at $8E56).
// The original (state frame7847, energy poked): $F8E0 prints OUT OF ENERGY ($9C5C: colour $81, rate $10, 255 flips)
// and plays a rattle; about 490 frames later $F96B forces the warp-in ($FB := 1, WAVEINIT), which ends in the
// warning (ALERT, its siren) and no message of its own, no tracking message, the fighters stay and attack.
module.exports = function ({boot, run, check, resumeFromTitle, quick}) {
  const late = m => {
    let n = 0;
    for (let i = 0; i < m.vicLog.length; i += 4) {
      const [l, c, r] = m.vicLog.slice(i, i + 3);
      if ((r === 32 || r === 33) && c >= 16 && c <= 55 && ((l >= 50 && l <= 76) || (l >= 230 && l <= 245))) n++;
    }
    return n;
  };
  const ready = () => {
    const k = boot('game', 'trace'); k.m.dma = true; run(k.m, k.hooks, 80);
    const S = k.p.symbols, A = k.m.ram;
    // a dogfight to spare, as the cockpit tests do
    A[S.APPR] = 0; A[S.APRUN] = 0; A[S.LRMODE] = 0; A[S.SQCOUNT] = 200; A[S.CURG] = 0;
    A[S.GSIZE] = A[S.GSIZE + 1] = A[S.GSIZE + 2] = 200;
    run(k.m, k.hooks, 40);
    return {k, m: k.m, A, S};
  };
  const energy = (A, S) => [0, 1, 2, 3].reduce((v, i) => v * 10 + A[S.HUDE + i] - 0x70, 0);
  const setEnergy = (A, S, v) => { for (let i = 3; i >= 0; i--) { A[S.HUDE + i] = 0x70 + v % 10; v = Math.floor(v / 10); } };
  const row = (A, S) => { let t = ''; for (let i = 0; i < 40; i++) t += String.fromCharCode(0x40 + (A[S.LRROW + i] & 0x3F)); return t.replace(/[@`]/g, ' ').trim(); };
  const strand = (g, v = 1) => {
    const {k, m, A, S} = g;
    setEnergy(A, S, v);
    let f = 0;
    while (!A[S.OEFLAG] && f++ < 1000) m.runFrame();
    return f;
  };

  // 1. the passive tick: -1 per 110 frames, also with the map open; none in the jump's own rate
  {
    const g = ready(), {k, m, A, S} = g;
    setEnergy(A, S, 5000);
    run(m, k.hooks, 1100);
    const flight = 5000 - energy(A, S);
    setEnergy(A, S, 5000);
    run(m, k.hooks, 4, i => m.setKey(7, 5, true)); m.setKey(7, 5, false);
    run(m, k.hooks, 20);
    const open = A[S.MAPSHOWN];
    setEnergy(A, S, 5000);
    run(m, k.hooks, 1100);
    const mapped = 5000 - energy(A, S);
    check(flight >= 9 && flight <= 11 && open && mapped >= 9 && mapped <= 11,
      `out of energy: energy falls by one every 110 frames in flight (${flight} in 1100 frames) and with the map open (${mapped})`);
  }

  // 2. the flash below 2000: the four digits' colours, 7 and 8 every 15 frames
  {
    const g = ready(), {k, m, A, S} = g;
    const seen = v => { setEnergy(A, S, v); const c = new Set(); for (let i = 0; i < 70; i++) { m.runFrame(); c.add(m.colorRam[0x3E] + '/' + m.colorRam[0x41]); } return [...c].sort().join(); };
    const hi = seen(2500), lo = seen(1500);
    check(lo.replace('1/1,', '') === '7/7,8/8' && hi.indexOf('7/7') < 0, `out of energy: the digits flash 7/8 below 2000 (${lo}) and not at 2500 (${hi})`);
  }

  // 3. the trigger: the decrement that finds 0000 wraps, the message, the tone, the flag; once
  {
    const g = ready(), {k, m, A, S} = g;
    setEnergy(A, S, 0);
    const before = A[S.OEFLAG];
    run(m, k.hooks, 5);
    const stillOk = !A[S.OEFLAG];          // (0000 alone is not out of energy: the next decrement is)
    const f = strand(g, 0);
    run(m, k.hooks, 3);
    const text = row(A, S);
    const sid = A[S.SNDON];
    check(!before && stillOk && A[S.OEFLAG] >= 1 && energy(A, S) === 0 && text === 'OUT OF ENERGY' && sid && A[S.MSGRATE] === 0x10 && A[S.MSGN] >= 0xFC && A[S.MSGCOL] === 0x81 &&
      A[S.SNDCNT] === 3 && A[S.SNDRLD] === 0x1E && A[S.SNDSTP] === 0x40 && A[S.SNDHI0] === 0x0B && A[S.SNDDIR] === 1 && !A[S.SYSHP + 4],
      `out of energy: the next decrement after 0000 (frame ${f}) sets the flag, the row says '${text}' (colours $${A[S.MSGCOL].toString(16)}, rate $${A[S.MSGRATE].toString(16)}, ${A[S.MSGN]} flips) with the original's $0912 rattle (${A[S.SNDCNT]} sweeps of ${A[S.SNDRLD]} frames, step $${A[S.SNDSTP].toString(16)}), the tracking computer is out`);
    // centred in the row (the original: 13 spaces, then the text) and in its colour at once
    check(A[S.LRROW + 12] !== 0x0F && (A[S.LRROW + 13] & 0x3F) === 0x0F && (A[S.LRROW + 25] & 0x3F) === 0x19 && [0, 0x20].includes(A[S.LRROW + 26] & 0x3F) &&
      [13, 20, 25].every(i => [1, 8].includes(m.colorRam[S.COLROW - 0xD800 + i] & 15)),
      `out of energy: the text starts at column 13 (the row's middle) and it is white or orange from the first frame, not black (${[13, 20, 25].map(i => m.colorRam[S.COLROW - 0xD800 + i] & 15)}, white and orange flipping)`);
    // a further decrement at 0000 (HENERGY: the jump's, the deflector's) does not wrap again: no new message, tone or counter
    run(m, k.hooks, 40);
    const counted = A[S.OEFLAG];
    A.fill(0x60, S.LRROW, S.LRROW + 40);
    A[S.SNDON] = 0;
    for (let i = 0; i < 12; i++) { A[S.HENC] = 0; call(m, S.HENERGY, 1); }
    check(counted > 5 && A[S.OEFLAG] >= counted && row(A, S) === '' && !A[S.SNDON] && energy(A, S) === 0, 'out of energy: HENERGY at 0000 after the flag wraps no more (no new message or tone, the counter runs on)');
  }

  // 4. the gates: fire, proton, map (C= and the right button), steering; the crosshair, enemies and clock run
  {
    const control = ready(), stuck = ready();
    strand(stuck, 1);
    run(stuck.m, stuck.k.hooks, 40);
    const test = (g, name) => {
      const {k, m, A, S} = g, out = {};
      m.mouse.present = true;
      const e0 = energy(A, S), p0 = A[0x485B];
      let shot = 0, fired = 0;
      run(m, k.hooks, 40, i => { m.mouse.left = i < 20; if (A[S.SHOTON]) shot++; });
      m.mouse.left = false; run(m, k.hooks, 60);
      out.fire = shot; out.shotEnergy = e0 - energy(A, S);
      run(m, k.hooks, 10, () => m.setKey(7, 5, true)); m.setKey(7, 5, false); run(m, k.hooks, 60);
      out.map = A[S.MAPSHOWN];
      if (A[S.MAPSHOWN]) { run(m, k.hooks, 10, () => m.setKey(7, 5, true)); m.setKey(7, 5, false); run(m, k.hooks, 60); }
      m.mouse.right = true; run(m, k.hooks, 12); m.mouse.right = false; run(m, k.hooks, 40);
      out.mapRight = A[S.MAPSHOWN];
      if (A[S.MAPSHOWN]) { run(m, k.hooks, 10, () => m.setKey(7, 5, true)); m.setKey(7, 5, false); run(m, k.hooks, 60); }
      run(m, k.hooks, 10, () => m.setKey(7, 4, true)); m.setKey(7, 4, false); run(m, k.hooks, 80);
      out.proton = p0 - A[0x485B];
      m.joy2 = 0x0B; run(m, k.hooks, 4); out.joy = A[S.JOY]; m.joy2 = 0;
      const cx = A[S.CURX]; m.moveMouse(6, 0); run(m, k.hooks, 4); out.cursor = A[S.CURX] - cx;
      return out;
    };
    const c = test(control, 'control'), s = test(stuck, 'stuck');
    check(c.fire > 0 && c.proton === 1 && s.fire === 0 && s.proton === 0 && s.map === 0 && s.mapRight === 0 && s.joy === 0xFF,
      `out of energy: no phasor (${s.fire} shot frames, ${c.fire} before), no proton (${s.proton}, ${c.proton}), no map (${s.map}/${s.mapRight}), no steering (JOY ${s.joy.toString(16)})`);
    check(s.cursor > 0 && c.map === 1 && c.mapRight === 1, `out of energy: the crosshair still follows the mouse (${s.cursor} steps); the control's C= and right button open the map (${c.map}, ${c.mapRight})`);
    check(stuck.A[stuck.S.OVRUN] === 0 && late(stuck.m) === 0, `out of energy: ${stuck.A[stuck.S.OVRUN]} overruns, ${late(stuck.m)} late split writes`);
  }

  // 5. the stars slow down (full speed, every other frame, every 4th) and stop after about 255 frames; the clock and enemies run
  {
    const g = ready(), {k, m, A, S} = g;
    let stars = 0, ticks = 0, fights = 0;
    k.hooks.on('STARS2', () => { stars++; });
    k.hooks.on('M_TICK', () => { ticks++; });
    run(m, k.hooks, 60);
    const idle = stars, idleTicks = ticks;
    A[S.WTCNT] = 1;
    strand(g, 1);
    const rates = [];
    for (let w = 0; w < 9; w++) { stars = 0; run(m, k.hooks, 64); rates.push(stars); }
    ticks = 0; const clock0 = Array.from(A.subarray(0x55D, 0x5DB)).join();
    A[S.WTCNT] = 1; run(m, k.hooks, 300);
    const noTick = ticks === 0;
    stars = 0; run(m, k.hooks, 120);
    check(idle >= 55 && rates[0] >= 60 && rates[2] <= 40 && rates[5] <= 40 && rates[7] <= 20 && rates[8] === 0 && stars === 0,
      `out of energy: the stars run ${idle} steps a second at first, then ${rates.join(', ')} per 64 frames over about 510 frames (the original's slow-down: about 400), and stop`);
    check(noTick && idleTicks >= 0, `out of energy: the world's clock stops (${ticks} ticks in 300 frames)`);
  }

  // 6. a jump: the energy runs out in it, the steps take a frame, the ship arrives at the destination, stranded
  if (!quick) {
    const g = ready(), {k, m, A, S} = g;
    A.fill(0, S.M_STATE, S.M_STATE + 60); A.fill(0, S.M_COUNT, S.M_COUNT + 60);
    for (const b of [12, 17, 42, 47]) A[S.M_STATE + b] = 0xFF;
    const dest = 38;
    run(m, k.hooks, 3, () => m.setKey(7, 5, true)); m.setKey(7, 5, false);
    run(m, k.hooks, 400);
    for (let i = 0; i < 400; i++) {
      const tx = 17 + 12 * (dest % 10) + 6, ty = 35 + 16 * Math.floor(dest / 10) + 8;
      const dx = Math.max(-3, Math.min(3, tx - A[S.M_MPX])), dy = Math.max(-3, Math.min(3, ty - A[S.M_MPY]));
      if (!dx && !dy) break;
      m.moveMouse(dx, -dy); run(m, k.hooks, 1);
    }
    run(m, k.hooks, 2);
    setEnergy(A, S, 2200);
    run(m, k.hooks, 4, i => { m.mouse.left = i < 2; });
    let f = 0, flagAt = -1, arriveAt = -1, jumpAt = -1, steps = 0, said = '';
    for (; f < 4000; f++) {
      m.runFrame();
      if (A[S.HYPON] === 2 && jumpAt < 0) { jumpAt = f; setEnergy(A, S, 6); }
      if (A[S.OEFLAG] && flagAt < 0) { flagAt = f; m.runFrame(); said = row(A, S); }
      if (flagAt >= 0 && !A[S.HYPON] && !A[S.WIPE]) { arriveAt = f; break; }
    }
    run(m, k.hooks, 60);
    check(jumpAt > 0 && flagAt > jumpAt && arriveAt > flagAt && arriveAt - flagAt < 160 &&
      A[S.M_SELX] + 10 * A[S.M_SELY] === dest && energy(A, S) === 0,
      `out of energy: in a jump (frame ${jumpAt}) the energy runs out (${flagAt}); the jump ends at once (the deceleration) and the ship arrives at sector ${A[S.M_SELX] + 10 * A[S.M_SELY]} ${arriveAt - flagAt} frames later, stranded`);
    check(A[S.OEFLAG] >= 1 && !A[S.MAPSHOWN] && said === 'OUT OF ENERGY', `out of energy: on arrival the flag stands, the map is shut; the row said '${said}' when the energy ran out`);
  }

  // 6b. the original's $F96B sets $FB: the warp-in ($1AF2: points rush in, $FF1B puts three fighters in place) is forced
  //     when the energy runs out, with no squadron called for (and in a base's tunnel too: not ported, see the brief)
  {
    const k = boot('game', 'trace'), m = k.m, A = m.ram, S = k.p.symbols; m.dma = true;
    run(m, k.hooks, 80);
    A[S.APPR] = 0; A[S.APRUN] = 0; A[S.LRMODE] = 0; A[S.SQCOUNT] = 0; A[S.ARRFX] = 0;
    A[S.ALIVE] = A[S.ALIVE + 1] = A[S.ALIVE + 2] = 0;
    const sel = A[S.M_SELY] * 10 + A[S.M_SELX]; A[S.M_STATE + sel] = 0; A[S.M_COUNT + sel] = 0;
    run(m, k.hooks, 60);
    const idle = A[S.ARRFX] | A[S.ALIVE] | A[S.ALIVE + 1] | A[S.ALIVE + 2];
    setEnergy(A, S, 1);
    let f = 0, rushed = 0, up = 0;
    for (; f < 1500 && !(A[S.ALIVE] && A[S.ALIVE + 1] && A[S.ALIVE + 2]); f++) { m.runFrame(); if (A[S.ARRFX] === 2) rushed++; }
    run(m, k.hooks, 30);
    check(!idle && A[S.OEFLAG] && f > 400 && rushed > 5 && A[S.ALIVE] && A[S.ALIVE + 1] && A[S.ALIVE + 2] && A[S.SQCOUNT] >= 3,
      `out of energy: the warp-in is forced (${rushed} rushing frames), three fighters in place after ${f} frames (the original: about 490 after its $F8E0) in an empty sector (idle ${idle})`);
  }

  // 6c. out of energy in the raster tunnel (a base's sequence, MSSTATE 16; the original's base loop $8CF8 runs $F927 too):
  //     the mines vanish, the tunnel slows down and STOPS (it stays, its bands and stars go on), the sequence ends as at an
  //     arrival (MSSTATE 0, normal flight's input / fights), OUT OF ENERGY blinks, three fighters warp in after the slow-down
  //     (about 540 frames after $F8E0 in the original's states 8219 / 8241) and attack; no overrun, no late split writes.
  //     Friendly base: the shots run the energy out (22, as the user's state frame10593: three shots); hostile: ENERGY10.
  for (const hostile of [0, 1]) {
    const k = boot('game', 'trace'), m = k.m, A = m.ram, S = k.p.symbols; m.dma = true;
    run(m, k.hooks, 60);
    A[S.M_STATE + 24] = hostile ? 0x80 : 0xFF; call(m, S.SECTORIN);
    run(m, k.hooks, 70);
    const up = A[S.MSSTATE] === 16 && A[S.MNLOAD] === 12 && A[S.MTAGE] >= 3;
    const lateAt = []; let late0 = 0, flagAt = -1, f = 0, phase = A[S.MTPHASE];
    const rates = [0], tail = [], rushed = [];
    if (hostile) { setEnergy(A, S, 0); call(m, S.ENERGY10); }
    else { setEnergy(A, S, 22); m.mouse.present = true; }
    let aliveAt = -1, steps = 0, said = '', msAt = -1, minesOff = -1, fight = 0;
    for (; f < 900; f++) {
      if (!hostile && flagAt < 0) m.mouse.left = f % 12 < 6;
      m.runFrame(); if (flagAt >= 0) { const l = late(m); if (l && f - flagAt > 12) late0 += l; if (l) lateAt.push(f - flagAt); }
      if (A[S.OEFLAG] && flagAt < 0) { flagAt = f; phase = A[S.MTPHASE]; m.mouse.left = false; said = row(A, S); }
      if (flagAt >= 0) {
        const t = f - flagAt, d = (A[S.MTPHASE] - phase) & 255; phase = A[S.MTPHASE];
        rates[Math.floor(t / 64)] = (rates[Math.floor(t / 64)] || 0) + d;
        if (t >= 560) tail.push(d);
        if (A[S.MSSTATE] === 0 && msAt < 0) msAt = t;
        if (t === 40) minesOff = (A[S.MNENA] === 0 && (m.vic[0x15] & 0x74) === 0) ? 1 : 0;
        if (A[S.ARRFX] === 2) rushed.push(t);
        if (aliveAt < 0 && A[S.ALIVE] && A[S.ALIVE + 1] && A[S.ALIVE + 2]) aliveAt = t;
        if (aliveAt >= 0 && t > aliveAt + 150) break;
      }
    }
    const kind = hostile ? 'hostile' : 'friendly';
    const tunnelOn = A[S.vv2 + 1] === (S.MNVB & 255) && A[S.vv2 + 2] === (S.MNVB >> 8);
    check(up && flagAt >= 0 && msAt >= 0 && msAt <= 4 && minesOff === 1 && tunnelOn,
      `out of energy in a ${kind} base's tunnel (${hostile ? 'ENERGY10' : 'three shots from 22'}): flag at frame ${flagAt}, the sequence ends ${msAt} frames later (MSSTATE ${A[S.MSSTATE]}), the mines are gone and their sprites off (${minesOff}), the tunnel's routine stays (${tunnelOn})`);
    check(rates[0] >= 60 && rates[2] < rates[0] && rates[6] < rates[2] && tail.length > 100 && tail.every(d => d === 0),
      `out of energy in a ${kind} base's tunnel: the tunnel's phase steps ${rates.slice(0, 11).join(', ')} per 64 frames and stops (${tail.filter(d => d).length} steps after frame 560)`);
    check(aliveAt > 400 && aliveAt < 900 && A[S.SQCOUNT] >= 3 && !A[S.MAPSHOWN] && A[S.MSSTATE] === 0,
      `out of energy in a ${kind} base's tunnel: three fighters warp in ${aliveAt} frames after the flag (${rushed.length} rush frames), SQCOUNT ${A[S.SQCOUNT]}, no map`);
    check(A[S.OVRUN] === 0 && late0 === 0, `out of energy in a ${kind} base's tunnel: ${A[S.OVRUN]} overruns, ${late0} late split writes (late frames after the flag: ${lateAt}; the shot's explosion in the air when it ran out may show 2 in the first 12)`);
  }
  // the map and a jump from it to sector `dest` (empty), up to the fire click: the jump runs on from the caller
  const startJump = (g, dest) => {
    const {k, m, A, S} = g;
    A.fill(0, S.M_STATE, S.M_STATE + 60); A.fill(0, S.M_COUNT, S.M_COUNT + 60);
    for (const b of [12, 17, 42, 47]) A[S.M_STATE + b] = 0xFF;
    A[S.M_STATE + 1] = 1; A[S.M_COUNT + 1] = 5;      // (an enemy squadron far away: the game is not won)
    run(m, k.hooks, 3, () => m.setKey(7, 5, true)); m.setKey(7, 5, false);
    run(m, k.hooks, 400);
    for (let i = 0; i < 400; i++) {
      const tx = 17 + 12 * (dest % 10) + 6, ty = 35 + 16 * Math.floor(dest / 10) + 8;
      const dx = Math.max(-3, Math.min(3, tx - A[S.M_MPX])), dy = Math.max(-3, Math.min(3, ty - A[S.M_MPY]));
      if (!dx && !dy) break;
      m.moveMouse(dx, -dy); run(m, k.hooks, 1);
    }
    run(m, k.hooks, 2);
  };

  // 8. the user's VICE test: the energy runs out in a jump. The message blinks on (no other message replaces it), the
  //    ship arrives, about 490 frames later the warp-in ends in the warning, no tracking message or mode, the three
  //    fighters stay and attack (they do not vanish), the A key does nothing
  if (!quick) {
    const k = boot('game', 'trace'), m = k.m, A = m.ram, S = k.p.symbols; m.dma = true;
    run(m, k.hooks, 80);
    A[S.APPR] = 0; A[S.APRUN] = 0; A[S.LRMODE] = 0; A[S.SQCOUNT] = 0; A[S.ARRFX] = 0; A[S.ALIVE] = A[S.ALIVE + 1] = A[S.ALIVE + 2] = 0;
    const g = {k, m, A, S};
    startJump(g, 38);
    setEnergy(A, S, 2200);
    run(m, k.hooks, 4, i => { m.mouse.left = i < 2; });
    const seq = [], tracking = [];
    let flagAt = -1, arriveAt = -1, warnAt = -1, aliveAt = -1, trackKey = 0, last = '', dead = -1, goneAfter = 0, f = 0;
    let poked = 0, decelAt = -1, sndOn = 0, sndRise = 0, sndPrev = 0, badCol = 0, colSeen = new Set(), flashSeen = new Set(), flaggedFrames = 0;
    for (; f < 3500; f++) {
      m.runFrame();
      if (A[S.HYPON] === 2 && !poked) { poked = 1; setEnergy(A, S, 6); }
      if (A[S.OEFLAG] && flagAt < 0) { flagAt = f; }
      if (flagAt >= 0 && f <= flagAt + 140) {
        // the run-out in the jump: the jump ends at once, one short tone, the message in its colours from the first frame, the flash
        if (A[S.HYPON] === 3 && decelAt < 0) decelAt = f;
        const snd = A[S.SNDON] ? 1 : 0; sndOn += snd; if (snd && !sndPrev) sndRise++; sndPrev = snd;
        const c = [13, 20, 25].map(i => m.colorRam[S.COLROW - 0xD800 + i] & 15);
        if (f > flagAt && c.some(x => x !== 1 && x !== 8)) badCol++;   // (the flag's own frame: the colours follow in the next, MSGCD = 1)
        c.forEach(x => colSeen.add(x));
        if (A[S.HYPON]) flashSeen.add(m.colorRam[0x3E]);
      }
      if (flagAt >= 0 && !A[S.HYPON] && !A[S.WIPE] && arriveAt < 0) arriveAt = f;
      const t = row(A, S);
      if (t && /^[A-Z ]+$/.test(t) && t !== last) { seq.push(t); last = t; if (/WARNING/.test(t) && warnAt < 0) warnAt = f; }
      if (A[S.TRUN] | A[S.TRACK]) tracking.push(f);   // (TON is asked for by the arrival for a frame: the computer is out and clears it)
      if (arriveAt >= 0 && f === arriveAt + 100) { m.setKey(1, 2, true); }
      if (arriveAt >= 0 && f === arriveAt + 110) { m.setKey(1, 2, false); trackKey = A[S.TRUN] | A[S.TRACK]; }
      const alive = A[S.ALIVE] && A[S.ALIVE + 1] && A[S.ALIVE + 2];
      if (alive && aliveAt < 0) aliveAt = f;
      if (aliveAt >= 0 && !(A[S.ALIVE] | A[S.ALIVE + 1] | A[S.ALIVE + 2]) && dead < 0 && !A[S.SHIPLOST] && !A[S.ENDMODE]) dead = f;
      if (A[S.SHIPLOST] || A[S.ENDMODE]) break;
      if (aliveAt >= 0 && f > aliveAt + 800) break;
    }
    const enter = seq.some(x => /ENTERING|SECTOR/.test(x)), track = seq.some(x => /TRACK/.test(x));
    seq.splice(0, Math.max(0, seq.indexOf('OUT OF ENERGY')));
    check(flagAt > 0 && arriveAt > flagAt && seq[0] === 'OUT OF ENERGY' && !enter && !track && warnAt > arriveAt && warnAt - flagAt > 450 && warnAt - flagAt < 900,
      `out of energy in a jump: messages ${JSON.stringify(seq)}; arrival ${arriveAt - flagAt} frames after the flag, the warning ${warnAt - flagAt} frames after the flag (the original: about 490)`);
    check(decelAt > flagAt && decelAt - flagAt <= 3 && arriveAt - flagAt < 160,
      `out of energy in a jump: the ship leaves the jump at once (deceleration ${decelAt - flagAt} frames after the flag, arrival after ${arriveAt - flagAt})`);
    check(sndRise === 1 && sndOn > 30 && sndOn < 110,
      `out of energy in a jump: one short tone (${sndRise} start, ${sndOn} frames), not held until the jump ends`);
    check(badCol === 0 && colSeen.has(1) && colSeen.has(8) && flashSeen.has(7) && flashSeen.has(8),
      `out of energy in a jump: the message is white / orange from the first frame, never black (${badCol} frames with another colour; seen ${[...colSeen].sort()}); the digits flash in the jump (${[...flashSeen].sort()})`);
    check(!tracking.length && !trackKey, `out of energy in a jump: no tracking mode or message (frames with tracking: ${tracking.length}, after the A key: ${trackKey})`);
    check(aliveAt > arriveAt && dead < 0 && (f > aliveAt + 800 || A[S.SHIPLOST] || A[S.ENDMODE]),
      `out of energy in a jump: three fighters in place ${aliveAt - arriveAt} frames after the arrival and they stay (${f - aliveAt} frames, vanished at ${dead}; ship lost: ${A[S.SHIPLOST]})`);
  }

  // 8b. the user's retest (frame3836): the energy runs out in a jump to a sector WITH an enemy squadron. The original's
  //     stranded ship runs no approach: no scanner lock, no rush at the group (APPR / APRUN / LRMODE stay 0 after the
  //     arrival), the warp-in brings three fighters, which stay
  if (!quick) {
    const k = boot('game', 'trace'), m = k.m, A = m.ram, S = k.p.symbols; m.dma = true;
    run(m, k.hooks, 80);
    A[S.APPR] = 0; A[S.APRUN] = 0; A[S.LRMODE] = 0; A[S.SQCOUNT] = 0; A[S.ARRFX] = 0; A[S.ALIVE] = A[S.ALIVE + 1] = A[S.ALIVE + 2] = 0;
    const g = {k, m, A, S};
    startJump(g, 38);
    A[S.M_STATE + 38] = 1; A[S.M_COUNT + 38] = 3;
    setEnergy(A, S, 2200);
    run(m, k.hooks, 4, i => { m.mouse.left = i < 2; });
    let poked = 0, arriveAt = -1, aliveAt = -1, appr = 0, f = 0, sq = 0;
    for (; f < 2500; f++) {
      m.runFrame();
      if (A[S.HYPON] === 2 && !poked) { poked = 1; setEnergy(A, S, 6); }
      if (A[S.OEFLAG] && !A[S.HYPON] && !A[S.WIPE] && arriveAt < 0) arriveAt = f;
      if (arriveAt >= 0 && (A[S.APPR] | A[S.APRUN])) appr++;
      if (arriveAt >= 0) sq = Math.max(sq, A[S.SQCOUNT]);
      if (A[S.ALIVE] && A[S.ALIVE + 1] && A[S.ALIVE + 2] && aliveAt < 0) aliveAt = f;
      if (A[S.SHIPLOST] || A[S.ENDMODE] || (aliveAt >= 0 && f > aliveAt + 300)) break;
    }
    check(arriveAt > 0 && appr === 0 && aliveAt > arriveAt && sq >= 3 && A[S.LRMODE] === 0,
      `out of energy in a jump to an enemy sector: arrival at frame ${arriveAt}, no approach or scanner lock (${appr} frames with one, LRMODE ${A[S.LRMODE]}), three fighters at frame ${aliveAt}, SQCOUNT ${sq}`);
  }

  // 9. energy out in a fight: the fighters stay (no new warp-in replaces them), the shot in the air finishes (it
  //    froze in its flash), the rest as in flight
  if (!quick) {
    const g = ready(), {k, m, A, S} = g;
    A[S.ALIVE] = A[S.ALIVE + 1] = A[S.ALIVE + 2] = 1;
    setEnergy(A, S, 5);
    m.mouse.present = true;
    let shotStart = -1, shotEnd = -1, arr = 0, vanished = 0, f = 0;
    for (; f < 900; f++) {
      m.mouse.left = f < 6;
      m.runFrame();
      if (A[S.SHOTON] && shotStart < 0) shotStart = f;
      if (shotStart >= 0 && !A[S.SHOTON] && !A[S.SHOTARM] && shotEnd < 0) shotEnd = f;
      if (A[S.ARRFX]) arr++;
      if (!(A[S.ALIVE] | A[S.ALIVE + 1] | A[S.ALIVE + 2])) vanished++;
      if (A[S.SHIPLOST] || A[S.ENDMODE]) break;
    }
    check(A[S.OEFLAG] && shotStart > 0 && shotEnd > shotStart && shotEnd - shotStart < 60 && !A[S.FIREFLAG] && !arr && !vanished,
      `out of energy in a fight: the last shot (frames ${shotStart}-${shotEnd}) ends and clears the fire flag, the fighters stay (${vanished} frames without), no warp-in over them (${arr})`);
  }

  // 10. the flash: below 2000 (7/8) in flight and in a base's tunnel; none in a jump (as the original: $FA5B is not called there) nor while
  //     docking ($F9D6 recharges instead); white again at 2000 and more, after a refill and on returning from the map
  {
    const g = ready(), {k, m, A, S} = g;
    const col = () => m.colorRam[0x3E];
    const seen = (n, each) => { const c = new Set(); for (let i = 0; i < n; i++) { if (each) each(i); m.runFrame(); if (i) c.add(col()); } return [...c].sort().join(); };
    setEnergy(A, S, 1500);
    const flashing = seen(70);
    const refill = (setEnergy(A, S, 9999), seen(3));
    check(flashing === '7,8' && refill === '1', `out of energy: below 2000 the digits flash ${flashing}; a refill to 9999 makes them white at once (${refill})`);
    setEnergy(A, S, 1500); run(m, k.hooks, 40);
    run(m, k.hooks, 4, () => m.setKey(7, 5, true)); m.setKey(7, 5, false); run(m, k.hooks, 30);
    const onMap = seen(70);
    setEnergy(A, S, 5000); run(m, k.hooks, 3);
    const mapWhite = col();
    run(m, k.hooks, 4, () => m.setKey(7, 5, true)); m.setKey(7, 5, false); run(m, k.hooks, 30);
    check(A[S.MAPSHOWN] === 0 && onMap === '7,8' && mapWhite === 1 && col() === 1,
      `out of energy: the digits flash with the map open (${onMap}) and are white at 5000 (${mapWhite}), also back in the cockpit (${col()})`);
    // docking (MSSTATE 8 = the report's beam): no flash, the colour stays; and it goes on afterwards
    const h = ready(), M = h.m, B = h.A, T = h.S;
    setEnergy(B, T, 1500); run(M, h.k.hooks, 40);
    B[T.MSSTATE] = 8;
    const c0 = M.colorRam[0x3E], dock = new Set();
    for (let i = 0; i < 60; i++) { M.runFrame(); dock.add(M.colorRam[0x3E]); B[T.MSSTATE] = 8; }
    B[T.MSSTATE] = 0;
    const after = new Set();
    for (let i = 0; i < 40; i++) { M.runFrame(); after.add(M.colorRam[0x3E]); }
    check(dock.size === 1 && dock.has(c0) && after.size === 2, `out of energy: no flash while docking (${[...dock]}), it goes on afterwards (${[...after].sort()})`);
    // a jump: the colour stays (the original's $FA5B is not called there), and it resumes at the arrival
    const j = ready(), P = j.m, C = j.A, U = j.S;
    startJump(j, 38);
    setEnergy(C, U, 1500);
    run(P, j.k.hooks, 4, i => { P.mouse.left = i < 2; });
    const jump = new Set(); let hyper = 0;
    for (let i = 0; i < 4000 && (i < 60 || C[U.HYPON] || C[U.WIPE]); i++) { P.runFrame(); if (C[U.HYPON]) { hyper++; if (hyper > 5) jump.add(P.colorRam[0x3E]); } }
    const back = new Set();
    for (let i = 0; i < 70; i++) { P.runFrame(); back.add(P.colorRam[0x3E]); }
    check(hyper > 100 && jump.size === 2 && jump.has(7) && jump.has(8) && back.size === 2, `out of energy: the digits flash in the jump too (${hyper} frames, colours ${[...jump].sort()}), and after the arrival (${[...back].sort()})`);
  }

  // 7. a new game clears it: die out of energy, the reset, the title, a new game with 9999 energy
  if (!quick) {
    const g = ready(), {k, m, A, S} = g;
    strand(g, 1);
    run(m, k.hooks, 300);
    A[S.SHIPLOST] = 1; call(m, S.ENDARM);
    m.mouse.left = true; m.setBreak(S.ENDRESET, true);
    for (let f = 0; f < 23500 && !m.breakInfo; f++) m.runFrame();
    m.setBreak(S.ENDRESET, false); m.breakInfo = null; m.mouse.left = false;
    run(m, k.hooks, 120);
    const atReset = A[S.OEFLAG], resetEnergy = energy(A, S);
    const started = resumeFromTitle(m, S, () => m.runFrame());
    run(m, k.hooks, 200);
    check(!atReset && resetEnergy === 9999 && started && !A[S.OEFLAG] && energy(A, S) >= 9900,
      `out of energy: a new game after dying out of energy has the flag clear (${atReset}) and energy ${resetEnergy}, then ${energy(A, S)}; fire works again`);
    let shot = 0;
    m.mouse.present = true;
    run(m, k.hooks, 40, i => { m.mouse.left = i < 20; if (A[S.SHOTON]) shot++; });
    m.mouse.left = false;
    check(shot > 0, `out of energy: the new game's phasor fires (${shot} shot frames)`);
  }

  function call(m, a, a0) {
    const c = m.cpu, saved = [c.pc, c.sp, c.p, c.a, c.x, c.y];
    c.push(255); c.push(243); c.pc = a; c.p |= 4; if (a0 !== undefined) c.a = a0;
    let n = 0; while (c.pc !== 0xFFF4 && n++ < 2e6) { c.step(); if (c.jam) throw Error(c.jam); }
    [c.pc, c.sp, c.p, c.a, c.x, c.y] = saved;
  }
};



