// Frame pacing of a display tick (requestAnimationFrame): how many emulated frames to run.
// Pure logic (no DOM, no clock of its own), so the headless tests drive it.
//
// Normal speed: the elapsed time goes into an accumulator and one frame runs per 20 ms of it.
// Fast (the C64 original's unpacker, up to GAMEENTRY) and the 2x / 5x speeds: as many frames as
// fit in a time budget of the tick. Two things the page once got wrong, a stall of 10+ seconds at the
// C64 title (the unpacker's end is found by a hook INSIDE a frame):
//   - the tick's frames were charged to the accumulator by "fast is now off", although they were run
//     in the fast mode, which does not use it: a debt of 175 frames = 3.5 s (and up to 1000 = 20 s) of
//     time without a frame;
//   - the rest of the tick's 1000 frames then ran with no time budget at all.
// Now a tick is one mode from start to end: when the fast mode ends inside it the tick stops and
// the next one begins at normal speed with an empty accumulator.
'use strict';

var SentinelPacing = (function () {
  var FRAME_MS = 1000 / 50, FAST_FRAMES = 1000;

  function Pacer(frameMs) { this.frameMs = frameMs || FRAME_MS; this.acc = 0; }

  Pacer.prototype.reset = function () { this.acc = 0; };

  // One tick. dt: ms since the last tick; c: {speed (1, 2, 5), isFast() (read while running),
  // frame() (one emulated frame; false when the program has stopped), now() (ms), budgetMs}.
  // Returns {ran, stopped}.
  Pacer.prototype.tick = function (dt, c) {
    var fast = c.isFast(), speed = c.speed, n, ran = 0, stopped = false;
    var throttled = fast || speed > 1, end = c.now() + c.budgetMs;
    if (fast) { n = FAST_FRAMES; this.acc = 0; }
    else { this.acc = Math.min(this.acc + dt * speed, this.frameMs * 4 * speed); n = Math.floor(this.acc / this.frameMs); }
    for (var i = 0; i < n; i++) {
      if (!c.frame()) { stopped = true; break; }
      ran++;
      if (throttled && c.now() > end) break;
      if (fast && !c.isFast()) break;           // the fast mode ended in this frame
    }
    if (!fast) this.acc -= ran * this.frameMs;
    return { ran: ran, stopped: stopped };
  };

  return { Pacer: Pacer, FRAME_MS: FRAME_MS, FAST_FRAMES: FAST_FRAMES };
})();

if (typeof module !== 'undefined') module.exports = SentinelPacing;
