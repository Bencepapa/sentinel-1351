"""Build the native C128 Sentinel: the cockpit and the sector map as one program.

usage: python c128-game/build.py   ->  c128-game/sentinel-c128-game.prg

Sources: c128-gui/cockpit/cockpit.asm and c128-map/map.asm stay standalone
programs; this script joins them with c128-game/game.asm (the glue):

- the map's source: every label and constant it defines gets the prefix M_
  (except the ship's shared variables below), its code moves right after the cockpit's second chunk and its
  second-display data from $4000-$43FF to $2900-$2CFF (the cockpit's font lives
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
  $2900  the map's second-display data (VDC characters, planet, row tables, texts),
         between the cockpit's first code chunk and its tables
  $xx00  the map's code: right after the cockpit's second chunk
  $5300  the glue (game.asm), CPU RAM the VIC-IIe cannot use
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
CODE2 = 0x8500
MAPCODE = 0xA500         # provisional: assemble() puts the map right after the cockpit's code
VDCDATA = 0x2900
GLUE = 0x5300            # game.asm's code and data (after the master copy at $5000)
OUT = os.path.join(HERE, 'sentinel-c128-game.prg')

SHARED = {'SHLD', 'HITS', 'SHIPLOST', 'DIFF', 'SYSHP', 'PTSX', 'PTSXH', 'PTSY', 'PTON'}    # the cockpit's, used by the map

PATCHES_MAP = [
    # the ship's variables are the cockpit's
    ('SYSHP   = $3D40         ; hit points of the eight ship systems (SHIP-STATUS.md)\n', ''),
    ('DIFF:   .BYTE 2\n', ''),
    ('SHLD:   .BYTE 0\n', ''),
    ('HITS:   .BYTE 0\n', ''),
    ('SHIPDEAD:.BYTE 0\n', ''),
    # the map opens in the cockpit's 3D view: its set-up clears only the view's
    # bitmap rows and colour matrix rows (the rest is the cockpit's)
    ('RESET:  LDA #<BITMAP\n        STA PTR\n        LDA #>BITMAP\n        STA PTR+1\n        LDX #32\n        LDY #0\n'
     '        TYA\nclearb: STA (PTR),Y\n        INY\n        BNE clearb\n        INC PTR+1\n        DEX\n        BNE clearb\n',
     'RESET:                  ; (game) the 3D view is wiped before (MAPVB)\n'),
    ('        LDX #0          ; icon colors live in the color matrix: clear it\nclrmat: LDA #0\n        STA SCREEN,X\n'
     '        STA SCREEN+256,X\n        STA SCREEN+512,X\n        STA SCREEN+768,X\n        INX\n        BNE clrmat\n',
     '                        ; (game) the view\'s matrix rows are wiped before (MAPVB)\n'),
    # fire on another sector: the jump
    ('        STA BR\n        LDA #1\n        STA BV\n        JSR BOX\n        JMP BLIP\n',
     '        STA BR\n        LDA #1\n        STA BV\n        JSR BOX\n        JSR BLIP\n        LDA #1          ; (game) jump there\n        STA MJUMPF\n        RTS\n'),
    # the world is made once and ticks all the time; drawn only while the map is open
    ('        JSR PLINIT\n        JSR SHIPINIT\n', '        JSR PLINIT\n'),
    ('        BNE iconret\n        JSR GENERATE\n', '        BNE iconret\n        JSR GENONCE\n'),
    ('TICKER: LDA ICONDONE\n', 'TICKER: LDA GENDONE     ; (game) the world exists\n'),
    ('tickdr: LDA #1\n        STA MODE\n        JSR DRAWALL\n',
     'tickdr: LDA #1          ; (game) changed cells stay marked: DRAWSOME draws them\n        STA MODE\n'),
    ('icnovdc:JSR DRAWALL\n', 'icnovdc:JSR MARKALL     ; (game) a few cells a frame: DRAWSOME\n'),
    ('BLINK:  LDA ICONDONE\n        BEQ blret\n', 'BLINK:  LDA MAPSHOWN     ; (game)\n        BEQ blret\n        LDA ICONDONE\n        BEQ blret\n'),
    # the cursor starts on the ship's sector
    ('        LDA #4\n        STA CURX\n        STA SELX\n        LDA #2\n        STA CURY\n        STA SELY\n',
     '        LDA SELX        ; (game) the ship\'s sector\n        STA CURX\n        LDA SELY\n        STA CURY\n'),
    ('SELX:   .BYTE 0\nSELY:   .BYTE 0\n', 'SELX:   .BYTE 4\nSELY:   .BYTE 2\n'),
    # the second display (VDC) is off: its updates take more than a frame's
    # spare time while the cockpit runs (to be spread over frames later)
    ('VDCON:  .BYTE 1', 'VDCON:  .BYTE 0'),
    # the cursor boxes are queued and drawn one a frame, faster (FBOX in game.asm):
    # three boxes at once took most of a frame and broke the raster splits
    # the cursor box follows CURX / CURY by itself (CFOL in game.asm), one box a
    # frame: the map's own erase / draw / repair after a move is skipped
    ('nr:     LDA OLDCX       ; erase the old box unless it is the selected sector\n',
     'nr:     LDA #$18        ; (game) CFOL draws the boxes\n        STA DELAY\n        RTS\n        LDA OLDCX\n'),
    ('BOX:    JSR VDCBOX      ; mirror the box on the second display\n',
     'BOX:    JMP QBOX        ; (game) queued, drawn by FBOX\n        JSR VDCBOX\n'),
    # the mouse pointer: the cockpit shows it (sprite 0 while the map is open)
    ('PTSX:   .BYTE 0         ; its sprite position (shared with c128-game\'s cockpit)\nPTSXH:  .BYTE 0\nPTSY:   .BYTE 0\nPTON:   .BYTE 0\n', ''),
    ('PTRVIC: LDA PTSX ', 'PTRVIC: RTS\n        LDA PTSX '),
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
    ('        JSR SECSTART    ; a squadron in the sector (c128-game: the map\'s start sector)\n',
     '        JSR GAMEINIT    ; (game) the world and the start sector\n'),
    # SPACE leaves only on a new press; C= opens and closes the map
    ('        LDA CIA1PB\n        AND #$10\n        BNE nospace\n        JMP EXIT\nnospace:LDA #$BF        ; port 2 pots for the next frame\n',
     '        LDA CIA1PB\n        AND #$10\n        BNE nospace\n        LDA SPREV\n        BNE nosp2\n        JMP EXIT\n'
     'nospace:LDA #$00\n        STA SPREV\nnosp2:  LDA CIA1PB      ; (game) C= opens / closes the map (the original\'s map key)\n'
     '        AND #$20\n        BNE nomapk\n        LDA CPREV\n        BNE nomap\n        LDA #$01\n        STA CPREV\n        JSR MAPTOG\n'
     '        JMP nomap\nnomapk: LDA #$00\n        STA CPREV\n'
     'nomap:  LDA #$BF        ; port 2 pots for the next frame\n'),
    # the hooks
    ('MAPINHK:RTS ', 'MAPINHK:JMP MAPIN '),
    ('MAPVBHK:RTS ', 'MAPVBHK:JMP MAPVB '),
    ('TICKHK: RTS ', 'TICKHK: JMP WORLD '),
    ('KILLHK: RTS             ; (c128-game: the map\'s COUNT follows)\n', 'KILLHK: JMP SECKILL     ; (game)\n'),
    ('EMPTYHK:JMP SECSTART    ; standalone: the next squadron arrives (c128-game: none)\n', 'EMPTYHK:RTS             ; (game) the sector is empty now\n'),
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
    mapsrc = prefix_map(mapsrc)
    glue = read('c128-game', 'game.asm')
    global MAPCODE
    for _ in range(3):              # the map's code goes right after the cockpit's second chunk
        source = cockpit + '\n' + mapsrc.replace('        * = $1D00\n', '        * = $%04X\n' % MAPCODE) + '\n' + glue
        chunks, symbols = asm(source)
        end = CODE2 + len(chunks[CODE2])
        want = (end + 0xFF) & 0xFF00
        if want == MAPCODE:
            return chunks, symbols
        MAPCODE = want
    raise SystemExit('the map code address does not settle')


def main():
    chunks, symbols = assemble()
    if set(chunks) != {ENTRY, CODE2, MAPCODE, GLUE}:
        raise SystemExit(f'unexpected assembly chunks: {[hex(c) for c in chunks]}')
    for start, limit in ((ENTRY, VDCDATA), (CODE2, MAPCODE), (MAPCODE, 0xC000), (GLUE, 0x6000)):
        if start + len(chunks[start]) > limit:
            raise SystemExit(f'code from ${start:04X} ends at ${start + len(chunks[start]):04X}, past ${limit:04X}')

    body = bytearray(cockpit_build.basic_stub())
    p = lambda address, data: put(body, address, data)
    cockpit_build.place_assets(p)
    map_build.place_assets(p, VDC=VDCDATA)
    cockpit_build.place_assets(p)                   # the cockpit's picture wins where they meet
    for address, data in chunks.items():
        p(address, data)
    # master copy of the colour matrix's view rows for MAPCLOSE (game.asm)
    p(symbols['MMAT'], bytes(body[0x4478 - LOAD:0x4478 - LOAD + 600]))

    with open(OUT, 'wb') as f:
        f.write(bytes((LOAD & 255, LOAD >> 8)) + body)
    ends = ', '.join(f'${a:04X}-${a + len(c) - 1:04X}' for a, c in sorted(chunks.items()))
    print(f'wrote {OUT} (${LOAD:04X}-${LOAD + len(body) - 1:04X}, code {ends}, entry ${symbols["START"]:04X})')
    return symbols


if __name__ == '__main__':
    main()
