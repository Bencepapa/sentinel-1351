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

After the sweep, the sector icons appear (as in the original, which redraws all
cells once the grid is done):

- orange motherships in the four corners and blue motherships near them
  (original positions and glyphs `$67` / `$66`, colors `$18` / `$16`);
- 16 squadrons at random free cells. Type 1-3 picks the color
  (`$1E`, `$1D`, `$14` as in the game) and the size picks 1, 2 or 3 icons
  (glyphs `$68`, `$69`, `$6A`). Fire replays the sweep with a new random layout.

Icon cells are drawn from the game's own 8x8 glyph shapes, expanded to 16 px
wide pixel-value-2 icons, with the color in the color matrix, exactly like
`$0816` and `$233C` do. The sector data uses the original `STATE` / `COUNT`
layout, and `DRAWCELL` draws one cell, so the animation (moving squadrons,
blinking motherships) only needs to change a cell and redraw it.

## Cursor

After the icons appear, a brown box marks the selected sector (start 4,2, the
player's position in the original). The joystick in port 2 or a 1351 mouse in
port 2 moves a second box over the grid (wrapping at the edges, with the same
24 frame cooldown and move click as the original). Fire (or the mouse's left
button) moves the selected sector to the cursor. R replays the sweep with a new
random layout, SPACE returns to BASIC 7.

The box is drawn over the sector's border in pixel value 2 (brown) and erased by
redrawing the border in value 3 (yellow), as the original `$2384` does; after
each move the selected sector's box is repaired, as at `$2231`. One difference:
a move is accepted as soon as the cooldown is over, while the original only
samples the stick every 24th frame.

Not included yet: the rotating planet. The icons are
animated every frame in the original (squadrons move between cells, a surrounded
mothership blinks), so the animation will be a per-frame update on top of this.

## Build and run

```powershell
python c128-map/build.py
& "C:\C64\GTK3VICE-3.7-win64\bin\x128.exe" `
  -40col -autostart c128-map\sentinel-c128-map.prg
```

See the controls under Cursor.

## Verification done

The finished bitmap at `$6000` was dumped from VICE 3.7 `x128` and compared to a
bitmap dumped from the original game (`ref/map-bitmap-6000.bin`): all 463
cells in map rows 4-16 that hold only grid pixels match byte for byte. The SID
registers show both voices gated on during the sweep and off afterwards.

The cursor was checked by feeding joystick input through RAM and comparing the
bitmap with the expected boxes after moves, wraps and a fire press (0 differences);
the 1351 mouse path is ported from the smoke test but not exercised.

The icon layer was checked by dumping the state arrays, color matrix and bitmap:
all 60 cells match the glyph and color rules (0 bad cells), 16 random squadrons use
all three types and all three sizes, and the 8 mothership cells match the original
game's bitmap byte for byte. The picture itself was not seen by me.

Confirmed by the user in x128: the grid effect looks as expected. Not
explicitly confirmed: the sound. (x128 opens two windows, VIC-IIe and
VDC; the effect is on the VIC-IIe one.)

Not verified by me: the on-screen picture and the audible result. The monitor's
`screenshot` command only captures the 80-column (VDC) screen on `x128`, so
this was checked by memory and register dumps. Please run it and compare the
look and sound with the original.
