'use strict';

const fs = require('fs');
const path = require('path');

module.exports = function ({boot, check, snap}) {
  const until = (m, predicate, limit) => {
    for (let f = 0; f < limit && !predicate(); f++) if (!m.runFrame()) return false;
    return !!predicate();
  };
  const start = hold => {
    const {m, hooks, p: {symbols: s}} = boot('game', 'trace', {atTitle: true});
    const a = m.ram;
    m.dma = true;
    m.mouse.present = false;
    const title = until(m, () => a[s.OVOWNER] === s.TITLEOWNER && a[s.TITLEARM], 120);
    m.setKey(0, 6, true);
    const menu = until(m, () => a[s.TITLEMENU] === 1, 12);
    m.setKey(0, 6, false);
    const armed = until(m, () => a[s.TITLEARM], 12);
    m.joy2 = 16;
    m.runFrame();
    if (!hold) m.joy2 = 0;
    const intro = until(m, () => a[s.INTROACTIVE], s.TITLECONFIRMFRAMES + 12);
    return {m, hooks, s, a, ready: title && menu && armed && intro};
  };
  const edge = m => {
    for (let i = 0; i < m.vicLog.length; i += 4) {
      const [line, , reg, value] = m.vicLog.slice(i, i + 4);
      if (line >= 75 && line <= 123 && reg === 0x21 && value === 0) return line;
    }
    return -1;
  };
  const late = m => m.vicLog.some((reg, i, log) => i % 4 === 2 && (reg === 32 || reg === 33) &&
    log[i - 2] >= 50 && log[i - 2] <= 245 && log[i - 1] >= 16 && log[i - 1] <= 55);
  const inMap = (a, s) => a[s.GENDONE] && a[s.MAPSHOWN] && !a[s.OVOWNER] && !a[s.INTROACTIVE];

  {
    const {m, s, a, ready} = start(false);
    const [welcome, ...lines] = fs.readFileSync(path.join(__dirname, '../../c128-game/title-intro.txt'), 'utf8')
      .split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('#'));
    const expected = Buffer.from(lines.map(line => 'a' + line.padEnd(38).replaceAll(' ', '@') + 'b').join(''));
    const pixels = new Map(), opened = [], closed = [], typed = [];
    let ribbon = false, splits = true, text = false, click = true, drawn = false;
    let previous = 0;
    for (let f = 0; f < 1250 && a[s.OVOWNER] === s.TITLEOWNER; f++) {
      const phase = a[s.INTROPHASE], line = a[s.INTROSPLIT];
      if (!m.runFrame()) break;
      if (edge(m) < 0 && !a[s.INTROACTIVE]) break;
      splits &&= !late(m) && !a[s.OVRUN] && m.clockMHz() === 1 && edge(m) === line;
      if (!phase) {
        const row = Buffer.from(a.subarray(s.LRROW, s.LRROW + 40)).toString().replaceAll('@', ' ');
        ribbon ||= row.includes(welcome);
      }
      if (phase === 1) opened.push(edge(m) - s.INTROBASE);
      if (phase === 4) closed.push(edge(m) - s.INTROBASE);
      const height = line - s.INTROBASE;
      if ([0, 24, 48].includes(height) && !pixels.has(height)) {
        const at = raster => m.video.px[(raster - 15) * 384 + 192];
        pixels.set(height, at(line - 1) === 0xff444444 && at(line) === 0xff000000);
        snap(m, 'game-intro-' + height);
      }
      if (phase === 2 && a[s.INTROINDEX] !== previous) {
        const index = a[s.INTROINDEX] - 1, code = expected[index];
        typed.push(f);
        previous = index + 1;
        click &&= m.sidLog.some((reg, i) => i % 3 === 1 && reg === 4 && m.sidLog[i + 1] === 17) ===
          (code >= 65 && code <= 90);
        click &&= a[s.INTROROW + index] === code;
        if (previous === 75) {
          snap(m, 'game-intro-typing');
          drawn = m.video.px.some((px, i) => i >= (75 - 15) * 384 && i < (99 - 15) * 384 &&
            (i % 384) > 40 && (i % 384) < 344 && px === 0xffffffff);
        }
      }
      if (phase === 3) text ||= expected.equals(Buffer.from(a.subarray(s.INTROROW, s.INTROROW + 240)));
    }
    const heights = Array.from({length: 48}, (_, i) => i);
    check(ready && ribbon && pixels.size === 3 && [...pixels.values()].every(Boolean) &&
      opened.join() === heights.join() && closed.join() === heights.map(i => 48 - i).concat(0).join() && splits,
    'title intro: welcome ribbon and 0/24/48-line pixels, one-line steps in both directions at 1 MHz with DMA');
    check(typed.length === 240 && typed.every((frame, i) => !i || frame === typed[i - 1] + 2) && click && text && drawn,
      'title intro: six briefing rows appear one cell every two frames, with one SID click per visible glyph');
    const map = until(m, () => inMap(a, s) && !a[s.WIPE], 80);
    check(map && !(m.vic[0x1a] & 1) && !a[s.OVRUN] && !a[s.MUSICWAIT],
      'title intro: closes automatically, hands off to the resident map, and leaves the raster IRQ off');
    m.setKey(7, 5, true);
    m.runFrame();
    m.setKey(7, 5, false);
    check(until(m, () => !a[s.MAPSHOWN] && !a[s.WIPE], 80), 'title intro: the initial map closes into normal flight');
  }

  for (const key of ['Fire', 'Space']) {
    const {m, hooks, s, a, ready} = start(key === 'Fire');
    let musicAfterReset = false;
    if (key === 'Fire') for (let f = 0; f < 20; f++) m.runFrame();
    const held = a[s.INTROACTIVE] && (key !== 'Fire' || !a[s.INTROARM]);
    m.joy2 = 0;
    until(m, () => a[s.INTROARM], 12);
    if (key === 'Space') until(m, () => a[s.INTROPHASE] === 2, 440);
    if (key === 'Fire') m.joy2 = 16;
    else m.setKey(7, 4, true);
    const advanced = until(m, () => inMap(a, s) && !a[s.WIPE], 60);
    const noTorpedo = !a[s.TREQ] && a[0x485b] === 0x78;
    m.joy2 = 0;
    m.setKey(7, 4, false);
    check(ready && held && advanced && noTorpedo && !a[s.OVRUN],
      `title intro: a fresh ${key} press advances directly to the map`);
    if (key !== 'Fire') continue;

    hooks.on('MUSICINIT', () => { musicAfterReset = true; });
    m.setKey(0, 3, true);
    const reset = until(m, () => a[s.OVOWNER] === s.TITLEOWNER && musicAfterReset, 140);
    m.setKey(0, 3, false);
    until(m, () => a[s.TITLEARM], 16);
    m.setKey(0, 6, true);
    const menu = until(m, () => a[s.TITLEMENU] === 1, 12);
    m.setKey(0, 6, false);
    until(m, () => a[s.TITLEARM], 12);
    m.joy2 = 16;
    m.runFrame();
    m.joy2 = 0;
    check(reset && menu && until(m, () => a[s.INTROACTIVE], s.TITLECONFIRMFRAMES + 12) &&
      a[s.INTROPHASE] === 0 && !a[s.OVRUN] && !a[s.MUSICWAIT],
    'title intro: F7 reset rearms the title cue and a new selection starts the welcome again');
  }
};
