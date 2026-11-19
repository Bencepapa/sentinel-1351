'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

module.exports = function ({boot, check}) {
  const open = () => {
    const k = boot('game', 'trace', {atTitle: true});
    k.m.dma = true;
    k.m.mouse.present = false;
    return k;
  };
  const append = (log, frame, sid) => {
    for (let i = 0; i < sid.length; i += 3) log.push([frame, sid[i + 1], sid[i + 2]]);
  };
  const clear = Array.from({length: 25}, (_, i) => [24 - i, 0]);
  const hash = events => crypto.createHash('sha256').update(Buffer.from(events.flatMap(
    ([frame, reg, value]) => [frame & 255, frame >> 8, reg, value]))).digest('hex');

  {
    const {m, hooks, p: {symbols: s}} = open();
    const score = fs.readFileSync(path.join(__dirname, '../../c128-game/title-music.txt'), 'utf8')
      .split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('#'));
    const frequency = note => {
      if (note === '-') return 0;
      const octave = Number(note.at(-1));
      const offset = 'C D EF G A B'.indexOf(note[0]) + (note[1] === '#' ? 1 : note[1] === 'b' ? -1 : 0);
      return Math.round(440 * 2 ** ((octave * 12 + offset - 57) / 12) * 16777216 / 985248);
    };
    const expected = [], actual = [];
    const write = (frame, writes) => expected.push(...writes.map(([reg, value]) => [frame, reg, value]));
    write(0, [...clear, [24, 15], [5, 38], [12, 38], [19, 38], [6, 164], [13, 164], [20, 164]]);
    let init, first, visible, done, stable = true;
    hooks.on('MUSICINIT', () => { init = m.frame; });
    hooks.on('TITLESCROLL', () => { visible ??= m.frame; });
    hooks.on('music_note', () => { first ??= m.frame; });
    const length = score.reduce((sum, line) => sum + Number(line.split(/\s+/)[0]), 0);
    for (let f = 0; f < 120 + length && !done; f++) {
      const frame = m.frame;
      if (!m.runFrame()) break;
      if (init === undefined) continue;
      append(actual, frame - init, m.sidLog);
      if (first === undefined) continue;
      stable = stable && !m.ram[s.OVRUN] && !m.vicLog.some((reg, i) => {
        if (i % 4 !== 2 || ![0x20, 0x21].includes(reg)) return false;
        const [line, cycle] = m.vicLog.slice(i - 2, i);
        return cycle >= 16 && cycle <= 55 && ((line >= 50 && line <= 76) || (line >= 230 && line <= 245));
      });
      if (frame >= first + length + 12) done = true;
    }
    let at = first - init;
    for (const line of score) {
      const [duration, ...notes] = line.split(/\s+/);
      notes.forEach((note, voice) => {
        const reg = voice * 7, pitch = frequency(note);
        write(at, [[reg + 4, 16], [reg, pitch & 255], [reg + 1, pitch >> 8]]);
        if (pitch) write(at, [[reg + 4, 17]]);
      });
      at += Number(duration);
    }
    write(at, clear);
    const firstDifference = Array.from({length: Math.max(expected.length, actual.length)}, (_, i) => i)
      .find(i => String(expected[i]) !== String(actual[i]));
    const mismatch = firstDifference === undefined ? '' :
      ` first difference at relative frame ${(expected[firstDifference] ?? actual[firstDifference])[0]}` +
      ` (expected ${expected[firstDifference]}, got ${actual[firstDifference]})`;
    check(done && stable && first === visible && first > init &&
      hash(actual) === hash(expected) && !m.ram[s.MUSICWAIT],
    `title music: all ${expected.length} ordered SID writes, SHA-256 ${hash(actual)}, one-shot silence and DMA splits.${mismatch}`);
  }

  for (const input of ['F5', 'F7', 'Fire']) {
    const {m, p: {symbols: s}} = open(), a = m.ram;
    for (let f = 0; f < 100 && !(a[s.OVOWNER] === s.TITLEOWNER && a[s.TITLEARM]); f++) m.runFrame();
    const playing = a[s.MUSICWAIT] && a[s.MUSICINDEX];
    if (input === 'Fire') m.joy2 = 16;
    else m.setKey(0, input === 'F5' ? 6 : 3, true);
    const writes = [];
    for (let f = 0; f < 12 && !a[s.TITLEMENU]; f++) {
      m.runFrame();
      append(writes, f, m.sidLog);
    }
    const cancelled = a[s.TITLEMENU] === 1 && !a[s.MUSICWAIT] &&
      writes.slice(-26).map(([, reg, value]) => [reg, value]).join() === [...clear, [24, 15]].join();
    m.joy2 = 0;
    m.setKey(0, 6, false);
    m.setKey(0, 3, false);
    const ready = m.runFrame() && a[s.TITLEARM] && m.sidLog.length === 0;
    check(playing && cancelled && ready, `title music: ${input} cancels all voices and enables selector effects`);
  }
};
