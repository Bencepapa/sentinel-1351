"""Build the native C128 cockpit (c128-gui/cockpit/cockpit.asm).

usage: python c128-gui/cockpit/build.py          ->  c128-gui/cockpit/sentinel-c128-cockpit.prg
       python c128-gui/cockpit/build.py --c64    ->  sentinel-c64-cockpit-test.prg

The --c64 variant is only a debugging aid: the picture uses nothing but the VIC, CIA
and SID, so the same program runs on a C64 (BASIC at $0801), where VICE can take
screenshots of the VIC picture.

Memory (bank 0, VIC bank 1 for the picture):
  $1C01  BASIC stub, SYS 7424
  $1D00  code
  $2D00  tables for the star field (y offsets, x offsets)
  $3000  color RAM image (1000 bytes, copied to $D800 at start)
  $4000  the font (128 characters, ref/charset-4000.bin)
  $4400  color matrix of the bitmap (ref/cockpit-art.bin)
  $4800  text screen (HUD and bottom strip)
  $3400  phasor shot path (x, then y at $3500)
  $4C00  sprite shapes: pointers $30-$35 = the crosshair $7D, tracking $49-$4B, guns $7E / $7F,
         $36-$3F = the phasor shot $67-$70
  (nothing at $5000-$5FFF: the C128's video chip reads the character ROM there)
  $6000  multicolor bitmap; the cockpit art fills cell rows 18-22 ($7680-$7CBF)
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'mouse', 'tools'))
from asm import asm

C64 = '--c64' in sys.argv
LOAD = 0x0801 if C64 else 0x1C01
ENTRY = 0x0900 if C64 else 0x1D00
YLO = 0x2D00
YHI = 0x2E00
XLO = 0x2F00
XHI = 0x2F28
COLORDATA = 0x3000
REF = os.path.join(HERE, '..', 'ref')
OUT = os.path.join(HERE, 'sentinel-c64-cockpit-test.prg' if C64 else 'sentinel-c128-cockpit.prg')


def basic_stub():
    text = str(ENTRY).encode('ascii')
    end = LOAD + 2 + 2 + 1 + len(text) + 1
    return bytes((end & 255, end >> 8, 10, 0, 0x9E)) + text + b'\0\0\0'


def put(body, address, data):
    offset = address - LOAD
    end = offset + len(data)
    if len(body) < end:
        body.extend(bytes(end - len(body)))
    body[offset:end] = data


def main():
    with open(os.path.join(HERE, 'cockpit.asm'), encoding='ascii') as f:
        source = f.read()
    if C64:
        source = source.replace('* = $1D00', '* = $%04X' % ENTRY)
    chunks, symbols = asm(source)
    if set(chunks) != {ENTRY}:
        raise SystemExit(f'unexpected assembly chunks: {list(chunks)}')
    code = chunks[ENTRY]
    if ENTRY + len(code) > YLO:
        raise SystemExit(f'code ends at ${ENTRY + len(code):04X}, past the tables at ${YLO:04X}')

    art = open(os.path.join(REF, 'cockpit-art.bin'), 'rb').read()
    screen, color, matrix, bitmap_rows = art[:1000], bytearray(art[1000:2000]), art[2000:3000], art[3000:4600]
    for r in range(3, 18):                         # the 3D view: stars in light gray
        for c in range(40):
            color[r * 40 + c] = 0x0F

    body = bytearray(basic_stub())
    put(body, ENTRY, code)
    yoff = [(y // 8) * 320 + (y & 7) for y in range(200)]
    put(body, YLO, bytes(v & 255 for v in yoff))
    put(body, YHI, bytes(v >> 8 for v in yoff))
    put(body, XLO, bytes(((x * 8) & 255) for x in range(40)))
    put(body, XHI, bytes(((x * 8) >> 8) for x in range(40)))
    put(body, COLORDATA, bytes(color))
    put(body, 0x4000, open(os.path.join(REF, 'charset-4000.bin'), 'rb').read())
    put(body, 0x4400, matrix)
    sprites = open(os.path.join(REF, 'sprites-4800.bin'), 'rb').read()
    order = [0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F,
             0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F,
             0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F,
             0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F,
             0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B, 0x7C, 0x7D, 0x7E, 0x7F]
    shape = lambda p: sprites[order.index(p) * 64:order.index(p) * 64 + 64]
    for new, original in enumerate((0x7D, 0x49, 0x4A, 0x4B, 0x7E, 0x7F)):
        put(body, 0x4C00 + new * 64, shape(original))      # pointers $30-$35
    for original in range(0x67, 0x71):                     # the phasor shot, $67-$70
        put(body, 0x4C00 + (original - 0x31 - 0x30) * 64, shape(original))   # pointers $36-$3F
    put(body, 0x4800, screen)
    put(body, 0x6000 + 18 * 320, bitmap_rows)

    with open(OUT, 'wb') as f:
        f.write(bytes((LOAD & 255, LOAD >> 8)) + body)
    print(f'wrote {OUT} (${LOAD:04X}-${LOAD + len(body) - 1:04X}, code ends ${ENTRY + len(code):04X}, '
          f'entry ${symbols["START"]:04X})')


if __name__ == '__main__':
    main()
