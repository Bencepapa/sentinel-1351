"""Build the native C128 Sentinel: the cockpit and the sector map as one program.

usage: python c128-game/build.py   ->  c128-game/sentinel-c128-game.prg

Sources: c128-gui/cockpit/cockpit.asm and c128-map/map.asm stay standalone
programs; this script joins them with c128-game/game.asm (the glue):

- the map's source: every label and constant it defines gets the prefix M_
  (except the ship's shared variables below), its code moves to $9D00 and its
  second-display data from $4000-$43FF to $B800-$BBFF (the cockpit's font lives
  at $4000); a few patches (PATCHES_MAP) turn it into the game's map screen;
- the cockpit's source: a few patches (PATCHES_COCKPIT) hook in the map key, the
  sectors and the squadron counts;
- the ship (systems, shields, hits, difficulty) is the cockpit's; the map's
  second display shows the same variables.

Memory, besides the cockpit's (c128-gui/cockpit/build.py) and the map's tables at
$3800-$3FFF (c128-map/build.py):
  $5000  master copies of the cockpit picture (the VIC-IIe cannot use $5000-$5FFF,
         the CPU can): bitmap rows 0-2 (sprite shapes), the shot slots in rows
         23-24, the cockpit art (rows 18-22), the colour matrix rows 3-22
  $9D00  the map's code, then the glue
  $B800  the map's second-display data (VDC characters, planet, row tables, texts)
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, os.path.join(ROOT, 'mouse', 'tools'))
from asm import asm
sys.path.insert(0, os.path.join(ROOT, 'c128-gui', 'cockpit'))
import build as cockpit_build                      # noqa: E402
del sys.modules['build']
sys.path.insert(0, os.path.join(ROOT, 'c128-map'))
import build as map_build                          # noqa: E402

LOAD = 0x1C01
ENTRY = 0x1D00
CODE2 = 0x8C00
MAPCODE = 0x9D00
VDCDATA = 0xB800
OUT = os.path.join(HERE, 'sentinel-c128-game.prg')

SHARED = {'SHLD', 'HITS', 'SHIPLOST', 'DIFF', 'SYSHP'}    # the cockpit's, used by the map

PATCHES_MAP = [
    # the ship's variables are the cockpit's
    ('SYSHP   = $3D40         ; hit points of the eight ship systems (SHIP-STATUS.md)\n', ''),
    ('DIFF:   .BYTE 2\n', ''),
    ('SHLD:   .BYTE 0\n', ''),
    ('HITS:   .BYTE 0\n', ''),
    ('SHIPDEAD:.BYTE 0\n', ''),
    # code and data addresses
    ('        * = $1D00\n', '        * = $9D00\n'),
    # the set-up part of START becomes a subroutine (TOMAP calls it)
    ('        LDA CIA2PA\n        AND #$FC\n        ORA #$02        ; VIC bank 1: $4000-$7FFF\n        STA CIA2PA\n        LDA #$3B',
     'MSETUP: LDA CIA2PA\n        AND #$FC\n        ORA #$02        ; VIC bank 1: $4000-$7FFF\n        STA CIA2PA\n        LDA #$3B'),
    ('        JSR RESET\n\nframe:', '        JMP RESET       ; (game: MSETUP ends here)\n\nframe:'),
    # SPACE goes back to the cockpit
    ('        BNE nospace\n        JMP EXIT\nnospace:', '        BNE nospace\n        JMP TOCOCK\nnospace:'),
    # fire on another sector: the jump
    ('        JSR CURSOR\n        JSR TICKER', '        JSR CURSOR\n        LDA MJUMPF\n        BEQ nojump\n        JMP TOCOCK\nnojump: JSR TICKER'),
    ('        STA BR\n        LDA #1\n        STA BV\n        JSR BOX\n        JMP BLIP\n',
     '        STA BR\n        LDA #1\n        STA BV\n        JSR BOX\n        JSR BLIP\n        LDA #1          ; (game) jump there\n        STA MJUMPF\n        RTS\n'),
    # the world is made once; the cursor starts on the ship's sector
    ('        JSR PLINIT\n        JSR SHIPINIT\n', '        JSR PLINIT\n'),
    ('        BNE iconret\n        JSR GENERATE\n', '        BNE iconret\n        JSR GENONCE\n'),
    ('        LDA #4\n        STA CURX\n        STA SELX\n        LDA #2\n        STA CURY\n        STA SELY\n',
     '        LDA SELX        ; (game) the ship\'s sector\n        STA CURX\n        LDA SELY\n        STA CURY\n'),
    ('SELX:   .BYTE 0\nSELY:   .BYTE 0\n', 'SELX:   .BYTE 4\nSELY:   .BYTE 2\n'),
]
MAP_EXTRA = """
GENONCE:LDA GENDONE     ; (game) the start layout only once
        BNE gon1
        INC GENDONE
        JMP GENERATE
gon1:   RTS
GENDONE:.BYTE 0
"""

PATCHES_COCKPIT = [
    ('        JSR NEWWAVE     ; a type-1 squadron wave\n',
     '        JSR GAMEINIT    ; (game) the world and the start sector\n'),
    # SPACE leaves only on a new press; C= opens the map
    ('        LDA CIA1PB\n        AND #$10\n        BNE nospace\n        JMP EXIT\nnospace:LDA #$BF        ; port 2 pots for the next frame\n',
     '        LDA CIA1PB\n        AND #$10\n        BNE nospace\n        LDA SPREV\n        BNE nosp2\n        JMP EXIT\n'
     'nospace:LDA #$00\n        STA SPREV\nnosp2:  LDA CIA1PB      ; (game) C= opens the map (the original\'s map key)\n'
     '        AND #$20\n        BNE nomapk\n        LDA CPREV\n        BNE nomap\n        JMP TOMAP\nnomapk: LDA #$00\n        STA CPREV\n'
     'nomap:  LDA #$BF        ; port 2 pots for the next frame\n'),
    # waves come from the sector's squadron
    ('        LDA ETYPE       ; all three alive: the flags get the type ($C7B9), after\n'
     '        STA ALIVE       ; WAVEINIT, which clears them\n        STA ALIVE+1\n        STA ALIVE+2\n'
     '        STA EHITS       ; shots each one takes: the type ($C7B9)\n        STA EHITS+1\n        STA EHITS+2\n'
     '        LDA TARGETS     ; the HUD\'s TARGETS count: refilled when it runs low (no\n'
     '        CMP #$73        ; squadrons yet)\n        BCS nw1\n        LDA #$79\n        STA TARGETS\n',
     '        JSR WAVEALIVE   ; (game) as many as the squadron has, up to 3\n'),
    ('        ORA EXPL\n        BNE fg4\n        JSR NEWWAVE\n', '        ORA EXPL\n        BNE fg4\n        JSR SECWAVE     ; (game)\n'),
    ('KILL:   DEC TARGETS     ; ($3CC4) one target less on the HUD, one more kill\n',
     'KILL:   JSR SECKILL     ; (game) the sector\'s COUNT -1, shown as TARGETS\n'),
]


def patch(text, patches, name):
    for old, new in patches:
        n = text.count(old)
        if n != 1:
            raise SystemExit(f'{name}: patch target found {n} times:\n{old}')
        text = text.replace(old, new)
    return text


def defined_names(text):
    names = set()
    for line in text.splitlines():
        code = line.split(';')[0].rstrip()
        m = re.match(r'^(\w+)\s*=', code)
        if m:
            names.add(m.group(1))
        m = re.match(r'^(\w+):', code)
        if m:
            names.add(m.group(1))
    return names


def prefix_map(text):
    names = defined_names(text) - SHARED
    for n in sorted(names, key=len, reverse=True):
        text = re.sub(r'(?<![\w$])' + n + r'(?!\w)', 'M_' + n, text)
    return text


def put(body, address, data):
    offset = address - LOAD
    end = offset + len(data)
    if len(body) < end:
        body.extend(bytes(end - len(body)))
    body[offset:end] = data


def assemble():
    """The joined source assembled: (chunks, symbols). Also used by js/build.py."""
    read = lambda *p: open(os.path.join(ROOT, *p), encoding='ascii').read()
    cockpit = patch(read('c128-gui', 'cockpit', 'cockpit.asm'), PATCHES_COCKPIT, 'cockpit')
    mapsrc = patch(read('c128-map', 'map.asm'), PATCHES_MAP, 'map').replace('SHIPDEAD', 'SHIPLOST') + MAP_EXTRA
    for name, value in (('VPLN', 0x4000), ('VCHARS', 0x4240), ('VROWLO', 0x4310), ('VROWHI', 0x4330),
                        ('VCOLTAB', 0x4350), ('VMSGS', 0x4360)):
        old = re.search(r'^%s\s*=\s*\$%04X' % (name, value), mapsrc, re.M)
        if not old:
            raise SystemExit(f'map: constant {name} = ${value:04X} not found')
        mapsrc = mapsrc.replace(old.group(0), '%s = $%04X' % (name, value - 0x4000 + VDCDATA))
    source = cockpit + '\n' + prefix_map(mapsrc) + '\n' + read('c128-game', 'game.asm')
    return asm(source)


def main():
    chunks, symbols = assemble()
    if set(chunks) != {ENTRY, CODE2, MAPCODE}:
        raise SystemExit(f'unexpected assembly chunks: {[hex(c) for c in chunks]}')
    for start, limit in ((ENTRY, cockpit_build.YLO), (CODE2, MAPCODE), (MAPCODE, VDCDATA)):
        if start + len(chunks[start]) > limit:
            raise SystemExit(f'code from ${start:04X} ends at ${start + len(chunks[start]):04X}, past ${limit:04X}')

    body = bytearray(cockpit_build.basic_stub())
    p = lambda address, data: put(body, address, data)
    cockpit_build.place_assets(p)
    map_build.place_assets(p, VDC=VDCDATA)
    cockpit_build.place_assets(p)                   # the cockpit's picture wins where they meet
    for address, data in chunks.items():
        p(address, data)
    # master copies for RESTORE (game.asm)
    get = lambda a, n: bytes(body[a - LOAD:a - LOAD + n])
    for src, dst, n in ((0x6000, symbols['MSPR'], 960), (0x7CC0, symbols['MSHOT'], 704),
                        (0x7680, symbols['MART'], 1600), (0x4478, symbols['MMAT'], 800)):
        p(dst, get(src, n))
    if symbols['MMAT'] + 800 > 0x6000:
        raise SystemExit('master copies past $5FFF')

    with open(OUT, 'wb') as f:
        f.write(bytes((LOAD & 255, LOAD >> 8)) + body)
    ends = ', '.join(f'${a:04X}-${a + len(c) - 1:04X}' for a, c in sorted(chunks.items()))
    print(f'wrote {OUT} (${LOAD:04X}-${LOAD + len(body) - 1:04X}, code {ends}, entry ${symbols["START"]:04X})')
    return symbols


if __name__ == '__main__':
    main()
