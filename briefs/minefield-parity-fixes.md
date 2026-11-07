# Fixes: the C128 game vs the C64 in the minefield and at the base (user's comparison)

Follow-up to `briefs/mothership-minefield.md` and `briefs/mothership-minefield-fixes.md` (same
rules; read `c128-game/mines.asm`, `PLAN-C128-COCKPIT.md` "Handing the work on"; do NOT commit or
push; the uncommitted work of the earlier stages is in the working tree). The user compared the
C128 game with the C64 original in the JS version and found (the C64 is the reference). The
steering lock at side reading 0 is OK in both, keep it. Fix the rest, measuring each in the
original (JS C64 machine, `m.dma = true`, saved states/calls as the plan describes):

1. **The crosshair/cursor is confined in the minefield**: on the C64 it can move only about
   50 pixels up and down (maybe less) from the centre. The port lets it go further (the
   previous fix only stopped the pitch steering). Measure the original's limit (both
   directions, mouse and joystick) and match it.
2. **ENTERING BASE SECTOR** (friendly base) / the enemy entry message: on arrival the C128
   shows it for a moment, then it vanishes at once and the arrows (long range row) take over
   and flash yellow/red for a while. On the C64 the message text stays up and *it* flashes.
   Trace the original's message line / flashing and fix the port (check the enemy base's
   message, too).
3. **At the start of every hyperspace jump, whatever was on the radar (fighters) leaves the
   radar quickly downwards**, as if left behind at high speed. Check in the original what the
   radar shows at the start of a jump (the long range switch, readings) and make the port
   match: report if the original does the same and what it looks like.
4. **At the mothership steering is allowed again in the C128 (the star field follows the
   cursor); the C64 locks it there too.** Find when the original unlocks (never in the
   mothership phases? only after the base's end?) and match it.
5. **No firing at the mothership and no proton torpedo in the minefield on the C64.** Check the
   original's exact conditions (the phasor at the base, SPACE / both buttons in the minefield
   and in the other mothership phases) and match them in the port (a click for a refused torpedo?
   what the original does with the protons count).

Tests: per point against the original (cursor limits, the message and its flashing frame by
frame, the radar at the jump's start, steering lock through the phases, fire / torpedo
conditions), late splits 0, OVRUN 0, all existing tests green: `python c128-game/build.py`,
`python js/build.py`, `python js/bundle.py`, `node js/test/run.js` ("all checks passed").
Update docs. Final message: root causes, fixes, what is verified, memory left, anything
uncertain (the user tests in VICE x128).
