# Sentinel 128 JS: hybrid runtime and debugger

The browser version follows the C128 port instead of being a second codebase.
The unchanged binaries run on a JS 6502 core: the native C128 programs
(the C128 game, cockpit, map, flight) and the full patched C64 game (`Sentinel-1351_v10.prg`).
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
cycles per frame (C128). Bad lines and sprite DMA do not steal cycles on the page, so
the CPU is faster than on the real machine, and the original's main loop rates with it.
`m.dma = true` adds them (43 cycles on a bad line, 3 + 2 per sprite on a sprite line);
the timing tests use it, and its rates matched what VICE shows.

The page links the running program's PRG for download (from the bytes it embeds) and the
GitHub repository.

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

## The itch.io page

A second, minimal page for [itch.io](https://itch.io/docs/creators/html5): only the game canvas, no debugger,
no text, no links. A C64-style selector (`C64 - HI 000000` / `C128 - HI 000000`, mouse, touch, up / down + Enter,
Right Ctrl, or Numpad 0, or 1 / 2 directly) starts the C64 original with the 1351 patch (`c64game`, unpacked at full speed first) or the C128 port
(`game`), at normal speed. Source: `itch-page.html` (page + CSS), `src/itch.js` (app), `src/hiscore.js` (score
logic); `itch.py` builds it. It works inside itch's iframe (sizes to the frame, no popups, audio starts on the first
gesture, keyboard focus on click) and adds no full-screen button (itch has its own).

```text
python js/itch.py           # js/dist/itch.html (one file, ~235 KB) and js/dist/itch.zip (index.html inside)
python js/itch.py --dev     # also js/itch-dev.html, loading src/*.js (serve js/ with a static server)
```

Upload `js/dist/itch.zip` as an HTML project ("This file will be played in the browser"); a 960 x 680 viewport
fits the picture (384:272), tick "Mobile friendly" if wanted. `itch.py` embeds only the two programs and the labels the
page uses from `programs.js` (run `python js/build.py` first when the programs changed; the pre-commit hook does both).

| Key | Action |
|---|---|
| M | mute on / off (overlay `MUTE ON` / `MUTE OFF`) |
| Alt+W | 5x speed on / off (overlay `>>>>>` while active) |
| Alt+Q | 2x speed on / off (overlay `>>`) |
| Ctrl+S / Ctrl+L | quick save / load, one slot per program (`localStorage`; kept in memory for the visit where the browser gives no storage; a save only loads into the build that made it) |
| Ctrl+R | back to the selector (overlay `RESET`) |

The browser's own meaning of these keys is cancelled, and the game does not see them (Alt is the C= key that opens the
map: it is held back for 120 ms, so Alt+W / Alt+Q do not open it; a tap still gives a C= press). Everything else is as on
the debugger page. Arrows steer, Right Ctrl or Numpad 0 fires, Left Alt opens the map, and Space launches a proton.
Mouse motion aims, the left button fires, the right button opens the map, and pressing both launches a proton.
In the C64 game, pointer movement or a mouse button switches to mouse mode, and a fresh arrow or Fire press
switches back to joystick mode. The page can capture the pointer on click and shows `ESC - RELEASE MOUSE` on capture.
At 2x / 5x the sound is off (the SID log is only played at normal speed).

**Overlay.** Big white pixel text with a glow, drawn on a canvas over the game (not part of the emulated screen), shown 3 s then
fading: top left `MUTE ON/OFF`, `SAVED`, `LOADED`, `NO SAVE`, `RESET`; top left (plain, no glow) `ESC - RELEASE MOUSE`;
upper right `JOYSTICK` / `MOUSE` in the C64 game; bottom `>>` / `>>>>>`
while the speed is up; in the black strip at the very top at a game over (death or victory, either program) `SCORE nnnnnn` (with `NEW HI` when it beats the stored best); the game's own end screen shows the rank and class. Sizes and times: `CONFIG` at the top of `src/itch.js`.

**Touch.** Touch is detected by a coarse primary pointer or the first touch. FIRE (left button), MAP (right) and TORP (both) buttons
appear while a game runs (their CSS is one block at the top of `itch-page.html`, "TOUCH CONTROLS"); dragging anywhere else aims
the crosshair. The selector takes taps.

**Score.** The original has no point score: its end screen shows a rank name and a class digit (the results of its rating routine
at `$F440`, the C128 port's `ENDRATING`) and the counters. The page leaves those to the game and adds a point score built from what the
game counts (`score()` in `src/hiscore.js`):

```text
points = 100 * enemy motherships destroyed          (0-4: the orange corner cells of the map, state other than $80)
       + 10 * (difficulty + 1) * enemy fighters destroyed     (difficulty 0-4 = 10, 20, 30, 40, 50 a kill)
  only after a victory:
       + 100 * friendly bases still standing         (0-4: the blue cells, state $FF; the end screen's BASE STATIONS)
       + max(0, 6000 - elapsed game seconds)           (6000 s = 100 game minutes)
```

The motherships and fighters count always; the bases left and the time left only when the game is won (a loss earns neither: dying at once
with nothing done scores 0).
It is capped at 999999 and shown as `SCORE nnnnnn`. Where the numbers come from: the fighters are the original's kill counter `$F434` (16 bit;
it counts from 1, so one is subtracted; the port's `KILLS`, and `ENDKILLS` = `KILLS` + 1), the map is `$033C` (the port's `M_STATE`, 60 cells,
corners `0 9 50 59` enemy and `12 17 42 47` friendly), the difficulty is `$E0` (the port's `DIFF`).
Both HUD clocks display `TIME MM:SS`, blink the colon every 30 frames, and advance once per 60 gameplay frames.
On the C64 the page counts clock advances at
`$FAE9`, continuing through the HUD's hour wrap. On the C128 it reads the screen digits at `HUDTIME` (`$484A-$484E`)
and adds the completed hours from `CLOCKHOURS`, capped at two hours for scoring. The C128 clock freezes during both endings
and resets with the game.
The original's rating also weighs the energy used, the shields
lost, the shots and protons fired; those are not in the point score. The counters are read just before the game consumes them (`$F440`
shifts them in place): for the C64 original at `$F3CE`, for the C128 port after `ENDRATINGINPUT` (`ENDRANKSET + 3`, only while the ENDING
overlay package is in). `rate()` / `rating()` in the same file work the end screen's rank and class out like the original does (`rating()` is
a port of the whole routine, checked against `$F440` on 4000 random games). The end of a game is found with hooks: for the C64 original the
instruction after `JSR $F440` in `$F3CE` (death and victory both pass there; the game restarts at `GAMEENTRY`), for the C128 port `end_rankok`
in the ENDING overlay package (`ENDRESET` re-arms). The best score per program is kept in `localStorage` (`sentinel-itch-hi-c64game`,
`sentinel-itch-hi-game`; in memory when storage is refused).

**Selector colours.** The selector shows the colours of the entry that is selected (mouse hover, arrows, a touch): the C64's blue with a
light blue border, and for the C128 the colours its VIC-IIe shows once the port runs (border and background black, the HUD's light blue text).

**Frame pacing.** `src/pacing.js` decides how many frames a display tick runs. The C64 original's unpacker runs at full speed up to `GAMEENTRY`;
the hook that ends it fires inside a frame, and the page used to charge that tick's frames to the 50 Hz accumulator afterwards (a debt of
3.5 s or more with no frame: the 10+ s stall at the C64 title) and to run the rest of the tick's 1000 frames without a time budget. A tick is now
one mode from start to end (`test/itch.js` simulates it). The debugger page (`src/app.js`) had the second half of the same fault.

**Audio (issue #14).** `src/audio.js` (shared with the debugger page) used to load the SID worklet only from a `blob:` URL, which fails
on `file://` pages and under some iframe sandboxes. It now tries the blob, then a `data:` URL, then runs the same synth in a
ScriptProcessorNode on the main thread. The context is made / resumed inside the first gesture (key, click, touch end) and again
when the tab becomes visible; frames are only sent while it runs. `audio.kind` says which path is playing.

## Build and test

```text
python js/build.py          # rebuild the C128 tests, export PRGs + symbols to js/programs.js
python js/bundle.py         # js/index.html (separate scripts) and js/dist/sentinel.html (one file)
python js/itch.py           # js/dist/itch.html and itch.zip, the itch.io page
node js/test/run.js         # headless checks, PNG snapshots in js/test/out
```

`test/itch.js` (called at the end of `run.js`) checks the score logic against the original, the end-of-game hooks in the
C64 original and the C128 port (death and victory), the store, the synth and the audio start fallbacks.

The headless checks run the five programs (C128 game, C64 game, cockpit, map, flight) with the ports in verify mode. They compare
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

