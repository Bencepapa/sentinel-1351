// 6502 disassembler for the debugger (same table as mouse/tools/dis6502.py).
'use strict';

var SentinelDisasm = (function () {
  var T = '00 BRK imp;01 ORA izx;05 ORA zp;06 ASL zp;08 PHP imp;09 ORA imm;0A ASL acc;0D ORA abs;0E ASL abs;10 BPL rel;11 ORA izy;15 ORA zpx;16 ASL zpx;18 CLC imp;19 ORA aby;1D ORA abx;1E ASL abx;20 JSR abs;21 AND izx;24 BIT zp;25 AND zp;26 ROL zp;28 PLP imp;29 AND imm;2A ROL acc;2C BIT abs;2D AND abs;2E ROL abs;30 BMI rel;31 AND izy;35 AND zpx;36 ROL zpx;38 SEC imp;39 AND aby;3D AND abx;3E ROL abx;40 RTI imp;41 EOR izx;45 EOR zp;46 LSR zp;48 PHA imp;49 EOR imm;4A LSR acc;4C JMP abs;4D EOR abs;4E LSR abs;50 BVC rel;51 EOR izy;55 EOR zpx;56 LSR zpx;58 CLI imp;59 EOR aby;5D EOR abx;5E LSR abx;60 RTS imp;61 ADC izx;65 ADC zp;66 ROR zp;68 PLA imp;69 ADC imm;6A ROR acc;6C JMP ind;6D ADC abs;6E ROR abs;70 BVS rel;71 ADC izy;75 ADC zpx;76 ROR zpx;78 SEI imp;79 ADC aby;7D ADC abx;7E ROR abx;81 STA izx;84 STY zp;85 STA zp;86 STX zp;88 DEY imp;8A TXA imp;8C STY abs;8D STA abs;8E STX abs;90 BCC rel;91 STA izy;94 STY zpx;95 STA zpx;96 STX zpy;98 TYA imp;99 STA aby;9A TXS imp;9D STA abx;A0 LDY imm;A1 LDA izx;A2 LDX imm;A4 LDY zp;A5 LDA zp;A6 LDX zp;A8 TAY imp;A9 LDA imm;AA TAX imp;AC LDY abs;AD LDA abs;AE LDX abs;B0 BCS rel;B1 LDA izy;B4 LDY zpx;B5 LDA zpx;B6 LDX zpy;B8 CLV imp;B9 LDA aby;BA TSX imp;BC LDY abx;BD LDA abx;BE LDX aby;C0 CPY imm;C1 CMP izx;C4 CPY zp;C5 CMP zp;C6 DEC zp;C8 INY imp;C9 CMP imm;CA DEX imp;CC CPY abs;CD CMP abs;CE DEC abs;D0 BNE rel;D1 CMP izy;D5 CMP zpx;D6 DEC zpx;D8 CLD imp;D9 CMP aby;DD CMP abx;DE DEC abx;E0 CPX imm;E1 SBC izx;E4 CPX zp;E5 SBC zp;E6 INC zp;E8 INX imp;E9 SBC imm;EA NOP imp;EC CPX abs;ED SBC abs;EE INC abs;F0 BEQ rel;F1 SBC izy;F5 SBC zpx;F6 INC zpx;F8 SED imp;F9 SBC aby;FD SBC abx;FE INC abx';
  var OPS = {};
  T.split(';').forEach(function (e) { var p = e.split(' '); OPS[parseInt(p[0], 16)] = [p[1], p[2]]; });
  var LEN = { imp: 1, acc: 1, imm: 2, zp: 2, zpx: 2, zpy: 2, izx: 2, izy: 2, rel: 2, abs: 3, abx: 3, aby: 3, ind: 3 };

  function h2(v) { return ('0' + v.toString(16).toUpperCase()).slice(-2); }
  function h4(v) { return ('000' + v.toString(16).toUpperCase()).slice(-4); }

  // One instruction at 'pc'. peek(a) reads memory; label(a) names an address.
  // Returns {pc, len, bytes, text, target}.
  function one(peek, pc, label) {
    var op = peek(pc), d = OPS[op];
    if (!d) return { pc: pc, len: 1, bytes: [op], text: '.byte $' + h2(op), target: null };
    var m = d[0], a = d[1], n = LEN[a], b1 = peek((pc + 1) & 0xFFFF), b2 = peek((pc + 2) & 0xFFFF);
    var bytes = [op, b1, b2].slice(0, n), w = b1 | (b2 << 8), t = null, s;
    function name(v, wide) {
      var l = label ? label(v) : null;
      return l || '$' + (wide ? h4(v) : h2(v));
    }
    switch (a) {
      case 'imp': s = m; break;
      case 'acc': s = m + ' A'; break;
      case 'imm': s = m + ' #$' + h2(b1); break;
      case 'zp': s = m + ' ' + name(b1); t = b1; break;
      case 'zpx': s = m + ' ' + name(b1) + ',X'; t = b1; break;
      case 'zpy': s = m + ' ' + name(b1) + ',Y'; t = b1; break;
      case 'izx': s = m + ' (' + name(b1) + ',X)'; break;
      case 'izy': s = m + ' (' + name(b1) + '),Y'; break;
      case 'rel': t = (pc + 2 + (b1 > 127 ? b1 - 256 : b1)) & 0xFFFF; s = m + ' ' + name(t, true); break;
      case 'abs': s = m + ' ' + name(w, true); t = w; break;
      case 'abx': s = m + ' ' + name(w, true) + ',X'; t = w; break;
      case 'aby': s = m + ' ' + name(w, true) + ',Y'; t = w; break;
      case 'ind': s = m + ' (' + name(w, true) + ')'; t = w; break;
    }
    return { pc: pc, len: n, bytes: bytes, text: s, target: t };
  }

  // 'count' instructions starting at 'pc'.
  function range(peek, pc, count, label) {
    var out = [];
    for (var i = 0; i < count; i++) { var d = one(peek, pc, label); out.push(d); pc = (pc + d.len) & 0xFFFF; }
    return out;
  }

  // A start address about 'back' instructions before 'pc' that decodes into pc.
  function backFrom(peek, pc, back) {
    for (var s = Math.max(0, pc - back * 3); s < pc; s++) {
      var a = s, n = 0;
      while (a < pc && n < back * 3) { a += one(peek, a).len; n++; }
      if (a === pc && n <= back) return s;
    }
    return pc;
  }

  return { one: one, range: range, backFrom: backFrom, h2: h2, h4: h4 };
})();

if (typeof module !== 'undefined') module.exports = SentinelDisasm;
