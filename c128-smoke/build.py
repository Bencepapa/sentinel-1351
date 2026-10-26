"""Build the native C128 BASIC 7 smoke-test PRG."""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'mouse', 'tools'))

from asm import asm

LOAD = 0x1C01
ENTRY = 0x1D00
OUT = os.path.join(HERE, 'sentinel-c128-smoke.prg')


def basic_stub():
    # BASIC 7 keeps its program at $1C01. Token $9E is SYS.
    text = str(ENTRY).encode('ascii')
    end = LOAD + 2 + 2 + 1 + len(text) + 1
    return bytes((end & 0xFF, end >> 8, 10, 0, 0x9E)) + text + b'\x00\x00\x00'


def main():
    with open(os.path.join(HERE, 'smoke.asm'), encoding='ascii') as f:
        chunks, symbols = asm(f.read())
    if ENTRY not in chunks:
        raise SystemExit(f'missing entry chunk: {list(chunks)}')

    stub = basic_stub()
    gap = ENTRY - (LOAD + len(stub))
    if gap < 0:
        raise SystemExit('BASIC stub overlaps machine code')
    body = bytearray(stub + bytes(gap))
    previous_end = LOAD + len(body)
    for address, code in sorted(chunks.items()):
        offset = address - LOAD
        if offset < len(stub):
            raise SystemExit(f'chunk at ${address:04X} overlaps BASIC stub')
        if address < previous_end:
            raise SystemExit(f'chunk at ${address:04X} overlaps previous chunk')
        if len(body) < offset:
            body.extend(bytes(offset - len(body)))
        end = offset + len(code)
        if len(body) < end:
            body.extend(bytes(end - len(body)))
        body[offset:end] = code
        previous_end = address + len(code)

    with open(OUT, 'wb') as f:
        f.write(bytes((LOAD & 0xFF, LOAD >> 8)) + bytes(body))
    print(f'wrote {OUT} (${LOAD:04X}-${LOAD + len(body) - 1:04X}, '
          f'entry ${symbols["START"]:04X})')


if __name__ == '__main__':
    main()
