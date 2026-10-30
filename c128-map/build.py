"""Build the native C128 Sentinel map grid draw-in test."""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'mouse', 'tools'))
from asm import asm
sys.path.insert(0, HERE)
from vdcdata import chardata, rowtables, textdata, shipdata, planetchars, VCOL

LOAD = 0x1C01
ENTRY = 0x1D00
YLO = 0x3800
YHI = 0x3900
XLO = 0x3A00
XHI = 0x3A28
OUT = os.path.join(HERE, 'sentinel-c128-map.prg')


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


def place_assets(put, VDC=0x4000):
    """Everything but the code. put(address, data). The second display's data
    ($4000-$43FF here) goes to VDC instead (c128-game/build.py moves it)."""
    yoff = [(y // 8) * 320 + (y & 7) for y in range(200)]
    xoff = [x * 8 for x in range(40)]
    put(YLO, bytes(v & 255 for v in yoff))
    put(YHI, bytes(v >> 8 for v in yoff))
    put(XLO, bytes(v & 255 for v in xoff))
    put(XHI, bytes(v >> 8 for v in xoff))

    # second display (VDC): custom characters, text row table, colour map
    put(VDC + 0x240, chardata())
    lo, hi = rowtables()
    put(VDC + 0x310, lo)
    put(VDC + 0x330, hi)
    put(VDC + 0x350, VCOL)
    plus = bytearray(64)                    # the mouse pointer: a 7x7 +, pointer $3F
    for r in range(7):
        plus[r * 3] = 0xFE if r == 3 else 0x10
    put(0x4FC0, bytes(plus))
    with open(os.path.join(HERE, 'ref', 'planet-sprites.bin'), 'rb') as f:
        sprites = f.read()
    put(0x4E40, sprites)          # planet sprite frames, pointers $39-$3C
    put(VDC, planetchars(sprites))   # the same frames as VDC characters
    for address, data in textdata() + shipdata():
        if 0x4000 <= address < 0x4400:
            address += VDC - 0x4000
        put(address, data)



def main():
    with open(os.path.join(HERE, 'map.asm'), encoding='ascii') as f:
        chunks, symbols = asm(f.read())
    if set(chunks) != {ENTRY}:
        raise SystemExit(f'unexpected assembly chunks: {list(chunks)}')

    if ENTRY + len(chunks[ENTRY]) > YLO:
        raise SystemExit(f'code ends at ${ENTRY + len(chunks[ENTRY]):04X}, past the tables at ${YLO:04X}')

    stub = basic_stub()
    body = bytearray(stub)
    put(body, ENTRY, chunks[ENTRY])

    place_assets(lambda address, data: put(body, address, data))

    with open(OUT, 'wb') as f:
        f.write(bytes((LOAD & 255, LOAD >> 8)) + body)
    print(f'wrote {OUT} (${LOAD:04X}-${LOAD + len(body) - 1:04X}, '
          f'entry ${symbols["START"]:04X})')


if __name__ == '__main__':
    main()
