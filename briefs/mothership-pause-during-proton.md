# Task: the base must not pause while the player's proton flies (GitHub issue #15)

Read first: `PLAN-C128-COCKPIT.md` "Status" and "Handing the work on" (all its rules: no
code moved in the glue/cockpit/map, new code in `$E000` through the existing slots, every
bound check in `build.py` kept; memory is 0 bytes high code, 64 packed, 1 glue - a fix
should rather change or reuse existing code than add), `c128-game/README.md`, and
`gh issue view 15 --repo Bencepapa/sentinel-1351`.

## Problem

In the C128 game the enemy (and friendly) base's ring approach stands still while the
player's proton torpedo is in flight. In the C64 original it keeps growing and flickering.
Reference: `briefs/ref/c64-proton-in-flight-mothership.state.json` (a C64 save state with
the player's torpedo in flight in a mothership sector; `m.loadState(m.stateFromText(...))`).

## What to do

1. In the original (JS C64 machine, `m.dma = true`) record, per frame during the torpedo's
   flight, the ring radius / phase counters (`$90F3`, `$953F`, `$953E`, `$8C3E`, see the
   plan's "Mothership sequences") and what else keeps running (flicker, sounds, rings).
2. In the port find why the base stands still (`MSPSTEP`, `MSSTEP`, `MSVB`, `MSPAINT`,
   `MSBLAST`, `GTORP`, `TSTEP`: probably the heavy work yields to the torpedo's unpacking
   in the same blank, or a state flag blocks `MSSTEP`) and fix it so the base's timeline
   (radius, phase, flicker timing, the arrival at the ring end) matches the original during
   the flight. A proton that hits still ends the approach as now.
3. Tests in `js/test/run.js` ("game:" group): radius/phase per frame during a flight vs the
   original (a few frames of drift allowed as in the existing tests), late splits 0, OVRUN 0,
   all existing tests green: `python c128-game/build.py`, `python js/build.py`,
   `python js/bundle.py`, `node js/test/run.js` ("all checks passed").
4. Update the README / plan if behaviour changes. Do NOT commit or push. Final message: root
   cause, fix, what is verified, memory left, anything uncertain (the user tests in VICE x128).
