'use strict';

module.exports = function ({boot, run, check, resumeFromTitle}) {
  function ready() {
    const game = boot('game', 'trace');
    game.m.dma = true;
    run(game.m, game.hooks, 80);
    return { ...game, S: game.p.symbols, A: game.m.ram };
  }

  function pulse(m, row) {
    m.setKey(0, row, true);
    m.runFrame();
    m.runFrame();
    m.setKey(0, row, false);
  }

  function until(m, done, frames) {
    for (let f = 0; f < frames && !done(); f++) m.runFrame();
    return done();
  }

  function call(m, address) {
    const c = m.cpu, saved = [c.pc, c.sp, c.p];
    c.push(255);
    c.push(243);
    c.pc = address;
    c.p |= 4;
    let steps = 0;
    while (c.pc !== 0xFFF4 && ++steps < 2000000) c.step();
    if (c.pc !== 0xFFF4) throw new Error('Function-key fixture did not return');
    [c.pc, c.sp, c.p] = saved;
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
    const {m, S, A} = ready();
    // Shift+F1 is F2. Start with a hidden colon to verify its phase on resume.
    A[S.CLOCKDIV] = 20;
    A[S.HUDTIME + 2] = 0x60;
    m.setKey(1, 7, true);
    pulse(m, 4);
    m.setKey(1, 7, false);
    const snapshot = () => [S.WTCNT, S.M_TICKC, S.CLOCKDIV, S.FRMC, S.CURX, S.CURY].map(p => A[p]).join();
    const before = snapshot();
    const pausedAndMuted = A[S.PAUSED] && A[S.HUDTIME + 2] === 0x6E && m.sid[0x18] === 0;
    let writes = 0, late = 0;
    for (let f = 0; f < 60; f++) {
      m.moveMouse(1, 0);
      m.setKey(0, 4, f > 3 && f < 12);
      m.runFrame();
      writes += m.sidLog.length;
      late += lateWrites(m);
    }
    check(pausedAndMuted && A[S.PAUSED] && before === snapshot() && !writes,
      'F1/F2 pauses the world, HUD timer, cursor and SID; F1 and mouse motion leave it paused');
    check(late === 0 && A[S.OVRUN] === 0, 'F1 preserves the DMA raster splits with no vertical-blank overrun');

    m.joy2 = 4;
    until(m, () => !A[S.PAUSED], 4);
    m.joy2 = 0;
    check(!A[S.PAUSED] && m.sid[0x18] === 15 && A[S.CLOCKDIV] < 20 && A[S.HUDTIME + 2] === 0x60,
      'A joystick direction resumes F1 with the previous clock phase and master volume');
    pulse(m, 4);
    m.joy2 = 16;
    check(until(m, () => !A[S.PAUSED], 4), 'Joystick fire also resumes F1');
  }

  {
    const {m, S, A} = ready();
    const initialSP = m.cpu.sp;
    A[S.DIFF] = 2;
    A[S.SHLD] = 1;
    A[0x485B] = 0x71;
    m.setKey(0, 3, true);
    const restarted = until(m, () => A[S.OVOWNER] === S.TITLEOWNER, 100);
    check(restarted && A[S.DIFF] === 0 && A[0x485B] === 0x78 &&
      A[S.SHLD] === A[S.SHTAB] && A[S.CLOCKDIV] === 60 && !A[S.OVREFUSE] && !A[S.PAUSED],
      'F7 restores difficulty, shields, protons and the clock on its return to TITLE');
    for (let f = 0; f < 20; f++) m.runFrame();
    check(A[S.CLOCKDIV] === 60 && !A[S.TITLEMENU] && Math.abs(m.cpu.sp - initialSP) < 12,
      'Holding F7 causes one restart and waits at TITLE with a balanced stack');
    m.setKey(0, 3, false);
    check(resumeFromTitle(m, S) && until(m, () => A[S.CLOCKDIV] < 60, 20),
      'The difficulty menu can start another flight after an F7 reset');
  }

  {
    const {m, S, A} = ready();
    A[S.M_SELX] = A[S.M_SELY] = 0;
    A[S.M_STATE] = 0x80;
    call(m, S.SECTORIN);
    const tunnel = until(m, () => A[S.MSSTATE] === 16 && A[S.MTPHASE] > 3, 600);
    pulse(m, 4);
    const phase = A[S.MTPHASE];
    let bands = 0;
    for (let f = 0; f < 10; f++) {
      m.runFrame();
      for (let i = 0; i < m.vicLog.length; i += 4) {
        if (m.vicLog[i] > 80 && m.vicLog[i] < 226 && m.vicLog[i + 2] === 0x20) bands++;
      }
    }
    check(tunnel && A[S.PAUSED] && A[S.MTPHASE] === phase && bands >= 80,
      'F1 holds the mine-tunnel phase while its raster IRQ continues drawing the eight bands');
    m.joy2 = 8;
    until(m, () => !A[S.PAUSED], 4);
    m.joy2 = 0;
    A[S.SHLD] = 1;
    pulse(m, 3);
    check(until(m, () => A[S.OVOWNER] === S.TITLEOWNER, 100) &&
      A[S.CLOCKDIV] === 60 && A[S.SHLD] === A[S.SHTAB] && !A[S.MSSTATE] &&
      !(m.vic[0x1a] & 1) && !A[S.OVREFUSE] && !A[S.OVRUN],
      'F7 shuts down the mine IRQ and returns to TITLE through ENDING');
  }

  // A friendly base's report. press = frames after the text is typed (state 10) when F3 is tapped
  // (negative: tapped during the typing, state 9), shift = Shift+F3 (= F4), energy = the starting HUD energy.
  function repair(skip, energy = '9890', shift = false, press = 0) {
    const {m, S, A} = ready();
    const base = 12;
    A[S.M_SELX] = base % 10;
    A[S.M_SELY] = Math.floor(base / 10);
    A[S.M_STATE + base] = 0xFF;
    call(m, S.SECTORIN);
    if (!until(m, () => A[S.MSSTATE] === 3, 600)) return {};
    A.fill(0, S.SYSHP, S.SYSHP + 8);
    A[S.SHLD] = 1;
    A[0x485A] = 0x70;
    A[0x485B] = 0x75;
    A.set([...energy].map(c => 0x70 + Number(c)), S.HUDE);
    call(m, S.MRSTART);
    if (!until(m, () => A[S.MSSTATE] === (press < 0 ? 9 : 10), 600)) return {};
    for (let f = 0; f < press; f++) m.runFrame();
    const start = m.frame;
    if (skip) {
      if (shift) m.setKey(1, 7, true);
      pulse(m, 5);
      m.setKey(1, 7, false);
    }
    let late = 0;
    const done = until(m, () => { late += lateWrites(m); return A[S.MSSTATE] === 0; }, 1500);
    return {
      done, late,
      frames: m.frame - start,
      systems: [...A.subarray(S.SYSHP, S.SYSHP + 8)],
      energy: [...A.subarray(S.HUDE, S.HUDE + 4)],
      protons: A[0x485B] - 0x70,
      shields: A[S.SHLD],
      overrun: A[S.OVRUN]
    };
  }

  {
    const normal = repair(false), skipped = repair(true);
    check(normal.done && skipped.done && normal.frames - skipped.frames > 75 &&
      normal.systems.join() === skipped.systems.join() && skipped.energy.every(digit => digit === 0x79) &&
      skipped.shields === normal.shields && skipped.protons === 6 && !skipped.overrun,
      `F3 skips the friendly inspection (${normal.frames} to ${skipped.frames} DMA frames), refills energy and awards exactly one proton`);
    // A drained ship used to wait out the whole refill (+9 a frame) after F3, as the original does: F3 looked dead.
    const drained = repair(false, '0000'), fast = repair(true, '0000'), shifted = repair(true, '0000', true, 40);
    check(drained.done && drained.frames > 1000 && fast.done && fast.frames < 40 &&
      fast.energy.every(digit => digit === 0x79) && fast.systems.join() === drained.systems.join() &&
      fast.shields === drained.shields && fast.protons === 6 && !fast.overrun && !fast.late,
      `F3 on a drained ship completes the repair at once (${drained.frames} to ${fast.frames} DMA frames): systems repaired, shields and energy full, one proton`);
    check(shifted.done && shifted.frames < 40 && shifted.energy.every(digit => digit === 0x79) &&
      shifted.systems.join() === drained.systems.join() && shifted.protons === 6 && !shifted.overrun,
      `Shift+F3 (F4) skips the same way, tapped 40 frames into the report (${shifted.frames} frames)`);
    // A tap while the text is still being typed (the original polls only afterwards) counts once the checks start.
    const early = repair(true, '5000', false, -1);
    check(early.done && early.frames < 120 && early.energy.every(digit => digit === 0x79) &&
      early.systems.join() === drained.systems.join() && early.protons === 6 && !early.overrun,
      `F3 tapped during the typing is honoured when the checks start (${early.frames} frames)`);
  }

  {
    // Outside the report F3 does nothing: normal flight and the mine tunnel.
    const {m, S, A} = ready();
    A.set([0x70, 0x70, 0x70, 0x70], S.HUDE);
    const state = () => [S.MSSTATE, S.MRROW, S.MREN, S.PAUSED, S.FKEYGO].map(a => A[a]).join();
    const before = state();
    for (let f = 0; f < 10; f++) { pulse(m, 5); m.runFrame(); }
    check(before === state() && A.subarray(S.HUDE, S.HUDE + 4).every(digit => digit < 0x79) && A[S.OVRUN] === 0,
      'F3 in normal flight does nothing: no latch, no energy refill, no state change');
    A[S.M_SELX] = A[S.M_SELY] = 0;
    A[S.M_STATE] = 0x80;
    call(m, S.SECTORIN);
    until(m, () => A[S.MSSTATE] === 16 && A[S.MTPHASE] > 3, 600);
    const energy = A.subarray(S.HUDE, S.HUDE + 4).join();
    for (let f = 0; f < 6; f++) { pulse(m, 5); m.runFrame(); }
    check(A[S.MSSTATE] === 16 && !A[S.FKEYGO] && !A[S.PAUSED] && energy === A.subarray(S.HUDE, S.HUDE + 4).join(),
      'F3 in the mine tunnel does nothing');
  }
};
