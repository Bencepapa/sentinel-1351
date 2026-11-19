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

  // Pixel value 2 is lettering. Mask out the moving stars (pixel value 3).
  const ink = byte => (byte & 0xaa) & ~((byte & 0x55) << 1);
  const letters = (ram, rows) => Buffer.from(rows.flatMap(row =>
    Array.from(ram.subarray(0x6000 + row * 320, 0x6000 + (row + 1) * 320), ink)));
  const titleRows = [4, 6, 8, 9, 10, 11, 13, 15, 16];
  const menuRows = [6, 8, 10, 12, 14];
  const inks = (ram, rows) => Buffer.from(rows.flatMap(row =>
    Array.from(ram.subarray(0x4400 + row * 40, 0x4400 + (row + 1) * 40))));
  const titleColors = ram => Buffer.from([
    ram[0x44a4], ram[0x4544], ram[0x456c], ram[0x4594], ram[0x45bc], ram[0x4667], ram[0x4689]
  ]);
  const bands = ram => Buffer.concat([
    Buffer.from(ram.subarray(0x44fb, 0x451c)), Buffer.from(ram.subarray(0x4612, 0x4633))
  ]);
  const scrollSplit = m => {
    for (let i = 0; i < m.vicLog.length; i += 4) {
      const [line, , reg, value] = m.vicLog.slice(i, i + 4);
      if (reg === 0x16 && line >= 230 && line <= 239) return value;
    }
    return -1;
  };
  const shotEnabled = m => m.vicLog.some((reg, i) => i % 4 === 2 && reg === 0x15 && (m.vicLog[i + 1] & 2));
  const sidWrites = (m, register) => m.sidLog.filter((_, i) => i % 3 === 2 && m.sidLog[i - 1] === register);
  const reference = (() => {
    const {m, hooks} = boot('c64game', 'trace');
    const A = m.ram, title = [], confirm = [];
    let accepted, brief, menu;
    hooks.on(0x8683, () => { accepted = m.frame; });
    hooks.on(0x96aa, () => { brief = m.frame; });
    for (let f = 0; f <= 560; f++) {
      if (f === 250) m.dma = true; // original loader needs its pre-DMA raster phase
      m.mouse.left = (f >= 300 && f < 308) || (f >= 400 && f < 408);
      m.runFrame();
      if (f >= 246 && f <= 299) {
        title.push({glyphs: letters(A, titleRows), colors: titleColors(A), bands: bands(A), cram: Buffer.from(A.subarray(0x4400, 0x47e8)),
          scroll: scrollSplit(m)});
      }
      if (f === 320) menu = {glyphs: letters(A, menuRows), colors: inks(A, menuRows), y: A[0x120a]};
      if (accepted !== undefined && brief === undefined) {
        confirm.push({color: A[0x44fc] & 15, shot: shotEnabled(m),
          charge: sidWrites(m, 4).includes(0x41), beep: sidWrites(m, 0x0b).includes(0x41)});
      }
    }
    return {title, menu, confirm, duration: brief - accepted};
  })();

  {
    const k = open(), {m, A, S} = k;
    const booted = until(m, () => title(k));
    check(booted && A.subarray(S.TITLELOGOBMP, S.TITLELOGOBMP + 192).some(Boolean) &&
      A.subarray(S.HUDE, S.HUDE + 4).every(digit => digit === 0x79) &&
      A.subarray(S.HUDTIME, S.HUDTIME + 5).join() === '112,112,110,112,112' &&
      A[S.TARGETS - 1] === 0x70 && A[S.TARGETS] === 0x70 &&
      Buffer.from(A.subarray(S.TITLEART, S.TITLETEXTEND)).equals(Buffer.from(
        m.ram1.subarray(S.B1TITLE + S.TITLEART - S.TITLEPKG, S.B1TITLE + S.TITLETEXTEND - S.TITLEPKG))),
    'title: cold boot draws the wordmark from bank 1 with S1 owned by TITLE and gameplay hooks/IRQ off');
    if (!booted) return;
    const compareAt = [0, 8, 16, 24, 32, 40, 50];
    let sameGlyphs = true, sameBands = true, sameColors = true, sameScroll = true, sameCells = true;
    for (let f = 0; f <= compareAt.at(-1); f++) {
      if (f) m.runFrame();
      const observed = reference.title[f];
      sameScroll = sameScroll && scrollSplit(m) === observed.scroll;
      if (!compareAt.includes(f)) continue;
      sameGlyphs = sameGlyphs && letters(A, titleRows).equals(observed.glyphs);
      sameCells = sameCells && Buffer.from(A.subarray(0x4400, 0x47e8)).equals(observed.cram);
      sameBands = sameBands && bands(A).equals(observed.bands);
      sameColors = sameColors && reference.title.slice(Math.max(0, f - 2), f + 3)
        .some(frame => titleColors(A).equals(frame.colors));
    }
    check(sameGlyphs, 'title: publisher, credits and four-row wordmark pixels match the C64 at seven frames');
    check(sameBands && sameColors,
      'title: opposite credit-band shifts match every sampled C64 frame; logo and credit palette within two frames');
    check(sameCells, 'title: every colour RAM cell (publisher, SYNAPSE SOFTWARE, PRESENTS, CREATED BY, both BRYAN BRANDENBURG rows, wordmark) matches the C64 at seven frames');
    snap(m, 'game-title');
    let last = A[S.TITLEPOS], fine = A[S.TITLEFINE], stable = true, spaced = true, wraps = 0;
    const count = S.TITLETEXTEND - S.TITLETEXT - 1;
    for (let f = 0; f <= count * 8; f++) {
      m.runFrame();
      fine = (fine - 1) & 7;
      stable = stable && scrollSplit(m) === fine && !late(m) && !A[S.OVRUN];
      if (fine === 7) {
        wraps += last === count ? 1 : 0;
        last = last === count ? 1 : last + 1;
        spaced = spaced && A[S.LRROW + 39] === A[S.TITLETEXT + last - 1];
      }
      spaced = spaced && A[S.TITLEPOS] === last;
    }
    const scrollText = Buffer.from(A.subarray(S.TITLETEXT, S.TITLETEXTEND - 1)).toString()
      .replaceAll('@', ' ').trimEnd();
    check(sameScroll && stable && spaced && wraps === 1 && scrollText.endsWith('PORT CREDITS GO HERE'),
      'title: C64 38-column fine scroll 7..0, eight frames per character, editable credits and no late splits/OVRUN');
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
    const held = A[S.TITLEMENU] === 1 && !A[S.GENDONE];
    fire(false);
    until(m, () => A[S.TITLEARM], 12);
    let splitOK = true;
    const tick = () => {
      const ok = m.runFrame();
      splitOK = splitOK && ok && !late(m) && !A[S.OVRUN];
      return ok;
    };
    if (device === 'joystick' && level === 0) {
      check(letters(A, menuRows).equals(reference.menu.glyphs) &&
        inks(A, menuRows).equals(reference.menu.colors) && A[S.CURY] === reference.menu.y &&
        A.subarray(S.LRROW, S.LRROW + 40).every(code => code === 0x60),
      'title: selector bitmap, palette, initial crosshair row and empty scroller match the C64');
    }
    const startX = A[S.CURX];
    if (mouse) m.moveMouse(12, 0);
    else m.joy2 = 8;
    tick();
    m.joy2 = 0;
    const movedHorizontally = A[S.CURX] > startX && A[S.DIFF] === 0;
    const moveTo = (row, direction) => {
      if (mouse) m.moveMouse(0, -16 * direction);
      else m.joy2 = direction > 0 ? 2 : 1;
      for (let f = 0; f < 10 && A[S.DIFF] !== row; f++) tick();
      m.joy2 = 0;
      tick();
      return A[S.DIFF] === row;
    };
    let moved = movedHorizontally;
    for (let row = 1; row <= level; row++) moved = moveTo(row, 1) && moved;
    if (level > 0) moved = moveTo(level - 1, -1) && moveTo(level, 1) && moved;
    const menuColors = inks(A, menuRows);
    const highlighted = [...Array(5)].every((_, row) =>
      menuColors.subarray(40 * row, 40 * (row + 1)).every(ink => ink === (row === level ? 0x17 : 0x19)));
    if (device === 'mouse' && level === 4) snap(m, 'game-title-selector');
    let placed = 0, leftAt;
    hooks.on('M_gensize', () => placed++);
    hooks.on('title_leave', () => { leftAt = m.frame; });
    fire(true);
    tick();
    const accepted = m.frame - 1;
    fire(false);
    const sequence = [];
    let began = false;
    for (let f = 1; f <= reference.duration + 40; f++) {
      m.setKey(7, 4, !!(A[S.INTROACTIVE] && A[S.INTROARM]));
      tick();
      m.setKey(7, 4, false);
      if (A[S.GENDONE] && !A[S.M_NSQ] && !A[S.OVOWNER]) {
        began = true;
        break;
      }
      if (leftAt !== undefined) continue;
      const colors = menuRows.map(row => A[0x4400 + row * 40 + 20] & 15);
      sequence[f] = {color: colors[level], hidden: colors.every((c, i) => i === level || !c),
        shot: shotEnabled(m), charge: sidWrites(m, 4).includes(0x41), beep: sidWrites(m, 0x0b).includes(0x41)};
      if (device === 'mouse' && level === 4 && f === 16) snap(m, 'game-title-confirm');
    }
    const duration = leftAt - accepted;
    const events = (timeline, event) => timeline.flatMap((frame, f) => frame[event] ? [f] : []);
    const shots = events(sequence, 'shot'), beeps = events(sequence, 'beep');
    const c64shots = events(reference.confirm, 'shot'), c64beeps = events(reference.confirm, 'beep');
    const inRange = (a, b, tolerance) => Math.abs(a - b) <= tolerance;
    const confirmOK = inRange(duration, reference.duration, 1) &&
      inRange(shots[0], c64shots[0], 3) && shots.length > 0 &&
      (level !== 0 || inRange(shots.at(-1), c64shots.at(-1), 3)) &&
      events(sequence, 'charge').join() === events(reference.confirm, 'charge').join() &&
      beeps.join() === c64beeps.join() &&
      sequence.slice(7).every(frame => frame.hidden) &&
      [10, 12, 14, 16, 18, 20, 22].every(f => reference.confirm.slice(f - 2, f + 3)
        .some(frame => frame.color === sequence[f]?.color));
    check(confirmOK && splitOK,
      `title: ${device} level ${level} phasor, palette and SID beeps through ${duration} DMA frames with 0 late splits/OVRUN`);
    const map = A.subarray(S.M_STATE, S.M_STATE + 60);
    const groups = [...map].filter(v => v >= 1 && v <= 3).length;
    const saneMap = map[24] === 0 && [0, 9, 50, 59].every(i => map[i] === 0x80) &&
      [12, 17, 42, 47].every(i => map[i] === 0xff);
    check(booted && entered && held && moved && highlighted && splitOK && began && A[S.MAPSHOWN] && A[S.DIFF] === level &&
      A[S.SHLD] === shields[level] && A[0x485b] === 0x78 &&
      A.subarray(S.SYSHP, S.SYSHP + 8).join() === systems[level].join() &&
      placed === squadrons[level] && groups >= placed - 1 && groups <= placed && saneMap &&
      !A[S.OVRUN] && !A[S.OVREFUSE],
    `title: ${device} level ${level} starts with ${A[S.SHLD]} shields, eight protons, original system HP and ${placed} squadron placements`);
  }
};
