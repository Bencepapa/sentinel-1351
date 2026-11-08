# Task: the minefield's raster tunnel (coloured background bands)

Read first: `PLAN-C128-COCKPIT.md` "Status" and "Handing the work on" (all its rules: no code
moved in the glue/cockpit/map; new code through existing slots; every bound check in
`build.py` kept; load-range rule; tests count late splits and OVRUN, both must stay 0),
`c128-game/README.md`, `c128-game/mines.asm`, and the earlier minefield briefs. **Memory is
very tight now: 1 resident byte, 246 packed-load bytes, 1 glue byte**: a rearrangement (more
packed streams, overlays, shared tables, generated tables) will probably be needed; the
plan's "Memory" notes and the README's memory map show the options.

## Goal

In the original's minefield (the stretch before a mothership's ring approach) the 3D view's
**background colour changes by raster interrupt, making coloured horizontal bands** above and
below the middle of the view (the "raster tunnel", see `briefs/img-tunnel/c64-tunnel.png`:
olive and purple bands with grey lines, the middle strip black, the bands moving outward
toward the top and the bottom of the view, as if flying through a tunnel). The C128 game has
the mines, the star band, the steering lock and the firing rules, but not these bands.
Port them. The save state `briefs/ref/c64-minefield.state.json` (C64 original, v10 patch) is
saved exactly at this point; load it with `m.loadState(m.stateFromText(...))`.

1. In the original (JS C64 machine, `m.dma = true`) trace the raster effect: the raster
   interrupt lines, the colours written to `$D021` (and `$D020` if used), their order, how
   they move frame by frame, which code does it (find it from the state; add labels to
   `js/c64-symbols.txt`), how it starts at the minefield's beginning and when/how it ends
   (when the ring approach starts? at arrival?), and its cost. `m.vicLog` per frame helps.
2. Port it into the C128 game's raster schedule (the cockpit's splits, `TLATE`, the free
   lines 78-194; the VIC-IIe's bad lines/sprite DMA steal cycles: use `m.dma`; VICE x128 is
   the reference): zero cost outside the minefield, no late split writes (`$D020` / `$D021`
   at lines 50-76 / 230-245, cycles 16-55) or OVRUN. The bands must stay behind the stars,
   mines and cockpit art exactly as in the original (check the colour/priority interplay with
   the bitmap's background pixels).
3. Tests in `js/test/run.js` ("game:" group) comparing the port with the original: per frame
   the `$D021` writes by raster line against the C64 trace (a few lines of drift allowed if
   the C128's line timing differs, say how much), start and end, late splits 0, OVRUN 0, all
   existing tests green: `python c128-game/build.py`, `python js/build.py`,
   `python js/bundle.py`, `node js/test/run.js` ("all checks passed").
4. Update docs. Do NOT commit or push. Final message: what the original does, what changed,
   what is verified, memory left, anything uncertain (the user tests in VICE x128).

## Note: this task was interrupted (the machine was shut down)

A previous run of this task left unfinished, uncommitted work in the tree: changes in
`c128-game/mines.asm`, `c128-game/build.py`, `js/test/run.js` and the generated PRG / bundle,
plus temporary scripts `briefs/adjust-tunnel*.py` (probably experiments with the band tables).
Read `git status` / `git diff` first, decide what is worth keeping, continue from there (do not
start over blindly), delete the temporary scripts when done, and make sure the final tree
builds and `node js/test/run.js` ends with "all checks passed".
