// SID sound: the register writes logged by the machine (with their cycle in
// the frame) are replayed in an AudioWorklet at the same timing. Three voices
// with triangle/saw/pulse/noise, ADSR and a simple state-variable filter.
// Not a cycle-exact SID, but the same register program produces the same notes.
'use strict';

var SentinelAudio = (function () {

  function workletSource() {
    var CLOCK = 985248;                    // PAL
    var ATTACK = [2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800, 1000, 3000, 5000, 8000];

    function Voice() {
      this.acc = 0; this.freq = 0; this.pw = 0; this.ctrl = 0; this.ad = 0; this.sr = 0;
      this.env = 0; this.state = 'release'; this.noise = 0x7FFFF8; this.prevBit19 = 0;
    }

    class SidProcessor extends AudioWorkletProcessor {
      constructor() {
        super();
        this.v = [new Voice(), new Voice(), new Voice()];
        this.reg = new Uint8Array(32);
        this.queue = [];          // [absCycle, reg, value]
        this.cycle = 0;           // SID cycles played so far
        this.lp = 0; this.bp = 0;
        this.port.onmessage = (e) => {
          const d = e.data;
          if (d.reset) { this.queue = []; this.cycle = d.cycle; for (let r = 0; r < 25; r++) this.write(r, 0); return; }
          // keep the latency between 1 and 4 frames
          const lag = d.frameStart - this.cycle;
          if (lag < 19656 || lag > 4 * 19656) this.cycle = d.frameStart - 2 * 19656;
          for (let i = 0; i < d.log.length; i += 3) this.queue.push([d.frameStart + d.log[i], d.log[i + 1], d.log[i + 2]]);
        };
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
      process(inputs, outputs) {
        const out = outputs[0][0];
        const step = CLOCK / sampleRate;
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
            const ms = 1000 / sampleRate;
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
        return true;
      }
    }
    registerProcessor('sid-processor', SidProcessor);
  }

  function Audio() { this.ctx = null; this.node = null; this.muted = false; this.sync = true; }

  Audio.prototype.start = function () {
    if (this.ctx) { if (this.ctx.state !== 'running') this.ctx.resume(); return Promise.resolve(); }
    var Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx || !window.AudioWorkletNode) return Promise.resolve();
    var self = this;
    this.ctx = new Ctx();
    var src = '(' + workletSource.toString() + ')();';
    var url = URL.createObjectURL(new Blob([src], { type: 'application/javascript' }));
    return this.ctx.audioWorklet.addModule(url).then(function () {
      self.node = new AudioWorkletNode(self.ctx, 'sid-processor');
      self.node.connect(self.ctx.destination);
      self.sync = true;
    }).catch(function (e) { console.warn('SID audio unavailable', e); });
  };

  // Called after every emulated frame with the machine's SID write log.
  Audio.prototype.frame = function (m, frameStartCycle) {
    if (!this.node || this.muted) return;
    var log = m.sidLog.slice();
    if (this.sync) {                       // the worklet starts from silence: give it the
      var pre = [];                        // registers written before the audio started
      for (var r = 0; r < 25; r++) pre.push(0, r, m.sid[r]);   // (volume, envelopes...)
      log = pre.concat(log);
      this.sync = false;
    }
    this.node.port.postMessage({ frameStart: frameStartCycle, log: log });
  };

  Audio.prototype.reset = function (cycle) {
    if (this.node) this.node.port.postMessage({ reset: true, cycle: cycle - 2 * 19656 });
    this.sync = true;
  };

  Audio.prototype.setMuted = function (on) {
    this.muted = on;
    if (on && this.node) this.node.port.postMessage({ reset: true, cycle: 0 });
    if (!on) this.sync = true;
  };

  return Audio;
})();
