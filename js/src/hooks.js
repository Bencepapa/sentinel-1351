// Label-based hooks on the running 8502 code.
//
//   hooks.trace('PLOTPIX')                      count calls per frame
//   hooks.port('PLOTPIX', fn, 'verify')         run the JS port AND the original,
//                                               compare registers + memory writes
//   hooks.port('PLOTPIX', fn, 'replace')        run only the JS port, then RTS
//
// A port is a function of a context:  ctx.a/x/y (in and out), ctx.rd(addr),
// ctx.wr(addr, v) (buffered), ctx.sym('NAME'), ctx.cycles (estimate, optional).
// Verify mode is how routines migrate from 6502 to JS without trusting either:
// the original keeps running, and every call checks the port against it.
'use strict';

var SentinelHooks = (function () {

  function Hooks(machine, symbols) {
    this.m = machine;
    this.symbols = symbols;
    this.at = new Uint8Array(0x10000);
    this.handlers = {};               // addr -> handler
    this.watches = {};                // return addr -> [pending verification]
    this.mismatches = [];
    this.onMismatch = null;
    machine.hooks = this;
  }

  var P = Hooks.prototype;

  // A label, or an address as a number / '$1234'.
  P.addr = function (name) {
    if (typeof name === 'number') return name & 0xFFFF;
    var a = this.symbols[name];
    if (a === undefined && /^\$[0-9a-f]{1,4}$/i.test(name)) a = parseInt(name.slice(1), 16);
    if (a === undefined) throw new Error('unknown label ' + name);
    return a;
  };

  // Label for an address (for the debugger), or null.
  P.labelOf = function (a) {
    if (!this.byAddr) {
      this.byAddr = {};
      for (var n in this.symbols) if (!(this.symbols[n] in this.byAddr)) this.byAddr[this.symbols[n]] = n;
    }
    return this.byAddr[a] || null;
  };

  P.handler = function (name) {
    var a = this.addr(name), h = this.handlers[a];
    if (!h) {
      if (typeof name === 'number' || name[0] === '$') name = this.labelOf(a) || '$' + ('000' + a.toString(16).toUpperCase()).slice(-4);
      h = this.handlers[a] = { name: name, addr: a, mode: 'trace', fn: null, listeners: [],
                               calls: 0, callsLastFrame: 0, verified: 0, failed: 0 };
      this.at[a] = 1;
    }
    return h;
  };

  P.trace = function (name) { this.handler(name); return this; };

  // Call fn(machine, handler) every time the routine is entered (events, cheats).
  // fn can stop the machine: m.breakRequest = {type: 'event', ...}.
  P.on = function (name, fn) { this.handler(name).listeners.push(fn); return this; };
  P.off = function (name, fn) {
    var h = this.handler(name);
    h.listeners = fn ? h.listeners.filter(function (f) { return f !== fn; }) : [];
  };

  // Skip a routine: it returns at once (RTS) without running. Used for cheats
  // like 'no damage'. mode 'off' turns it back on.
  P.skip = function (name, on) { return this.port(name, function () {}, on === false ? 'trace' : 'replace'); };

  // Forget verifications in flight (after load state).
  P.resetPending = function () {
    for (var a in this.watches) if (!this.handlers[a]) this.at[a] = 0;
    this.watches = {};
  };

  P.port = function (name, fn, mode) {
    var h = this.handler(name);
    h.fn = fn; h.mode = mode || 'verify';
    return this;
  };

  P.setMode = function (name, mode) { this.handler(name).mode = mode; };

  P.endFrame = function () {
    for (var a in this.handlers) {
      var h = this.handlers[a];
      h.callsLastFrame = h.calls; h.calls = 0;
    }
  };

  // ---- context for JS ports -------------------------------------------------

  function Ctx(hooks, cpu) {
    this.h = hooks; this.m = hooks.m;
    this.a = cpu.a; this.x = cpu.x; this.y = cpu.y;
    this.writes = new Map();
    this.cycles = 0;
  }
  Ctx.prototype.rd = function (a) {
    a &= 0xFFFF;
    return this.writes.has(a) ? this.writes.get(a) : this.m.read(a);
  };
  Ctx.prototype.wr = function (a, v) { this.writes.set(a & 0xFFFF, v & 0xFF); };
  Ctx.prototype.sym = function (n) { return this.h.addr(n); };

  // ---- called by the machine when PC hits a hooked address -----------------

  P.enter = function (pc) {
    var m = this.m, cpu = m.cpu;
    if (this.watches[pc]) this.checkReturn(pc);
    var h = this.handlers[pc];
    if (!h) { cpu.step(); return; }
    h.calls++;
    for (var i = 0; i < h.listeners.length; i++) h.listeners[i](m, h);
    if (!h.fn || h.mode === 'trace' || h.mode === 'off' || m.writeLog) { cpu.step(); return; }

    var ctx = new Ctx(this, cpu);
    h.fn(ctx);

    if (h.mode === 'replace') {
      ctx.writes.forEach(function (v, a) { m.write(a, v); });
      cpu.a = ctx.a & 0xFF; cpu.x = ctx.x & 0xFF; cpu.y = ctx.y & 0xFF;
      cpu.nz(cpu.a);
      cpu.pc = ((cpu.pull() | (cpu.pull() << 8)) + 1) & 0xFFFF;   // RTS
      cpu.cycles += ctx.cycles || 12;
      return;
    }

    // verify: remember what the port predicts, run the original, compare on return
    var ret = ((m.ram[0x100 | ((cpu.sp + 1) & 0xFF)] | (m.ram[0x100 | ((cpu.sp + 2) & 0xFF)] << 8)) + 1) & 0xFFFF;
    var w = { h: h, sp: (cpu.sp + 2) & 0xFF, entrySp: cpu.sp, ctx: ctx };
    (this.watches[ret] = this.watches[ret] || []).push(w);
    this.at[ret] = 1;
    m.writeLog = [];
    cpu.step();
  };

  P.checkReturn = function (pc) {
    var m = this.m, cpu = m.cpu, list = this.watches[pc];
    for (var i = list.length - 1; i >= 0; i--) {
      var w = list[i];
      if (w.sp !== cpu.sp) continue;
      list.splice(i, 1);
      var ctx = w.ctx, diffs = [];
      ['a', 'x', 'y'].forEach(function (r) {
        if ((ctx[r] & 0xFF) !== cpu[r]) diffs.push(r.toUpperCase() + ' port=' + hex(ctx[r] & 0xFF) + ' 6502=' + hex(cpu[r]));
      });
      // the routine's own stack traffic (JSR/PHA below the caller's stack) is scratch
      var seen = new Set((m.writeLog || []).filter(function (a) {
        return !(a >= 0x100 && a <= (0x100 | w.entrySp));
      }));
      ctx.writes.forEach(function (v, a) {
        if (!seen.has(a)) diffs.push('$' + hex4(a) + ' written by port only');
        else if (m.read(a) !== v) diffs.push('$' + hex4(a) + ' port=' + hex(v) + ' 6502=' + hex(m.read(a)));
      });
      seen.forEach(function (a) {
        if (!ctx.writes.has(a)) diffs.push('$' + hex4(a) + ' written by 6502 only');
      });
      m.writeLog = null;
      if (diffs.length) {
        w.h.failed++;
        var rec = { name: w.h.name, frame: m.frame, diffs: diffs };
        if (this.mismatches.length < 50) this.mismatches.push(rec);
        if (this.onMismatch) this.onMismatch(rec);
      } else {
        w.h.verified++;
      }
    }
    if (!list.length) {
      delete this.watches[pc];
      if (!this.handlers[pc]) this.at[pc] = 0;
    }
  };

  function hex(v) { return ('0' + v.toString(16).toUpperCase()).slice(-2); }
  function hex4(v) { return ('000' + v.toString(16).toUpperCase()).slice(-4); }

  return Hooks;
})();

if (typeof module !== 'undefined') module.exports = SentinelHooks;
