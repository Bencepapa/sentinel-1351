# Sentinel native C128 flight-kernel test

This test exercises a point-star perspective field in native C128 mode. It uses
the same multicolor layering rule as Sentinel's pixel primitives at `$EF53` and
`$EEE6`: pixel value 2 is never overwritten by a star.

The surrounding loop is intentionally small rather than pretending to be the
complete game. This harness moves twelve single multicolor pixels away from a
mouse-controlled vanishing point in the real `$6000-$7FFF` bitmap. Stars start
and respawn at pseudorandom safe screen positions. This movement is test
scaffolding, not original game behavior; the real star field, steering and fight
are in [`c128-gui/cockpit`](../c128-gui/cockpit).

## Build and run

```powershell
python c128-flight/build.py
& "C:\dev\c64\GTK3VICE-3.9-win64\bin\x128.exe" `
  +go64 -40col -controlport2device 3 `
  -autostart c128-flight\sentinel-c128-flight.prg
```

Move the 1351 to steer the vanishing point. The left button fires a laser bolt:
sprite 1 flies from the lower center to the vanishing point along an X/Y point
list, in the role of the original's `$3580`, with no collision or sound. Press
both buttons to restore the saved VIC-IIe/CIA state and return to BASIC 7.

This proves native C128 execution of the relevant VIC-IIe bitmap layout, SID
POT input, frame scheduling, protected pixel rendering, and the first required
MMU transition. The harness selects configuration `$0E`
(bank 0 RAM with I/O and KERNAL ROM), so the CPU reads RAM rather than BASIC
ROM at `$4000-$7FFF`; without this, writes reach bitmap RAM but erase operations
read ROM bytes back and leave corrupt trails. The original MMU configuration
is restored on exit.

The real shot, with its hit test and sound, is in
[`c128-gui/cockpit`](../c128-gui/cockpit).
