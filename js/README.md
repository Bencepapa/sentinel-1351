# Sentinel 128 JS: hybrid runtime and debugger

The browser version follows the C128 port instead of being a second codebase.
The unchanged binaries run on a JS 6502 core: the native C128 programs
(cockpit, map, flight) and the full patched C64 game (`Sentinel-1351_v8.prg`).
The chips around them are replaced by JS:

| Part | How it is handled |
|---|---|
| 8502 | `src/cpu6502.js`, all documented opcodes; passes Klaus Dormann's 6502 functional test |
| Models | `c128`: MMU configuration register at `$FF00`/`$D500`, VDC, `$D030` 2 MHz. `c64`: memory map from the processor port `$00`/`$01` (the game runs with `$01=$2D`, RAM under the KERNAL) |
| IRQ | raster compare (`$D012`/`$D011`, `$D019` latch and acknowledge, `$D01A` mask) |
| VIC-II / VIC-IIe | `src/video.js`: text, hires and multicolor bitmap, sprites with priority, bank from CIA2; drawn line by line from register and sprite-pointer writes logged with their raster line and cycle, so raster splits work (the cockpit's HUD / bitmap / strip, colour bars, sprites reused lower down); sprite-sprite and sprite-background collisions (`$D01E`/`$D01F`), rendered up to the current line when the program reads them |
| VDC | register file at `$D600/$D601`, update address, data, block fill/copy, 80x25 text with attributes |
| SID | `src/audio.js`: register writes replayed in an AudioWorklet at their cycle in the frame; voice 3 noise readable at `$D41B` |
| CIA1 | keyboard matrix, joystick in port 2 |
| 1351 | proportional mode on the port 2 pots (pointer lock on desktop, drag on touch) |
| ROMs | none: an original font (`src/font.js`) stands in for the character ROM and the VDC character set |

Timing is a PAL frame of 312 lines x 63 cycles; `$D012` follows the cycle
count, so the tests' raster waits work unchanged. `$D030` bit 0 doubles the
cycles per frame (C128). Bad lines and sprite DMA do not steal cycles yet, so
the CPU is a little faster than on the real machine.

## Debugger

The page is a workbench: the machine on the left, the debugger on the right.

- **Run / Pause / Step / Frame / +50**, speed 1x-4x or Max. A pause can land in
  the middle of a frame: the screen shows the lines drawn so far and a red line
  at the beam. The C64 game unpacks at full speed until it reaches `GAMEENTRY`.
- **Breakpoints**: click a line in the CPU view, or `bk LABEL` in the monitor.
- **Write watches**: `w ADDR [END]` stops right after the instruction that
  writes there, showing the old and new value and the writer's PC.
- **Watches**: values with a 5-second history graph; click a value to change
  it, tick *freeze* to make the program's writes to it be ignored.
- **Cheats** and **events** per program (`src/profiles.js`). For the C64 game:
  invulnerable (skips `HIT`), freeze shields / energy / protons, planet
  survives; events for game over, ship hit, system destroyed, energy out and
  torpedo launch, each can log and/or pause.
- **Save states**: 4 slots, kept in the browser (localStorage); Export / Import
  as a file. A state can be saved in the middle of a frame; loading it and
  running gives the same frames again (checked by the tests).
- **Monitor** (VICE-like): `help` lists the commands: `r`, `d`, `m`, `>`, `bk`,
  `del`, `w`, `uw`, `fr`, `uf`, `show`, `tr`, `sk`, `z`, `f`, `g`, `save`, `load`, `l`.
  Addresses are labels (`SHIELDS`, `HIT+3`) or hex (`$844F`, `844F`).

### C64 game labels

`js/c64-symbols.txt` names the game's routines and variables (from
`MOUSE-SUPPORT.md`, `MAP-LOGIC.md`, `c128-gui/README.md`, and new ones found
with the debugger by putting write watches on the HUD digits):

| Label | Address | What |
|---|---|---|
| `SHIELDS` | `$844F` | shields (binary), drawn by `SHOWSHIELDS` `$8487` |
| `PROTONS` | `$8450` | proton torpedoes, drawn by `SHOWPROTONS` `$849E` |
| `ENERGY` | `$543E` | energy has no variable: the four HUD digits count down (`ENERGYTICK` `$F886`, `ENERGYOUT` `$F8E0`) |
| `SYSTEMS` | `$39-$40` | eight ship-system counters, set per difficulty by `SHIPINIT` `$8451` |
| `HIT` | `$84D7` | the ship is hit: a random system -1 (message at `SYSDOWN` when one reaches 0), then shields -1 |
| `SHIELDSLOST` / `PLANETLOST` | `$8300` / `$F431` | game-over flags, checked by `GAMEOVERCHK` `$99F3` |
| `GAMEOVER` | `$8869` | the game-over sequence |

Add labels to the file and run `python js/build.py`; the monitor, the CPU view
and the profiles use them at once.

## Hooks: moving routines to JS one at a time

`js/build.py` exports each test's symbol table, so JS hooks routines by
label, never by address:

```js
hooks.trace('DRAWCELL');                    // calls per frame
hooks.port('PLOTPIX', plotpix, 'verify');   // run the JS port AND the 6502 original,
                                            // compare A/X/Y and every byte written
hooks.port('PLOTPIX', plotpix, 'replace');  // run only the JS port
```

`src/native.js` has the first ports: `PLOTPIX` (the protected plot, `$EF53`),
`ERASEPIX` (`$EEE6`) and `MOVCHK` (1351 delta). In verify mode, every call is
checked against the original.

## Build and test

```text
python js/build.py          # rebuild the C128 tests, export PRGs + symbols to js/programs.js
python js/bundle.py         # js/index.html (separate scripts) and js/dist/sentinel.html (one file)
node js/test/run.js         # headless checks, PNG snapshots in js/test/out
```

The headless checks run the four programs (C64 game, cockpit, map, flight) with the ports in verify mode. They compare
the map's grid cells with the original game's bitmap (`c128-map/ref`), and
exercise the cursor, fast ticks, the planet sprite, the cockpit crosshair and vertical-blank budget (`OVRUN`), and the exits. For the C64 game they start a game and test the debugger: breakpoints, single steps, write watches, save / load in the middle of a frame (same memory 60 frames later), the cheats on a directly called `HIT`, and the game-over event.

`index.html` needs a local web server (`python -m http.server` in `js/`);
`dist/sentinel.html` opens directly.

## Keeping it in sync

`.githooks/pre-commit` rebuilds the embedded PRGs (`js/build.py`, `js/bundle.py`) and adds the
results to the commit whenever C128 sources or the JS build change. Enable it once per clone:

```text
git config core.hooksPath .githooks
```

