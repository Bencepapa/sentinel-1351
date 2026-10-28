// 6502 / 8502 core: all documented opcodes, decimal mode, cycle counts with
// page-crossing penalties. Undocumented opcodes halt the CPU (cpu.jam).
// Memory goes through bus.read(addr) / bus.write(addr, value).
'use strict';

var CPU6502 = (function () {
  var C = 1, Z = 2, I = 4, D = 8, B = 16, U = 32, V = 64, N = 128;

  function CPU(bus) {
    this.bus = bus;
    this.a = 0; this.x = 0; this.y = 0;
    this.sp = 0xFF; this.pc = 0; this.p = U | I;
    this.cycles = 0;
    this.jam = null;
  }

  var P = CPU.prototype;

  P.rd = function (a) { return this.bus.read(a & 0xFFFF); };
  P.wr = function (a, v) { this.bus.write(a & 0xFFFF, v & 0xFF); };
  P.rd16 = function (a) { return this.rd(a) | (this.rd(a + 1) << 8); };
  // JMP (ind) page wrap bug
  P.rd16bug = function (a) { return this.rd(a) | (this.rd((a & 0xFF00) | ((a + 1) & 0xFF)) << 8); };
  P.push = function (v) { this.wr(0x100 | this.sp, v); this.sp = (this.sp - 1) & 0xFF; };
  P.pull = function () { this.sp = (this.sp + 1) & 0xFF; return this.rd(0x100 | this.sp); };
  P.nz = function (v) { this.p = (this.p & ~(N | Z)) | (v & N) | (v ? 0 : Z); return v; };

  // ---- addressing: each returns an effective address (and sets this.extra)
  P.imm = function () { return this.pc++; };
  P.zp = function () { return this.rd(this.pc++); };
  P.zpx = function () { return (this.rd(this.pc++) + this.x) & 0xFF; };
  P.zpy = function () { return (this.rd(this.pc++) + this.y) & 0xFF; };
  P.abs = function () { var a = this.rd16(this.pc); this.pc += 2; return a; };
  P.abx = function (pen) {
    var b = this.rd16(this.pc); this.pc += 2; var a = (b + this.x) & 0xFFFF;
    if (pen && ((a ^ b) & 0xFF00)) this.cycles++; return a;
  };
  P.aby = function (pen) {
    var b = this.rd16(this.pc); this.pc += 2; var a = (b + this.y) & 0xFFFF;
    if (pen && ((a ^ b) & 0xFF00)) this.cycles++; return a;
  };
  P.izx = function () {
    var z = (this.rd(this.pc++) + this.x) & 0xFF;
    return this.rd(z) | (this.rd((z + 1) & 0xFF) << 8);
  };
  P.izy = function (pen) {
    var z = this.rd(this.pc++);
    var b = this.rd(z) | (this.rd((z + 1) & 0xFF) << 8);
    var a = (b + this.y) & 0xFFFF;
    if (pen && ((a ^ b) & 0xFF00)) this.cycles++; return a;
  };

  // ---- ALU
  P.adc = function (m) {
    var a = this.a, c = this.p & C, r;
    if (this.p & D) {
      var lo = (a & 0x0F) + (m & 0x0F) + c;
      var hi = (a & 0xF0) + (m & 0xF0);
      if (lo > 9) { lo += 6; }
      if (lo > 0x0F) hi += 0x10;
      var zbin = ((a + m + c) & 0xFF) === 0;
      this.p &= ~(N | V | Z | C);
      if (zbin) this.p |= Z;
      if (hi & 0x80) this.p |= N;
      if (~(a ^ m) & (a ^ hi) & 0x80) this.p |= V;
      if (hi > 0x90) hi += 0x60;
      if (hi > 0xFF) this.p |= C;
      this.a = ((hi & 0xF0) | (lo & 0x0F)) & 0xFF;
      return;
    }
    r = a + m + c;
    this.p &= ~(C | V);
    if (r > 0xFF) this.p |= C;
    if (~(a ^ m) & (a ^ r) & 0x80) this.p |= V;
    this.a = this.nz(r & 0xFF);
  };
  P.sbc = function (m) {
    var a = this.a, c = this.p & C, r = a - m - (1 - c);
    var bin = r & 0xFF;
    this.p &= ~(C | V);
    if (r >= 0) this.p |= C;
    if ((a ^ m) & (a ^ bin) & 0x80) this.p |= V;
    this.nz(bin);
    if (this.p & D) {
      var lo = (a & 0x0F) - (m & 0x0F) - (1 - c);
      var hi = (a & 0xF0) - (m & 0xF0);
      if (lo & 0x10) { lo -= 6; hi -= 0x10; }
      if (hi & 0x100) hi -= 0x60;
      this.a = ((hi & 0xF0) | (lo & 0x0F)) & 0xFF;
    } else {
      this.a = bin;
    }
  };
  P.cmp = function (r, m) {
    var t = r - m;
    this.p = (this.p & ~C) | (t >= 0 ? C : 0);
    this.nz(t & 0xFF);
  };
  P.bit = function (m) {
    this.p = (this.p & ~(N | V | Z)) | (m & (N | V)) | ((this.a & m) ? 0 : Z);
  };
  P.asl = function (v) { this.p = (this.p & ~C) | ((v >> 7) & 1); return this.nz((v << 1) & 0xFF); };
  P.lsr = function (v) { this.p = (this.p & ~C) | (v & 1); return this.nz(v >> 1); };
  P.rol = function (v) { var c = this.p & C; this.p = (this.p & ~C) | ((v >> 7) & 1); return this.nz(((v << 1) | c) & 0xFF); };
  P.ror = function (v) { var c = this.p & C; this.p = (this.p & ~C) | (v & 1); return this.nz((v >> 1) | (c << 7)); };

  P.branch = function (cond) {
    var o = this.rd(this.pc++);
    if (cond) {
      if (o & 0x80) o -= 256;
      var t = (this.pc + o) & 0xFFFF;
      this.cycles += ((t ^ this.pc) & 0xFF00) ? 2 : 1;
      this.pc = t;
    }
  };

  // Read-modify-write. The real 6502 writes the old value back first; that
  // dummy write is left out so I/O registers with write side effects (VDC
  // data, SID) see one write per instruction.
  P.rmw = function (a, f) { var v = this.rd(a); this.wr(a, f.call(this, v)); };

  P.irq = function () {
    if (this.p & I) return;
    this.push(this.pc >> 8); this.push(this.pc & 0xFF);
    this.push((this.p & ~B) | U); this.p |= I;
    this.pc = this.rd16(0xFFFE); this.cycles += 7;
  };
  P.nmi = function () {
    this.push(this.pc >> 8); this.push(this.pc & 0xFF);
    this.push((this.p & ~B) | U); this.p |= I;
    this.pc = this.rd16(0xFFFA); this.cycles += 7;
  };

  // ---- execute one instruction; returns cycles used
  P.step = function () {
    var start = this.cycles, op = this.rd(this.pc), a, v;
    var at = this.pc;
    this.pc = (this.pc + 1) & 0xFFFF;
    switch (op) {
      // loads
      case 0xA9: this.a = this.nz(this.rd(this.imm())); this.cycles += 2; break;
      case 0xA5: this.a = this.nz(this.rd(this.zp())); this.cycles += 3; break;
      case 0xB5: this.a = this.nz(this.rd(this.zpx())); this.cycles += 4; break;
      case 0xAD: this.a = this.nz(this.rd(this.abs())); this.cycles += 4; break;
      case 0xBD: this.a = this.nz(this.rd(this.abx(1))); this.cycles += 4; break;
      case 0xB9: this.a = this.nz(this.rd(this.aby(1))); this.cycles += 4; break;
      case 0xA1: this.a = this.nz(this.rd(this.izx())); this.cycles += 6; break;
      case 0xB1: this.a = this.nz(this.rd(this.izy(1))); this.cycles += 5; break;
      case 0xA2: this.x = this.nz(this.rd(this.imm())); this.cycles += 2; break;
      case 0xA6: this.x = this.nz(this.rd(this.zp())); this.cycles += 3; break;
      case 0xB6: this.x = this.nz(this.rd(this.zpy())); this.cycles += 4; break;
      case 0xAE: this.x = this.nz(this.rd(this.abs())); this.cycles += 4; break;
      case 0xBE: this.x = this.nz(this.rd(this.aby(1))); this.cycles += 4; break;
      case 0xA0: this.y = this.nz(this.rd(this.imm())); this.cycles += 2; break;
      case 0xA4: this.y = this.nz(this.rd(this.zp())); this.cycles += 3; break;
      case 0xB4: this.y = this.nz(this.rd(this.zpx())); this.cycles += 4; break;
      case 0xAC: this.y = this.nz(this.rd(this.abs())); this.cycles += 4; break;
      case 0xBC: this.y = this.nz(this.rd(this.abx(1))); this.cycles += 4; break;
      // stores
      case 0x85: this.wr(this.zp(), this.a); this.cycles += 3; break;
      case 0x95: this.wr(this.zpx(), this.a); this.cycles += 4; break;
      case 0x8D: this.wr(this.abs(), this.a); this.cycles += 4; break;
      case 0x9D: this.wr(this.abx(0), this.a); this.cycles += 5; break;
      case 0x99: this.wr(this.aby(0), this.a); this.cycles += 5; break;
      case 0x81: this.wr(this.izx(), this.a); this.cycles += 6; break;
      case 0x91: this.wr(this.izy(0), this.a); this.cycles += 6; break;
      case 0x86: this.wr(this.zp(), this.x); this.cycles += 3; break;
      case 0x96: this.wr(this.zpy(), this.x); this.cycles += 4; break;
      case 0x8E: this.wr(this.abs(), this.x); this.cycles += 4; break;
      case 0x84: this.wr(this.zp(), this.y); this.cycles += 3; break;
      case 0x94: this.wr(this.zpx(), this.y); this.cycles += 4; break;
      case 0x8C: this.wr(this.abs(), this.y); this.cycles += 4; break;
      // transfers
      case 0xAA: this.x = this.nz(this.a); this.cycles += 2; break;
      case 0xA8: this.y = this.nz(this.a); this.cycles += 2; break;
      case 0x8A: this.a = this.nz(this.x); this.cycles += 2; break;
      case 0x98: this.a = this.nz(this.y); this.cycles += 2; break;
      case 0xBA: this.x = this.nz(this.sp); this.cycles += 2; break;
      case 0x9A: this.sp = this.x; this.cycles += 2; break;
      // stack
      case 0x48: this.push(this.a); this.cycles += 3; break;
      case 0x08: this.push(this.p | B | U); this.cycles += 3; break;
      case 0x68: this.a = this.nz(this.pull()); this.cycles += 4; break;
      case 0x28: this.p = (this.pull() & ~B) | U; this.cycles += 4; break;
      // logic / arithmetic (ORA AND EOR ADC CMP SBC share the pattern)
      case 0x09: case 0x05: case 0x15: case 0x0D: case 0x1D: case 0x19: case 0x01: case 0x11:
      case 0x29: case 0x25: case 0x35: case 0x2D: case 0x3D: case 0x39: case 0x21: case 0x31:
      case 0x49: case 0x45: case 0x55: case 0x4D: case 0x5D: case 0x59: case 0x41: case 0x51:
      case 0x69: case 0x65: case 0x75: case 0x6D: case 0x7D: case 0x79: case 0x61: case 0x71:
      case 0xC9: case 0xC5: case 0xD5: case 0xCD: case 0xDD: case 0xD9: case 0xC1: case 0xD1:
      case 0xE9: case 0xE5: case 0xF5: case 0xED: case 0xFD: case 0xF9: case 0xE1: case 0xF1:
        switch (op & 0x1F) {
          case 0x09: a = this.imm(); this.cycles += 2; break;
          case 0x05: a = this.zp(); this.cycles += 3; break;
          case 0x15: a = this.zpx(); this.cycles += 4; break;
          case 0x0D: a = this.abs(); this.cycles += 4; break;
          case 0x1D: a = this.abx(1); this.cycles += 4; break;
          case 0x19: a = this.aby(1); this.cycles += 4; break;
          case 0x01: a = this.izx(); this.cycles += 6; break;
          case 0x11: a = this.izy(1); this.cycles += 5; break;
        }
        v = this.rd(a);
        switch (op >> 5) {
          case 0: this.a = this.nz(this.a | v); break;
          case 1: this.a = this.nz(this.a & v); break;
          case 2: this.a = this.nz(this.a ^ v); break;
          case 3: this.adc(v); break;
          case 6: this.cmp(this.a, v); break;
          case 7: this.sbc(v); break;
        }
        break;
      case 0xE0: this.cmp(this.x, this.rd(this.imm())); this.cycles += 2; break;
      case 0xE4: this.cmp(this.x, this.rd(this.zp())); this.cycles += 3; break;
      case 0xEC: this.cmp(this.x, this.rd(this.abs())); this.cycles += 4; break;
      case 0xC0: this.cmp(this.y, this.rd(this.imm())); this.cycles += 2; break;
      case 0xC4: this.cmp(this.y, this.rd(this.zp())); this.cycles += 3; break;
      case 0xCC: this.cmp(this.y, this.rd(this.abs())); this.cycles += 4; break;
      case 0x24: this.bit(this.rd(this.zp())); this.cycles += 3; break;
      case 0x2C: this.bit(this.rd(this.abs())); this.cycles += 4; break;
      // inc / dec
      case 0xE8: this.x = this.nz((this.x + 1) & 0xFF); this.cycles += 2; break;
      case 0xC8: this.y = this.nz((this.y + 1) & 0xFF); this.cycles += 2; break;
      case 0xCA: this.x = this.nz((this.x - 1) & 0xFF); this.cycles += 2; break;
      case 0x88: this.y = this.nz((this.y - 1) & 0xFF); this.cycles += 2; break;
      case 0xE6: this.rmw(this.zp(), inc); this.cycles += 5; break;
      case 0xF6: this.rmw(this.zpx(), inc); this.cycles += 6; break;
      case 0xEE: this.rmw(this.abs(), inc); this.cycles += 6; break;
      case 0xFE: this.rmw(this.abx(0), inc); this.cycles += 7; break;
      case 0xC6: this.rmw(this.zp(), dec); this.cycles += 5; break;
      case 0xD6: this.rmw(this.zpx(), dec); this.cycles += 6; break;
      case 0xCE: this.rmw(this.abs(), dec); this.cycles += 6; break;
      case 0xDE: this.rmw(this.abx(0), dec); this.cycles += 7; break;
      // shifts
      case 0x0A: this.a = this.asl(this.a); this.cycles += 2; break;
      case 0x4A: this.a = this.lsr(this.a); this.cycles += 2; break;
      case 0x2A: this.a = this.rol(this.a); this.cycles += 2; break;
      case 0x6A: this.a = this.ror(this.a); this.cycles += 2; break;
      case 0x06: this.rmw(this.zp(), P.asl); this.cycles += 5; break;
      case 0x16: this.rmw(this.zpx(), P.asl); this.cycles += 6; break;
      case 0x0E: this.rmw(this.abs(), P.asl); this.cycles += 6; break;
      case 0x1E: this.rmw(this.abx(0), P.asl); this.cycles += 7; break;
      case 0x46: this.rmw(this.zp(), P.lsr); this.cycles += 5; break;
      case 0x56: this.rmw(this.zpx(), P.lsr); this.cycles += 6; break;
      case 0x4E: this.rmw(this.abs(), P.lsr); this.cycles += 6; break;
      case 0x5E: this.rmw(this.abx(0), P.lsr); this.cycles += 7; break;
      case 0x26: this.rmw(this.zp(), P.rol); this.cycles += 5; break;
      case 0x36: this.rmw(this.zpx(), P.rol); this.cycles += 6; break;
      case 0x2E: this.rmw(this.abs(), P.rol); this.cycles += 6; break;
      case 0x3E: this.rmw(this.abx(0), P.rol); this.cycles += 7; break;
      case 0x66: this.rmw(this.zp(), P.ror); this.cycles += 5; break;
      case 0x76: this.rmw(this.zpx(), P.ror); this.cycles += 6; break;
      case 0x6E: this.rmw(this.abs(), P.ror); this.cycles += 6; break;
      case 0x7E: this.rmw(this.abx(0), P.ror); this.cycles += 7; break;
      // jumps
      case 0x4C: this.pc = this.rd16(this.pc); this.cycles += 3; break;
      case 0x6C: this.pc = this.rd16bug(this.rd16(this.pc)); this.cycles += 5; break;
      case 0x20:
        a = this.rd16(this.pc); v = (this.pc + 1) & 0xFFFF;
        this.push(v >> 8); this.push(v & 0xFF); this.pc = a; this.cycles += 6; break;
      case 0x60: this.pc = ((this.pull() | (this.pull() << 8)) + 1) & 0xFFFF; this.cycles += 6; break;
      case 0x40:
        this.p = (this.pull() & ~B) | U;
        this.pc = this.pull() | (this.pull() << 8); this.cycles += 6; break;
      case 0x00:
        this.pc = (this.pc + 1) & 0xFFFF;
        this.push(this.pc >> 8); this.push(this.pc & 0xFF);
        this.push(this.p | B | U); this.p |= I;
        this.pc = this.rd16(0xFFFE); this.cycles += 7; break;
      // branches
      case 0x10: this.branch(!(this.p & N)); this.cycles += 2; break;
      case 0x30: this.branch(this.p & N); this.cycles += 2; break;
      case 0x50: this.branch(!(this.p & V)); this.cycles += 2; break;
      case 0x70: this.branch(this.p & V); this.cycles += 2; break;
      case 0x90: this.branch(!(this.p & C)); this.cycles += 2; break;
      case 0xB0: this.branch(this.p & C); this.cycles += 2; break;
      case 0xD0: this.branch(!(this.p & Z)); this.cycles += 2; break;
      case 0xF0: this.branch(this.p & Z); this.cycles += 2; break;
      // flags
      case 0x18: this.p &= ~C; this.cycles += 2; break;
      case 0x38: this.p |= C; this.cycles += 2; break;
      case 0x58: this.p &= ~I; this.cycles += 2; break;
      case 0x78: this.p |= I; this.cycles += 2; break;
      case 0xB8: this.p &= ~V; this.cycles += 2; break;
      case 0xD8: this.p &= ~D; this.cycles += 2; break;
      case 0xF8: this.p |= D; this.cycles += 2; break;
      case 0xEA: this.cycles += 2; break;
      default:
        this.pc = at;
        this.jam = 'illegal opcode $' + hex(op, 2) + ' at $' + hex(at, 4);
        this.cycles += 2;
    }
    return this.cycles - start;
  };

  function inc(v) { return this.nz((v + 1) & 0xFF); }
  function dec(v) { return this.nz((v - 1) & 0xFF); }
  function hex(v, n) { return ('000' + v.toString(16).toUpperCase()).slice(-n); }

  CPU.FLAGS = { C: C, Z: Z, I: I, D: D, B: B, U: U, V: V, N: N };
  CPU.hex = hex;
  return CPU;
})();

if (typeof module !== 'undefined') module.exports = CPU6502;
