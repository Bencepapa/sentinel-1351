"""Extract every sprite of Sentinel from a (patched or original) multi-file D64.

usage: python c128-gui/extract_sprites.py [Sentinel-1351_v8.d64]

The game keeps all sprite shapes in VIC bank 1 ($4000-$7FFF), 64 bytes per shape,
addressed by a sprite pointer 0-255 (address = $4000 + pointer * 64):

    pointers $20-$4F   $4800-$53FF   48 shapes
    pointers $60-$7F   $5800-$5FFF   32 shapes
    (pointers $50-$5F are the text screen at $5400, $00-$1F the character set and
     the colour matrix, $80-$FF the bitmap)

They are plain data in the disk image (identical to the running game), so nothing has
to be run. Writes, next to this script, under ref/:

    sprites-4800.bin   all 80 shapes, 64 bytes each, in pointer order
    sprites-sheet.png  labelled sheet of all 80 shapes (white on dark)
    charset-4000.bin   the 128-character set the HUD text uses ($4000-$43FF)
    charset-sheet.png  the character set as a sheet
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'mouse', 'tools'))
sys.path.insert(0, os.path.join(HERE, '..', 'mouse'))
from build import file_sectors, read_file   # noqa: E402

D64 = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'Sentinel-1351_v8.d64')
POINTERS = list(range(0x20, 0x50)) + list(range(0x60, 0x80))


def memory_image(d64):
    """Rebuild the C64 memory the loader chain leaves behind (see mouse/onefile.py)."""
    d = open(d64, 'rb').read()
    files = {n: read_file(d, file_sectors(d, n)) for n in ('SN0', 'SN1', 'SN2', 'SN3')}
    m = bytearray(65536)
    for name in ('SN1', 'SN2', 'SN3'):
        data = files[name]
        base = data[0] | data[1] << 8
        body = data[2:]
        m[base:base + len(body)] = body
    return m


def main():
    mem = memory_image(D64)
    blocks = {p: bytes(mem[0x4000 + p * 64:0x4000 + p * 64 + 64]) for p in POINTERS}
    out = os.path.join(HERE, 'ref')
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, 'sprites-4800.bin'), 'wb') as f:
        for p in POINTERS:
            f.write(blocks[p])
    print('wrote', os.path.join(out, 'sprites-4800.bin'), len(POINTERS) * 64, 'bytes')

    with open(os.path.join(out, 'charset-4000.bin'), 'wb') as f:
        f.write(bytes(mem[0x4000:0x4400]))
    print('wrote', os.path.join(out, 'charset-4000.bin'), 1024, 'bytes')

    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print('PIL not installed: no sheet written')
        return
    scale, cols = 3, 10
    cw, ch = 24 * scale + 10, 21 * scale + 24
    rows = (len(POINTERS) + cols - 1) // cols
    img = Image.new('RGB', (cols * cw + 10, rows * ch + 10), (30, 30, 38))
    draw = ImageDraw.Draw(img)
    for n, p in enumerate(POINTERS):
        x0 = 10 + (n % cols) * cw
        y0 = 10 + (n // cols) * ch
        blk = blocks[p]
        draw.rectangle([x0 - 1, y0 + 12 - 1, x0 + 24 * scale, y0 + 12 + 21 * scale], outline=(70, 70, 90))
        draw.text((x0, y0 - 2), '$%02X' % p, fill=(255, 210, 90))
        for r in range(21):
            for c in range(24):
                if (blk[r * 3 + c // 8] >> (7 - c % 8)) & 1:
                    draw.rectangle([x0 + c * scale, y0 + 12 + r * scale,
                                    x0 + c * scale + scale - 1, y0 + 12 + r * scale + scale - 1],
                                   fill=(240, 240, 240))
    path = os.path.join(out, 'sprites-sheet.png')
    img.save(path)
    print('wrote', path)

    # character set sheet: 16 x 8 characters, code in the label row
    chars = bytes(mem[0x4000:0x4400])
    sheet = Image.new('RGB', (16 * 10 + 8, 8 * 10 + 8), (30, 30, 38))
    for code in range(128):
        cx, cy = (code % 16) * 10 + 4, (code // 16) * 10 + 4
        for y in range(8):
            for x in range(8):
                if (chars[code * 8 + y] >> (7 - x)) & 1:
                    sheet.putpixel((cx + x, cy + y), (240, 240, 240))
    sheet = sheet.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST)
    path = os.path.join(out, 'charset-sheet.png')
    sheet.save(path)
    print('wrote', path)


if __name__ == '__main__':
    main()
