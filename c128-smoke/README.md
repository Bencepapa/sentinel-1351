# Sentinel C128 native-mode smoke test

This is the smallest useful test before attempting a native C128 port of
Sentinel. It starts as a BASIC 7 program at `$1C01`, remains in C128 mode, and
runs 8502 machine code at `$1D00`.

It verifies the parts that the existing mouse patch needs:

- VIC-IIe 40-column register and sprite access;
- SID POTX/POTY reads from a 1351 in control port 2;
- CIA port-2 selection with `$DC00=$BF`;
- the exact `MOVCHK` delta conversion used by `mouse/sentinel_mouse.asm`;
- one update per frame while running at 1 MHz;
- visibility of the native C128 MMU register at `$FF00`.

It deliberately does not switch the MMU or load the game yet. That should be
the next test after this hardware/input baseline works.

## Build

```powershell
python c128-smoke/build.py
```

## Run in VICE

```powershell
& "C:\dev\c64\GTK3VICE-3.9-win64\bin\x128.exe" `
  +go64 -40col -controlport2device 3 `
  -autostart c128-smoke\sentinel-c128-smoke.prg
```

Move the mouse after VICE has grabbed it. The numeric POT values and deltas
should change and VIC sprite 0 should move. The raw POT counters naturally wrap;
the independently accumulated cursor position does not. Its X coordinate is
9-bit and both axes are clamped to the visible playfield. The left button
changes the border to red. Press both mouse buttons to restore the saved
registers and return to BASIC 7.

On real hardware, load and run `SENTINEL-C128-SMOKE.PRG` normally from C128
mode with a 1351 in control port 2. The test must start from the C128 BASIC 7
screen, not after `GO64`.

## What success proves

Success proves that the Sentinel mouse algorithm and its required C64-style
I/O devices work without entering C64 mode. It does not yet prove that the
game's almost-64-KB memory image can run under C128 MMU control. The next
milestone is a small MMU trampoline that alternates between I/O-visible and
all-RAM configurations while executing outside `$D000-$DFFF`, followed by
relocation of the game's live `$FF00-$FF14` routine.
