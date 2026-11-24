'use strict';

const crypto = require('crypto');

// The title tune and the selector's engine hum, compared write for write with the
// original C64 game (patched PRG, DMA on from frame 250 as the original's loader needs).
module.exports = function ({boot, check}) {
  const SURVEY_SHA = '10743917c6a3c36ed2cdc30eaff062948e3dedb1f3d89cbc3bb9ba27769f0cbd';
  const original = (() => {
    const {m, hooks} = boot('c64game', 'trace');
    let init, pc = 0;
    const events = [], write = m.sidWrite.bind(m);
    m.sidWrite = (reg, value) => {
      pc = m.cpu.pc;
      if (init !== undefined && pc >= 0x1c70 && pc <= 0x1ec6) events.push([m.frame - init, reg, value]);
      write(reg, value);
    };
    hooks.on(0x1c70, () => { init ??= m.frame; });
    for (let f = 0; f < 4700; f++) {
      if (f === 250) m.dma = true;
      if (!m.runFrame()) break;
    }
    return events;
  })();
  const sha = events => crypto.createHash('sha256').update(Buffer.from(events.flatMap(
    ([frame, reg, value]) => [frame & 255, frame >> 8, reg, value]))).digest('hex');
  const open = () => {
    const k = boot('game', 'trace', {atTitle: true});
    k.m.dma = true;
    k.m.mouse.present = false;
    return k;
  };
  const same = (a, b) => {
    const at = Array.from({length: Math.max(a.length, b.length)}, (_, i) => i)
      .find(i => String(a[i]) !== String(b[i]));
    return at === undefined ? '' : ` first difference at write ${at}: original ${a[at]}, port ${b[at]}`;
  };

  // The stored stream is 13,150 writes of the writer range $1C70-$1EC6 (init, ticks, final clear).
  check(original.length === 13150 && sha(original.map(([frame, reg, value]) => [frame, reg, value])) === SURVEY_SHA,
    `title music: the reference trace is the survey's ${original.length} writes, SHA-256 ${sha(original).slice(0, 12)}`);

  {
    const {m, hooks, p: {symbols: s}} = open();
    let init, ticked = 0, stable = true;
    hooks.on('MUSICINIT', () => { init = m.frame; });
    const events = [];
    for (let f = 0; f < 4800 && (init === undefined || events.length < original.length ||
      m.frame - init < original.at(-1)[0] + 10); f++) {
      const frame = m.frame;
      if (!m.runFrame()) break;
      if (init === undefined) continue;
      for (let i = 0; i < m.sidLog.length; i += 3) events.push([frame - init, m.sidLog[i + 1], m.sidLog[i + 2]]);
      stable = stable && !m.ram[s.OVRUN] && !m.vicLog.some((reg, i) => {
        if (i % 4 !== 2 || ![0x20, 0x21].includes(reg)) return false;
        const [line, cycle] = m.vicLog.slice(i - 2, i);
        return cycle >= 16 && cycle <= 55 && ((line >= 50 && line <= 76) || (line >= 230 && line <= 245));
      });
      ticked++;
    }
    check(events.length === original.length && sha(events) === sha(original) && stable && m.ram[s.MUSTOP] === 255,
      `title music: all ${events.length} SID writes of the original tune (init, six frequency writes a tick, gates, ` +
      `final clear) at the original's frames, SHA-256 ${sha(events).slice(0, 12)}, 0 late splits/OVRUN.${same(original.map(e => e.join()), events.map(e => e.join()))}`);
  }

  // F5, F7 and Fire leave the title: the three controls off, the hum's burst, volume $1F ($18B4, $C38E).
  for (const input of ['F5', 'F7', 'Fire']) {
    const {m, p: {symbols: s}} = open(), a = m.ram;
    for (let f = 0; f < 100 && !(a[s.OVOWNER] === s.TITLEOWNER && a[s.TITLEARM]); f++) m.runFrame();
    for (let f = 0; f < 20; f++) m.runFrame();
    const playing = !a[s.MUSTOP];
    if (input === 'Fire') m.joy2 = 16;
    else m.setKey(0, input === 'F5' ? 6 : 3, true);
    const writes = [];
    for (let f = 0; f < 12 && !a[s.TITLEMENU]; f++) {
      m.runFrame();
      for (let i = 0; i < m.sidLog.length; i += 3) writes.push([m.sidLog[i + 1], m.sidLog[i + 2]]);
    }
    m.joy2 = 0;
    m.setKey(0, 6, false);
    m.setKey(0, 3, false);
    const hum = [[18, 0], [15, 8], [14, 0x68], [20, 0xa0], [19, 0x22], [18, 0x81], [24, 0x1f]];
    const tail = writes.slice(-10);
    check(playing && a[s.TITLEMENU] === 1 && tail.join() ===
      [[4, 0], [11, 0], [18, 0], ...hum].slice(-10).join() && !a[s.OVRUN],
    `title music: ${input} cancels the tune (controls off) and starts the engine hum with volume $1F`);
  }

  // Selector idle: no SID write at all (the hum sustains); the confirm brings a burst every sixth frame.
  {
    const {m, p: {symbols: s}} = open(), a = m.ram;
    for (let f = 0; f < 100 && !(a[s.OVOWNER] === s.TITLEOWNER && a[s.TITLEARM]); f++) m.runFrame();
    m.setKey(0, 6, true);
    for (let f = 0; f < 12 && !a[s.TITLEMENU]; f++) m.runFrame();
    m.setKey(0, 6, false);
    for (let f = 0; f < 12 && !a[s.TITLEARM]; f++) m.runFrame();
    let quiet = true;
    for (let f = 0; f < 60; f++) {
      m.runFrame();
      if (f === 20) m.joy2 = 1;
      if (f === 40) m.joy2 = 0;
      quiet &&= m.sidLog.length === 0;
    }
    check(quiet && a[s.ENGON] === 1, 'title selector: sustained hum, no SID write while the selection moves (as the original)');
  }
};
