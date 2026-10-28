// Frame renderers: the VIC-IIe screen (40 columns) and the VDC screen
// (80 columns). Both read the chips' registers and memory once per frame.
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

  var VIC_W = 384, VIC_H = 272, LEFT = 32, TOP = 36;
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

  var fg = new Uint8Array(320 * 200);   // foreground mask for sprite priority

  // The VIC sees the character ROM at $1000-$1FFF of banks 0 and 2.
  function vicByte(m, bank, off) {
    if ((bank === 0 || bank === 0x8000) && off >= 0x1000 && off < 0x2000) return Font.rom[off & 0x7FF];
    return m.ram[bank + off];
  }

  function renderVic(m, px) {           // px: Uint32Array(VIC_W * VIC_H)
    var v = m.vic, bank = m.vicBank();
    var border = VICC[v[0x20] & 15];
    px.fill(border);
    if (!(v[0x11] & 0x10)) return;      // display off
    var bmm = v[0x11] & 0x20, mcm = v[0x16] & 0x10, ecm = v[0x11] & 0x40;
    var screen = (v[0x18] >> 4) * 0x400;
    var bg0 = v[0x21] & 15;
    var x, y, cx, cy, line, b, i, col, base, o;
    fg.fill(0);

    for (cy = 0; cy < 25; cy++) {
      for (cx = 0; cx < 40; cx++) {
        i = cy * 40 + cx;
        var sc = vicByte(m, bank, screen + i);
        var cr = m.colorRam[i] & 15;
        for (line = 0; line < 8; line++) {
          y = cy * 8 + line;
          o = (TOP + y) * VIC_W + LEFT + cx * 8;
          var fo = y * 320 + cx * 8;
          if (bmm) {
            b = m.ram[bank + ((v[0x18] & 8) ? 0x2000 : 0) + i * 8 + line];
            if (mcm) {
              for (x = 0; x < 4; x++) {
                var pv = (b >> (6 - x * 2)) & 3;
                col = pv === 0 ? bg0 : pv === 1 ? sc >> 4 : pv === 2 ? sc & 15 : cr;
                px[o + x * 2] = px[o + x * 2 + 1] = VICC[col];
                if (pv & 2) fg[fo + x * 2] = fg[fo + x * 2 + 1] = 1;
              }
            } else {
              for (x = 0; x < 8; x++) {
                var on = (b >> (7 - x)) & 1;
                px[o + x] = VICC[on ? sc >> 4 : sc & 15];
                if (on) fg[fo + x] = 1;
              }
            }
          } else {
            base = (v[0x18] & 0x0E) * 0x400;
            var code = ecm ? sc & 63 : sc;
            b = vicByte(m, bank, base + code * 8 + line);
            var bgc = ecm ? (v[0x21 + (sc >> 6)] & 15) : bg0;
            if (mcm && (cr & 8)) {
              for (x = 0; x < 4; x++) {
                var p2 = (b >> (6 - x * 2)) & 3;
                col = p2 === 0 ? bgc : p2 === 1 ? v[0x22] & 15 : p2 === 2 ? v[0x23] & 15 : cr & 7;
                px[o + x * 2] = px[o + x * 2 + 1] = VICC[col];
                if (p2 & 2) fg[fo + x * 2] = fg[fo + x * 2 + 1] = 1;
              }
            } else {
              for (x = 0; x < 8; x++) {
                var t = (b >> (7 - x)) & 1;
                px[o + x] = VICC[t ? cr : bgc];
                if (t) fg[fo + x] = 1;
              }
            }
          }
        }
      }
    }
    renderSprites(m, px, bank, screen);
  }

  function renderSprites(m, px, bank, screen) {
    var v = m.vic;
    for (var s = 7; s >= 0; s--) {
      if (!(v[0x15] & (1 << s))) continue;
      var sx = v[s * 2] | ((v[0x10] >> s) & 1) << 8;
      var sy = v[s * 2 + 1];
      var data = bank + m.ram[bank + screen + 0x3F8 + s] * 64;
      var mc = v[0x1C] & (1 << s), xe = v[0x1D] & (1 << s), ye = v[0x17] & (1 << s);
      var behind = v[0x1B] & (1 << s);
      var cols = [0, v[0x25] & 15, v[0x27 + s] & 15, v[0x26] & 15];
      for (var row = 0; row < 21; row++) {
        for (var yy = 0; yy < (ye ? 2 : 1); yy++) {
          var py = sy - 50 + row * (ye ? 2 : 1) + yy + TOP;
          if (py < 0 || py >= VIC_H) continue;
          var bits = (m.ram[data + row * 3] << 16) | (m.ram[data + row * 3 + 1] << 8) | m.ram[data + row * 3 + 2];
          for (var bx = 0; bx < 24; bx++) {
            var c;
            if (mc) { c = (bits >> (22 - (bx & ~1))) & 3; } else { c = ((bits >> (23 - bx)) & 1) ? 2 : 0; }
            if (!c) continue;
            for (var xx = 0; xx < (xe ? 2 : 1); xx++) {
              var pxx = sx - 24 + bx * (xe ? 2 : 1) + xx + LEFT;
              if (pxx < 0 || pxx >= VIC_W) continue;
              var gx = pxx - LEFT, gy = py - TOP;
              if (behind && gx >= 0 && gx < 320 && gy >= 0 && gy < 200 && fg[gy * 320 + gx]) continue;
              px[py * VIC_W + pxx] = VICC[cols[c]];
            }
          }
        }
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
