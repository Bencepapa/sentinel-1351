# Sentinel native C128 flight-kernel test

This test carries a characteristic, separable part of Sentinel's flight view
into native C128 mode. It uses the original seven-pixel hostile-squadron
marker from `$3166-$3193`, its matching erase walk from `$3138-$3165`, and the
same multicolor layering rule as the pixel primitives at `$EF53` and `$EEE6`:
pixel value 2 is never overwritten by a squadron marker. The marker
intentionally looks like a small `H` in the original game.

The surrounding loop is intentionally small rather than pretending to be the
complete game. The game tracks three hostile squadrons; this stress harness
moves twelve markers away from a mouse-controlled vanishing point in the real
`$6000-$7FFF` multicolor bitmap. Its centered respawning is not original game
behavior. The full projection and steering code is not included yet because
it depends on sector data, movement streams, three 16-bit world-coordinate
sets, and the complete raster IRQ.

## Build and run

```powershell
python c128-flight/build.py
& "C:\dev\c64\GTK3VICE-3.9-win64\bin\x128.exe" `
  +go64 -40col -controlport2device 3 `
  -autostart c128-flight\sentinel-c128-flight.prg
```

Move the 1351 to steer the vanishing point. Press both buttons to restore the
saved VIC-IIe/CIA state and return to BASIC 7.

This proves native C128 execution of the relevant VIC-IIe bitmap layout, SID
POT input, frame scheduling, an authentic Sentinel rendering primitive, and
the first required MMU transition. The harness selects configuration `$0E`
(bank 0 RAM with I/O and KERNAL ROM), so the CPU reads RAM rather than BASIC
ROM at `$4000-$7FFF`; without this, writes reach bitmap RAM but erase operations
read ROM bytes back and leave corrupt trails. The original MMU configuration
is restored on exit.

It does not yet execute original code from RAM under the C128 KERNAL at
`$E000-$FFFF`.
