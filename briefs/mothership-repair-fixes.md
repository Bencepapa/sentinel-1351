# Fixes after the user's VICE x128 test of the friendly repair sequence

Follow-up to `briefs/mothership-repair.md` (same constraints, tests, no commit /
push, overwrite `chatgpt_handover.md` at the end). The attached screenshots, in
order:

1. port: a fight after docking; the radar's long range tracker shows noise
   (the cyan block in the radar box);
2. port: noise on the left gun while shooting;
3. port: the same noise later on the right gun too;
4. port: the tractor beam stops short of the guns (clipped at the cockpit);
5. and 6. the **C64 original**: the beam reaches all the way down to the guns;
7. left: the port's repair screen; right: the **C64 original**'s;
8. the **C64 original** during a repair: the damaged system's row flashes red,
   the computer's coloured blocks below the list.

## What to fix (the user's findings)

1. **The beam must reach the guns**, as in the original (screenshots 5-6): do not
   clip it at y >= 144. Draw over the cockpit art where the original does and
   restore the art afterwards (or whatever the original does there: check what
   remains after the sequence), keeping the raster timing.
2. **The repair screen's layout** is wrong (no margin). In the original
   (screenshots 7 right, 8) the radar is removed, the list starts **one row lower**
   than in the port (the original's rows 4, 6, ... 18), there is a left margin,
   and the results column sits further left; match the original's columns and
   rows exactly (the original's text routine and positions: `$92E3` onward).
   Remove the radar box/cockpit art the way the original does during the report.
3. **The computer's coloured blocks are missing**: two rows of flashing
   random-colour blocks below the list (the original's `$9510` scan, screenshot
   8). Port them, flashing as in the original (rate measured with `m.dma`).
4. **The damaged system's repair sound is missing.** Port the sound the original
   plays while a damaged system is scanned/repaired (with the flashing red row).
5. **Leaving the repair screen**: the mothership shows for a moment in green, then
   it is erased row by row quickly. It must not reappear: go to the map the way
   the original does (check what the original shows between the report and the
   map), with no stale bitmap/colour visible.
6. **After docking, the next fight shows noise** in the radar's long range tracker
   (screenshot 1) and on **both guns while shooting** (screenshots 2-3): the
   temporary font copy (or the report's text/colour writes) overwrites sprite
   shapes or other data that are not restored (the radar/scan sprites, the gun
   or shot shapes, `TSHOT`, the shot slots of bitmap rows 23-24, ...). Find
   exactly what is overwritten (compare memory before docking and after the
   map returns) and restore it, or use memory that nothing else needs. Add a
   test that compares all sprite shapes, the cockpit's master copies and the
   colour data before and after a complete docking.

Notes from the user about the original (for the plan; not to port now): during
the minefield the original shows stars only in a horizontal band; the mines stick
on the screen (a bug) and the star field cannot be moved then (it is locked
anyway once the right direction is found in the minefield).

Memory is almost full ($E000 code: 4 bytes, packed image: 76 bytes): rearrange
as needed (the build's bound checks must stay), and report what is left.
