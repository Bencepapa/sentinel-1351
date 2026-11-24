'use strict';

module.exports = function ({boot, check, snap}) {
  const {m, p: {symbols: s}} = boot('game', 'trace', {atTitle: true});
  const a = m.ram;
  m.dma = true;
  m.mouse.present = false;
  const until = (predicate, limit) => {
    for (let f = 0; f < limit && !predicate(); f++) if (!m.runFrame()) return false;
    return !!predicate();
  };
  const ready = until(() => a[s.OVOWNER] === s.TITLEOWNER && a[s.TITLEARM], 120);
  // The build gives the punctuation glyphs a font slot only when the scroller text uses them.
  const glyphs = [0x7a, 0x6c, ...Array.from({length: s.TITLEPUNCTSIZE / 8}, (_, i) => 0x1f + i)];
  const pixels = glyphs.map(code => Buffer.from(a.subarray(0x4000 + code * 8, 0x4008 + code * 8)));
  a.set([...glyphs, 0x40, 0x40, 0xff], s.TITLETEXT);
  a[s.TITLEPOS] = 0;
  const scrolled = until(() => a[s.TITLEPOS] === glyphs.length + 2, 104);
  check(ready && scrolled && pixels.every(glyph => glyph.some(Boolean)) &&
    new Set(pixels.map(glyph => glyph.toString('hex'))).size === glyphs.length &&
    Buffer.from(a.subarray(s.LRROW + 38 - glyphs.length, s.LRROW + 38)).equals(Buffer.from(glyphs)),
  'title charset: the period, dash and the used punctuation glyphs scroll through the live title font');
  if (scrolled) snap(m, 'game-title-punctuation');

  m.setKey(0, 6, true);
  const menu = until(() => a[s.TITLEMENU] === 1, 12);
  m.setKey(0, 6, false);
  until(() => a[s.TITLEARM], 12);
  m.joy2 = 16;
  m.runFrame();
  m.joy2 = 0;
  const briefing = until(() => a[s.INTROACTIVE], s.TITLECONFIRMFRAMES + 12);
  check(menu && briefing &&
    a.subarray(s.TITLEPUNCTFONT, s.TITLEPUNCTFONT + s.TITLEPUNCTSIZE).every(byte => byte === 0) && !a[s.OVRUN],
  'title charset: the borrowed font slots are blank again before the briefing');
};
