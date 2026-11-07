# Task: the minefield before the motherships (the "raster tunnel")

Read first: `PLAN-C128-COCKPIT.md` "Status" and "Handing the work on" (all its rules: no code
moved in the glue `$5300`, the cockpit's chunks or the map; new code through the existing
slots; every bound check in `build.py` kept; anything loaded must lie inside what the C128
KERNAL LOAD writes; tests count late splits and OVRUN, both must stay 0), the plan's
"Mothership sequences" and its "Memory" notes, and `c128-game/README.md` (the memory map
the last task wrote). The memory rearrangement freed **3,299 bytes at `$EA16-$F6F8`**,
usable in every gameplay mode: this task is what it was made for.
`briefs/mothership-repair.md` shows the expected form of work.

## Goal

Port the original's minefield (item 1 of the Status list): the mines `$71-$7C` with their
code `$CCDF` / `$CD27`, around the motherships (in the original the minefield comes before
the base's ring approach / in the mothership sector; find exactly when and where it is
entered and left, how the ship is hit by a mine - `$84D7`, `SHIPHIT` - and the sounds,
flash, scoring, energy, and what ends it). The user's observations of the original (the
"raster tunnel"): the stars appear only in a horizontal band; the star field cannot be
steered once the right direction is locked; mines can stay stuck on the screen (an original
bug: decide with the user's wish for faithfulness - keep it only if it is harmless, and
say what you chose).

1. Trace it in the original (JS C64 machine, `m.dma = true`, call routines directly, the
   mothership sector entry `$FCE1` / `$FD3B`, `$8C3F` / `$8C44` -> `$8D1C` -> `$9054`;
   note the preliminary positioning phase is already ported, see the plan): what the
   minefield does frame by frame, mine movement and sizes (shapes `$71-$7C`), sprites used,
   raster effect / star band, steering lock, collisions and damage, and how it hands over
   to the ring approach.
2. Port it faithfully with the cost-when-idle rule (zero in flight and fights), using the
   freed `$EA16-$F6F8` area (and packed streams unpacked at init if needed). Sprite shapes
   must not overwrite any asset region (the earlier VICE noise bug); keep the C128 KERNAL
   LOAD range rule.
3. Tests in `js/test/run.js` ("game:" group) comparing the port with the original (mine
   sprite positions/shapes, hits, star band, timing in frames with DMA), split timing (late
   writes 0, OVRUN 0), all existing tests green: `python c128-game/build.py`,
   `python js/build.py`, `python js/bundle.py`, `node js/test/run.js` ("all checks passed").
4. Update `c128-game/README.md` and the plan's Status. Do NOT commit or push. Final
   message: what the original does, what changed, what is verified, memory left, anything
   uncertain (the user tests in VICE x128). If the work is too big for one pass, deliver it
   in working stages (e.g. the mines and damage first, the raster tunnel after) and say
   which stage is done.
