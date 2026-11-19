# Task: C64 multicolor bitmap converter tool (Python, standalone)

Write a small standalone Python 3 tool `tools/c64mc.py` (create `tools/` if missing; only the standard library
plus Pillow `PIL` if it is installed; check with `python -c "import PIL"`; if Pillow is missing, read PNG with a
tiny pure-Python decoder using zlib/struct, 8-bit RGB/RGBA/indexed, non-interlaced). No changes to the game code.
Test images: `box_cover/*.png` (a book-cover style painting; `original.png` is the source), plus synthetic images
generated in the tests.

## What it must do (C64 multicolor bitmap mode, 160x200 pixels, each pixel 2 bits)
Input: a PNG; crop and scale to 160x200 (or accept an already 160x200 / 320x200 image; a 320x200 input is
reduced by taking 2 wide pixels as one). Output files for the image `NAME`:
- `NAME.bitmap` 8000 bytes (the standard C64 multicolor bitmap layout: 40x25 cells of 4x8 multicolor pixels, 8 bytes
  per cell, 2 bits per pixel: `00` = background colour, `01` = screen RAM high nibble, `10` = screen RAM low nibble,
  `11` = colour RAM),
- `NAME.screen` 1000 bytes, `NAME.color` 1000 bytes (low nibble used),
- `NAME.bg` 1 byte (global background colour `$D021`) or, with bands (below), a table.
- `NAME.png` a preview rendered with the C64 palette (use Pepto PAL colours as in js/src/video.js VIC_PAL, the
  16-entry list), 4x scaled, with an optional grid overlay.
- `NAME.report.txt`: the quantisation error per band, number of cells that needed a compromise.

Three commands (argparse subcommands):
1. `convert IN.png OUTPREFIX [--crop x0,y0,x1,y1] [--bg N | --bands "y0:bg0,y1:bg1,..."] [--dither none|ordered]`
   Map the picture to the 16-colour C64 palette (perceptual distance; use Lab or weighted RGB), then for every
   4x8 cell choose the best 3 colours (plus the band's background) that minimise the error; cells may use fewer
   colours. Bands: the global background colour `$D021` may differ per horizontal band, band edges must lie on cell
   row boundaries (multiples of 8 pixel lines); `--bands auto N` tries 1..N bands (N<=4) with every background colour
   per band and picks the edges and colours that minimise the total error; report the result for 1,2,3,4 bands so
   the user can compare. Never produce random isolated colour switches: prefer solutions with a smaller number of
   distinct colours per band (a small penalty per used colour).
2. `check IN.png [--bands "..."]` for an image that is ALREADY painted in C64 palette colours at 160x200 (or 320x200):
   strict validation: lists every cell (cell x, cell y) that has more than 3 non-background colours (using the band's
   background) or contains colours outside the palette; prints a summary and writes a preview PNG with the violating
   cells outlined in red. Exit code 1 if there are violations. This is for the user's repainting workflow.
3. `encode IN.png OUTPREFIX [--bands "..."]` strict encoder for a repainted image: no quantisation; fails with the
   `check` report if rules are broken, otherwise writes the same outputs as `convert`.
Also `bands` info: the band table output `NAME.bands` as lines `startrow bg` (cell rows 0..24) and a note how a
raster IRQ would apply it.

## Tests and docs
- `tools/test_c64mc.py` (plain python, no pytest needed, `python tools/test_c64mc.py` prints ok lines and exits 1 on
  failure): synthetic images (flat colours, a vertical gradient that needs 2 bands, a cell with 4 colours which
  must be reported by `check`, round trip encode -> decode -> same pixels), bitmap layout correctness against a
  hand-computed cell, the band edges on cell boundaries.
- A decoder function in the tool (`decode(prefix) -> RGB image`) used by the round-trip test.
- A short `tools/README.md`: usage, the file formats, the repaint workflow (convert -> repaint in any editor that
  keeps the C64 palette -> check -> encode).
- Run the tool on `box_cover/original.png` with a landscape crop around the three characters (e.g. the middle
  part, 8:5 aspect) and write the previews into `tools/out/` (do not commit big images; the user decides about
  the artwork, it is third-party art: do not add the box_cover files to git).

Branch feature/game-end. Do NOT run `git add`, commit or push. Keep temp files inside the project. Final message: a
5-line summary (files, commands, test result, limits).
