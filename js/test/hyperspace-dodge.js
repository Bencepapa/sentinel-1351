module.exports = function ({boot, run, check}) {
  // Hyperspace steering, vertical: the original's dodge ($B8D9) moves the meteors DOWN for joystick down / the mouse
  // pulled back (bit 1 of $96 clear: Y += growth), UP for up / pushed forward; the port must do the same.
  const {m, hooks, p} = boot('game', 'trace');
  m.dma = true;
  run(m, hooks, 60);
  const r = m.ram, s = p.symbols;
  r[s.M_SELX] = r[s.M_SELY] = r[s.HFROMY] = 2; r[s.HFROMX] = 1; r[s.HPEND] = 1; r[s.HYPON] = 4;
  for (let i = 0; i < 1500 && r[s.HYPON] !== 2; i++) { r[s.WTCNT] = 100; m.runFrame(); }
  check(r[s.HYPON] === 2, 'port hyperspace: the jump is running');
  const st = m.saveState();
  let before = 0, joyAt = 0, after = 0, calls = 0;
  hooks.on('HDODGE', () => { r[s.HMACT] = 1; r[s.HMSHP] = 0x70; r[s.HMY] = 120; r[s.HMX] = 80; r[s.HMXH] = 0; before = 120; joyAt = r[s.HDJ] & 15; });
  hooks.on('mt_ddr', () => { after = r[s.HMY]; calls++; });
  function dodge(label, setup, expectDy) {
    m.loadState(st); calls = 0; after = 0; joyAt = 15;
    for (let f = 0; f < 90 && !(calls && joyAt !== 15); f++) { setup(); r[s.WTCNT] = 100; m.runFrame(); }
    setup = null;
    check(calls > 0 && (after - before) * expectDy > 0, `port hyperspace dodge: ${label}: HDJ ${joyAt.toString(2).padStart(4, '0')}, meteor Y ${before} -> ${after} (${expectDy > 0 ? 'down' : 'up'} expected)`);
  }
  dodge('joystick down', () => { m.mouse.present = false; m.joy2 = 2; }, +1);
  dodge('joystick up', () => { m.mouse.present = false; m.joy2 = 1; }, -1);
  dodge('mouse pulled back = down', () => m.moveMouse(0, -3), +1);
  dodge('mouse pushed forward = up', () => m.moveMouse(0, 3), -1);
  m.joy2 = 0; m.mouse.present = true;
};


