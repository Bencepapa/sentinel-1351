# Task 2 for tools/c64mc.py: palette option, compose command, less noise

Context: `tools/c64mc.py` (+ tools/test_c64mc.py, tools/README.md) exists and works (read the README and the code
first). The user converted the cover (box_cover/original.png) with several online converters:
box_cover/IMG2C64MC.png, IMG2C64MC2.png, micheldebree.png, png2c64.png, zoopersoft_overpaint.png (these files are
third-party / the user's work: never `git add` them; box_cover/ and tools/out/ are in .gitignore). The strict `check`
rejects them (hundreds of cells with "off-palette" pixels) because those tools use different RGB values for the 16
C64 colours than our Pepto PAL list, and `check` tolerates only 4 RGB levels. Also, different converters are better
in different regions of the picture (the top has much gray but is noisy and loses colours such as the green
X-wing; the two aliens at the bottom are noisy; the man's head is high-contrast and good in some versions), so the
user wants to take regions from several candidates.

Do:
1. **`--palette pepto|colodore|vice|auto`** for `check`, `encode` and `convert` previews (default `pepto`): add the
   16-colour RGB tables for the Colodore and the VICE 3.x defaults (use the well known values; Pepto's table is
   already in the tool); `auto` = for each input image pick the table with the fewest off-palette pixels
   (print which one was chosen). Also add `--tolerance N` (RGB levels, default 4) and a `--nearest` switch that
   maps any off-palette pixel to the nearest palette colour (perceptual distance) before checking, so slightly
   different converters' colours are accepted. Re-run `check` for the five box_cover images with `--palette auto`
   and show the table: cells violating with more than 3 colours, off-palette pixels, which palette was detected.
   Note: if a converter's image is 320x200 with doubled pixels, handle it as the tool already does; if an image
   has some other size (e.g. a scaled preview) report it clearly instead of failing silently.
2. **`compose`** command: `compose OUT.png --base A.png [--from B.png x0,y0,x1,y1] [--from C.png ...] [--bands "..."]`
   builds a new 160x200 / 320x200 candidate by taking the base image and replacing the given rectangles (in cell
   units or pixels, snapped to the 4x8 cell grid with a note) from the other candidate images; all inputs normalised
   to the same palette (`--palette auto` per input); then run the strict check on the result and write the
   preview with the violating cells outlined, so the user can iterate on the region list. Also `compose --list`
   style helper `grid`: write a preview of an input with the 4x8 cell grid and cell coordinates every 5 cells so the
   user can read off rectangle coordinates (`tools/c64mc.py grid IN.png OUT.png`).
   Seams: where a region boundary cuts a cell row it is fine, but warn when a cell would get more than 3 colours.
3. **Less noise** option in `convert`: `--smooth N` (0..3): a cheap pre-filter before quantisation (e.g. median
   or bilateral-like edge-preserving smoothing, pure Python or Pillow), and `--flat W` (weight 0..1) that adds a
   penalty for choosing a colour set that differs from the neighbouring cells' set (so large areas keep one
   colour set instead of random switching), and `--keep-colors "R,G,B;..."` or `--boost-colors 2,5` to give extra
   weight to small important colours (e.g. green 5 for the X-wing wings, cyan 3 for the alien head). Produce
   `tools/out/cover_smooth{0,1,2,3}.png` previews of the same crop (`112,100,912,600`, auto bands up to 4) and a
   short table of RMS error and number of distinct colour sets per band.
4. Tests in tools/test_c64mc.py for the palette detection, `nearest`, `compose` (rectangle replaced, seam warning)
   and the smoothing; update tools/README.md (palettes, compose workflow, the repaint workflow).

Branch feature/game-end. Do NOT run `git add`, commit or push. Keep temp files inside the project (.zen/).
Final message: a 6-line summary and the `check --palette auto` table for the five reference images.
