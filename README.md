# Sentinel 1351 mouse support

Reverse-engineering notes, build tools, and a Commodore 1351 mouse patch for
Bryan Brandenburg's 1984 Commodore 64 game *Sentinel* (Synapse Software).
This is not related to Geoff Crammond's *The Sentinel*.

The repository also contains native Commodore 128 experiments that establish
which parts of the patched game can run directly in C128 mode without `GO64`.

**Play it in the browser:** <https://bencepapa.github.io/sentinel-1351/> (the patched C64 game and the C128 cockpit, map and flight programs on a JS 6502 core, with a debugger: breakpoints, write watches, save states, cheats; see [js/README.md](js/README.md)).

## C64 mouse patch

The 1351 goes in control port 2. It directly moves the flight crosshair while
preserving joystick fallback. The left button fires, the right button opens
the map, and both buttons launch a proton torpedo.

Detailed reverse-engineering and control documentation is in
[`MOUSE-SUPPORT.md`](MOUSE-SUPPORT.md).

Build from a locally supplied original disk image:

```text
python mouse/build.py Sentinel.d64 Sentinel-1351_v8.d64
python mouse/onefile.py Sentinel-1351_v8.d64 Sentinel-1351_v8.prg
```

The original disk image is intentionally not included. The latest patched D64
and one-file PRG are included as convenience builds.

## Native C128 tests

### 1351 smoke test

[`c128-smoke`](c128-smoke) starts from BASIC 7 at `$1C01` and verifies native
C128 access to the VIC-IIe, SID POT registers, CIA control port, 9-bit sprite
positioning, and the mouse delta routine used by the C64 patch.

```text
python c128-smoke/build.py
```

### Flight-kernel test

[`c128-flight`](c128-flight) runs a multicolor bitmap flight loop in native
C128 mode. It carries over Sentinel's original seven-pixel hostile-squadron
marker, which intentionally appears as a small `H`, its erase walk, and its
protected-pixel layering rule. The game tracks three squadrons; this test
harness moves twelve markers to stress the renderer while the 1351 controls
the vanishing point. Its movement and respawning are test scaffolding, not the
original game logic.

This test also exercises the first required C128 MMU transition. Configuration
`$0E` exposes bank 0 RAM at `$4000-$7FFF` while retaining I/O and KERNAL ROM,
allowing both the CPU and VIC-IIe to access the bitmap at `$6000`.

```text
python c128-flight/build.py
```

Run either test with VICE 3.9 `x128`:

```powershell
& "C:\dev\c64\GTK3VICE-3.9-win64\bin\x128.exe" `
  +go64 -40col -controlport2device 3 `
  -autostart c128-flight\sentinel-c128-flight.prg
```

Press both mouse buttons to restore the saved machine state and return to
BASIC 7.

## Repository layout

- `mouse/`: C64 patch assembly, D64 patcher, one-file packer, and analysis tools
- `c128-smoke/`: minimal native C128 hardware and mouse test
- `c128-flight/`: native C128 bitmap/MMU/flight-rendering test
- `MOUSE-SUPPORT.md`: complete C64 patch documentation
- `LESSONS-ADVGUI.md`: reusable C64 mouse-driver and testing notes

## Status

The C64 mouse patch and both native C128 tests have been exercised in VICE and
interactively with 1351 input. A complete native C128 port of the game has not
yet been produced.
