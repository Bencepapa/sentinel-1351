// High-level C128 machine for the Sentinel C128 code.
//
// The 8502 code runs unchanged on a 6502 core. The chips around it are not
// emulated cycle by cycle; they are register files that JS reads once per
// frame (VIC-IIe bitmap/text/sprites, VDC text screen) or turns into WebAudio
// (SID). Routines can be hooked by label (see hooks.js) to trace them, or to
// replace them with JS ports that are verified against the original code.
//
// No ROMs are needed: the tests run with interrupts off, sync on $D012 and talk
// to the hardware directly. The VDC character set and the VIC character ROM are
// replaced by an original font (font.js).
'use strict';

var C128 = (function () {
  var CPU = (typeof CPU6502 !== 'undefined') ? CPU6502 : require('./cpu6502.js');

  var PAL_LINES = 312, PAL_LINE_CYCLES = 63;
  var FRAME_CYCLES = PAL_LINES * PAL_LINE_CYCLES;   // 19656 at 1 MHz
  var RETURN_TRAP = 0xFFF0;                         // RTS from START lands here

  function Machine() {
    var m = this;
    this.ram = new Uint8Array(0x10000);
    this.colorRam = new Uint8Array(0x400);
    this.vic = new Uint8Array(0x40);
    this.sid = new Uint8Array(0x20);
    this.vdcRam = new Uint8Array(0x10000);
    this.vdcReg = new Uint8Array(0x40);
    this.mmu = new Uint8Array(0x0C);
    this.cpu = new CPU({ read: function (a) { return m.read(a); },
                         write: function (a, v) { m.write(a, v); } });
    this.hooks = null;            // set by Hooks
    this.writeLog = null;         // addresses written while a port is verified
    this.sidLog = [];             // [cycleInFrame, reg, value] for audio
    this.frame = 0;
    this.frameStart = 0;
    this.stopped = null;          // reason the program stopped
    this.reset();
  }

  var P = Machine.prototype;

  P.reset = function () {
    this.ram.fill(0);
    this.colorRam.fill(14);
    this.vic.fill(0);
    this.sid.fill(0);
    this.vdcRam.fill(0);
    this.vdcReg.fill(0);
    this.mmu.fill(0);
    this.mmuCR = 0x00;            // after RUN from BASIC: ROMs + I/O
    // VIC as BASIC leaves it: text at $0400, light blue on blue
    this.vic[0x11] = 0x1B; this.vic[0x16] = 0xC8; this.vic[0x18] = 0x14;
    this.vic[0x20] = 13; this.vic[0x21] = 11;
    this.vic[0x30] = 0xFC;
    // CIA1: keyboard columns out, rows in. CIA2: VIC bank 0.
    this.cia1 = { pra: 0x7F, prb: 0xFF, ddra: 0xFF, ddrb: 0x00 };
    this.cia2 = { pra: 0x97, prb: 0xFF, ddra: 0x3F, ddrb: 0x00 };
    // VDC as the KERNAL sets it up: 80x25, screen $0000, attributes $0800,
    // character set $2000, 16 bytes per character.
    var r = this.vdcReg;
    r[0] = 126; r[1] = 80; r[2] = 102; r[4] = 39; r[6] = 25; r[9] = 7;
    r[12] = 0x00; r[13] = 0x00; r[20] = 0x08; r[21] = 0x00;
    r[22] = 0x78; r[23] = 0x08; r[25] = 0x47; r[26] = 0xF0; r[27] = 0; r[28] = 0x2F;
    this.vdcIndex = 0;
    if (typeof SentinelFont !== 'undefined') SentinelFont.loadVdc(this.vdcRam, 0x2000);
    this.vdcRam.fill(0x20, 0, 0x800);                 // blank screen
    this.vdcRam.fill(0x8D, 0x800, 0x1000);            // KERNAL default attribute
    // input
    this.keys = new Uint8Array(8);                     // pressed rows per column
    this.joy2 = 0;                                     // bits 0-4 active (1 = pressed)
    this.mouse = { present: true, x: 0, y: 0, left: false, right: false };
    this.noise = 0x7FFFF8;
    this.noisePhase = 0;
    this.sidLog.length = 0;
    this.stopped = null;
    this.cpu.jam = null;
  };

  // ---- loading -------------------------------------------------------------

  P.loadPrg = function (bytes) {
    var load = bytes[0] | (bytes[1] << 8);
    this.ram.set(bytes.subarray(2), load);
    return load;
  };

  // Start a program at its entry, as SYS from BASIC 7 would: RTS at the end
  // returns to a trap address that stops the machine.
  P.start = function (entry) {
    var c = this.cpu;
    c.sp = 0xFB; c.p = 0x24; c.a = c.x = c.y = 0;
    var ret = RETURN_TRAP - 1;
    c.push(ret >> 8); c.push(ret & 0xFF);
    c.pc = entry;
    this.frameStart = c.cycles;
    this.frame = 0;
    this.stopped = null;
  };

  // ---- timing --------------------------------------------------------------

  P.clockMHz = function () { return (this.vic[0x30] & 1) ? 2 : 1; };
  P.cycleInFrame = function () { return this.cpu.cycles - this.frameStart; };
  P.rasterLine = function () {
    var c = this.cycleInFrame();
    return Math.floor(c / (PAL_LINE_CYCLES * this.clockMHz())) % PAL_LINES;
  };

  // Run one PAL frame. Returns false once the program has stopped.
  P.runFrame = function () {
    if (this.stopped) return false;
    var c = this.cpu, hooks = this.hooks;
    var end = this.frameStart + FRAME_CYCLES * this.clockMHz();
    this.sidLog.length = 0;
    while (c.cycles < end) {
      if (c.pc === RETURN_TRAP) { this.stopped = 'returned to BASIC'; break; }
      if (hooks && hooks.at[c.pc]) { hooks.enter(c.pc); if (this.stopped) break; continue; }
      c.step();
      if (c.jam) { this.stopped = c.jam; break; }
    }
    this.frameStart = end;
    this.frame++;
    return !this.stopped;
  };

  // ---- memory map ------------------------------------------------------------

  P.ioVisible = function () { return (this.mmuCR & 1) === 0; };

  P.read = function (a) {
    if (a >= 0xD000 && a < 0xE000 && this.ioVisible()) return this.ioRead(a);
    if (a >= 0xFF00 && a <= 0xFF04) return a === 0xFF00 ? this.mmuCR : 0;
    return this.ram[a];
  };

  P.write = function (a, v) {
    if (this.writeLog) this.writeLog.push(a);
    if (a >= 0xD000 && a < 0xE000 && this.ioVisible()) { this.ioWrite(a, v); return; }
    if (a === 0xFF00) { this.mmuCR = v; return; }
    if (a > 0xFF00 && a <= 0xFF04) { this.mmuCR = this.mmu[a - 0xFF00]; return; }
    this.ram[a] = v;
  };

  P.ioRead = function (a) {
    if (a < 0xD400) return this.vicRead(a & 0x3F);
    if (a < 0xD500) return this.sidRead(a & 0x1F);
    if (a < 0xD600) return (a & 0xFF) === 0 ? this.mmuCR : this.mmu[(a & 0x0F) % 12];
    if (a < 0xD700) return (a & 1) ? this.vdcRead(this.vdcIndex) : 0x80 | 0x02;  // status: ready, version 2
    if (a < 0xD800) return 0xFF;
    if (a < 0xDC00) return this.colorRam[a & 0x3FF] & 0x0F;
    if (a < 0xDD00) return this.cia1Read(a & 0x0F);
    if (a < 0xDE00) return this.cia2Read(a & 0x0F);
    return 0xFF;
  };

  P.ioWrite = function (a, v) {
    if (a < 0xD400) { this.vic[a & 0x3F] = v; return; }
    if (a < 0xD500) { this.sidWrite(a & 0x1F, v); return; }
    if (a < 0xD600) { if ((a & 0xFF) === 0) this.mmuCR = v; else this.mmu[(a & 0x0F) % 12] = v; return; }
    if (a < 0xD700) { if (a & 1) this.vdcWrite(this.vdcIndex, v); else this.vdcIndex = v & 0x3F; return; }
    if (a < 0xD800) return;
    if (a < 0xDC00) { this.colorRam[a & 0x3FF] = v & 0x0F; return; }
    if (a < 0xDD00) { this.ciaWrite(this.cia1, a & 0x0F, v); return; }
    if (a < 0xDE00) { this.ciaWrite(this.cia2, a & 0x0F, v); return; }
  };

  // ---- VIC-IIe registers -------------------------------------------------

  P.vicRead = function (r) {
    var line;
    switch (r) {
      case 0x11: line = this.rasterLine(); return (this.vic[0x11] & 0x7F) | ((line & 0x100) >> 1);
      case 0x12: return this.rasterLine() & 0xFF;
      case 0x1E: case 0x1F: return 0;            // no collisions reported
      case 0x16: return this.vic[r] | 0xC0;
      case 0x18: return this.vic[r] | 0x01;
      case 0x19: case 0x1A: return this.vic[r] | 0xF0;
      case 0x2F: return this.vic[r] | 0xF8;
      case 0x30: return this.vic[r] | 0xFC;
    }
    if (r >= 0x20 && r <= 0x2E) return this.vic[r] | 0xF0;
    if (r > 0x30) return 0xFF;
    return this.vic[r];
  };

  // VIC bank from CIA2 port A bits 0-1 (inverted)
  P.vicBank = function () {
    var pa = (this.cia2.pra & this.cia2.ddra) | (~this.cia2.ddra & 0xFF);
    return (3 - (pa & 3)) * 0x4000;
  };

  // ---- CIA ---------------------------------------------------------------

  P.ciaWrite = function (cia, r, v) {
    switch (r) {
      case 0: cia.pra = v; break;
      case 1: cia.prb = v; break;
      case 2: cia.ddra = v; break;
      case 3: cia.ddrb = v; break;
    }
  };

  // Port 2 joystick lines (active low), with the 1351's buttons on fire/up.
  P.port2Lines = function () {
    var j = this.joy2;
    if (this.mouse.present) {
      if (this.mouse.left) j |= 0x10;
      if (this.mouse.right) j |= 0x01;
    }
    return ~j & 0x1F | 0xE0;
  };

  P.cia1Read = function (r) {
    var cia = this.cia1;
    switch (r) {
      case 0: {
        var out = (cia.pra & cia.ddra) | (~cia.ddra & 0xFF);
        return out & this.port2Lines();
      }
      case 1: {
        // keyboard: AND of the rows of every column driven low on port A
        var cols = ((cia.pra & cia.ddra) | (~cia.ddra & 0xFF)) & this.port2Lines();
        var rows = 0xFF;
        for (var c = 0; c < 8; c++) if (!(cols & (1 << c))) rows &= ~this.keys[c];
        return rows & 0xFF;
      }
      case 2: return cia.ddra;
      case 3: return cia.ddrb;
      case 4: return this.cpu.cycles & 0xFF;          // timer A low (free running)
      case 5: return (this.cpu.cycles >> 8) & 0xFF;
      case 0x0D: return 0;
    }
    return 0;
  };

  P.cia2Read = function (r) {
    var cia = this.cia2;
    if (r === 0) return (cia.pra & cia.ddra) | (~cia.ddra & 0xFF);
    if (r === 1) return 0xFF;
    if (r === 2) return cia.ddra;
    if (r === 3) return cia.ddrb;
    return 0;
  };

  // ---- SID ---------------------------------------------------------------

  P.sidWrite = function (r, v) {
    this.sid[r] = v;
    if (r < 0x19) this.sidLog.push(this.cycleInFrame(), r, v);
  };

  P.sidRead = function (r) {
    switch (r) {
      case 0x19: return this.potValue(0);
      case 0x1A: return this.potValue(1);
      case 0x1B: return this.osc3();
      case 0x1C: return 0;
    }
    return 0;
  };

  // 1351 in proportional mode: bits 6-1 carry the position, read on port 2
  // when CIA1 port A bits 7/6 select it. An empty port reads $FF.
  P.potValue = function (axis) {
    var sel = this.cia1.pra & 0xC0;
    if (!this.mouse.present || sel !== 0x80) return 0xFF;
    var v = axis === 0 ? this.mouse.x : this.mouse.y;
    return (v << 1) & 0x7E;
  };

  // Voice 3 oscillator output. Only the noise waveform matters here (the
  // tests use it as a random source), so it is the SID's 23-bit LFSR clocked
  // by the voice 3 accumulator.
  P.osc3 = function () {
    var now = this.cpu.cycles;
    var freq = this.sid[0x0E] | (this.sid[0x0F] << 8);
    var elapsed = now - (this.osc3Time || 0);
    this.osc3Time = now;
    var phase = this.noisePhase + freq * elapsed;
    var clocks = Math.floor(phase / 0x80000);          // bit 19 rising edges
    this.noisePhase = phase % 0x80000;
    clocks = Math.min(clocks, 64);
    var n = this.noise;
    for (var i = 0; i < clocks; i++) {
      var bit = ((n >> 22) ^ (n >> 17)) & 1;
      n = ((n << 1) | bit) & 0x7FFFFF;
    }
    this.noise = n;
    if ((this.sid[0x12] & 0x80) === 0) return 0;
    return ((n >> 15) & 0x80) | ((n >> 14) & 0x40) | ((n >> 11) & 0x20) | ((n >> 9) & 0x10) |
           ((n >> 8) & 0x08) | ((n >> 5) & 0x04) | ((n >> 3) & 0x02) | ((n >> 2) & 0x01);
  };

  // ---- VDC (8563) ----------------------------------------------------------

  P.vdcAddr = function () { return ((this.vdcReg[18] << 8) | this.vdcReg[19]) & 0xFFFF; };
  P.vdcSetAddr = function (a) { this.vdcReg[18] = (a >> 8) & 0xFF; this.vdcReg[19] = a & 0xFF; };

  P.vdcWrite = function (r, v) {
    var reg = this.vdcReg, i, n, a;
    reg[r] = v;
    if (r === 31) {
      a = this.vdcAddr();
      this.vdcRam[a] = v;
      this.vdcSetAddr(a + 1);
    } else if (r === 30) {
      // word count: N more writes (fill with R31) or copies (R24 bit 7)
      n = v === 0 ? 256 : v;
      a = this.vdcAddr();
      if (reg[24] & 0x80) {
        var src = (reg[32] << 8) | reg[33];
        for (i = 0; i < n; i++) this.vdcRam[(a + i) & 0xFFFF] = this.vdcRam[(src + i) & 0xFFFF];
        src += n; reg[32] = (src >> 8) & 0xFF; reg[33] = src & 0xFF;
      } else {
        for (i = 0; i < n; i++) this.vdcRam[(a + i) & 0xFFFF] = reg[31];
      }
      this.vdcSetAddr(a + n);
    }
  };

  P.vdcRead = function (r) {
    if (r === 31) {
      var a = this.vdcAddr(), v = this.vdcRam[a];
      this.vdcSetAddr(a + 1);
      return v;
    }
    return this.vdcReg[r];
  };

  // ---- input ---------------------------------------------------------------

  P.setKey = function (col, row, down) {
    if (down) this.keys[col] |= (1 << row); else this.keys[col] &= ~(1 << row);
  };

  // Mouse motion in 1351 counts (Y up is positive, as on the real mouse).
  P.moveMouse = function (dx, dy) {
    this.mouse.x = (this.mouse.x + dx) & 0x3F;
    this.mouse.y = (this.mouse.y + dy) & 0x3F;
  };

  Machine.FRAME_CYCLES = FRAME_CYCLES;
  Machine.RETURN_TRAP = RETURN_TRAP;
  return Machine;
})();

if (typeof module !== 'undefined') module.exports = C128;
