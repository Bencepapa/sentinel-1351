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

### Still open

- Icon routine and grid-drawing routine addresses (trace writes to
  `$6000-$7FFF` while the map opens).
- What `$033C` / `$0378` hold (they are filled with sector flags/counts:
  values 0..9, `$80`, `$FF`).

## Open questions

- Which charset does the map use: ROM, or a custom one in the game's RAM?
- Does the map use sprites (cursor, markers)? `$D028` is set to 6 at
  `$FCB5`, so sprite 7 colour is touched on exit.
- C128-native 40-col vs 80-col: this plan keeps 40 columns and the VIC-IIe.
- VICE 3.7 vs the 3.9 command in `c128-flight/README.md`: the flag
  `-controlport2device 3` should exist in both; verify.
