'use strict';

// The confirm's welcome ribbon and the Starfleet briefing, frame by frame against the original
// C64 game (patched PRG, DMA from frame 250): ribbon text, ink and fine scroll, every SID write
// from the confirm to the bar's closing, the bar's raster steps, the typed message and its
// colours, HUD and sprite registers. Frames are counted from the accepted confirm (the
// original's $8683 and the port's Fire press); a frame of tolerance covers the port's polling.
module.exports = function ({boot, check, snap}) {
  const until = (m, predicate, limit) => {
    for (let f = 0; f < limit && !predicate(); f++) if (!m.runFrame()) return false;
    return !!predicate();
  };
  const fineOf = m => {
    let value = -1;
    for (let i = 0; i < m.vicLog.length; i += 4) {
      if (m.vicLog[i + 2] === 0x16 && m.vicLog[i] >= 225 && m.vicLog[i] <= 240) value = m.vicLog[i + 3] & 15;
    }
    return value;
  };
  const splitOf = m => {          // the line where the view's bitmap begins (D021 := black)
    for (let i = 0; i < m.vicLog.length; i += 4) {
      if (m.vicLog[i] >= 74 && m.vicLog[i] <= 126 && m.vicLog[i + 2] === 0x21 && m.vicLog[i + 3] === 0) return m.vicLog[i];
    }
    return -1;
  };
  // The mode and colour writes of the HUD, the view split, the ribbon and the borders ($D011, $D016 split
  // values, $D020, $D021) as a sorted list per frame. The C64's extra bitmap strip at lines 226-231 and its
  // $D018 screen address are left out; $D016's ribbon value is checked on its own.
  const registers = (m, rel) => {
    const out = [];
    for (let i = 0; i < m.vicLog.length; i += 4) {
      const line = m.vicLog[i], reg = m.vicLog[i + 2], value = m.vicLog[i + 3];
      if (![0x11, 0x16, 0x20, 0x21].includes(reg) || (line >= 226 && line <= 231) || (rel < 505 && line > 80 && line < 225)) continue;
      if (reg === 0x16 && line >= 225) continue;
      out.push(reg.toString(16) + '=' + value.toString(16));
    }
    return out.sort().join(' ');
  };
  // Absolute cycle (line * 63 + cycle) of the ribbon strip's writes: $D016 (the fine value, not the reset to 8),
  // $D020/$D021 to $0B, from the log of one frame.
  const strip = m => {
    const out = {};
    for (let i = 0; i < m.vicLog.length; i += 4) {
      const line = m.vicLog[i], at = line * 63 + m.vicLog[i + 1], reg = m.vicLog[i + 2], value = m.vicLog[i + 3];
      if (line < 229 || line > 236) continue;
      if (reg === 0x16 && value !== 8 && value !== 0x18) out.fine = at;
      if (reg === 0x20 && value === 0x0b) out.border = at;
      if (reg === 0x21 && value === 0x0b) out.background = at;
    }
    return out;
  };
  // The ribbon strip as drawn by the machine's own renderer: pixel lines 236, 238 and 240, columns 40-343,
  // 0 = background. (The renderer reads the screen matrix when it draws, so this is what the page shows.)
  const WIDTH = require('../src/video.js').VIC_W;
  const ribbonPixels = m => [236, 238, 240].map(line => Array.from({length: 304}, (_, x) =>
    m.video.px[(line - 15) * WIDTH + 40 + x] === m.video.px[(line - 15) * WIDTH + 30] ? 0 : 1).join('')).join('|');
  const left = signature => signature.split('|')[1].indexOf('1');
  const text = (a, base, from, to) => Buffer.from(a.subarray(base + from, base + to)).toString('latin1');
  const ink = (m, from, to) => Array.from(m.colorRam.subarray(from, to)).join();
  const spriteState = m => {      // sprite registers at line 200 and D015 over the lines 195-229
    const regs = new Map([[0x15, 0], [0x1b, 0], [0x10, 0]]);
    let enable = 0;
    const lines = [];
    for (let i = 0; i < m.vicLog.length; i += 4) {
      const line = m.vicLog[i], reg = m.vicLog[i + 2], value = m.vicLog[i + 3];
      if (line <= 200 && (reg <= 0x0f || reg === 0x10 || reg === 0x27 || reg === 0x2a)) regs.set(reg, value);
      if (reg === 0x15) { if (line < 205) enable = value; else if (line < 229) lines.push(value); }
    }
    return {x: [regs.get(0), regs.get(6)], y: [regs.get(1), regs.get(7)], gunsOn: [enable, ...lines].some(v => (v & 9) === 9)};
  };

  // ---- the original ---------------------------------------------------------------------------
  const original = (() => {
    const {m, hooks} = boot('c64game', 'trace');
    let accepted;
    hooks.on(0x8683, () => { accepted = m.frame; });
    const ribbon = [], sid = [], splits = [], sprites = [], regs = [], strips = [], pixels = [];
    const rows = {};
    for (let f = 0; f < 1720; f++) {
      if (f === 250) m.dma = true;
      m.mouse.left = (f >= 300 && f < 308) || (f >= 400 && f < 408);
      if (!m.runFrame()) break;
      if (accepted === undefined) continue;
      const rel = f - accepted;
      ribbon[rel] = {row: text(m.ram, 0x5798, 0, 40), ink: m.colorRam[0x398], fine: fineOf(m)};
      splits[rel] = splitOf(m);
      regs[rel] = registers(m, rel);
      strips[rel] = strip(m);
      if (rel < 520) pixels[rel] = ribbonPixels(m);
      for (let i = 0; i < m.sidLog.length; i += 3) sid.push([rel, m.sidLog[i + 1], m.sidLog[i + 2]]);
      if ([300, 420, 520, 640, 700].includes(rel)) {
        sprites[rel] = spriteState(m);
        sprites[rel].hud = [text(m.ram, 0x5400, 0, 40), text(m.ram, 0x5428, 0, 40), text(m.ram, 0x5450, 0, 40)];
        sprites[rel].hudInk = ink(m, 0, 120);
      }
      if ([520, 553, 700, 1000, 1014, 1016, 1016 + 40, 1016 + 80, 1250, 1255].includes(rel)) {
        rows[rel] = {text: text(m.ram, 0x5478, 0, 240), ink: ink(m, 0x078, 0x168)};
      }
    }
    return {ribbon, sid, splits, sprites, rows, regs, strips, pixels};
  })();

  // ---- the port --------------------------------------------------------------------------------
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
    const accepted = m.frame - 1;
    if (!hold) m.joy2 = 0;
    return {m, hooks, s, a, accepted, ready: title && menu && armed};
  };
  const late = m => m.vicLog.some((reg, i, log) => i % 4 === 2 && (reg === 32 || reg === 33) &&
    ((log[i - 2] >= 50 && log[i - 2] <= 76) || (log[i - 2] >= 230 && log[i - 2] <= 245)) && log[i - 1] >= 16 && log[i - 1] <= 55);
  const inMap = (a, s) => a[s.GENDONE] && a[s.MAPSHOWN] && !a[s.OVOWNER] && !a[s.INTROACTIVE];
  const near = (list, rel, predicate) => [rel - 1, rel, rel + 1].some(q => list[q] && predicate(list[q]));

  {
    const {m, s, a, accepted, ready} = start(false);
    const ribbon = [], sid = [], splits = [], sprites = [], rows = {}, regs = [], strips = [], pixels = [], beepFrames = new Set();
    let ok = true, overrun = false, intro = 0, lateAt, over;
    for (let f = 0; f < 1500 && over === undefined; f++) {
      const rel = m.frame - accepted;
      if (!m.runFrame()) break;
      overrun ||= !!a[s.OVRUN];
      if (rel >= 1 && a[s.INTROACTIVE] && !(late(m) === false)) { ok = false; lateAt ??= rel; }
      ribbon[rel] = {row: text(a, 0x4b98, 0, 40), ink: m.colorRam[0x398], fine: fineOf(m)};
      splits[rel] = splitOf(m);
      regs[rel] = registers(m, rel);
      strips[rel] = strip(m);
      if (rel < 520) pixels[rel] = ribbonPixels(m);
      for (let i = 0; i < m.sidLog.length; i += 3) {
        sid.push([rel, m.sidLog[i + 1], m.sidLog[i + 2]]);
        if (m.sidLog[i + 1] === 0x0b && m.sidLog[i + 2] === 0x41) beepFrames.add(rel);
      }
      if ([300, 420, 520, 640, 700].includes(rel)) {
        sprites[rel] = spriteState(m);
        sprites[rel].hud = [text(a, 0x4800, 0, 40), text(a, 0x4828, 0, 40), text(a, 0x4850, 0, 40)];
        sprites[rel].hudInk = ink(m, 0, 120);
      }
      if ([520, 553, 700, 1000, 1014, 1016, 1016 + 40, 1016 + 80, 1250, 1255].includes(rel)) {
        rows[rel] = {text: text(a, s.INTROROW, 0, 240), ink: ink(m, 0x078, 0x168)};
      }
      if (a[s.INTROACTIVE]) intro = rel;
      if (rel > 200 && !a[s.INTROACTIVE]) over = rel;
    }

    // The welcome ribbon: the row as it ends a frame (the VIC and the page fetch it for the strip in that
    // frame), its ink and this frame's fine scroll equal the original's frame for frame, through all 504 frames.
    let ribbonOK = true, firstBad = '';
    for (let rel = 6; rel < 504; rel++) {
      const shown = {row: ribbon[rel].row, ink: ribbon[rel].ink, fine: ribbon[rel].fine};
      const o = original.ribbon[rel];
      if (!(o.row === shown.row && o.ink === shown.ink && o.fine === shown.fine)) {
        ribbonOK = false;
        firstBad ||= ` first difference at frame ${rel}: ${JSON.stringify(shown)}`;
      }
    }
    const welcome = ribbon.some(r => r.row.includes('@WELCOME@ABOARD@CAPTAIN\x7f@STANDBY@FOR@MESSAGE@FROM@STARFLEET@COMMAND'.slice(0, 20))) ||
      ribbon.some(r => r.row.includes('WELCOME@ABOARD@CAPTAIN'));
    check(ready && ribbonOK && welcome,
      `title intro: the welcome ribbon (text, white/black ink flips, 7-5-3-1 fine scroll, light green end) matches the C64 for 504 frames.${firstBad}`);

    // The raster registers of every frame through the welcome and the briefing (the title loop to frame 155,
    // then the IRQ handlers): D011/D016/D020/D021 writes equal the original's, so the HUD frame, its side blocks
    // and the view's edge line stay intact when the first glyph leaves the left edge and when the ribbon ends.
    let registersOK = true, firstRegisters = '';
    for (let rel = 6; rel < 505; rel++) {
      if (rel >= 154 && rel <= 157) continue;
      if (!regs[rel] || !near(original.regs, rel, o => o === regs[rel])) {
        registersOK = false;
        firstRegisters ||= ` frame ${rel}: ${regs[rel]} / ${original.regs[rel]}`;
      }
    }
    check(registersOK, `title intro: HUD border/mode writes ($D011, $D016, $D020, $D021) match the C64 on every frame of the welcome (to the bar's opening).${firstRegisters}`);

    // Where the text is on screen, frame by frame (pixels as the renderer drew them): identical to the original's on
    // every frame 8-504, and never moving backwards: 2 pixels a frame to the left, no jump forward or back at the
    // cell steps (every 4th frame) - with and without the DMA model (the page runs without it).
    const same = (list, reference) => { let first = ''; for (let rel = 8; rel < 505; rel++) if (list[rel] !== reference[rel]) { first ||= ` first difference at frame ${rel}`; } return first; };
    const noDma = (() => {
      const {m, a, s: S, accepted: acc} = start(false);
      m.dma = false;
      const px = [];
      for (let f = 0; f < 520; f++) { if (!m.runFrame()) break; px[m.frame - 1 - acc] = ribbonPixels(m); }
      return px;
    })();
    const edges = pixels.map(left), jumps = [];
    for (let rel = 9; rel < 505; rel++) if (edges[rel] >= 0 && edges[rel - 1] >= 16 && edges[rel] > edges[rel - 1]) jumps.push(rel);
    const differences = same(pixels, original.pixels), differencesNoDma = same(noDma, original.pixels);
    check(!differences && !differencesNoDma && !jumps.length,
      `title intro: the ribbon text's on-screen position equals the C64's on every frame (pixels, DMA ${differences || 'ok'}, no DMA ${differencesNoDma || 'ok'}) and never moves backwards${jumps.length ? ' (back at ' + jumps.slice(0, 5) + ')' : ''}`);

    // The strip's write cycles are stable on every frame, also on ink-change and beep frames. The original writes
    // $D016 at line 234, cycle 5 (after the border/mode writes). The port writes it first, at the end of line 232
    // (cycle 50-62, or 0-11 of line 233): before cycle 16 of line 233, so that line never starts half shifted (the
    // x shake of a write near that cycle). Each write keeps the original's own spread (5 cycles) plus 3.
    const spread = (list, key) => { const v = list.slice(6, 504).map(x => x && x[key]).filter(Boolean); return [Math.min(...v), Math.max(...v), v.length]; };
    let stripOK = true, stripWhy = '';
    for (const key of ['fine', 'border', 'background']) {
      const [lo, hi, n] = spread(strips, key), [olo, ohi] = spread(original.strips, key);
      const good = n > 450 && hi - lo <= ohi - olo + 3 && Math.abs(lo - olo) <= 150 && (key !== 'fine' || (lo >= 232 * 63 + 50 && hi < 233 * 63 + 12));
      if (!good) { stripOK = false; stripWhy += ` ${key}: ${Math.floor(lo / 63)}:${lo % 63}-${Math.floor(hi / 63)}:${hi % 63} (C64 ${Math.floor(olo / 63)}:${olo % 63}-${Math.floor(ohi / 63)}:${ohi % 63})`; }
    }
    const beeps = [...beepFrames].filter(r => r >= 6 && r < 504), inkFlips = beeps.length;
    const onBeeps = beeps.every(r => strips[r] && strips[r].fine >= 232 * 63 + 50 && strips[r].fine < 233 * 63 + 12);
    check(stripOK && onBeeps && inkFlips >= 40, `title intro: the ribbon strip's $D016/$D020/$D021 write cycles are stable on all frames, including the ${inkFlips} ink-change and beep frames (fine value before cycle 16 of line 233, within the C64's spread).${stripWhy}`);

    // Every SID write from the confirm's second second to the bar's end: same registers and values in the
    // same order, each within a frame; the port's hand-off (noise voice) is not part of the intro.
    const mine = sid.filter(e => e[0] >= 25 && e[0] <= 1303 && !(e[0] >= 1304));
    const theirs = original.sid.filter(e => e[0] >= 25 && e[0] <= 1303);
    const firstDifference = Array.from({length: Math.max(mine.length, theirs.length)}, (_, i) => i).find(i => {
      const x = mine[i], y = theirs[i];
      return !x || !y || x[1] !== y[1] || x[2] !== y[2] || Math.abs(x[0] - y[0]) > 1;
    });
    check(firstDifference === undefined,
      `title intro: all ${theirs.length} SID writes (ribbon beeps, engine hum, 96 bar blips, 174 glyph clicks) match the C64 in order and frame` +
      (firstDifference === undefined ? '' : `; first difference at write ${firstDifference}: ${theirs[firstDifference]} / ${mine[firstDifference]}`));

    // The bar: one line a frame in both directions, the same lines as the original (the port writes its
    // colour change two lines earlier than the C64's bitmap handoff, which the original delays by two).
    const lines = splits.slice(500, 1302);
    const through = Array.from({length: 49}, (_, i) => 75 + i).filter(line => lines.includes(line)).length >= 44; // (the bad line 75: the first steps wait at 78)
    const down = lines.filter((line, i) => i && line < lines[i - 1]).length;
    const steps = lines.every((line, i) => !i || Math.abs(line - lines[i - 1]) <= 4 || line < 0 || lines[i - 1] < 0);
    const follows = splits.every((line, rel) => rel < 500 || rel > 1303 || near(original.splits, rel, o => Math.abs(o - line - 1) <= 4 || o < 0 || line < 0));
    check(through && steps && follows && Math.max(...lines) <= 124 && Math.max(...lines) >= 123 && Math.min(...lines.filter(l => l > 0)) <= 76 && down > 40,
      `title intro: the bar opens from line 75 to 123 and closes again one line a frame, as the original (within 4 lines and a frame)`);

    // The typed message: the original's 231 glyph codes and white ink; the last row flashes 15 / 1 every 40 frames.
    const typed = rows[1014] && original.rows[1014];
    check(typed && rows[1014].text.slice(0, 231) === original.rows[1014].text.slice(0, 231) &&
      rows[1014].ink === original.rows[1014].ink &&
      rows[1016].ink === original.rows[1016].ink && rows[1016 + 40].ink === original.rows[1016 + 40].ink &&
      rows[1016 + 80].ink === original.rows[1016 + 80].ink && rows[520].ink === original.rows[520].ink,
    'title intro: the briefing text (6 rows of the original, side rules, 231 glyphs) and all 240 ink cells match the C64, with the 40-frame 15/1 flash');
    check(rows[553].text.slice(0, 6) === original.rows[553].text.slice(0, 6) && rows[1000].text === original.rows[1000].text,
      'title intro: the typing progress at frames 553 and 1000 equals the C64 (a glyph every second frame)');

    // HUD and sprites during the welcome: the guns and the same sprite positions, the HUD rows and ink.
    const mask = row => row.slice(0, 22) + row.slice(26, 34) + row.slice(39); // energy and time digits move
    const spritesOK = [300, 420, 520, 640, 700].every(rel => {
      const x = sprites[rel], y = original.sprites[rel];
      return x && y && x.gunsOn && y.gunsOn && x.x.join() === y.x.join() && x.y.join() === y.y.join() &&
        x.hud[0] === y.hud[0] && mask(x.hud[1]) === mask(y.hud[1]) && x.hud[2] === y.hud[2] &&
        x.hudInk === y.hudInk;
    });
    check(spritesOK, 'title intro: the HUD rows and ink, and both guns (sprite 0 and 3: enabled over lines 205-229, same X/Y), match the C64 at 5 frames of the welcome');
    check(ok && !overrun && m.clockMHz() === 1, `title intro: 0 late splits and 0 OVRUN through the welcome and briefing (DMA)${lateAt === undefined ? '' : ', first late frame ' + lateAt}`);
    snap(m, 'game-intro-end');

    const map = until(m, () => inMap(a, s) && !a[s.WIPE], 80);
    check(over !== undefined && over - 1300 < 8 && map && !(m.vic[0x1a] & 1) && !a[s.OVRUN],
      `title intro: closes automatically at frame ${over} (the C64's 1301), hands off to the resident map, and leaves the raster IRQ off`);
    m.setKey(7, 5, true);
    m.runFrame();
    m.setKey(7, 5, false);
    check(until(m, () => !a[s.MAPSHOWN] && !a[s.WIPE], 80), 'title intro: the initial map closes into normal flight');
  }

  // No flash between the briefing and the map: the view clears under the running raster handlers (HUD intact)
  // and the screen is blank for one frame at most (the load and the first map frame), not the ~6 it was.
  {
    const {m, s, a} = start(false);
    const Video = require('../src/video.js');
    const px = new Uint32Array(Video.VIC_W * Video.VIC_H);
    const lit = () => { Video.renderVic(m, px); let n = 0; for (const c of px) if (c & 0xffffff) n++; return n; };
    until(m, () => a[s.INTROPHASE] >= 4 && a[s.INTROACTIVE], 2000);
    let blank = 0, run = 0, maxRun = 0, hudLoss = 0, after = 0;
    for (let f = 0; f < 120 && after < 20; f++) {
      if (!m.runFrame()) break;
      const n = lit();
      if (a[s.MAPSHOWN] && !a[s.INTROACTIVE]) after++;
      if (n < 3000) { blank++; run++; maxRun = Math.max(maxRun, run); } else run = 0;
      if (a[s.INTROACTIVE] && n < 9000) hudLoss++;
    }
    check(blank <= 1 && maxRun <= 1 && hudLoss === 0 && after >= 20,
      `title intro: briefing to map has ${blank} blank frame(s) (longest run ${maxRun}; was about 6) and the HUD stays up while the view clears (${hudLoss} bad frames)`);
  }

  // Screenshots of the three bar heights and the typing.
  {
    const {m, s, a, accepted, ready} = start(false);
    const seen = new Set();
    for (let f = 0; f < 1100; f++) {
      if (!m.runFrame()) break;
      const line = splitOf(m);
      for (const height of [0, 24, 48]) if (line === 75 + height && !seen.has(height) && a[s.INTROPHASE] <= 2) {
        seen.add(height);
        snap(m, 'game-intro-' + height);
      }
      if (a[s.INTROINDEX] === 75 && !seen.has('typing')) { seen.add('typing'); snap(m, 'game-intro-typing'); }
    }
    check(ready && seen.size === 4, `title intro: screenshots at the 0, 24 and 48-line bar and while typing (${[...seen]})`);
  }

  for (const key of ['Fire', 'Space']) {
    const {m, hooks, s, a, ready} = start(key === 'Fire');
    let musicAfterReset = false;
    until(m, () => a[s.INTROACTIVE], s.TITLECONFIRMFRAMES + 12);
    if (key === 'Fire') for (let f = 0; f < 20; f++) m.runFrame();
    const held = a[s.INTROACTIVE] && (key !== 'Fire' || !a[s.INTROARM]);
    m.joy2 = 0;
    until(m, () => a[s.INTROARM], 12);
    if (key === 'Space') until(m, () => a[s.INTROPHASE] === 2, 700);
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
      a[s.INTROPHASE] === 0 && !a[s.OVRUN],
    'title intro: F7 reset rearms the title cue and a new selection starts the welcome again');
  }
};
