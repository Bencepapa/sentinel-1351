// JS ports of 8502 routines, written to be checked against the originals in
// verify mode (hooks.js). Each port reproduces the routine's visible results:
// the registers A/X/Y on return and every byte it writes.
'use strict';

var SentinelNative = (function () {

  // PIXADDR: PTR = bitmap address of multicolor pixel POSX/POSY, X = POSX & 3, Y = 0
  function pixaddr(c) {
    var ptr = c.sym('PTR');
    var y = c.rd(c.sym('POSY')), x = c.rd(c.sym('POSX'));
    var lo = c.rd(c.sym('YLO') + y);
    var hi = (c.rd(c.sym('YHI') + y) + 0x60) & 0xFF;
    var col = x >> 2;
    var sum = lo + c.rd(c.sym('XLO') + col);
    lo = sum & 0xFF;
    hi = (hi + c.rd(c.sym('XHI') + col) + (sum >> 8)) & 0xFF;
    c.wr(ptr, lo); c.wr(ptr + 1, hi);
    c.y = 0; c.x = x & 3; c.a = x & 3;
    return (hi << 8) | lo;
  }

  // Sentinel's protected multicolor plot ($EF53): pixel value 2 is kept,
  // anything else becomes value 3.
  function plotpix(c) {
    var addr = pixaddr(c), x = c.x;
    var b = c.rd(addr), mask3 = c.rd(c.sym('MASK3') + x), mask2 = c.rd(c.sym('MASK2') + x);
    if ((b & mask3) === mask2) { c.a = b & mask3; c.cycles = 70; return; }
    c.a = (b & c.rd(c.sym('CLEARM') + x)) | mask3;
    c.wr(addr, c.a);
    c.cycles = 80;
  }

  // The matching erase ($EEE6): clears the pixel unless it is value 2.
  function erasepix(c) {
    var addr = pixaddr(c), x = c.x;
    var b = c.rd(addr), mask3 = c.rd(c.sym('MASK3') + x), mask2 = c.rd(c.sym('MASK2') + x);
    if ((b & mask3) === mask2) { c.a = b & mask3; c.cycles = 70; return; }
    c.a = b & c.rd(c.sym('CLEARM') + x);
    c.wr(addr, c.a);
    c.cycles = 78;
  }

  // 1351 delta: A = new pot, Y = old pot. Returns A = signed delta (7-bit
  // difference halved, +-1 jitter ignored), Y = the value to keep as "old".
  function movchk(c) {
    var old = c.y, cur = c.a;
    c.wr(c.sym('OLDV'), old);
    var t = ((cur - old) << 1) & 0xFF;     // ASL
    t = (t >> 1) | (t & 0x80);             // CMP #$80 / ROR: sign extend
    if (t !== 0xFF) {
      t = (t >> 1) | (t & 0x80);
      if (t !== 0) { c.a = t; c.y = cur; c.cycles = 30; return; }
    }
    c.a = 0; c.y = old; c.cycles = 30;
  }

  var PORTS = { PLOTPIX: plotpix, ERASEPIX: erasepix, MOVCHK: movchk };

  return {
    PORTS: PORTS,
    // Install every port the program has a label for.
    install: function (hooks, mode) {
      var names = [];
      for (var n in PORTS) if (hooks.symbols[n] !== undefined) { hooks.port(n, PORTS[n], mode); names.push(n); }
      return names;
    },
  };
})();

if (typeof module !== 'undefined') module.exports = SentinelNative;
