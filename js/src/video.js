// Frame renderers: the VIC-IIe screen (40 columns) and the VDC screen
// (80 columns).
//
// The VIC screen is drawn line by line from the register state at each raster
// position: the machine logs every VIC register write and sprite pointer write
// with its line and cycle, so raster splits (text strip / bitmap / text strip,
// colour bars, sprites reused lower on the screen) come out as on the real chip.
// A write in the middle of a line takes effect from the matching pixel.
'use strict';

var SentinelVideo = (function () {
  var Font = (typeof SentinelFont !== 'undefined') ? SentinelFont : require('./font.js');

  // VIC-II palette (Pepto PAL)
  var VIC_PAL = [
    0x000000, 0xFFFFFF, 0x68372B, 0x70A4B2, 0x6F3D86, 0x588D43, 0x352879, 0xB8C76F,
    0x6F4F25, 0x433900, 0x9A6759, 0x444444, 0x6C6C6C, 0x9AD284, 0x6C5EB5, 0x959595,
  ];
  // VDC RGBI palette (attribute colour = R G B I)
  var VDC_PAL = [
    0x000000, 0x555555, 0x0000AA, 0x5555FF, 0x00AA00, 0x55FF55, 0x00AAAA, 0x55FFFF,
    0xAA0000, 0xFF5555, 0xAA00AA, 0xFF55FF, 0xAA5500, 0xFFFF55, 0xAAAAAA, 0xFFFFFF,
  ];

  // Canvas: 384 x 272 PAL picture. Canvas x 32 = sprite x 24 = left edge of the
  // 40-column window; canvas row 0 = raster line 15, so text row 0 (yscroll 3)
  // starts at raster 51 = canvas row 36.
  var VIC_W = 384, VIC_H = 272, LEFT = 32, FIRST_LINE = 15;
  var VDC_W = 640, VDC_H = 200;

  function rgba(pal) {
    var out = new Uint32Array(16);
    for (var i = 0; i < 16; i++) {
      var c = pal[i];
      out[i] = 0xFF000000 | ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF);
    }
    return out;
  }
  var VICC = rgba(VIC_PAL), VDCC = rgba(VDC_PAL);

  // ---- VIC-IIe ---------------------------------------------------------------

  // Canvas x where a write in cycle c of a line takes effect.
  function cycleX(c) { return c * 8 - 96; }

  // The C128's VIC sees the character ROM at VIC address $1000-$1FFF (found on
  // the real machine in banks 0 and 1; bank 2 as on the C64).
  function vicByte(m, bank, off) {
    if (bank !== 0xC000 && off >= 0x1000 && off < 0x2000) return Font.rom[off & 0x7FF];
    return m.ram[bank + off];
  }

  var line = new Uint32Array(VIC_W);     // one rendered line
  var fgl = new Uint8Array(VIC_W);       // foreground mask of that line (sprite priority)
  var cols = new Uint8Array(4);

  // Render raster line 'raster' with registers v and sprite pointers ptr.
  function renderLine(m, v, ptr, raster, bank) {
    var border = VICC[v[0x20] & 15];
    line.fill(border);
    fgl.fill(0);
    var den = v[0x11] & 0x10;
    var rsel = v[0x11] & 0x08, csel = v[0x16] & 0x08;
    var top = rsel ? 51 : 55, bottom = rsel ? 251 : 247;
    var inWindow = den && raster >= top && raster < bottom;
    var wl = csel ? LEFT : LEFT + 7, wr = csel ? LEFT + 320 : LEFT + 311;
    var screen = (v[0x18] >> 4) * 0x400;

    if (inWindow) {
      var bg0 = v[0x21] & 15;
      for (var i = wl; i < wr; i++) line[i] = VICC[bg0];
      var ys = v[0x11] & 7, xs = v[0x16] & 7;
      var y = raster - 48 - ys;
      if (y >= 0 && y < 200) drawGraphics(m, v, bank, screen, y, LEFT + xs, bg0);
    }
    drawSprites(m, v, ptr, bank, screen, raster);
    if (inWindow) {                       // the side borders cover the edge pixels
      for (var a = 0; a < wl; a++) line[a] = border;
      for (var b = wr; b < VIC_W; b++) line[b] = border;
    } else {
      line.fill(border);
    }
  }

  function drawGraphics(m, v, bank, screen, y, x0, bg0) {
    var bmm = v[0x11] & 0x20, mcm = v[0x16] & 0x10, ecm = v[0x11] & 0x40;
    var cy = y >> 3, ln = y & 7, x, b, col;
    var charBase = (v[0x18] & 0x0E) * 0x400, bmBase = (v[0x18] & 8) ? 0x2000 : 0;
    for (var cx = 0; cx < 40; cx++) {
      var i = cy * 40 + cx;
      var sc = vicByte(m, bank, screen + i);
      var cr = m.colorRam[i] & 15;
      var o = x0 + cx * 8;
      if (bmm) {
        b = m.ram[bank + bmBase + i * 8 + ln];
        if (mcm) {
          for (x = 0; x < 4; x++) {
            var pv = (b >> (6 - x * 2)) & 3;
            col = pv === 0 ? bg0 : pv === 1 ? sc >> 4 : pv === 2 ? sc & 15 : cr;
            put(o + x * 2, col, pv & 2); put(o + x * 2 + 1, col, pv & 2);
          }
        } else {
          for (x = 0; x < 8; x++) { var on = (b >> (7 - x)) & 1; put(o + x, on ? sc >> 4 : sc & 15, on); }
        }
      } else {
        var code = ecm ? sc & 63 : sc;
        b = vicByte(m, bank, charBase + code * 8 + ln);
        var bgc = ecm ? (v[0x21 + (sc >> 6)] & 15) : bg0;
        if (mcm && (cr & 8)) {
          for (x = 0; x < 4; x++) {
            var p2 = (b >> (6 - x * 2)) & 3;
            col = p2 === 0 ? bgc : p2 === 1 ? v[0x22] & 15 : p2 === 2 ? v[0x23] & 15 : cr & 7;
            put(o + x * 2, col, p2 & 2); put(o + x * 2 + 1, col, p2 & 2);
          }
        } else {
          for (x = 0; x < 8; x++) { var t = (b >> (7 - x)) & 1; put(o + x, t ? cr : bgc, t); }
        }
      }
    }
  }

  function put(x, col, isFg) {
    if (x >= VIC_W) return;
    line[x] = VICC[col];
    fgl[x] = isFg ? 1 : 0;
  }

  // Sprites visible on this raster line, from the registers of this line. The
  // shape row is fetched with the pointer of the current screen, as the VIC does.
  function drawSprites(m, v, ptr, bank, screen, raster) {
    if (!v[0x15]) return;
    var ptrBase = ((bank + screen) >> 10) * 8;
    for (var s = 7; s >= 0; s--) {
      if (!(v[0x15] & (1 << s))) continue;
      var sy = v[s * 2 + 1], ye = (v[0x17] >> s) & 1;
      var dy = (raster - sy) & 0xFF;          // wraps like the 8-bit compare
      var h = ye ? 42 : 21;
      if (dy >= h || raster > 300) continue;
      var row = ye ? dy >> 1 : dy;
      var sx = v[s * 2] | (((v[0x10] >> s) & 1) << 8);
      var data = bank + ptr[ptrBase + s] * 64 + row * 3;
      var bits = (m.ram[data] << 16) | (m.ram[data + 1] << 8) | m.ram[data + 2];
      if (!bits) continue;
      var mc = (v[0x1C] >> s) & 1, xe = (v[0x1D] >> s) & 1, behind = (v[0x1B] >> s) & 1;
      cols[1] = v[0x25] & 15; cols[2] = v[0x27 + s] & 15; cols[3] = v[0x26] & 15;
      var w = xe ? 2 : 1;
      var px0 = sx - 24 + LEFT;
      if (sx >= 0x1F8) px0 -= 0x1F8;            // x positions past the right edge wrap (PAL)
      for (var bx = 0; bx < 24; bx++) {
        var c = mc ? (bits >> (22 - (bx & ~1))) & 3 : ((bits >> (23 - bx)) & 1) << 1;
        if (!c) continue;
        for (var k = 0; k < w; k++) {
          var x = px0 + bx * w + k;
          if (x < 0 || x >= VIC_W) continue;
          if (behind && fgl[x]) continue;
          line[x] = VICC[cols[c]];
        }
      }
    }
  }

  var regs = new Uint8Array(0x40), ptrs = new Uint8Array(512);

  function renderVic(m, px) {            // px: Uint32Array(VIC_W * VIC_H)
    regs.set(m.vicStart);
    ptrs.set(m.ptrStart);
    var vl = m.vicLog, pl = m.ptrLog, vi = 0, pi = 0;
    var bank = m.vicBank();
    for (var row = 0; row < VIC_H; row++) {
      var raster = row + FIRST_LINE, o = row * VIC_W;
      // pointer writes up to the start of this line
      while (pi < pl.length && (pl[pi] < raster || (pl[pi] === raster && cycleX(pl[pi + 1]) <= 0))) {
        var a = pl[pi + 2]; ptrs[(a >> 10) * 8 + (a & 7)] = pl[pi + 3]; pi += 4;
      }
      // register writes before the visible part of the line
      while (vi < vl.length && (vl[vi] < raster || (vl[vi] === raster && cycleX(vl[vi + 1]) <= 0))) {
        regs[vl[vi + 2]] = vl[vi + 3]; vi += 4;
      }
      var x0 = 0;
      while (true) {
        renderLine(m, regs, ptrs, raster, bank);
        var x1 = VIC_W;
        if (vi < vl.length && vl[vi] === raster) x1 = Math.min(VIC_W, cycleX(vl[vi + 1]));
        for (var x = x0; x < x1; x++) px[o + x] = line[x];
        if (x1 >= VIC_W) break;
        // apply every write that lands at this pixel, then draw the rest of the line
        while (vi < vl.length && vl[vi] === raster && cycleX(vl[vi + 1]) <= x1) { regs[vl[vi + 2]] = vl[vi + 3]; vi += 4; }
        x0 = x1;
      }
    }
  }

  // ---- VDC -------------------------------------------------------------------

  function renderVdc(m, px, blinkOn) {   // px: Uint32Array(VDC_W * VDC_H)
    var r = m.vdcReg, ram = m.vdcRam;
    var cols = r[1] || 80, rows = Math.min(r[6] || 25, 25);
    var stride = cols + r[27];
    var disp = (r[12] << 8) | r[13];
    var attr = (r[20] << 8) | r[21];
    var charBase = (r[28] & 0xE0) << 8;
    var bgc = VDCC[r[26] & 15];
    var attrsOn = r[25] & 0x40;
    var fgDefault = (r[26] >> 4) & 15;
    var reverseAll = r[24] & 0x40;
    px.fill(bgc);
    for (var cy = 0; cy < rows; cy++) {
      for (var cx = 0; cx < Math.min(cols, 80); cx++) {
        var off = cy * stride + cx;
        var ch = ram[(disp + off) & 0xFFFF];
        var at = attrsOn ? ram[(attr + off) & 0xFFFF] : fgDefault;
        var set = (at & 0x80) ? 0x1000 : 0;
        var fgc = VDCC[at & 15];
        var rev = ((at >> 6) & 1) ^ (reverseAll ? 1 : 0);
        var hide = (at & 0x10) && !blinkOn;
        for (var line = 0; line < 8; line++) {
          var b = hide ? 0 : ram[(charBase + set + ch * 16 + line) & 0xFFFF];
          if ((at & 0x20) && line === 7) b = 0xFF;
          if (rev) b ^= 0xFF;
          var o = (cy * 8 + line) * VDC_W + cx * 8;
          for (var x = 0; x < 8; x++) px[o + x] = (b & (0x80 >> x)) ? fgc : bgc;
        }
      }
    }
  }

  return {
    VIC_W: VIC_W, VIC_H: VIC_H, VDC_W: VDC_W, VDC_H: VDC_H,
    renderVic: renderVic, renderVdc: renderVdc,
  };
})();

if (typeof module !== 'undefined') module.exports = SentinelVideo;
