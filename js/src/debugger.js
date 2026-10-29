// Debugger for one running program: watches with history, cheats, events,
// save-state slots and a VICE-like monitor command line. No DOM here, so the
// headless tests drive it the same way the page does.
'use strict';

var SentinelDebugger = (function () {
  var Dis = (typeof SentinelDisasm !== 'undefined') ? SentinelDisasm : require('./disasm.js');
  var h2 = Dis.h2, h4 = Dis.h4;
  var HISTORY = 240;

  function Debugger(machine, hooks, name, profile) {
    this.m = machine; this.hooks = hooks; this.program = name;
    this.profile = profile || { watches: [], cheats: [], events: [], keys: [] };
    this.watches = [];
    this.cheats = {};                 // id -> on
    this.eventsOn = {};               // event name -> {pause}
    this.slots = {};                  // slot -> state object
    this.log = [];                    // {frame, text, kind}
    this.onLog = null;
    this.pauseRequested = null;
    var self = this;
    this.profile.watches.forEach(function (w) { self.addWatch(w.at, w.size, w.fmt, w.name); });
    this.profile.events.forEach(function (e) { self.setEvent(e, true, !!e.pause); });
  }

  var D = Debugger.prototype;

  D.say = function (text, kind) {
    var e = { frame: this.m.frame, text: text, kind: kind || 'info' };
    this.log.push(e);
    if (this.log.length > 300) this.log.shift();
    if (this.onLog) this.onLog(e);
  };

  // ---- addresses -----------------------------------------------------------------

  // 'LABEL', 'LABEL+3', '$C000', 'C000', '49152' (with a leading '#')
  D.parse = function (t) {
    if (typeof t === 'number') return t & 0xFFFF;
    t = String(t).trim();
    var m = /^([^+\-]+)([+\-][0-9a-fA-F$]+)?$/.exec(t);
    if (!m) throw new Error('bad address ' + t);
    var base = m[1], off = 0, a;
    if (m[2]) off = parseInt(m[2].replace('$', ''), m[2].indexOf('$') >= 0 ? 16 : 10) * (m[2][0] === '-' ? -1 : 1);
    if (this.hooks.symbols[base] !== undefined) a = this.hooks.symbols[base];
    else if (base[0] === '#') a = parseInt(base.slice(1), 10);
    else if (/^\$?[0-9a-fA-F]{1,4}$/.test(base)) a = parseInt(base.replace('$', ''), 16);
    else throw new Error('unknown label ' + base);
    return (a + off) & 0xFFFF;
  };

  D.label = function (a) { return this.hooks.labelOf(a); };
  D.name = function (a) { var l = this.label(a); return l ? l + ' ($' + h4(a) + ')' : '$' + h4(a); };

  // ---- watches ---------------------------------------------------------------

  D.addWatch = function (at, size, fmt, name) {
    var a = this.parse(at);
    var w = { at: at, addr: a, size: size || 1, fmt: fmt || 'dec', name: name || this.name(a),
              hist: new Float64Array(HISTORY), pos: 0, filled: 0 };
    this.watches.push(w);
    return w;
  };
  D.removeWatch = function (i) { this.watches.splice(i, 1); };

  D.value = function (w) {
    var m = this.m, a = w.addr, i, v = 0;
    if (w.fmt === 'digits') {
      for (i = 0; i < w.size; i++) v = v * 10 + Math.max(0, Math.min(9, m.peek(a + i) - 0x70));
      return v;
    }
    if (w.fmt === 'bytes') return m.peek(a);
    for (i = w.size - 1; i >= 0; i--) v = v * 256 + m.peek(a + i);
    return v;
  };

  D.text = function (w) {
    var m = this.m, v = this.value(w), i, out = [];
    if (w.fmt === 'bytes') { for (i = 0; i < w.size; i++) out.push(h2(m.peek(w.addr + i))); return out.join(' '); }
    if (w.fmt === 'hex') return '$' + (w.size > 1 ? h4(v) : h2(v));
    return String(v);
  };

  D.frozen = function (w) {
    for (var i = 0; i < (w.fmt === 'bytes' ? 1 : w.size); i++) if (!this.m.frozenAt[(w.addr + i) & 0xFFFF]) return false;
    return true;
  };

  // Set a watch to a number (written in its own format).
  D.setWatch = function (w, v) {
    var m = this.m, i;
    if (w.fmt === 'digits') {
      var s = String(Math.max(0, Math.floor(v))).padStart(w.size, '0').slice(-w.size);
      for (i = 0; i < w.size; i++) m.poke(w.addr + i, 0x70 + +s[i]);
    } else {
      for (i = 0; i < w.size; i++) { m.poke(w.addr + i, v & 0xFF); v = Math.floor(v / 256); }
    }
  };

  D.freezeWatch = function (w, on) {
    var n = w.fmt === 'bytes' ? w.size : w.size;
    for (var i = 0; i < n; i++) { var a = (w.addr + i) & 0xFFFF; this.m.freeze(a, on ? this.m.ram[a] : null); }
  };

  // Called once per frame by the page / tests.
  D.sample = function () {
    for (var i = 0; i < this.watches.length; i++) {
      var w = this.watches[i];
      w.hist[w.pos] = this.value(w);
      w.pos = (w.pos + 1) % HISTORY;
      if (w.filled < HISTORY) w.filled++;
    }
  };

  // ---- cheats ---------------------------------------------------------------------

  D.setCheat = function (id, on) {
    var c = this.profile.cheats.filter(function (x) { return x.id === id; })[0];
    if (!c) throw new Error('no cheat ' + id);
    var m = this.m, self = this;
    if (c.skip) this.hooks.skip(c.skip, on);
    (c.freeze || []).forEach(function (f) {
      var a = self.parse(f.at);
      for (var i = 0; i < (f.size || 1); i++) {
        var v = f.value !== undefined ? f.value : m.ram[(a + i) & 0xFFFF];
        m.freeze(a + i, on ? v : null);
      }
    });
    this.cheats[id] = on;
    this.say((on ? 'Cheat on: ' : 'Cheat off: ') + c.name, 'cheat');
  };

  // ---- events ---------------------------------------------------------------------

  D.setEvent = function (e, on, pause) {
    var self = this, h = this.hooks;
    var cur = this.eventsOn[e.name];
    if (cur) h.off(e.at, cur.fn);
    if (!on) { delete this.eventsOn[e.name]; return; }
    var rec = { pause: pause, count: 0, fn: null };
    rec.fn = function (m) {
      rec.count++;
      self.say(e.name + ' (' + e.at + ', frame ' + m.frame + ')', 'event');
      if (rec.pause) m.breakRequest = { type: 'event', name: e.name, pc: m.cpu.pc };
    };
    h.on(e.at, rec.fn);
    this.eventsOn[e.name] = rec;
  };

  // ---- save states ---------------------------------------------------------------

  D.storageKey = function (slot) { return 'sentinel-state-' + this.program + '-' + slot; };

  D.save = function (slot) {
    var s = this.m.saveState();
    this.slots[slot] = s;
    try { localStorage.setItem(this.storageKey(slot), this.m.stateToText(s)); } catch (e) { /* memory only */ }
    this.say('Saved slot ' + slot + ' at frame ' + s.frame + ', raster ' + this.m.rasterLine(), 'state');
    return s;
  };

  D.load = function (slot) {
    var s = this.slots[slot];
    if (!s) {
      try { var t = localStorage.getItem(this.storageKey(slot)); if (t) s = this.slots[slot] = this.m.stateFromText(t); } catch (e) { /* none */ }
    }
    if (!s) throw new Error('slot ' + slot + ' is empty');
    this.m.loadState(s);
    this.say('Loaded slot ' + slot + ' (frame ' + s.frame + ')', 'state');
    return s;
  };

  D.hasSlot = function (slot) {
    if (this.slots[slot]) return true;
    try { return !!localStorage.getItem(this.storageKey(slot)); } catch (e) { return false; }
  };

  // ---- views ---------------------------------------------------------------------

  D.registers = function () {
    var c = this.m.cpu, f = '', names = 'NV-BDIZC';
    for (var i = 7; i >= 0; i--) f += (c.p >> i) & 1 ? names[7 - i] : '.';
    return 'PC=' + h4(c.pc) + ' A=' + h2(c.a) + ' X=' + h2(c.x) + ' Y=' + h2(c.y) + ' SP=' + h2(c.sp) + ' ' + f +
           '  line ' + this.m.rasterLine() + ' cyc ' + this.m.rasterCycle() + '  frame ' + this.m.frame;
  };

  D.disasm = function (addr, count) {
    var m = this.m, self = this;
    return Dis.range(function (a) { return m.peek(a); }, addr, count, function (a) { return self.label(a); });
  };

  D.dump = function (addr, rows) {
    var out = [];
    for (var r = 0; r < rows; r++) {
      var a = (addr + r * 16) & 0xFFFF, hx = [], tx = '';
      for (var i = 0; i < 16; i++) {
        var v = this.m.peek(a + i);
        hx.push(h2(v));
        tx += (v >= 0x20 && v < 0x7F) ? String.fromCharCode(v) : '.';
      }
      out.push('$' + h4(a) + '  ' + hx.join(' ') + '  ' + tx);
    }
    return out;
  };

  // ---- monitor command line ----------------------------------------------------------

  var HELP = [
    'r                     registers',
    'd [addr] [n]          disassemble (default: PC)',
    'm [addr] [rows]       memory',
    '> addr b1 b2 ...      write bytes (RAM)',
    'io addr b             write an I/O register',
    'bk addr | bl | del addr|all     PC breakpoints',
    'w addr [end] | uw addr|all      stop when the program writes there',
    'fr addr [val] | uf addr|all     freeze (writes ignored)',
    'show addr [size] [dec|hex|digits|bytes] [name]   add to the watch list',
    'tr label | sk label [off]       trace calls / skip a routine (RTS at once)',
    'z [n]  f [n]  g                step instructions / frames, continue',
    'save [slot] | load [slot]     save states',
    'l [filter]                     labels',
    'Addresses: LABEL, LABEL+n, $c000 or c000.',
  ];

  // Returns lines of output. Commands that change run state set
  // this.pauseRequested / this.resumeRequested / this.stepRequest for the page.
  D.exec = function (line) {
    var self = this, m = this.m;
    var p = line.trim().split(/\s+/), cmd = (p[0] || '').toLowerCase(), args = p.slice(1);
    var out = [];
    var addrOr = function (i, def) { return args[i] !== undefined ? self.parse(args[i]) : def; };
    switch (cmd) {
      case '': return [];
      case 'help': case '?': return HELP;
      case 'r': return [this.registers()];
      case 'd': {
        var a = addrOr(0, m.cpu.pc), n = args[1] ? parseInt(args[1], 10) : 12;
        this.lastD = a;
        return this.disasm(a, n).map(function (d) {
          var l = self.label(d.pc);
          return (m.bpAt[d.pc] ? '*' : ' ') + (d.pc === m.cpu.pc ? '>' : ' ') + '$' + h4(d.pc) + '  ' +
                 d.bytes.map(h2).join(' ').padEnd(9) + ' ' + d.text + (l ? '   ; ' + l : '');
        });
      }
      case 'm': return this.dump(addrOr(0, 0), args[1] ? parseInt(args[1], 10) : 8);
      case '>': {
        var b = this.parse(args[0]);
        args.slice(1).forEach(function (v, i) { m.poke(b + i, parseInt(v.replace('$', ''), 16)); });
        return this.dump(b, 1);
      }
      case 'io': m.poke(this.parse(args[0]), parseInt(args[1].replace('$', ''), 16), true); return ['ok'];
      case 'bk': case 'break': {
        var ba = this.parse(args[0]); m.setBreak(ba, true); return ['breakpoint at ' + this.name(ba)];
      }
      case 'bl': {
        for (var i = 0; i < 0x10000; i++) if (m.bpAt[i]) out.push(this.name(i));
        return out.length ? out : ['no breakpoints'];
      }
      case 'del': {
        if (args[0] === 'all') { m.bpAt.fill(0); return ['all breakpoints deleted']; }
        m.setBreak(this.parse(args[0]), false); return ['deleted'];
      }
      case 'w': case 'watch': {
        var wa = this.parse(args[0]), we = args[1] ? this.parse(args[1]) : wa;
        for (var x = wa; x <= we; x++) m.setWatch(x, true);
        return ['stop on writes to ' + this.name(wa) + (we !== wa ? ' - $' + h4(we) : '')];
      }
      case 'uw': {
        if (args[0] === 'all') { m.wpAt.fill(0); return ['all write watches removed']; }
        m.setWatch(this.parse(args[0]), false); return ['removed'];
      }
      case 'fr': {
        var fa = this.parse(args[0]);
        var fv = args[1] !== undefined ? parseInt(args[1].replace('$', ''), args[1][0] === '$' ? 16 : 10) : m.ram[fa];
        m.freeze(fa, fv); return ['frozen ' + this.name(fa) + ' = ' + fv];
      }
      case 'uf': {
        if (args[0] === 'all') { Object.keys(m.frozen).forEach(function (k) { m.freeze(+k, null); }); return ['nothing frozen']; }
        m.freeze(this.parse(args[0]), null); return ['unfrozen'];
      }
      case 'show': {
        var w = this.addWatch(args[0], args[1] ? parseInt(args[1], 10) : 1, args[2], args.slice(3).join(' ') || undefined);
        return ['watching ' + w.name];
      }
      case 'tr': this.hooks.trace(args[0]); return ['tracing ' + args[0]];
      case 'sk': this.hooks.skip(args[0], args[1] !== 'off'); return [(args[1] === 'off' ? 'running ' : 'skipping ') + args[0]];
      case 'z': this.stepRequest = { kind: 'instr', n: args[0] ? parseInt(args[0], 10) : 1 }; return [];
      case 'f': this.stepRequest = { kind: 'frame', n: args[0] ? parseInt(args[0], 10) : 1 }; return [];
      case 'g': case 'x': this.resumeRequested = true; return [];
      case 'save': this.save(args[0] || '1'); return [];
      case 'load': this.load(args[0] || '1'); return [];
      case 'l': {
        var f = (args[0] || '').toUpperCase(), syms = this.hooks.symbols;
        Object.keys(syms).filter(function (k) { return k.indexOf(f) >= 0; }).slice(0, 60)
          .forEach(function (k) { out.push('$' + h4(syms[k]) + '  ' + k); });
        return out.length ? out : ['no labels match'];
      }
    }
    return ['unknown command ' + cmd + ' (help lists them)'];
  };

  return Debugger;
})();

if (typeof module !== 'undefined') module.exports = SentinelDebugger;
