'use strict';
// The C64 original's blanking of the display (LDA $D011 / AND #$EF / ORA #$20 / STA $D011 at $8D9A,
// the arrival after a destroyed mothership) copies the raster's bit 8 into the IRQ compare. Done on
// a line >= 256 it kills the IRQ chain: black screen, no win screen. hooks.fixC64Original() (the page).
module.exports = function ({boot, check, fs, path}) {
  const saved = JSON.parse(fs.readFileSync(path.join(__dirname, '../../briefs/ref/c64-proton-in-flight-mothership.state.json'), 'utf8'));
  const trial = (fix, seed) => {
    const k = boot('c64game', 'trace'), m = k.m, R = m.ram;
    if (fix) k.hooks.fixC64Original();
    m.loadState(m.stateFromText(JSON.stringify(saved.state)));
    for (let i = 0; i < 60; i++) { R[0x33C + i] = 0; R[0x378 + i] = 0; }     // only the destroyed mothership is left
    for (const b of [12, 17, 42, 47]) R[0x33C + b] = 0xFF;
    R[0x33C] = 0x80; R[0x378] = 1;
    let line = -1;
    const rd = m.vicRead;
    m.vicRead = function (r) { if (r === 0x11 && m.cpu.pc === 0x8D9D && line < 0) line = m.rasterLine(); return rd.call(this, r); };
    const frames = seed % 25, steps = (seed * 7919) % 20000;
    for (let i = 0; i < frames; i++) m.runFrame();
    for (let i = 0; i < steps; i++) m.cpu.step();
    for (let i = 0; i < 200; i++) m.runFrame();
    return { line, alive: !(m.vic[0x11] & 0x80) && !!(m.vic[0x11] & 0x10) };
  };
  let plainDead = 0, fixedDead = 0, late = 0, arrivals = 0;
  for (let s = 1; s <= 40; s++) {
    const a = trial(false, s), b = trial(true, s);
    if (a.line >= 256) late++;
    if (a.line >= 0) arrivals++;
    if (!a.alive) plainDead++;
    if (!b.alive) fixedDead++;
  }
  check(arrivals === 40 && late > 0 && plainDead === late,
    `c64 original: the arrival's $D011 read-modify-write on a line >= 256 kills the IRQ chain (${late} of ${arrivals} arrivals, ${plainDead} dead chains)`);
  check(fixedDead === 0, `c64 original: with the page's fix the IRQ chain and display survive all ${arrivals} arrivals (${fixedDead} dead)`);
};
