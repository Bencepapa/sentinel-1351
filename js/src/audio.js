// SID sound: the register writes logged by the machine (with their cycle in
// the frame) are replayed in an AudioWorklet at the same timing. Three voices
// with triangle/saw/pulse/noise, ADSR and a simple state-variable filter.
// Not a cycle-exact SID, but the same register program produces the same notes.
'use strict';

var SentinelAudio = (function () {

  // The synth itself. Its source text is also what the worklet module runs, so it must stay
  // self-contained (no outer variables). Returns the engine class.
  function sidCore() {
    var CLOCK = 985248;                    // PAL
    var ATTACK = [2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800, 1000, 3000, 5000, 8000];

    function Voice() {
      this.acc = 0; this.freq = 0; this.pw = 0; this.ctrl = 0; this.ad = 0; this.sr = 0;
      this.env = 0; this.state = 'release'; this.noise = 0x7FFFF8; this.prevBit19 = 0;
    }

    class SidEngine {
      constructor(rate) {
        this.rate = rate;
        this.v = [new Voice(), new Voice(), new Voice()];
        this.reg = new Uint8Array(32);
        this.queue = [];          // [absCycle, reg, value]
        this.cycle = 0;           // SID cycles played so far
        this.lp = 0; this.bp = 0;
      }
      // {reset, cycle} silences and restarts the clock; {frameStart, log} queues one frame's writes
      message(d) {
        if (d.reset) { this.queue = []; this.cycle = d.cycle; for (let r = 0; r < 25; r++) this.write(r, 0); return; }
        // keep the latency between 1 and 4 frames
        const lag = d.frameStart - this.cycle;
        if (lag < 19656 || lag > 4 * 19656) this.cycle = d.frameStart - 2 * 19656;
        for (let i = 0; i < d.log.length; i += 3) this.queue.push([d.frameStart + d.log[i], d.log[i + 1], d.log[i + 2]]);
        if (this.queue.length > 30000) this.queue.splice(0, this.queue.length - 30000);   // nobody is playing them
      }
      write(r, v) {
        this.reg[r] = v;
        if (r < 21) {
          const vo = this.v[Math.floor(r / 7)], k = r % 7;
          if (k === 0) vo.freq = (vo.freq & 0xFF00) | v;
          else if (k === 1) vo.freq = (vo.freq & 0xFF) | (v << 8);
          else if (k === 2) vo.pw = (vo.pw & 0xF00) | v;
          else if (k === 3) vo.pw = (vo.pw & 0xFF) | ((v & 15) << 8);
          else if (k === 4) {
            if ((v & 1) && !(vo.ctrl & 1)) vo.state = 'attack';
            if (!(v & 1) && (vo.ctrl & 1)) vo.state = 'release';
            if (v & 8) vo.acc = 0;
            vo.ctrl = v;
          } else if (k === 5) vo.ad = v; else vo.sr = v;
        }
      }
      render(out) {
        const step = CLOCK / this.rate;
        const reg = this.reg;
        for (let s = 0; s < out.length; s++) {
          const next = this.cycle + step;
          while (this.queue.length && this.queue[0][0] <= next) { const q = this.queue.shift(); this.write(q[1], q[2]); }
          this.cycle = next;
          let mixF = 0, mixD = 0;
          const filt = reg[23] & 7;
          for (let i = 0; i < 3; i++) {
            const vo = this.v[i];
            // envelope (linear; decay/release 3x the attack table)
            const ms = 1000 / this.rate;
            const sus = ((vo.sr >> 4) / 15);
            if (vo.state === 'attack') { vo.env += ms / ATTACK[vo.ad >> 4]; if (vo.env >= 1) { vo.env = 1; vo.state = 'decay'; } }
            else if (vo.state === 'decay') { vo.env -= ms / (3 * ATTACK[vo.ad & 15]); if (vo.env <= sus) { vo.env = sus; vo.state = 'sustain'; } }
            else if (vo.state === 'sustain') { vo.env = sus; }
            else { vo.env -= ms / (3 * ATTACK[vo.sr & 15]); if (vo.env < 0) vo.env = 0; }
            // oscillator
            const prev = vo.acc;
            vo.acc = (vo.acc + vo.freq * step) % 0x1000000;
            if ((vo.acc & 0x80000) && !(prev & 0x80000) || vo.freq * step >= 0x80000) {
              const n = vo.noise; vo.noise = ((n << 1) | (((n >> 22) ^ (n >> 17)) & 1)) & 0x7FFFFF;
            }
            const c = vo.ctrl;
            if (c & 8) continue;
            let w = -1, x = vo.acc / 0x1000000;
            if (c & 0x80) { w = ((vo.noise >> 15) & 0xFF) / 127.5 - 1; }
            else if (c & 0x40) { w = (x * 4096 < vo.pw) ? 1 : -1; if (c & 0x20) w = Math.min(w, x * 2 - 1); }
            else if (c & 0x20) { w = x * 2 - 1; }
            else if (c & 0x10) {
              let t = x < 0.5 ? x * 4 - 1 : 3 - x * 4;
              if ((c & 4) && (this.v[(i + 2) % 3].acc & 0x800000)) t = -t;   // ring mod
              w = t;
            } else continue;
            const sOut = w * vo.env;
            if (filt & (1 << i)) mixF += sOut; else if (!(i === 2 && (reg[24] & 0x80))) mixD += sOut;
          }
          // filter
          const fc = ((reg[22] << 3) | (reg[21] & 7)) / 2047;
          const f = Math.min(0.9, 0.02 + fc * 0.8);
          const q = 1.2 - (reg[23] >> 4) / 15;
          const hp = mixF - this.lp - q * this.bp;
          this.bp += f * hp; this.lp += f * this.bp;
          let filtered = 0;
          if (reg[24] & 0x10) filtered += this.lp;
          if (reg[24] & 0x20) filtered += this.bp;
          if (reg[24] & 0x40) filtered += hp;
          out[s] = (mixD + filtered) * (reg[24] & 15) / 15 * 0.25;
        }
      }
    }
    return SidEngine;
  }

  // The worklet module: the engine plus a processor that feeds it.
  function workletSource() {
    var Engine = sidCore();
    class SidProcessor extends AudioWorkletProcessor {
      constructor() {
        super();
        this.e = new Engine(sampleRate);
        this.port.onmessage = (ev) => this.e.message(ev.data);
      }
      process(inputs, outputs) { this.e.render(outputs[0][0]); return true; }
    }
    registerProcessor('sid-processor', SidProcessor);
  }

  // ---- the audio object --------------------------------------------------------
  //
  // Starting is the fragile part (issue #14): the AudioContext has to be made / resumed
  // inside a user gesture, and the worklet module has to be loadable where the page runs
  // (a blob: URL fails on file:// pages and under some iframe sandboxes / CSPs). So the
  // module is tried as a blob, then as a data: URL, and if neither loads, the same engine
  // runs in a ScriptProcessorNode on the main thread. `kind` says which one is playing.

  function Audio() {
    var self = this;
    this.ctx = null; this.node = null; this.engine = null; this.kind = 'none';
    this.muted = false; this.sync = true; this.starting = null;
    if (typeof document !== 'undefined') {
      document.addEventListener('visibilitychange', function () { if (!document.hidden) self.resume(); });
    }
  }

  Audio.prototype.resume = function () {
    var c = this.ctx;
    if (c && c.state !== 'running' && c.state !== 'closed') {
      try { var p = c.resume(); if (p && p.catch) p.catch(function () { /* needs a gesture */ }); } catch (e) { /* ignore */ }
    }
  };

  Audio.prototype.running = function () {
    return !!this.ctx && this.ctx.state === 'running' && this.kind !== 'none';
  };

  // Call from a user gesture (key, click, touch). Safe to call again and again.
  Audio.prototype.start = function () {
    var self = this;
    if (this.ctx) { this.resume(); return this.starting || Promise.resolve(); }
    var Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return Promise.resolve();
    try { this.ctx = new Ctx(); } catch (e) { console.warn('No audio context', e); return Promise.resolve(); }
    this.resume();
    this.ctx.onstatechange = function () { if (self.ctx.state === 'running') self.sync = true; };
    this.starting = this.makeNode().then(function () {
      self.sync = true;
    }, function (e) { console.warn('SID audio unavailable', e); });
    return this.starting;
  };

  Audio.prototype.makeNode = function () {
    var self = this, ctx = this.ctx;
    var src = Audio.moduleSource();
    var blobUrl = null;
    function viaWorklet(url, kind) {
      return ctx.audioWorklet.addModule(url).then(function () {
        self.node = new window.AudioWorkletNode(ctx, 'sid-processor');
        self.node.connect(ctx.destination);
        self.kind = kind;
      });
    }
    function scriptNode() {
      if (!ctx.createScriptProcessor) return Promise.reject(new Error('no audio output available'));
      var Engine = sidCore(), engine = new Engine(ctx.sampleRate);
      var node = ctx.createScriptProcessor(1024, 1, 1);
      node.onaudioprocess = function (e) { engine.render(e.outputBuffer.getChannelData(0)); };
      node.connect(ctx.destination);
      self.engine = engine; self.node = node; self.kind = 'script';
      return Promise.resolve();
    }
    if (!(ctx.audioWorklet && window.AudioWorkletNode)) return scriptNode();
    var chain = Promise.resolve().then(function () {
      blobUrl = URL.createObjectURL(new Blob([src], { type: 'application/javascript' }));
      return viaWorklet(blobUrl, 'worklet-blob');
    }).catch(function () {
      return viaWorklet('data:application/javascript;base64,' + btoa(unescape(encodeURIComponent(src))), 'worklet-data');
    }).catch(scriptNode);
    return chain.then(function () { if (blobUrl) URL.revokeObjectURL(blobUrl); });
  };

  Audio.prototype.send = function (d) {
    if (this.engine) this.engine.message(d);
    else if (this.node) this.node.port.postMessage(d);
  };

  // Called after every emulated frame with the machine's SID write log.
  Audio.prototype.frame = function (m, frameStartCycle) {
    if (!this.node || this.muted) return;
    if (this.ctx.state !== 'running') { this.sync = true; return; }   // nobody is listening yet
    var log = m.sidLog.slice();
    if (this.sync) {                       // the synth starts from silence: give it the
      var pre = [];                        // registers written before the audio started
      for (var r = 0; r < 25; r++) pre.push(0, r, m.sid[r]);   // (volume, envelopes...)
      log = pre.concat(log);
      this.sync = false;
    }
    this.send({ frameStart: frameStartCycle, log: log });
  };

  Audio.prototype.reset = function (cycle) {
    this.send({ reset: true, cycle: cycle - 2 * 19656 });
    this.sync = true;
  };

  // Silence now (the log is not being fed: speed-up, pause); the registers come back with the next frame().
  Audio.prototype.silence = function () {
    this.send({ reset: true, cycle: 0 });
    this.sync = true;
  };

  Audio.prototype.setMuted = function (on) {
    this.muted = on;
    if (on) this.send({ reset: true, cycle: 0 });
    if (!on) this.sync = true;
  };

  // The worklet module text, and the bare synth (tests, and the ScriptProcessor fallback).
  Audio.moduleSource = function () { return 'var sidCore = ' + sidCore.toString() + ';\n(' + workletSource.toString() + ')();'; };
  Audio.createEngine = function (rate) { var E = sidCore(); return new E(rate); };

  return Audio;
})();

if (typeof module !== 'undefined') module.exports = SentinelAudio;
