# Task: the mothership approach in the C128 Sentinel port

You are working in `C:\dev\c64\sentinel`: a native Commodore 128 port of Synapse's
*Sentinel* (C64, 1984), built from 6502 sources. Read `README.md`,
`c128-game/README.md`, `PLAN-C128-COCKPIT.md` (above all "Mothership sequences"
and "Frame budget"), `MAP-LOGIC.md` and `FINDINGS.md` first.

## Goal (this task only)

Port what happens when the ship arrives in a **mothership sector** (the map's
STATE `$80` = enemy/orange, `$FF` = friendly/blue; today `SECTORIN` in
`c128-game/game.asm` treats both as empty: "a mothership: not ported yet"):

1. Entering the sector: what the original does at `$FBFB` / `$FC77` (messages,
   sounds, flags; `$E2` marks an enemy mothership).
2. **The approach**: the loop at `$90F3`. Every 128 frames the radius `$43` grows
   and the mothership is drawn as concentric "strange circles" by `$3635` /
   `$364C` (a circle routine that takes a centre and a radius; the port already
   has a fixed-centre version, `CIRCLE` / `CIRCSTEP` in
   `c128-gui/cockpit/cockpit.asm`, and a free-centre one for the torpedo's
   rings, `TBLAST` / `TPLOT8` in `game.asm`). The approach ends when the radius
   reaches `$22`.
3. What ends the approach in each case, as far as the code shows it (do NOT port
   the enemy torpedo, the mines, the tractor beam or the repair yet; note what
   you find about them in `PLAN-C128-COCKPIT.md`).

Leave the minefield (`$71-$7C`, `$CCDF` / `$CD27`), the enemy mothership's torpedo
(`$CF01` / `$CF04`, 31 frames from `$A000`, the same data as our torpedo's
`TORPA`), destroying a mothership and the friendly repair (`$932D`) for later
tasks.

## How to read the original

The JS emulator runs the patched C64 game (`Sentinel-1351_v10.prg`) and the C128
programs. Scripts in Node can boot it and disassemble; see `js/test/run.js` for
`boot`, `run`, `callAt`, `m.ram`, `m.vicLog` / `m.sidLog` (register writes per
frame with raster line and cycle), `m.setBreak`, `m.wpAt` (write watchpoints),
`m.setKey(row, col, down)`, `m.mouse`, `m.moveMouse`. `SentinelDisasm.one` (in
`js/src`) disassembles. **Set `m.dma = true`** whenever you measure timing: it
models the VIC's stolen cycles, without it every rate is too fast. Measure rates
in frames on the original before porting them (the original's loops are not tied
to the frame; the port is frame-locked: see "Speeds" in the plan).

## The port's constraints (important)

- **Memory is full** in the fixed chunks: `$5300-$5FFF` (glue), `$C000-$CFFF`
  (HIGH) and the map's chunk up to `$C000`. New code goes in the **`$E000` chunk**
  (`* = $E000` at the end of `game.asm`, code up to `$E9FF`). Its image is packed
  by `c128-game/build.py` (`lz_pack`) into the 3D view's bitmap and unpacked by
  `GAMEINIT` (`GUNPACK`); data tables live above `$EA00` (see the constants there,
  they end at `$FEFF`). If the code passes `$EA00`, move the data constants up
  and the `TSH1` copy in `GINIT2` with them (that has been done twice already).
- **Timing is tight.** The frame is a polled raster schedule (splits at lines
  ~56, 76, 194, 233, 242). Do not change the size or position of code in the
  glue or the cockpit chunks before routines that are already there: a shift of
  a few bytes moved page crossings and broke the fight's split test before. Add
  code in `$E000`, reach it through existing hooks or **self-modifying JSR
  slots** (as `sprcj`, `shpj`, `torpj`), and keep the cost for flight and fights
  at zero when your feature is idle.
- Heavy work (circles, colour fills, bitmap clears) must run in pieces with a
  raster check and continue in the next frame (see `TLATE`, `TDEC`, `TCOL`,
  `HSTLATE`): the vertical blank (2 MHz, lines 251-47) has little time left in a
  fight.
- Build: `python c128-game/build.py`, then `python js/build.py` and
  `python js/bundle.py` (the browser page and `js/programs.js`).
- Labels in `game.asm` use a `g_xx` prefix per routine; the assembler
  (`mouse/tools/asm.py`) has no `label+n` expressions for forward labels and no
  long branches: use `JMP` for far targets.

## Tests

- `node js/test/run.js` must end with "all checks passed". Watch above all:
  "in a fight the splits' colours change off the screen", "with the cursor test
  on every frame has its top split", "no frame overran" and the hyperspace and
  approach checks. Add checks for what you port (entering a mothership sector, the
  rings growing at the original's rate, no overrun meanwhile).
- Check real timing with `m.dma = true`: count frames with late split writes
  (`$D020` / `$D021` at lines 50-76 or 230-245, cycle 16-55) and `OVRUN`.

## Deliverables

- The code (`c128-game/game.asm`, `c128-game/build.py` if needed), the rebuilt
  `c128-game/sentinel-c128-game.prg`, `js/programs.js`, `js/dist/sentinel.html`.
- Notes: what the original does (addresses, rates) in `PLAN-C128-COCKPIT.md`
  ("Mothership sequences"), a short user-facing line in `c128-game/README.md`.
- A summary at the end: what is ported, what differs from the original, what is
  left, and the test results.
- Do **not** commit or push; the user tests in VICE x128 first.
