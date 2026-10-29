// Frame renderers: the VIC-II / VIC-IIe screen and the VDC screen (80 columns).
//
// The VIC screen is drawn line by line from the register state at each raster
// position: the machine logs every VIC register write and sprite pointer write
// with its line and cycle, so raster splits (text strip / bitmap / text strip,
// colour bars, sprites reused lower on the screen) come out as on the real chip.
// A write in the middle of a line takes effect from the matching pixel.
//
// Rendering is incremental: the machine asks for lines up to the current raster
// when the program reads the collision registers, when it pauses in the middle
// of a frame, and at the end of every frame. Sprite-sprite and sprite-background
// collisions are found while drawing, as the VIC does.
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

  // Canvas x where a write in cycle c of a line takes effect.
  function cycleX(c) { return c * 8 - 96; }

  // ---- VIC renderer, one per machine ------------------------------------------

  function Vic(m) {
    this.m = m;
    this.px = new Uint32Array(VIC_W * VIC_H);
    this.regs = new Uint8Array(0x40);
    this.ptrs = new Uint8Array(512);
    this.line = new Uint32Array(VIC_W);
    this.fg = new Uint8Array(VIC_W);      // foreground mask of the line (priority, collisions)
    this.spr = new Uint8Array(VIC_W);     // sprites that drew each pixel (collisions)
    this.cols = new Uint8Array(4);
    this.next = 0;                         // next raster line to draw
    this.vi = 0; this.pi = 0;              // positions in the machine's logs
  }

  var V = Vic.prototype;

  V.beginFrame = function () {
    this.regs.set(this.m.vicStart);
    this.ptrs.set(this.m.ptrStart);
    this.next = 0; this.vi = 0; this.pi = 0;
  };

  // Draw again from the start of the frame up to 'raster' (after load state).
  V.replay = function (raster) { this.beginFrame(); this.renderTo(raster); };

  // The C64's VIC sees the character ROM at VIC address $1000-$1FFF in banks 0
  // and 2; the C128's VIC-IIe, as found on the real machine, in banks 0-2.
  V.vicByte = function (bank, off) {
    if (off >= 0x1000 && off < 0x2000 && (this.m.model === 'c64' ? (bank === 0 || bank === 0x8000) : bank !== 0xC000)) {
      return Font.rom[off & 0x7FF];
    }
    return this.m.ram[bank + off];
  };

  // Draw every raster line before 'raster'.
  V.renderTo = function (raster) {
    var m = this.m, vl = m.vicLog, pl = m.ptrLog, regs = this.regs, px = this.px;
    raster = Math.min(raster, 312);
    var bank = m.vicBank();
    for (; this.next < raster; this.next++) {
      var r = this.next;
      while (this.pi < pl.length && (pl[this.pi] < r || (pl[this.pi] === r && cycleX(pl[this.pi + 1]) <= 0))) {
        var a = pl[this.pi + 2]; this.ptrs[(a >> 10) * 8 + (a & 7)] = pl[this.pi + 3]; this.pi += 4;
      }
      while (this.vi < vl.length && (vl[this.vi] < r || (vl[this.vi] === r && cycleX(vl[this.vi + 1]) <= 0))) {
        regs[vl[this.vi + 2]] = vl[this.vi + 3]; this.vi += 4;
      }
      var row = r - FIRST_LINE, visible = row >= 0 && row < VIC_H;
      var x0 = 0;
      while (true) {
        this.renderLine(regs, r, bank);
        var x1 = VIC_W;
        if (this.vi < vl.length && vl[this.vi] === r) x1 = Math.max(x0, Math.min(VIC_W, cycleX(vl[this.vi + 1])));
        if (visible) for (var x = x0; x < x1; x++) px[row * VIC_W + x] = this.line[x];
        if (x1 >= VIC_W) break;
        while (this.vi < vl.length && vl[this.vi] === r && cycleX(vl[this.vi + 1]) <= x1) {
          regs[vl[this.vi + 2]] = vl[this.vi + 3]; this.vi += 4;
        }
        x0 = x1;
      }
    }
  };

  V.renderLine = function (v, raster, bank) {
    var line = this.line, fg = this.fg;
    var border = VICC[v[0x20] & 15];
    line.fill(border);
    fg.fill(0);
    var den = v[0x11] & 0x10;
    var rsel = v[0x11] & 0x08, csel = v[0x16] & 0x08;
    var top = rsel ? 51 : 55, bottom = rsel ? 251 : 247;
    var inWindow = den && raster >= top && raster < bottom;
    var wl = csel ? LEFT : LEFT + 7, wr = csel ? LEFT + 320 : LEFT + 311;
    var screen = (v[0x18] >> 4) * 0x400;

    if (inWindow) {
      var bg0 = v[0x21] & 15;
      for (var i = wl; i < wr; i++) line[i] = VICC[bg0];
      var y = raster - 48 - (v[0x11] & 7);
      if (y >= 0 && y < 200) this.drawGraphics(v, bank, screen, y, LEFT + (v[0x16] & 7), bg0);
    }
    this.drawSprites(v, bank, screen, raster);
    if (inWindow) {
      for (var a = 0; a < wl; a++) line[a] = border;
      for (var b = wr; b < VIC_W; b++) line[b] = border;
    } else {
      line.fill(border);
    }
  };

  V.drawGraphics = function (v, bank, screen, y, x0, bg0) {
    var m = this.m, line = this.line, fg = this.fg;
    var bmm = v[0x11] & 0x20, mcm = v[0x16] & 0x10, ecm = v[0x11] & 0x40;
    var cy = y >> 3, ln = y & 7, x, b, col, o;
    var charBase = (v[0x18] & 0x0E) * 0x400, bmBase = (v[0x18] & 8) ? 0x2000 : 0;
    function put(x, c, f) { if (x < VIC_W) { line[x] = VICC[c]; fg[x] = f ? 1 : 0; } }
    for (var cx = 0; cx < 40; cx++) {
      var i = cy * 40 + cx;
      var sc = this.vicByte(bank, screen + i);
      var cr = m.colorRam[i] & 15;
      o = x0 + cx * 8;
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
        b = this.vicByte(bank, charBase + code * 8 + ln);
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
  };

  // Sprites on this raster line, from this line's registers. The shape row is
  // fetched with the pointer of the current screen, as the VIC does.
  V.drawSprites = function (v, bank, screen, raster) {
    if (!v[0x15]) return;
    var m = this.m, line = this.line, fg = this.fg, spr = this.spr, cols = this.cols;
    var ptrBase = ((bank + screen) >> 10) * 8;
    var any = false, ss = 0, sb = 0;
    for (var s = 7; s >= 0; s--) {
      if (!(v[0x15] & (1 << s))) continue;
      var sy = v[s * 2 + 1], ye = (v[0x17] >> s) & 1;
      var dy = (raster - sy) & 0xFF;          // wraps like the 8-bit compare
      if (dy >= (ye ? 42 : 21) || raster > 300) continue;
      var row = ye ? dy >> 1 : dy;
      var data = bank + this.ptrs[ptrBase + s] * 64 + row * 3;
      var bits = (m.ram[data] << 16) | (m.ram[data + 1] << 8) | m.ram[data + 2];
      if (!bits) continue;
      if (!any) { spr.fill(0); any = true; }
      var sx = v[s * 2] | (((v[0x10] >> s) & 1) << 8);
      var mc = (v[0x1C] >> s) & 1, xe = (v[0x1D] >> s) & 1, behind = (v[0x1B] >> s) & 1;
      cols[1] = v[0x25] & 15; cols[2] = v[0x27 + s] & 15; cols[3] = v[0x26] & 15;
      var w = xe ? 2 : 1;
      var px0 = sx - 24 + LEFT;
      if (sx >= 0x1F8) px0 -= 0x1F8;          // x positions past the right edge wrap (PAL)
      for (var bx = 0; bx < 24; bx++) {
        var c = mc ? (bits >> (22 - (bx & ~1))) & 3 : ((bits >> (23 - bx)) & 1) << 1;
        if (!c) continue;
        for (var k = 0; k < w; k++) {
          var x = px0 + bx * w + k;
          if (x < 0 || x >= VIC_W) continue;
          if (spr[x]) ss |= spr[x] | (1 << s);
          spr[x] |= 1 << s;
          if (fg[x]) { sb |= 1 << s; if (behind) continue; }
          line[x] = VICC[cols[c]];
        }
      }
    }
    if (ss) { if (!m.collSS) m.vicIrq |= 4; m.collSS |= ss; }
    if (sb) { if (!m.collSB) m.vicIrq |= 2; m.collSB |= sb; }
  };

  // Compatibility: copy the machine's last picture.
  function renderVic(m, px) { px.set(m.video.px); }

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
    Vic: Vic, renderVic: renderVic, renderVdc: renderVdc,
  };
})();

if (typeof module !== 'undefined') module.exports = SentinelVideo;
