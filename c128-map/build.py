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

    yoff = [(y // 8) * 320 + (y & 7) for y in range(200)]
    xoff = [x * 8 for x in range(40)]
    put(body, YLO, bytes(v & 255 for v in yoff))
    put(body, YHI, bytes(v >> 8 for v in yoff))
    put(body, XLO, bytes(v & 255 for v in xoff))
    put(body, XHI, bytes(v >> 8 for v in xoff))

    # second display (VDC): custom characters, text row table, colour map
    put(body, 0x4240, chardata())
    lo, hi = rowtables()
    put(body, 0x4310, lo)
    put(body, 0x4330, hi)
    put(body, 0x4350, VCOL)
    with open(os.path.join(HERE, 'ref', 'planet-sprites.bin'), 'rb') as f:
        sprites = f.read()
    put(body, 0x4E40, sprites)          # planet sprite frames, pointers $39-$3C
    put(body, 0x4000, planetchars(sprites))   # the same frames as VDC characters
    for address, data in textdata() + shipdata():
        put(body, address, data)

    with open(OUT, 'wb') as f:
        f.write(bytes((LOAD & 255, LOAD >> 8)) + body)
    print(f'wrote {OUT} (${LOAD:04X}-${LOAD + len(body) - 1:04X}, '
          f'entry ${symbols["START"]:04X})')


if __name__ == '__main__':
    main()
