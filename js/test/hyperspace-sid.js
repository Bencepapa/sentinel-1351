'use strict';

module.exports = function ({boot, run, check}) {
  // Capture the six writes of the noise burst independently of the warp
  // oscillator, the sweep, and sounds caused by meteor hits.
  function trace(m, advance) {
    const bursts = [];
    let late = 0, cruiseStart = -1;
    for (let i = 0; i < 800; i++) {
      const phase = advance();
      if (!phase) break;
      if (phase === 'cruise' && cruiseStart < 0) cruiseStart = i;
      const pairs = m.sidLog.filter((_, index) => index % 3 !== 0);
      const start = pairs.findIndex((reg, index) =>
        index % 2 === 0 && reg === 0x12 && pairs[index + 1] === 0 &&
        pairs[index + 2] === 0x0F && pairs[index + 3] === 8);
      if (start >= 0 && phase !== 'before') {
        bursts.push({frame: i, phase, writes: pairs.slice(start, start + 12),
          afterPitch: pairs.slice(0, start).some((reg, index) => index % 2 === 0 && reg === 0x10)});
      }
      for (let j = 0; j < m.vicLog.length; j += 4) {
        const line = m.vicLog[j], cycle = m.vicLog[j + 1], reg = m.vicLog[j + 2];
        if ((reg === 0x20 || reg === 0x21) && cycle >= 16 && cycle <= 55 &&
            ((line >= 50 && line <= 76) || (line >= 230 && line <= 245))) late++;
      }
    }
    return {bursts, late, cruiseStart};
  }

  function original(occupied) {
    const {m, hooks} = boot('c64game', 'trace');
    run(m, hooks, 300);
    run(m, hooks, 300, i => { m.mouse.left = i < 10 || (i >= 150 && i < 160); });
    m.mouse.left = false;
    run(m, hooks, 200);
    m.dma = true;
    const r = m.ram;
    r[0xBA] = 1;
    r[0x2B13] = 9;
    r[0xDF] = r[0xDE] = 2;
    r[0x033C + 22] = r[0x0378 + 22] = occupied ? 3 : 0;
    m.cpu.pc = 0xFC9A; // The map accepted the jump.
    return trace(m, () => {
      const phase = r[0xE6] ? 'decel' : r[0xDA] ? 'cruise' : r[0xBA] ? 'before' : '';
      if (phase) m.runFrame();
      return phase;
    });
  }

  function port(occupied) {
    const {m, hooks, p} = boot('game', 'trace');
    m.dma = true;
    run(m, hooks, 60);
    const r = m.ram, s = p.symbols;
    r[s.M_STATE + 22] = occupied ? 1 : 0;
    r[s.M_COUNT + 22] = occupied ? 3 : 0;
    r[s.M_SELX] = r[s.M_SELY] = r[s.HFROMY] = 2;
    r[s.HFROMX] = 1;
    r[s.HPEND] = 1;
    r[s.HYPON] = 4;
    const observed = trace(m, () => {
      const phase = ['', 'before', 'cruise', 'decel', 'before'][r[s.HYPON]];
      if (phase) {
        r[s.WTCNT] = 100;
        m.runFrame();
      }
      return phase;
    });
    return {...observed, overrun: r[s.OVRUN]};
  }

  const cadence = bursts => bursts.slice(1).map((burst, i) => burst.frame - bursts[i].frame);
  for (const occupied of [false, true]) {
    const reference = original(occupied), game = port(occupied);
    const firstReferenceWrites = reference.bursts[0]?.writes.join();
    check(reference.bursts.length > 20 && game.bursts.length > 20 &&
      reference.bursts[0].frame === reference.cruiseStart &&
      game.bursts[0].frame === game.cruiseStart &&
      reference.bursts.some(burst => burst.phase === 'decel') &&
      game.bursts.some(burst => burst.phase === 'decel') &&
      cadence(reference.bursts).every(gap => gap === 6) &&
      cadence(game.bursts).every(gap => gap === 6) &&
      game.bursts.every(burst => burst.afterPitch && burst.writes.join() === firstReferenceWrites),
      `game: warp to an ${occupied ? 'occupied' : 'empty'} sector replays the original six-register SID burst every six frames (${reference.bursts.length} C64, ${game.bursts.length} C128)`);
    check(!game.late && !game.overrun,
      `game: warp SID timing has ${game.late} late splits and ${game.overrun} overruns`);
  }
};
