# Sentinel 1351 mouse support and native C128 port

Reverse-engineering notes, build tools, a Commodore 1351 mouse patch and a native
Commodore 128 port of Bryan Brandenburg's 1984 Commodore 64 game *Sentinel* (Synapse
Software). This is not related to Geoff Crammond's *The Sentinel*.

**Play it in the browser:** <https://bencepapa.github.io/sentinel-1351/> (the C128 game by default; also the patched C64 game and the C128 test programs, on a JS 6502 core with a debugger: breakpoints, write watches, save states, cheats; see [js/README.md](js/README.md)).

## C128 game

[`c128-game`](c128-game) is the port: the cockpit and the sector map as one native
C128 program, rewritten routine by routine and checked against the original. It
includes the long-range approach, three fighter types, the tracking computer,
the live sector map, ship damage, hyperspace, proton torpedoes, motherships,
bases and both endings. The TIME display advances every 60 gameplay frames
and resets after game over. See [`PLAN-C128-COCKPIT.md`](PLAN-C128-COCKPIT.md).
Ideas beyond the original, such as
online multiplayer, are [GitHub issues](https://github.com/Bencepapa/sentinel-1351/issues).

```powershell
python c128-game/build.py
& "C:\dev\c64\GTK3VICE-3.9-win64\bin\x128.exe" `
  +go64 -40col -controlport2device 3 `
  -autostart c128-game\sentinel-c128-game.prg
```

The cockpit title uses the C64 bitmap lettering, animated credit colours,
a 38-column scroller and the original's one-shot three-voice SID tune. F5, F7 or Fire opens the
difficulty selector (the original's engine hum starts). Move the
crosshair with a port-2 joystick or 1351 mouse and fire to confirm Skirmish,
Assault, Battle, Invasion or Armageddon. The phasor fires and the selected
difficulty flashes for about three seconds while the original's welcome ribbon scrolls
(white and black, with a beep every 12 frames). The original Starfleet briefing opens a 48-line
panel and is typed glyph by glyph. The sector map opens when the panel closes.
A fresh Fire or Space press advances from the briefing straight to the map.
[Editable title text and music](c128-game/README.md#how-it-plays)

In flight, left button or fire shoots, the right button or C= opens the map, A
switches the tracking computer, and SPACE launches a proton torpedo.
There is no return to BASIC 7 (RUN/STOP does nothing; reset the machine to leave).

## C64 mouse patch

The 1351 goes in control port 2. It directly moves the flight crosshair while
preserving joystick fallback. The left button fires, the right button opens
the map, and both buttons launch a proton torpedo.

Detailed reverse-engineering and control documentation is in
[`MOUSE-SUPPORT.md`](MOUSE-SUPPORT.md).

Build from a locally supplied original disk image:

```text
python mouse/build.py Sentinel.d64 Sentinel-1351_v10.d64
python mouse/onefile.py Sentinel-1351_v10.d64 Sentinel-1351_v10.prg
```

The original disk image is intentionally not included. The latest patched D64
and one-file PRG are included as convenience builds.

## Native C128 test programs

The pieces the game was built from, kept as standalone programs:

- [`c128-smoke`](c128-smoke): VIC-IIe, SID POT, CIA port and 1351 access from BASIC 7.
- [`c128-flight`](c128-flight): a multicolor bitmap flight loop: point stars steered by
  the 1351, a laser sprite, and the first MMU transition. Its movement is test
  scaffolding, not the original game logic.
- [`c128-gui/cockpit`](c128-gui/cockpit): the cockpit with its fight; the original's sprites,
  font and raster schedule are documented in [`c128-gui`](c128-gui).
- [`c128-map`](c128-map): the sector map with its grid, icons, cursor, moving squadrons
  and the second (VDC) display.

Each has a `build.py` and a README with its VICE command line.

## Repository layout

- `mouse/`: C64 patch assembly, D64 patcher, one-file packer, and analysis tools
- `c128-game/`: the C128 game (`game.asm` joins the cockpit and the map)
- `c128-gui/`: the original's GUI assets and layout, and the cockpit
- `c128-map/`, `c128-flight/`, `c128-smoke/`: the other native C128 programs
- `js/`: the browser version, its debugger and the headless tests
- `MOUSE-SUPPORT.md`: complete C64 patch documentation
- `PLAN-C128-COCKPIT.md`: the port's status and what the original's fight does
- `PLAN-C128-MAP-GUI.md`: how the original's map works
- `MAP-LOGIC.md`, `SHIP-STATUS.md`, `FINDINGS.md`: the original's rules, damage, bugs and quirks
- `manual.TXT`: the game's original manual (see Credits)

## Credits

`manual.TXT` is an unchanged copy of the Project 64 etext of the Sentinel manual
(`SENTIN10.TXT`, March 1997, etext #181), converted by Chris Rogerson from the British
cassette version. The original game is by Bryan Brandenburg (spelled Brian Brandenberg
in the manual), (c) 1984 Synsoft, distributed in the UK by US Gold.
