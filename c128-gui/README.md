# Sentinel GUI assets and layout (C64 original)

Everything here is read from the C64 game (`Sentinel-1351_v8`) so the C128 port can
rebuild the cockpit. `python c128-gui/extract_sprites.py` regenerates the files in
`ref/` straight from the disk image; nothing has to be run in an emulator.

![All sprites](ref/sprites-sheet.png)

## Sprites (`ref/sprites-4800.bin`, `ref/sprites-sheet.png`)

All shapes are in VIC bank 1, 64 bytes each, addressed by a sprite pointer
(address = `$4000 + pointer * 64`). They are plain data in the disk image and
identical to the running game, so there is nothing to generate:

| pointers | address | what it is |
|---|---|---|
| `$20-$30` | `$4800-$4C3F` | enemy twin-pod fighters, tiny to close, in several rotations |
| `$31-$38` | `$4C40-$4E3F` | lens-shaped saucers, one shape per distance (tiny to big) |
| `$39-$3D` | `$4E40-$4FFF` | the planet, five globe frames (`$39-$3C` are cycled, see below) |
| `$3E-$44` | `$4F80-$513F` | small spiky enemies, growing |
| `$45`, `$46` | `$5140-$51BF` | blank on disk, **filled at run time** (see below) |
| `$47`, `$48` | `$51C0-$523F` | two big diagonal arms, mirrored: the gun barrels (left, right) |
| `$49-$4B` | `$5240-$52FF` | the crosshair: plain, tracking, locked |
| `$4C-$4E` | `$5300-$53BF` | corner marks, three sizes (crosshair at distance) |
| `$60-$63` | `$5800-$58FF` | explosion, four growing frames |
| `$64`, `$65` | `$5900-$597F` | digits (for a status read-out) and a dome shape (a base) |
| `$66-$68` | `$5980-$5A3F` | tiny dots |
| `$69-$70` | `$5A40-$5C3F` | irregular blobs, growing (debris / fire balls) |
| `$71-$7C` | `$5C40-$5F3F` | the basestar, one shape per distance (big to tiny) |
| `$7D` | `$5F40` | a target frame with three small squares underneath |
| `$7E`, `$7F` | `$5F80-$5FFF` | two big striped diagonal pods, mirrored (gun pods or fins) |

Pointers `$50-$5F` are the text screen (`$5400`), `$00-$1F` the character set and
colour matrix, `$80-$FF` the bitmap, so nothing else in the bank is a sprite.

Names are my reading of the shapes; they are not from the game. What the code
confirms (writes to the pointer shadow `$B0-$B7`, copied to `$47F8-$47FF` by the
raster interrupt):

- sprite 0 is the crosshair: pointer `$49`, stepped to `$4A`, `$4B`, back to `$49`
  while a target is locked (`$12CC-$12E0`);
- sprite 1 is the planet on the map (pointers `$39-$3C`, every 8th frame) and is
  reused for other shapes in flight (`$66`, `$67`, `$70`, `$7C` are written to it);
- sprites 5 and 6 get pointers `$45` / `$46`, which are blank on disk: at `$CF64`
  the game copies 128 bytes (two shapes) from a table into `$5140-$51BF` and
  steps through the table, with both sprites X-expanded. It looks like a close
  approach / ramming animation after which the ship is hit five times (`$84D7`);
- sprite 4 gets `$4C` (`$374C`);
- which sprites show the gun barrels `$47/$48` and the pods `$7E/$7F` is **not
  found by constant**; those shapes are probably chosen from a table. To do.

## Font (`ref/charset-4000.bin`, `ref/charset-sheet.png`)

The game has one font: the character set at `$4000` (128 characters, 8 bytes each).
The text screen (`$5400`, character set `$4000`, `D018` = `$50`) uses it for the HUD, and
the title, menu and messages are the *same glyphs* expanded to double width into the
bitmap (`$9BE5`, like the map icons). Codes `$00-$1F` are data, not glyphs; the
glyphs start at `$20` (digits and hex letters), then the letters, symbols (planet,
saucers, arrows) and a second set of digits.

![Font](ref/charset-sheet.png)

## The cockpit as the game builds it

The raster interrupt (table at `$0A42`) switches the video mode five times per frame:
a text strip on top (screen `$5400`, character set `$4000`), the multicolor bitmap
(`$6000`, matrix `$4400`) for the 3D view, and a text strip at the bottom again
(`$D011` = `$3B` / `$1B`, `$D018` = `$18` / `$50`).

- **Upper HUD** (text screen `$5400`, row 0 is a border line):
  - row 1: `SHIELDS` (col 1, value at col 10-11, `$5432`), `ENERGY` (col 14), `TIME`;
  - row 2: `PROTONS` (col 1), `SECTOR` (col 14, written `05.03`), `TARGETS` (col 28);
  - row 3: a chequered border.
  See `ref/cockpit-text-layer.png`.
- **Lower part**: a strip of tick marks and rivets from the text layer, and the radar
  viewport and the two gun emplacements, which are part of the bitmap, not text.
  See `ref/cockpit-flight.png`.

![Cockpit in flight](ref/cockpit-flight.png)

## Not done yet

- Which sprite slots show the guns, and how the firing is drawn.
- The data behind the run-time sprites `$45` / `$46` (table at `($5D)`, `$CF64`).
- The rest of the lower GUI: the radar contents, the emplacements as bitmap data.
