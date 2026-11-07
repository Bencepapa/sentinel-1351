# Task: rearrange the C128 game's memory to make room for the minefield (raster tunnel)

Read first: `PLAN-C128-COCKPIT.md` "Status" and "Handing the work on" (rules: no code moved
in the glue `$5300`, the cockpit's chunks or the map, because a few bytes shift page
crossings and break the fight's split timing; new code in the `$E000` chunk through the
existing slots; every bound check in `build.py` kept; anything loaded must lie inside
what the C128 KERNAL LOAD writes - a tail at `$FF05` once froze the game), the "Mothership
sequences" part of the plan, and `c128-game/README.md` ("How it is built").

## Problem

The next feature is the minefield before the motherships (mines `$71-$7C`, `$CCDF` /
`$CD27`, with the star band / "raster tunnel"; the user's observations are in the plan's
Status). It will need probably 2-3 KB of new code and data. Free now: `$E000` code 0 bytes
(to TORPA), the packed image 68 bytes before the cockpit art (`$7680`), the glue 1 byte.

## Goal: free at least 3 KB (more is better) without changing behaviour

This task is only the rearrangement, no new feature. Ideas (choose by measuring, then
explain): more data and cold code in further packed streams (`lz_pack`) unpacked at init
into space that is free afterwards or staged beneath I/O (`$D000-$DFFF`, read with
MMU `$3F` during init only, as STR2Y / the positioning tail already are); sharing tables
with the cockpit or the map; generating data in code (shape masters, tables); moving the
rarely used sequences (the repair report text, the mothership view jobs) into a
swappable overlay unpacked on demand into a scratch area that flight and fights do not
use (check that the load/unpack time fits between frames or happens behind a blanked
screen or the map); the `TORPA` stream (31 frames) and other big masters packed tighter.
Start by producing a memory map of everything from `$1C01` to `$FFF9` (code, tables,
masters, buffers, what is live at run time in flight / in a fight / in a mothership
sequence / in hyperspace) and put it in `c128-game/README.md` or the plan, so the rest of
the work can see what is free in each mode.

## Constraints and tests

- Behaviour must stay identical: all existing tests green (`python c128-game/build.py`,
  `python js/build.py`, `python js/bundle.py`, `node js/test/run.js`, "all checks passed"),
  split timing late writes 0 and OVRUN 0, no symbol below `$E000` moved (compare before and
  after), no sprite asset region overwritten, nothing needed at load time outside the
  KERNAL LOAD range. Add tests for anything new (e.g. an overlay is unpacked correctly and
  restored; the free area is really unused: fill it with a pattern and run the existing
  scenarios, they must not change).
- Update `c128-game/README.md` and the plan's Status / "Handing the work on" memory notes.
  Do NOT commit or push. Final message: the memory map summary, what was freed and where
  (addresses, sizes, and in which modes it is usable), what is verified, risks (the user
  tests in VICE x128).
