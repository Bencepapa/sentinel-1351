# Sentinel native C128 map grid draw-in test

Ports the sector-map grid animation of the C64 game (`$B094-$B269`) to native
C128 mode, including the sound.

- Seven horizontal lines (2 px thick) grow one pixel per frame, even rows from
  the left and odd rows from the right.
- 16 silent frames follow.
- Eleven vertical lines (2 px wide) grow one pixel per frame, even columns from
  the top and odd columns from the bottom.
- Sound is the original two-voice SID setup (`$B26D`); voice 1's gate toggles
  every second frame (`$B2BC`), which gives the rapid beeping while drawing.
- Pixels use Sentinel's protected multicolor plot (`$EF53`).

Not included yet: sector icons, the cursor and the rotating planet. Those are
animated every frame in the original (squadrons move between cells, a surrounded
mothership blinks), so they will be a per-frame update layer, not a one-time draw.

## Build and run

```powershell
python c128-map/build.py
& "C:\C64\GTK3VICE-3.7-win64\bin\x128.exe" `
  -40col -autostart c128-map\sentinel-c128-map.prg
```

Port 2 fire restarts the animation after it finishes. SPACE returns to BASIC 7.

## Verification done

The finished bitmap at `$6000` was dumped from VICE 3.7 `x128` and compared to a
bitmap dumped from the original game (`ref/map-bitmap-6000.bin`): all 463
cells in map rows 4-16 that hold only grid pixels match byte for byte. The SID
registers show both voices gated on during the sweep and off afterwards.

Confirmed by the user in x128: the grid effect looks as expected. Not
explicitly confirmed: the sound. (x128 opens two windows, VIC-IIe and
VDC; the effect is on the VIC-IIe one.)

Not verified by me: the on-screen picture and the audible result. The monitor's
`screenshot` command only captures the 80-column (VDC) screen on `x128`, so
this was checked by memory and register dumps. Please run it and compare the
look and sound with the original.
