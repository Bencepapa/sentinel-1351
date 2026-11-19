'use strict';

module.exports = function ({boot, check, snap}) {
  const until = (m, predicate, limit = 100) => {
    for (let f = 0; f < limit && !predicate(); f++) {
      if (!m.runFrame()) return false;
    }
    return predicate();
  };
  const open = () => {
    const k = boot('game', 'trace', {atTitle: true});
    k.m.dma = true;
    k.m.mouse.present = false;
    return {...k, S: k.p.symbols, A: k.m.ram};
  };
  const word = (a, p) => a[p] | (a[p + 1] << 8);
  const title = ({m, A, S}) => A[S.OVOWNER] === S.TITLEOWNER && A[S.TITLEARM] &&
    !(m.vic[0x1a] & 1) && word(A, 0xfffe) === S.NMIRTI &&
    word(A, S.vv2 + 1) < S.S1BASE && word(A, S.sprcj + 1) < S.S1BASE &&
    !A[S.OVJOB] && !A[S.GENDONE] && !A[S.OVREFUSE];
  const late = m => {
    for (let i = 0; i < m.vicLog.length; i += 4) {
      const [line, cycle, reg] = m.vicLog.slice(i, i + 3);
      if ((reg === 0x20 || reg === 0x21) && cycle >= 16 && cycle <= 55 &&
          ((line >= 50 && line <= 76) || (line >= 230 && line <= 245))) return true;
    }
    return false;
  };

  {
    const k = open(), {m, A, S} = k;
    const booted = until(m, () => title(k));
    check(booted && A.subarray(S.TITLELOGOBMP, S.TITLELOGOBMP + 192).some(Boolean) &&
      A.subarray(S.HUDE, S.HUDE + 4).every(digit => digit === 0x79) &&
      A.subarray(S.HUDTIME, S.HUDTIME + 5).join() === '112,112,110,112,112' &&
      A[S.TARGETS - 1] === 0x70 && A[S.TARGETS] === 0x70 &&
      Buffer.from(A.subarray(S.TITLEART, S.TITLEEND)).equals(Buffer.from(
        m.ram1.subarray(S.B1TITLE + S.TITLEART - S.TITLEPKG, S.B1TITLE + S.TITLEEND - S.TITLEPKG))),
    'title: cold boot draws the wordmark from bank 1 with S1 owned by TITLE and gameplay hooks/IRQ off');
    if (!booted) return;
    snap(m, 'game-title');
    let last = A[S.TITLEPOS], fine = A[S.TITLEFINE], stable = true, spaced = true, wraps = 0;
    const count = S.TITLETEXTEND - S.TITLETEXT - 1;
    for (let f = 0; f <= count * 8; f++) {
      m.runFrame();
      fine = (fine - 1) & 7;
      let split = -1;
      for (let i = 0; i < m.vicLog.length; i += 4) {
        const [line, , reg, value] = m.vicLog.slice(i, i + 4);
        if (reg === 0x16 && line >= 230 && line <= 239) split = value;
      }
      stable = stable && split === fine && !late(m) && !A[S.OVRUN];
      if (fine === 7) {
        wraps += last === count ? 1 : 0;
        last = last === count ? 1 : last + 1;
        spaced = spaced && A[S.LRROW + 39] === A[S.TITLETEXT + last - 1];
      }
      spaced = spaced && A[S.TITLEPOS] === last;
    }
    check(stable && spaced && wraps === 1,
      'title: 38-column fine scroll 7..0, one character every eight DMA frames, terminator wraps with zero late splits/OVRUN');
  }

  const shields = [40, 30, 25, 25, 25], squadrons = [10, 15, 24, 31, 44];
  const systems = [
    [255, 255, 4, 6, 3, 4, 2, 255],
    [10, 10, 3, 4, 3, 4, 2, 255],
    [5, 6, 2, 4, 3, 4, 2, 255],
    [5, 4, 2, 4, 3, 4, 2, 255],
    [5, 4, 2, 4, 3, 4, 2, 255],
  ];
  for (const device of ['joystick', 'mouse']) for (let level = 0; level < 5; level++) {
    const k = open(), {m, A, S, hooks} = k;
    const mouse = device === 'mouse';
    if (mouse) m.mouse.present = true;
    const fire = down => { if (mouse) m.mouse.left = down; else m.joy2 = down ? 16 : 0; };
    const booted = until(m, () => title(k));
    if (level === 0) m.setKey(0, 6, true);
    else if (level === 1) m.setKey(0, 3, true);
    else fire(true);
    const entered = until(m, () => A[S.TITLEMENU], 12);
    m.setKey(0, 6, false);
    m.setKey(0, 3, false);
    if (level > 1) {
      for (let f = 0; f < 3; f++) m.runFrame();
    }
    const held = !A[S.GENDONE];
    fire(false);
    until(m, () => A[S.TITLEARM], 12);
    let splitOK = true;
    for (let row = 1; row <= level; row++) {
      if (mouse) m.moveMouse(0, -16);
      else m.joy2 = 2;
      m.runFrame();
      splitOK = splitOK && !late(m);
      m.joy2 = 0;
      m.runFrame();
      splitOK = splitOK && !late(m);
    }
    if (level > 0) {
      if (mouse) m.moveMouse(0, 16);
      else m.joy2 = 1;
      m.runFrame();
      const movedUp = A[S.DIFF] === level - 1;
      m.joy2 = 0;
      m.runFrame();
      if (mouse) m.moveMouse(0, -16);
      else m.joy2 = 2;
      m.runFrame();
      m.joy2 = 0;
      m.runFrame();
      splitOK = splitOK && movedUp;
    }
    const highlighted = [...Array(5)].every((_, row) =>
      (m.colorRam[0x100 + row * 40] & 15) === (row === level ? 7 : 14));
    if (device === 'mouse' && level === 4) snap(m, 'game-title-selector');
    let placed = 0;
    hooks.on('M_gensize', () => placed++);
    fire(true);
    const began = until(m, () => A[S.GENDONE] && A[S.M_NSQ] === 0 && A[S.OVOWNER] === 0, 30);
    fire(false);
    const map = A.subarray(S.M_STATE, S.M_STATE + 60);
    const groups = [...map].filter(v => v >= 1 && v <= 3).length;
    const saneMap = map[24] === 0 && [0, 9, 50, 59].every(i => map[i] === 0x80) &&
      [12, 17, 42, 47].every(i => map[i] === 0xff);
    check(booted && entered && held && highlighted && splitOK && began && A[S.DIFF] === level &&
      A[S.SHLD] === shields[level] && A[0x485b] === 0x78 &&
      A.subarray(S.SYSHP, S.SYSHP + 8).join() === systems[level].join() &&
      placed === squadrons[level] && groups >= placed - 1 && groups <= placed && saneMap &&
      !A[S.OVRUN] && !A[S.OVREFUSE],
    `title: ${device} level ${level} starts with ${A[S.SHLD]} shields, eight protons, original system HP and ${placed} squadron placements`);
  }
};
