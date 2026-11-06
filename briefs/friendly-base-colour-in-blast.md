# Task: the friendly base keeps its blue colour in a proton blast (GitHub issue #16)

Read first: `PLAN-C128-COCKPIT.md` "Status" and "Handing the work on" (all its rules: no
code moved in the glue/cockpit/map, new code in `$E000` through the existing slots, every
bound check in `build.py` kept; memory is 0 bytes high code, 66 packed, 1 glue - prefer
changing existing code), `c128-game/README.md`, the plan's "Mothership sequences"
(proton rule and phase: `MSBLAST`, `MSFLASH`).

## Problem

Attacking a friendly base with a proton while it is invulnerable (hidden phase 0, a miss):
in the C128 game the base turns orange for the blast's duration, probably because
`MSFLASH` flashes / restores colour RAM with the explosion's orange. In the original the
base keeps its blue colour.

## What to do

1. In the original (JS C64 machine, `m.dma = true`, call routines directly, `$BB81`,
   `$BAD1` = 0) record the 3D view's colour RAM / border / background frame by frame during
   a proton miss on a friendly base (hidden phase) and on an enemy base (both phases),
   and a hit; note exactly what changes.
2. Make the port match (`MSFLASH` / `MSBLAST`), for friendly and enemy bases, miss and hit.
3. Tests in `js/test/run.js` ("game:" group): the base's colours frame by frame vs the
   original during the blast, late splits 0, OVRUN 0; all existing tests green:
   `python c128-game/build.py`, `python js/build.py`, `python js/bundle.py`,
   `node js/test/run.js` ("all checks passed").
4. Update docs if behaviour changes. Do NOT commit or push. Final message: root cause, fix,
   what is verified, memory left, anything uncertain (the user tests in VICE x128).
