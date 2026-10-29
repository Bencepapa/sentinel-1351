## Second display (VDC): planet colour clash, squadrons cut the planet, friendly mothership too dark

Found while testing `main` (5d6491e) in VICE x128 with the 80-column (VDC) map view.
Minor visual problems, none of them affect the game logic.

### What I see

1. **The planet is cut by squadron icons.** The globe in the middle of the map is
   a 3x3 block of characters. Squadron icons that sit in the four sectors around
   the centre overwrite parts of it, so its shape is broken.
2. **Colour clash when the planet changes colour.** When the planet is surrounded it
   flashes through colours, and the squadron icons next to it change colour with it.
3. **Friendly (blue) motherships are hard to read.** They are dark blue on black.
   Light blue would be easier to see.

### Why (from the code)

- The planet block is text columns 17-19, rows 7-9 (`VPLX` / `VPLY` in `c128-map/map.asm`).
  The icon characters of the four sectors that meet at the centre are
  (col 17, row 7), (col 19, row 7), (col 17, row 9) and (col 19, row 9): one character
  of each of those icons lies inside the planet block, so the two overlap.
- The VDC colours characters, not pixels. `VDCPLCOL` writes the planet colour into
  all 9 attribute bytes of the block, including the 4 characters that belong to
  squadron icons, so they change colour too. `VDCPLDEF` redefines the 9 character
  shapes every frame, which also replaces the overlapped icon halves.
- The blue mothership colour comes from `VCOL` in `c128-map/vdcdata.py`: the game's
  colour 6 maps to VDC colour 2 (dark blue).

### Ideas

- Give the planet its own space on the VDC view only: make the centre sectors wider
  (and/or add a gap around the centre) so that no icon shares a character with the
  planet block. The VIC-IIe bitmap view and the game logic stay as they are.
- Light blue (VDC colour 3) for the friendly mothership. Squadron type 1 currently uses
  light blue as well, so one of the two needs another colour, for example type 1
  light purple or light gray (the planet is cyan).
- Once the planet no longer shares characters with icons, recolouring it cannot affect
  the squadrons.

### Not affected

The VIC-IIe window (bitmap + sprite planet) and the ship status panel.
