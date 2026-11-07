# Fixes after the user's VICE x128 test of the minefield

Follow-up to `briefs/mothership-minefield.md` (same rules; read it, `c128-game/mines.asm`,
and `PLAN-C128-COCKPIT.md` "Handing the work on"; do NOT commit or push; the previous
stage's uncommitted changes are in the working tree: build on them). The user says the
mines and their movement are right, and the banded stars with the mines look right. Fix:

1. **The ship must not steer up/down in the minefield** (only left/right), as in the
   original: check in the original what the joystick/mouse does there (vertical input
   ignored, the pitch reading stays?) and match it.
2. **Horizontal steering is too fast**: the numbers beside the right arrow on the long
   range scanner row spin too fast while steering and it is hard to aim at the base. Measure
   the original's rate in the minefield (readings per frame with the same joystick input, and
   with the mouse patch's mask: crosshair off-centre = held direction; `m.dma = true`) and match
   it; if the original really is this fast, say so with the measured numbers.
3. **The restricted star band must stay when the mothership appears**: in the port the field
   switches to the full star field as soon as the base shows up; in the original the band
   stays (check until when: ring approach start, positioning, end?). Match it.
4. **The steering lock does not work as the original's**: with the side reading within +-3
   (and what the original's condition exactly is: `$C848`-like check on the long range
   readings, the distance `$2C43`, the depth), the original locks the direction; in the port
   it locks only when the base is directly in front (distance below 1?), not even at a
   reading of 0. Trace the original's lock condition and the unlock, and fix the port.

Tests: add/adjust tests in `js/test/run.js` ("game:" group) for each point against the
original (vertical input ignored, readings per frame, the band during the base's
appearance, the lock at +-3 and 0), late splits 0, OVRUN 0, all existing tests green:
`python c128-game/build.py`, `python js/build.py`, `python js/bundle.py`,
`node js/test/run.js` ("all checks passed"). Update docs. Final message: root causes,
fixes, what is verified, memory left, anything uncertain (the user tests in VICE x128).
