// High-level C64 / C128 machine for the Sentinel code.
//
// The 6502/8502 code runs unchanged on a 6502 core. The chips around it are
// register files: the VIC is drawn line by line from logged register writes
// (video.js), the SID is replayed in an AudioWorklet (audio.js), the VDC keeps
// its own RAM. Two models:
//
//   c128  native C128 mode as the tests use it: MMU configuration register at
//         $FF00/$D500, VDC at $D600, $D030 2 MHz bit
//   c64   C64 memory map from the processor port $00/$01, used by the full
//         patched game (Sentinel-1351_v8.prg)
//
// No ROMs: the programs bank them out or never call them. ROM areas read as RAM,
// the character ROM is an original font (font.js).
//
// Debugging lives here too, because it has to sit in the instruction loop:
// PC breakpoints, write watchpoints, frozen addresses, instruction / frame
// stepping that can stop in the middle of a frame, and save / load state.
'use strict';

var C128 = (function () {
  var CPU = (typeof CPU6502 !== 'undefined') ? CPU6502 : require('./cpu6502.js');
  var Video = (typeof SentinelVideo !== 'undefined') ? SentinelVideo : require('./video.js');
  var Font = (typeof SentinelFont !== 'undefined') ? SentinelFont : require('./font.js');

  var PAL_LINES = 312, PAL_LINE_CYCLES = 63;
  var FRAME_CYCLES = PAL_LINES * PAL_LINE_CYCLES;   // 19656 at 1 MHz
  var RETURN_TRAP = 0xFFF0;                         // RTS from START lands here (C128 tests)

  function Machine(model) {
    var m = this;
    this.model = model === 'c64' ? 'c64' : 'c128';
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
    this.vicLog = [];             // [line, cycleInLine, reg, value]: VIC writes this frame
    this.ptrLog = [];             // [line, cycleInLine, addr, value]: sprite pointer writes
    this.vicStart = new Uint8Array(0x40);   // VIC registers when the frame began
    this.ptrStart = new Uint8Array(512);    // sprite pointers of every 1K screen then
    // debugging
    this.bpAt = new Uint8Array(0x10000);    // PC breakpoints
    this.wpAt = new Uint8Array(0x10000);    // write watchpoints
    this.frozenAt = new Uint8Array(0x10000);
    this.frozen = {};                        // addr -> value
    this.watchHit = null;
    this.breakInfo = null;                   // why the last run() stopped early
    this.skipBreakAt = -1;
    this.video = new Video.Vic(this);
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
    this.mmuCR = 0x00;            // C128 after RUN from BASIC: ROMs + I/O
    this.port0 = 0x2F;            // C64 processor port: DDR, data
    this.port1 = 0x37;
    // VIC as BASIC leaves it: text at $0400
    this.vic[0x11] = 0x1B; this.vic[0x16] = 0xC8; this.vic[0x18] = 0x14;
    this.vic[0x20] = 14; this.vic[0x21] = 6;
    this.vic[0x30] = 0xFC;
    this.vicIrq = 0;              // latched interrupt bits of $D019
    this.collSS = 0; this.collSB = 0;
    // CIA1: keyboard columns out, rows in. CIA2: VIC bank 0.
    this.cia1 = { pra: 0x7F, prb: 0xFF, ddra: 0xFF, ddrb: 0x00, icrMask: 0 };
    this.cia2 = { pra: 0x97, prb: 0xFF, ddra: 0x3F, ddrb: 0x00, icrMask: 0 };
    // VDC as the KERNAL sets it up: 80x25, screen $0000, attributes $0800,
    // character set $2000, 16 bytes per character.
    var r = this.vdcReg;
    r[0] = 126; r[1] = 80; r[2] = 102; r[4] = 39; r[6] = 25; r[9] = 7;
    r[12] = 0x00; r[13] = 0x00; r[20] = 0x08; r[21] = 0x00;
    r[22] = 0x78; r[23] = 0x08; r[25] = 0x47; r[26] = 0xF0; r[27] = 0; r[28] = 0x2F;
    this.vdcIndex = 0;
    Font.loadVdc(this.vdcRam, 0x2000);
    this.vdcRam.fill(0x20, 0, 0x800);                 // blank screen
    this.vdcRam.fill(0x8D, 0x800, 0x1000);            // KERNAL default attribute
    // input
    this.keys = new Uint8Array(8);                     // pressed rows per column
    this.joy2 = 0;                                     // bits 0-4 active (1 = pressed)
    this.mouse = { present: true, x: 0, y: 0, left: false, right: false };
    this.noise = 0x7FFFF8;
    this.noisePhase = 0;
    this.osc3Time = 0;
    this.sidLog.length = 0;
    this.stopped = null;
    this.romReads = 0;
    this.cpu.jam = null;
    this.cpu.cycles = 0;
    this.frame = 0;
    this.frameStart = 0;
    this.vCycle = 0;
    this.lastCpu = 0;
    this.frameOpen = false;
    this.lastLine = 0;
  };

  // ---- loading -------------------------------------------------------------

  P.loadPrg = function (bytes) {
    var load = bytes[0] | (bytes[1] << 8);
    this.ram.set(bytes.subarray(2), load);
    return load;
  };

  // Start a program at its entry, as SYS from BASIC would: RTS at the end
  // returns to a trap address that stops the machine.
  P.start = function (entry) {
    var c = this.cpu;
    c.sp = 0xFB; c.p = 0x24; c.a = c.x = c.y = 0;
    var ret = RETURN_TRAP - 1;
    c.push(ret >> 8); c.push(ret & 0xFF);
    c.pc = entry;
    this.frameStart = c.cycles;
    this.vCycle = 0;
    this.lastCpu = c.cycles;
    this.frame = 0;
    this.frameOpen = false;
    this.stopped = null;
  };

  // ---- timing --------------------------------------------------------------

  P.clockMHz = function () { return (this.model === 'c128' && (this.vic[0x30] & 1)) ? 2 : 1; };
  // Cycles since the frame started, counted at 1 MHz: in the C128's 2 MHz mode
  // ($D030 bit 0) the processor runs two cycles per raster cycle. vCycle holds
  // the raster time up to the last instruction, lastCpu the processor's count then.
  P.cycleInFrame = function () {
    return this.vCycle + (this.cpu.cycles - this.lastCpu) / this.clockMHz();
  };
  P.syncClock = function () {
    this.vCycle += (this.cpu.cycles - this.lastCpu) / this.clockMHz();
    this.lastCpu = this.cpu.cycles;
    if (this.dma) this.stealCycles();
  };
  // Optional (m.dma = true, the timing tests): the cycles the VIC takes from the
  // processor, as on a real machine: 43 on a bad line, 3 + 2 per sprite on a line
  // with sprite data. Off by default: the page and the rates measured against the
  // original run without them.
  P.stealCycles = function () {
    var line = Math.floor((this.vCycle - 12) / PAL_LINE_CYCLES);        // (from cycle 12)
    if (this.dmaFrame !== this.frame) { this.dmaFrame = this.frame; this.dmaLine = -1; }
    while (this.dmaLine < line) {
      var l = ++this.dmaLine, v = this.vic, steal = 0, n = 0;
      if ((v[0x11] & 0x10) && l >= 48 && l <= 247 && (l & 7) === (v[0x11] & 7)) steal += 43;
      for (var i = 0; i < 8; i++) {
        if (!(v[0x15] & (1 << i))) continue;
        var d = (l - v[1 + 2 * i]) & 0x1FF;
        if (d < ((v[0x17] & (1 << i)) ? 42 : 21)) n++;
      }
      if (n) steal += 3 + 2 * n;
      this.vCycle += steal;
    }
  };
  P.rasterLine = function () {
    var c = this.cycleInFrame();
    return Math.floor(c / PAL_LINE_CYCLES) % PAL_LINES;
  };
  P.rasterCycle = function () {
    return Math.floor(this.cycleInFrame()) % PAL_LINE_CYCLES;
  };

  P.beginFrame = function () {
    this.frameEnd = this.frameStart + FRAME_CYCLES;
    this.sidLog.length = 0;
    this.vicLog.length = 0;
    this.ptrLog.length = 0;
    this.vicStart.set(this.vic);
    for (var b = 0; b < 64; b++) this.ptrStart.set(this.ram.subarray(b * 0x400 + 0x3F8, b * 0x400 + 0x400), b * 8);
    this.video.beginFrame();
    this.frameOpen = true;
    this.lastLine = 0;
    this.checkRaster(0);
  };

  P.endFrame = function () {
    this.video.renderTo(PAL_LINES);
    this.frameStart = this.frameEnd;
    this.vCycle -= FRAME_CYCLES;
    this.frame++;
    this.frameOpen = false;
    if (this.hooks) this.hooks.endFrame();
    if (this.onFrame) this.onFrame(this);
  };

  // Run until the end of the current frame. Returns 'frame' when it ended,
  // 'break' when a breakpoint / watchpoint / hook stopped it (this.breakInfo
  // says why; the next run() continues the same frame), 'stopped' when the
  // program ended or the CPU jammed.
  P.run = function () {
    if (this.stopped) return 'stopped';
    if (!this.frameOpen) this.beginFrame();
    var c = this.cpu, hooks = this.hooks, bp = this.bpAt;
    this.breakInfo = null;
    while (this.cycleInFrame() < FRAME_CYCLES) {
      var pc = c.pc;
      if (bp[pc] && pc !== this.skipBreakAt) {
        this.breakInfo = { type: 'break', pc: pc };
        this.skipBreakAt = pc;
        return 'break';
      }
      this.skipBreakAt = -1;
      if (this.exec()) return this.stopped ? 'stopped' : 'break';
    }
    this.endFrame();
    return 'frame';
  };

  // One instruction (plus any interrupt it lets in). Returns true if the
  // machine must stop: the program ended, the CPU jammed, a watchpoint fired
  // or a hook asked for a break.
  P.exec = function () {
    var c = this.cpu, pc = c.pc;
    if (pc === RETURN_TRAP) { this.stopped = 'returned to BASIC'; return true; }
    this.instrPC = pc;
    if (this.hooks && this.hooks.at[pc]) this.hooks.enter(pc); else c.step();
    this.syncClock();
    if (c.jam) { this.stopped = c.jam; return true; }
    if (this.stopped) return true;
    var line = this.rasterLine();
    if (line !== this.lastLine) this.checkRaster(line);
    if ((this.vicIrq & this.vic[0x1A] & 0x0F) && !(c.p & 4)) c.irq();
    if (this.watchHit) {
      this.breakInfo = this.watchHit; this.watchHit = null;
      return true;
    }
    if (this.breakRequest) {
      this.breakInfo = this.breakRequest; this.breakRequest = null;
      return true;
    }
    return false;
  };

  // Raster compare: latch bit 0 of $D019 on the line that matches.
  P.checkRaster = function (line) {
    var cmp = this.vic[0x12] | ((this.vic[0x11] & 0x80) << 1);
    var from = this.lastLine;
    this.lastLine = line;
    // the lines entered since the last check: (from, line], or just 'line' at frame start
    if (line === cmp || (line > from && cmp > from && cmp <= line)) this.vicIrq |= 1;
  };

  // Step one instruction, finishing the frame if it ends. Returns as run().
  P.stepInstruction = function () {
    if (this.stopped) return 'stopped';
    if (!this.frameOpen) this.beginFrame();
    this.skipBreakAt = -1;
    this.breakInfo = null;
    if (this.exec()) return this.stopped ? 'stopped' : 'break';
    if (this.cycleInFrame() >= FRAME_CYCLES) { this.endFrame(); return 'frame'; }
    return 'step';
  };

  // Compatibility: run a whole frame, ignoring breakpoints' "stop" (they still
  // stop if set). Returns false once the program has stopped.
  P.runFrame = function () {
    var r;
    do { r = this.run(); } while (r === 'break' && !this.breakInfo);
    return r !== 'stopped';
  };

  // ---- memory map ------------------------------------------------------------

  // Raster position of a write, for the line-by-line renderer.
  P.logAt = function (log, what, v) {
    var c = Math.floor(this.cycleInFrame());
    log.push(Math.floor(c / PAL_LINE_CYCLES), c % PAL_LINE_CYCLES, what, v);
  };

  // C64 banking: bits 0-2 of the port (inputs read high)
  P.c64Bits = function () { return (this.port1 | ~this.port0) & 7; };

  P.ioVisible = function () {
    if (this.model === 'c128') return (this.mmuCR & 1) === 0;
    var b = this.c64Bits();
    return (b & 4) && (b & 3);
  };

  P.read = function (a) {
    if (this.model === 'c64') {
      if (a < 2) return a === 0 ? this.port0 : ((this.port1 & this.port0) | (~this.port0 & 0x17)) & 0xFF;
      if (a >= 0xD000 && a < 0xE000) {
        var b = this.c64Bits();
        if ((b & 3) && (b & 4)) return this.ioRead(a);
        if ((b & 3) && !(b & 4)) return Font.rom[a & 0x7FF];
      }
      return this.ram[a];
    }
    if (a >= 0xD000 && a < 0xE000 && this.ioVisible()) return this.ioRead(a);
    if (a >= 0xFF00 && a <= 0xFF04) return a === 0xFF00 ? this.mmuCR : 0;
    return this.ram[a];
  };

  // Read without side effects (debugger, watches): I/O shows the register file.
  P.peek = function (a) {
    a &= 0xFFFF;
    if (a >= 0xD000 && a < 0xE000 && this.ioVisible()) {
      if (a < 0xD400) {
        var r = a & 0x3F;
        if (r === 0x12) return this.rasterLine() & 0xFF;
        if (r === 0x19) return this.vicIrq;
        if (r === 0x1E) return this.collSS;
        if (r === 0x1F) return this.collSB;
        return this.vic[r];
      }
      if (a < 0xD800) return a < 0xD500 ? this.sid[a & 0x1F] : 0xFF;
      if (a < 0xDC00) return this.colorRam[a & 0x3FF];
      return this.ram[a];
    }
    if (this.model === 'c64' && a < 2) return a === 0 ? this.port0 : this.port1;
    return this.ram[a];
  };

  // Write from the debugger: RAM always (also under I/O), or I/O when asked.
  P.poke = function (a, v, io) {
    a &= 0xFFFF; v &= 0xFF;
    if (io && a >= 0xD000 && a < 0xE000) { this.ioWrite(a, v); return; }
    this.ram[a] = v;
    if (this.frozenAt[a]) this.frozen[a] = v;
  };

  P.write = function (a, v) {
    if (this.writeLog) this.writeLog.push(a);
    if (this.wpAt[a] && !this.watchHit) {
      this.watchHit = { type: 'watch', addr: a, old: this.peek(a), value: v, pc: this.instrPC };
    }
    if (this.model === 'c64') {
      if (a < 2) { if (a === 0) this.port0 = v; else this.port1 = v; this.ram[a] = v; return; }
      if (a >= 0xD000 && a < 0xE000 && this.ioVisible()) { this.ioWrite(a, v); return; }
    } else {
      if (a >= 0xD000 && a < 0xE000 && this.ioVisible()) { this.ioWrite(a, v); return; }
      if (a === 0xFF00) { this.mmuCR = v; return; }
      if (a > 0xFF00 && a <= 0xFF04) { this.mmuCR = this.mmu[a - 0xFF00]; return; }
    }
    if (this.frozenAt[a]) return;
    if ((a & 0x3F8) === 0x3F8) this.logAt(this.ptrLog, a, v);
    this.ram[a] = v;
  };

  P.ioRead = function (a) {
    if (a < 0xD400) return this.vicRead(a & 0x3F);
    if (this.model === 'c64') {
      if (a < 0xD800) return this.sidRead(a & 0x1F);
    } else {
      if (a < 0xD500) return this.sidRead(a & 0x1F);
      if (a < 0xD600) return (a & 0xFF) === 0 ? this.mmuCR : this.mmu[(a & 0x0F) % 12];
      if (a < 0xD700) return (a & 1) ? this.vdcRead(this.vdcIndex) : 0x80 | 0x02;  // status: ready, version 2
      if (a < 0xD800) return 0xFF;
    }
    if (a < 0xDC00) return (this.colorRam[a & 0x3FF] & 0x0F) | 0xF0;
    if (a < 0xDD00) return this.cia1Read(a & 0x0F);
    if (a < 0xDE00) return this.cia2Read(a & 0x0F);
    return 0xFF;
  };

  P.ioWrite = function (a, v) {
    if (a < 0xD400) { this.vicWrite(a & 0x3F, v); return; }
    if (this.model === 'c64') {
      if (a < 0xD800) { this.sidWrite(a & 0x1F, v); return; }
    } else {
      if (a < 0xD500) { this.sidWrite(a & 0x1F, v); return; }
      if (a < 0xD600) { if ((a & 0xFF) === 0) this.mmuCR = v; else this.mmu[(a & 0x0F) % 12] = v; return; }
      if (a < 0xD700) { if (a & 1) this.vdcWrite(this.vdcIndex, v); else this.vdcIndex = v & 0x3F; return; }
      if (a < 0xD800) return;
    }
    if (a < 0xDC00) { this.colorRam[a & 0x3FF] = v & 0x0F; return; }
    if (a < 0xDD00) { this.ciaWrite(this.cia1, a & 0x0F, v); return; }
    if (a < 0xDE00) { this.ciaWrite(this.cia2, a & 0x0F, v); return; }
  };

  // ---- VIC registers -------------------------------------------------------

  P.vicWrite = function (r, v) {
    if (r === 0x19) { this.vicIrq &= ~v & 0x0F; return; }      // acknowledge
    if (r === 0x1E || r === 0x1F) return;
    if (r === 0x30 && this.model === 'c64') return;
    this.logAt(this.vicLog, r, v);
    this.vic[r] = v;
    if (r === 0x12 || r === 0x11) {
      // the compare matches at once if it is set to the current line
      var cmp = this.vic[0x12] | ((this.vic[0x11] & 0x80) << 1);
      if (cmp === this.rasterLine() && this.rasterCycle() === 0) this.vicIrq |= 1;
    }
  };

  P.vicRead = function (r) {
    var line, v;
    switch (r) {
      case 0x11: line = this.rasterLine(); return (this.vic[0x11] & 0x7F) | ((line & 0x100) >> 1);
      case 0x12: return this.rasterLine() & 0xFF;
      case 0x19: return this.vicIrq | 0x70 | ((this.vicIrq & this.vic[0x1A] & 0x0F) ? 0x80 : 0);
      case 0x1E: this.video.renderTo(this.rasterLine()); v = this.collSS; this.collSS = 0; return v;
      case 0x1F: this.video.renderTo(this.rasterLine()); v = this.collSB; this.collSB = 0; return v;
      case 0x16: return this.vic[r] | 0xC0;
      case 0x18: return this.vic[r] | 0x01;
      case 0x1A: return this.vic[r] | 0xF0;
      case 0x2F: return this.model === 'c128' ? this.vic[r] | 0xF8 : 0xFF;
      case 0x30: return this.model === 'c128' ? this.vic[r] | 0xFC : 0xFF;
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
      case 0x0D: if (v & 0x80) cia.icrMask |= v & 0x1F; else cia.icrMask &= ~v; break;
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
    if (r < 0x19) this.sidLog.push(Math.floor(this.cycleInFrame()), r, v);
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

  // Voice 3 oscillator output. Only the noise waveform matters here (used as a
  // random source), so it is the SID's 23-bit LFSR clocked by the voice 3
  // accumulator.
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

  // ---- debugging -------------------------------------------------------------

  P.setBreak = function (a, on) { this.bpAt[a & 0xFFFF] = on ? 1 : 0; };
  P.setWatch = function (a, on) { this.wpAt[a & 0xFFFF] = on ? 1 : 0; };
  P.freeze = function (a, v) {
    a &= 0xFFFF;
    if (v === null || v === undefined) { this.frozenAt[a] = 0; delete this.frozen[a]; return; }
    this.ram[a] = v & 0xFF; this.frozenAt[a] = 1; this.frozen[a] = v & 0xFF;
  };

  // ---- save / load state -------------------------------------------------------

  var ARRAYS = ['ram', 'colorRam', 'vic', 'sid', 'vdcRam', 'vdcReg', 'mmu', 'vicStart', 'ptrStart', 'keys'];
  var SCALARS = ['model', 'mmuCR', 'port0', 'port1', 'vicIrq', 'collSS', 'collSB', 'vdcIndex', 'joy2',
                 'noise', 'noisePhase', 'osc3Time', 'stopped', 'frame', 'frameStart', 'frameEnd', 'vCycle', 'lastCpu',
                 'frameOpen', 'lastLine'];

  P.saveState = function () {
    var s = { version: 1, cpu: {}, arrays: {}, cia1: Object.assign({}, this.cia1),
              cia2: Object.assign({}, this.cia2), mouse: Object.assign({}, this.mouse),
              vicLog: this.vicLog.slice(), ptrLog: this.ptrLog.slice(), sidLog: this.sidLog.slice()};
    var self = this;
    ['a', 'x', 'y', 'sp', 'pc', 'p', 'cycles'].forEach(function (k) { s.cpu[k] = self.cpu[k]; });
    ARRAYS.forEach(function (k) { if (!(k === 'vdcRam' && self.model === 'c64')) s.arrays[k] = self[k].slice(); });
    SCALARS.forEach(function (k) { s[k] = self[k]; });
    return s;
  };

  P.loadState = function (s) {
    var self = this;
    if (s.model !== this.model) throw new Error('state is for a ' + s.model + ', this machine is a ' + this.model);
    ['a', 'x', 'y', 'sp', 'pc', 'p', 'cycles'].forEach(function (k) { self.cpu[k] = s.cpu[k]; });
    this.cpu.jam = null;
    ARRAYS.forEach(function (k) { if (s.arrays[k]) self[k].set(s.arrays[k]); });
    SCALARS.forEach(function (k) { self[k] = s[k]; });
    if (s.vCycle === undefined) { this.vCycle = s.cpu.cycles - s.frameStart; this.lastCpu = s.cpu.cycles; }
    this.cia1 = Object.assign({}, s.cia1); this.cia2 = Object.assign({}, s.cia2);
    Object.assign(this.mouse, s.mouse);
    this.vicLog = s.vicLog.slice(); this.ptrLog = s.ptrLog.slice(); this.sidLog = s.sidLog.slice();
    // frozen addresses are debugger settings, not machine state: they stay and win
    for (var a in this.frozen) this.ram[a] = this.frozen[a];
    this.writeLog = null; this.watchHit = null; this.breakInfo = null; this.skipBreakAt = this.cpu.pc;
    if (this.hooks) this.hooks.resetPending();
    // re-render the part of the frame that already ran
    this.video.replay(this.frameOpen ? this.rasterLine() : PAL_LINES);
  };

  // Compact text form (base64 of a JSON with base64 arrays), for files / storage.
  P.stateToText = function (s) {
    s = s || this.saveState();
    var o = Object.assign({}, s, { arrays: {} });
    for (var k in s.arrays) o.arrays[k] = b64(s.arrays[k]);
    return JSON.stringify(o);
  };
  P.stateFromText = function (t) {
    var o = JSON.parse(t);
    for (var k in o.arrays) o.arrays[k] = unb64(o.arrays[k]);
    return o;
  };

  function b64(u8) {
    if (typeof Buffer !== 'undefined') return Buffer.from(u8).toString('base64');
    var s = '';
    for (var i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
    return btoa(s);
  }
  function unb64(t) {
    if (typeof Buffer !== 'undefined') return new Uint8Array(Buffer.from(t, 'base64'));
    var s = atob(t), u = new Uint8Array(s.length);
    for (var i = 0; i < s.length; i++) u[i] = s.charCodeAt(i);
    return u;
  }

  Machine.FRAME_CYCLES = FRAME_CYCLES;
  Machine.LINE_CYCLES = PAL_LINE_CYCLES;
  Machine.LINES = PAL_LINES;
  Machine.RETURN_TRAP = RETURN_TRAP;
  return Machine;
})();

if (typeof module !== 'undefined') module.exports = C128;
