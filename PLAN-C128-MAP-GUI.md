# C128 port plan: map screen and GUI

Branch: `c128-map-gui`. Gun and shooting work is on the other machine, so this
branch stays out of the flight-kernel files (`c128-flight/flight.asm`).

Analysis source: a full 64 KB memory image rebuilt from `Sentinel-1351_v8.d64`
(same code path as `mouse/onefile.py: image()`), disassembled with
`mouse/tools/dis6502.py`. Everything below marked *(hyp)* is read from
disassembly only and has not been confirmed in VICE yet.

## What the code tells us about the map

- View state is `$B8`: 0 = cockpit, non-zero = another screen. The C= flag at
  `$FDEC` (set by the keyboard scan, or by the mouse patch's right button)
  is stored into `$B8` at `$FB5F` and starts the map.
- Real entry is `$FB48-$FBC0` (setup) and `$FBC1-$FC95` (per-frame loop).
  A near copy at `$4040-$40BF` is stale data and not the live code *(hyp)*.
- Map exit is `$FC59` (`$B8=0`), and the sector walk-up at `$FC96-$FDDE`
  rebuilds the cockpit.
- Map data: sector grid index from `$22D6` (X=`$92`, Y=`$93`), sector state in
  `$033C,X` and `$0378,X`, text screen near `$4400`, colour RAM `$D800`
  *(hyp, from the `$BA99` fills with Y=`$44` / `$D8`)*.
- Text is drawn by `JSR $9BE5` with a string pointer pushed on the stack
  (three PHA before the call, X/Y = column/row) and `$0921`.
- `$BA99` looks like "fill 32 pages with A starting at page Y" *(hyp)*. The
  mouse notes already say `$BA72` clears the `$6000-$7FFF` bitmap, so the
  family is the screen/bitmap clear helpers.

## Why the map first

| | Map screen | Flight GUI |
|---|---|---|
| Video mode | Text screen at `$4400` + colour RAM. VIC-IIe is identical to the C64 here. | Multicolor bitmap with five raster splits per frame. |
| Dependencies | Sector tables (`$033C`, `$0378`), text routine `$9BE5`, a few fills. | Whole raster IRQ chain, sprite multiplexing, bitmap layout. |
| Overlap with the gun work | None | High: HUD, crosshair and torpedoes sit in the same IRQ. |
| Input | Joystick / mouse directions (`MSYN` path from the C64 patch) | Same, plus flight steering. |

Recommendation: port the map first, flight GUI second.

## Steps

1. **Confirm the map facts in VICE 3.7** (`C:\C64\GTK3VICE-3.7-win64\bin\x128.exe`
   in C64 mode, or `x64sc`). Use `-remotemonitor`, press C=, then dump
   `$4400`, `$D800`, `$033C-$03B3`, `$0378`; watch `$B8`. Save PNGs as
   reference.
2. **Extract the map data and strings** into a standalone include
   (`c128-map/mapdata.inc`): sector tables, glyph set the map uses, strings
   called through `$9BE5`.
3. **Native C128 map test** (`c128-map/map.asm` + `build.py`, same shape as
   `c128-flight`, reusing `mouse/tools/asm.py`):
   BASIC 7 stub at `$1C01`, VIC-IIe text mode, copy the glyph set to a RAM
   charset (MMU config `$0E` as in the flight test), draw the grid from the
   tables, move a cursor with 1351 deltas and joystick.
4. **Port the text routine** (`$9BE5`) as a clean 6510 routine, no
   stack-pushed pointer, and keep the original string format.
5. **Hook point for the full game** later: the map loop must return the chosen
   sector and cursor state the same way `$FC96` expects (`$92/$93`).
6. **Then the flight GUI**: list what the cockpit draws outside the 3D view
   (HUD, crosshair, torpedo/laser sprites) and decide which parts go into the
   raster IRQ. Coordinate with the shooting branch first.


## Confirmed in VICE 3.7 (x64sc, skirmish, map open)

Reference files: `c128-map/ref/map-screen.png`, `c128-map/ref/map-state.txt`
(raw monitor dumps), `c128-map/ref/vice_monitor.py` (socket helper).

- **Map active:** `$B8=$0A`, `$B9=1`, `$88=0`, sector `$92/$93` = 4,2.
  The map is a *yellow 10-column grid of sectors* with ship icons in the
  playfield and the status header + cockpit panel unchanged.
- **Correction to the first draft:** the map is *not* a text screen. The
  raster table at `$0A42-$0A65` (5 splits) gives, for the top playfield,
  `$D011=$3B`, `$D016=$18`, `$D018=$18`: multicolor **bitmap at `$6000`**,
  video matrix `$4400`, colour RAM `$D800`, VIC bank 1 (`$DD00=$C6`).
  The map grid and icons are drawn into the same bitmap the flight view uses.
  The lower cockpit panel is text mode (`$D011=$1B`, `$D018=$50`: screen
  `$5400`, charset `$4000`). No sprites are enabled on the map (`$D015=0`).
- **Split table** (`$0A42` D011, `$0A47` D016, `$0A4C` border/background,
  `$0A51` D018, `$0A56` next raster line, `$0A5C/$0A61` next vector):
  D011 3B 3B 3B 1B 1B; D016 18 18 18 00 08; D018 18 18 18 50 50;
  next lines C2 E3 E9 38 4A. The D018 write is at `$0B03`.
- **Input to reach the map without a keyboard:** the game uses its own flag
  bytes. F5=`$FDE3`, SPACE=`$FDE5`, C= (map)=`$FDEC`, WASZ=`$FDE6-$FDE9`.
  Patching `$867F` to `LDA #1` makes the difficulty menu accept; nopping the
  flag clears in the scans (`$FDF5-$FE03`, `$FE38-$FE43`, `$FE70-$FE7B`)
  lets the monitor hold a key down.
- The game keeps running while the map is open (shields and time change),
  so freeze it at once with the monitor.

### Effect on the plan

- The map shares the **bitmap renderer** with the flight view. The C128
  flight test already has multicolor bitmap setup, the MMU `$0E` transition
  and the original pixel primitives, so the map port builds on
  `c128-flight/flight.asm` rather than a new text-mode harness.
- Step 3 becomes: native C128 test that draws the grid and icons into the
  `$6000` bitmap, with the `$4400` matrix / `$D800` colours, then adds the
  cursor.
- Overlap with the shooting branch is therefore larger than first thought:
  reuse the pixel primitives read-only and put new code in a separate file.


## Map routines traced (static, `$2000-$2400` region)

All addresses are in the C64 memory image; none are run on the C128 yet.

- **Geometry:** 10 columns x 6 rows = 60 sectors. Sector index =
  `row*10+col` (`$22D6`: X=col, Y=row -> X). Current sector `$92` (col) /
  `$93` (row); cursor target `$DF` / `$DE`; previous cursor `$20E2` / `$20E1`.
- **Cell positions:** column text cells `$2075` = 5,8,11,...,32;
  row text cells `$207F` = 5,7,9,11,13,15 (6th entry 12 is unused padding).
  Pixel centre used for the cursor box: x = col*4+4, y = row*8+4.
- **Sector data:** `$033C[idx]` = state (`$00` empty, `$80` special,
  `$FF` another special; small values 1-4 = types) and `$0378[idx]` =
  count/strength (0..9). `$20F1` clears `$033C-$03B3`.
- **Full redraw:** `$215C` (checks `$20F0`) walks idx 59..0 (`$20E3`):
  empty -> `$2355` erases the glyph (char `$60`); `$FF` -> `$22F0`
  (colour `$16`, glyph `$66`); `$80` -> `$232E` (colour `$18`, glyph
  `$67`); else `$2301` (colour from `$22FE` table, glyph `$68/$69/$6A`
  by count < 4 / < 7 / more). Then `$21BE` draws the cursor.
- **Glyph draw:** `JSR $0816` with A = glyph code, X = row cell, Y = col
  cell. Colour matrix cell is set by `$233C` (`$BA11` computes the
  `$4400` + `$D800` address). So icons are *character-cell glyphs inside
  the bitmap area*, not sprites.
- **Cursor box:** `$2384` (A = 0 erase, 1 erase old, 2 draw current-sector
  marker, 3 draw new). It plots a rectangle with the pixel routine at
  `$EF45` (pixel in `$36`/`$37`), selecting set vs erase colour tables by
  patching the operand at `$EF4E` (`$EE52` / `$EE56`). The box is 16 wide
  (x-3..x+12) and 16/17 tall (y-5..y+11).
- **Cursor input:** `$21C8` (rate limited by `$21C7`, reload 24 frames)
  reads the direction byte `$96` bits 0-3, wraps columns 0-9 and rows 0-5,
  redraws old/new cursor. This is the hook for mouse and joystick on the map.
- **Grid lines:** drawn from a command stream at `$2024-$2074` (0x80 starts
  a segment, then coordinates) -- decode next.
- **Open/close:** open = `$FB5A` -> `$99A1` (sets `$B8=1`, clears
  `$0A5A` split index) + `$223D` (SID blip). Exit = `$FC59` (`$B8=0`).
  Per-frame blink and update = `$2B14`.

### Port order for the map

1. `$EF45` pixel primitive + `$EE46/$EE52/$EE56` tables (already in
   `c128-flight`).
2. Cell address helper `$BA11`, glyph drawer `$0816`, and the glyph bitmaps
   (chars `$60-$6A`).
3. Grid line command stream `$2024` and its interpreter (find it).
4. Sector data tables + `$215C` redraw loop.
5. Cursor `$2384` + input `$21C8`.


- Icon routine and grid-drawing routine addresses (trace writes to
  `$6000-$7FFF` while the map opens).
- What `$033C` / `$0378` hold (they are filled with sector flags/counts:
  values 0..9, `$80`, `$FF`).

## Grid draw-in effect (traced with VICE 3.7 from an in-flight snapshot)

The grid is not a static line list. `$B094` (called every frame from the
main loop at `$102D`) runs an animated draw-in. `$B0F2-$B198` is the
per-frame step and `$B2D2` is `JMP $EF53` (plot a pixel with the layering rule).

- **Setup** (`$B0A2-$B0F1`, runs once while `$B075` is 0): `$B071=$11` (x of the
  left front = 17), `$B072=$8A` (x of the right front = 138), `$B07C=$10`,
  clears `$B077/$B078/$B07A/$B07B`, patches `$B2D3/$B2D4` to `$EF53`.
- **Each step:** both fronts move 2 px inward/outward and the 7 horizontal
  lines are plotted at the front x positions. Table `$B08A..$B090` =
  y = 35,51,67,83,99,115,131 (16 px apart = 2 cell rows). Plotting uses
  `$70` = x, `$71` = y, and a second pixel at y+1, so lines are 2 px thick.
- **Verticals:** table `$B07F..$B088` = x = 29,41,53,65,77,89,101,113,125,137
  (12 px apart = 3 cell columns); the first one is at x = 17 (`$B071` start).
  The step logic at `$B168-$B18B` compares the front with the table entry
  (`$B079` index) and skips past it when they match (hypothesis: the vertical
  is drawn by the remaining passes; not traced in detail).
- **Finish:** at x >= `$8B` it sets `$B07A=$81`; `$B198` onward runs a short
  sound blip (`$B26D`/`$B2BC`), writes `$20F0` = `$B093`, and the glyph redraw
  (`$215C`) puts the sector icons on top.
- **Finished bitmap** (`c128-map/ref/map-bitmap-6000.bin`,
  `map-screen-inflight.png`): 11 vertical lines (`$3C` bytes every 3rd cell
  column from col 4, full cell height) and 7 horizontal lines (`$FF` on
  scanlines 3 and 4 of every 2nd cell row starting at row 4). Each grid cell is
  12 px wide and 16 px tall (160x200 multicolor pixel units), 10 x 6 cells.

### Port consequence

A native C128 version does not need the sweep: draw the 11 vertical and
7 horizontal lines straight into the bitmap with the byte patterns above (or
reuse the sweep for the same look), then draw the sector icons on top.

### Icon layer is dynamic (from the user)

Icons are not drawn once: squadrons move between cells, a mothership blinks
when surrounded, and the planet at the centre rotates. The C128 port needs a
per-frame update layer: keep sector state, redraw only the changed cells
(`$215C` walks all 60 cells and the glyph drawer `$0816` already erases by
drawing glyph `$60`), and animate the blink and the planet from a frame
counter. `$2B14` is the original per-frame map blink/update hook.

### First C128 build: grid draw-in

`c128-map/` holds the native test (`map.asm`, `build.py`, `README.md`): the
sweep, the pause and the beeping sound are ported; the finished bitmap matches
the original on all 463 grid-only cells. The user ran it in x128 and confirmed
the grid effect looks as expected (sound not explicitly confirmed).

### Quirks found while debugging

- C= is read only on frames with `$A0 AND 3 = 2` (`$0B43-$0B59` picks
  `$FDEE` / `$FE36` / `$FE6E` by the frame counter), so a tap can be missed;
  hold the key about half a second. In VICE's default layout C= is Left Ctrl
  and Tab is CTRL.
- Snapshots: launch `x64sc` with `-sound -sounddev dummy`. `+sound` plus a
  snapshot that restores a SID engine produced "Cannot initialize SID Engine".
- Shield counter address not found yet (`$B6` was a false lead).

## Open questions

- Which charset does the map use: ROM, or a custom one in the game's RAM?
- Does the map use sprites (cursor, markers)? `$D028` is set to 6 at
  `$FCB5`, so sprite 7 colour is touched on exit.
- C128-native 40-col vs 80-col: this plan keeps 40 columns and the VIC-IIe.
- VICE 3.7 vs the 3.9 command in `c128-flight/README.md`: the flag
  `-controlport2device 3` should exist in both; verify.
