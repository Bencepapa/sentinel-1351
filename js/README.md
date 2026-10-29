# Sentinel 128 JS: hybrid runtime

The browser version follows the C128 port instead of being a second codebase.
The unchanged 8502 binaries run on a JS 6502 core. The chips around them are
replaced by JS that reads their registers once per frame:

| Part | How it is handled |
|---|---|
| 8502 | `src/cpu6502.js`, all documented opcodes; passes Klaus Dormann's 6502 functional test |
| MMU | `$FF00`/`$D500` configuration register; I/O visible when bit 0 is 0 |
| VIC-IIe | `src/video.js`: text, hires and multicolor bitmap, sprites with priority, bank from CIA2; drawn line by line from register and sprite-pointer writes logged with their raster line and cycle, so raster splits work (the cockpit's HUD / bitmap / strip, colour bars, sprites reused lower down) |
| VDC | register file at `$D600/$D601`, update address, data, block fill/copy, 80x25 text with attributes |
| SID | `src/audio.js`: register writes replayed in an AudioWorklet at their cycle in the frame; voice 3 noise readable at `$D41B` |
| CIA1 | keyboard matrix, joystick in port 2 |
| 1351 | proportional mode on the port 2 pots (pointer lock on desktop, drag on touch) |
| ROMs | none: an original font (`src/font.js`) stands in for the character ROM and the VDC character set |

Timing is a PAL frame of 312 lines x 63 cycles; `$D012` follows the cycle
count, so the tests' raster waits work unchanged. `$D030` bit 0 doubles the
cycles per frame.

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

The headless checks run the three programs (cockpit, map, flight) with the ports in verify mode. They compare
the map's grid cells with the original game's bitmap (`c128-map/ref`), and
exercise the cursor, fast ticks, the planet sprite, the cockpit crosshair and vertical-blank budget (`OVRUN`), and the exits.

`index.html` needs a local web server (`python -m http.server` in `js/`);
`dist/sentinel.html` opens directly.

## Keeping it in sync

`.githooks/pre-commit` rebuilds the embedded PRGs (`js/build.py`, `js/bundle.py`) and adds the
results to the commit whenever C128 sources or the JS build change. Enable it once per clone:

```text
git config core.hooksPath .githooks
```

