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
  $C000  more of the glue, in the RAM under the KERNAL (MMU $3E: the game calls no
         KERNAL routine; the NMI and IRQ vectors point to an RTI)
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
HIGH2 = 0xE000           # more code, under the KERNAL too: loaded at HIGH2SRC (the view's bitmap)
HIGH2SRC = 0x6200        # packed image; overlaps type-1 slots restored by GINIT2
HIGH = 0xC000            # game.asm's code in the RAM under the KERNAL (MMU $3E)
OUT = os.path.join(HERE, 'sentinel-c128-game.prg')

SHARED = {'SHLD', 'HITS', 'SHIPLOST', 'DIFF', 'SYSHP', 'PTSX', 'PTSXH', 'PTSY', 'PTON'}    # the cockpit's, used by the map

PATCHES_MAP = [
    # the map's beeps set voices 1 and 2 up whole (game.asm GSNDTOG, GBLIP): a fight's
    # sounds change them while the map is open
    ('SNDTOG: DEC SNDCNT\n        BNE sndret\n        LDA #2\n        STA SNDCNT\n        LDA SNDVAL\n'
     '        EOR #$01\n        STA SNDVAL\n        STA $D404\nsndret: RTS\n',
     'SNDTOG: JMP GSNDTOG     ; (game)\n'),
    ('BLIP:   LDA #0\n        STA $D404\n        STA $D406\n        STA $D402\n        LDA #8\n        STA $D403\n'
     '        LDA #1\n        STA $D405\n        LDA #$8F\n        STA $D401\n        LDA #$41\n        STA $D404\n        RTS\n',
     'BLIP:   JMP GBLIP       ; (game)\n'),
    # the planet's frames step in game.asm (GPLANET): the map's code is full
    ("PLANET: INC PCNT\n        LDA PCNT\n        AND #$07\n        BNE plrt\n        LDX PFRM        ; $39-$3C, then the fifth frame, the original's unused $3D\n        CPX #PL5        ; (it fills the gap between $3C and $39)\n        BEQ plk0\n        INX\n        CPX #$3D\n        BCC plkok\n        LDX #PL5\n        BNE plkok\nplk0:   LDX #$39\nplkok:   STX PFRM\n        STX $47F9\n        JSR VDCPLDEF\nplrt:  RTS\n", 'PLANET: JMP GPLANET     ; (game)\n'),
    # the planet's fifth frame: pointer $3D is the cockpit's barrels here, $FF is free
    ('PL5     = $3D           ; sprite pointer of the planet\'s fifth frame (c128-game: $FF)\n',
     'PL5     = $FF           ; (game) sprite pointer of the planet\'s fifth frame\n'),
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
    # fire on the ship's own sector closes the map (the original's $FBFB)
    ('        BNE selgo\n        RTS\nselgo:  LDA SELX\n',
     '        BNE selgo\n        LDA #2          ; (game) no jump\n        STA MJUMPF\n        RTS\nselgo:  LDA SELX\n'),
    # the squadrons' move in steps (MVSTEP): all 60 sectors at once took 100 lines
    ('mprow:  LDA #9\n        STA PCOL\nmpcol:  JSR MOVECELL\n        DEC PCOL\n        BPL mpcol\n        DEC PROW\n        BPL mprow\n        LDX #59\n',
     '        LDA #9\n        STA PCOL\n        LDA #1\n        STA MVON\n        RTS\nMVCOMMIT:LDX #59\n'),
    ('        LDA NEWCT,X\n        STA COUNT,X\n        DEX\n        BPL mpcb\n        RTS\n',
     '        LDA NEWCT,X\n        STA COUNT,X\n        DEX\n        BPL mpcb\n        JMP SQINCHK     ; (game) into the ship\'s sector? ($BEDF)\n'),
    # the mouse pointer: the cockpit shows it (sprite 0 while the map is open)
    ('PTSX:   .BYTE 0         ; its sprite position (shared with c128-game\'s cockpit)\nPTSXH:  .BYTE 0\nPTSY:   .BYTE 0\nPTON:   .BYTE 0\n', ''),
    ('PTRVIC: LDA PTSX ', 'PTRVIC: RTS\n        LDA PTSX '),
]
MAP_EXTRA = ""

PATCHES_COCKPIT = [
    ('        JSR SECSTART    ; a squadron in the sector (c128-game: the map\'s start sector)\n',
     '        JSR GAMEINIT    ; (game) the world and the start sector\n'),
    # SPACE is the proton torpedo (TSPACE, game.asm GTORP), RUN/STOP leaves (the same
    # bytes as before: the code after keeps its addresses); C= opens and closes the map
    ('        LDA CIA1PB\n        AND #$10\n        BNE nospace\n        JMP EXIT\nnospace:LDA #$BF        ; port 2 pots for the next frame\n',
     '        LDA CIA1PB\n        BMI nostop      ; (game) RUN/STOP leaves\n        JMP EXIT\nnostop: AND #$10        ; SPACE: the torpedo (GSPACE while held)\n        BNE nospace\n        JSR GSPACE\n'
     'nospace:LDA #$00\n        STA SPREV\nnosp2:  JSR MAPKEY      ; (game) C= or the right mouse button: the map opens / closes\n'
     '        BNE nomapk\n        LDA CPREV\n        BNE nomap\n        LDA #$01\n        STA CPREV\n        JSR MAPTOG\n'
     '        JMP nomap\nnomapk: LDA #$00\n        STA CPREV\n'
     'nomap:  LDA #$BF        ; port 2 pots for the next frame\n'),
    # the hooks
    ('MAPINHK:RTS ', 'MAPINHK:JMP MAPIN '),
    ('MAPVBHK:RTS ', 'MAPVBHK:JMP MAPVB '),
    ('TICKHK: RTS ', 'TICKHK: JMP WORLD '),
    ('KILLHK: RTS             ; (c128-game: the map\'s COUNT follows)\n', 'KILLHK: JMP SECKILL     ; (game)\n'),
    ('EMPTYHK:JMP SECSTART    ; standalone: the next squadron arrives (c128-game: none)\n', 'EMPTYHK:RTS             ; (game) the sector is empty now\n'),
    ('nov3:   LDA #168        ; the explosions', 'nov3:   JSR VIEWWORK    ; (game)\n        LDA #168        ; the explosions'),
    # the RAM under the KERNAL is the game's: $C000-$CFFF holds code (HIGH)
    ('        LDA #$0E        ; bank 0 RAM + I/O + KERNAL ROM\n', '        LDA #$3E        ; (game) bank 0 RAM + I/O, RAM under the KERNAL too\n'),
    # the hyperspace cursor test (H, game.asm HINPUT): input and the crosshair's colour
    ('iv1:    JMP INPUT\n', 'iv1:    JMP HINPUT      ; (game)\n'),
    # hyperspace (game.asm HYPVB): the view's frame work, the crosshair hidden
    ('VIEWVB: LDA MAPSHOWN\n        ORA WIPE\n', 'VIEWVB: LDA MAPSHOWN\n        ORA WIPE\n        ORA HYPON       ; (game)\n'),
    ('sc3:    STA $D001\n', 'sc3:    JSR HCRY        ; (game) hidden in hyperspace\n'),
    # sprite 1 stays the map's planet while the map's pixels are on the screen (HMAP)
    ('        LDA MAPSHOWN\n        BNE scm\n', '        LDA MAPSPR      ; (game)\n        BNE scm\n'),
    ('        LDA MAPSHOWN    ; the map open: the pointer (if a mouse), the planet\n        BEQ scv\n',
     '        LDA MAPSPR      ; (game) the map open: the pointer (if a mouse), the planet\n        BEQ scv\n'),
    # in hyperspace the meteors' sprites after the crosshair's (HSPRC)
    ('        JSR SPRCROSS    ; the crosshair\n', 'sprcj:  JSR SPRCROSS    ; (game) the crosshair (HSPRC, the meteors, in hyperspace)\n'),
    # no burst over the open map (MAPOPEN stops them; a shot reaching the ship started one)
    ('        LDA EXPL2       ; ($CA80) 12 points burst where it was\n        BNE efm9\n',
     '        LDA EXPL2       ; ($CA80) 12 points burst where it was\n        ORA MAPSHOWN    ; (game) not over the map\n        BNE efm9\n'),
    # the tracking passes in the fight's slot stop earlier: a pass can take ~20 lines, and
    # after a shot the fight starts late in the view (line 133), past 194 otherwise
    ('        LDA #176        ; the fight\'s slot: until line 176\n',
     '        LDA #160        ; (game) the fight\'s slot: until line 160\n'),
    # squadron types 2 and 3 (game.asm GTYPE, GESHP, GSTRX / GSTRY, GSHLOAD)
    ('NEWWAVE:LDA #$01        ; type 1\n', 'NEWWAVE:LDA SQTYPE      ; (game) the squadron\'s type ($A5)\n'),
    ('        LDA #$01\n        STA $D02D\n        LDA #$00\n',
     '        LDA #$01\n        STA $D02D\n        JSR GTYPE       ; (game) the type\'s looks\n        LDA #$00\n'),
    ('        LDY #>STREAMS   ; x stream (original page $E8, table $FF15)\n',
     '        JSR GSTRX       ; (game) x stream by type ($FF15)\n'),
    ('        LDY #$82        ; y stream, STREAMS page + 2 ($EA, table $FF18)\n',
     '        JSR GSTRY       ; (game) y stream by type ($FF18)\n'),
    ('        SEC\n        LDA #$2F\n        SBC ZT\n        STA ESHP,Y\n',
     'plshp:  SEC             ; (game) $2E86; types 2, 3: JSR GESHP ($2EBE, $2F18), set by GTYPE\n        LDA #$2F\n        SBC ZT\n        STA ESHP,Y\n'),
    ('        LDA $D01C       ; type 1: single colour, not expanded, in front\n        AND #$8F\n        STA $D01C\n        LDA $D01D\n        AND #$8F\n',
     '        LDA $D01C       ; (game) the type\'s colours and width: GTYPE sets sprmc, sprxe\nsprmc:  AND #$8F\n        STA $D01C\n        LDA $D01D\nsprxe:  AND #$8F\n'),
    # in hyperspace no steering, enemy fire or approach in the vertical blank (HVBR)
    ('vbr:    LDA APPR\n        BEQ vbdog\n', 'vbr:    JSR HVBR        ; (game)\n        BEQ vbdog\n'),
    # in hyperspace the border pulses (HBORD), the sweeps leave it alone
    ('        BNE sd0\n        LDA #$0E\n        STA HUDBRD\nsd0:    RTS\n',
     '        BNE sd0\n        LDA #$0E\n        JSR HBRDSET     ; (game)\nsd0:    RTS\n'),
    ('vbr0:   LDA RADPEND\n        BEQ vbr\n','vbr0:   LDA RADPEND\n        BEQ vbr\n        LDX HNORAD      ; (game) no radar marks in hyperspace until its scanner runs\n        BNE vbr\n'),
    ('        LDA NUMCOL      ; white, light green while the target is behind ($3934)\n',
     '        LDA HCOLOR      ; (game) NUMCOL, or the colours of the hyperspace test\n'),
    # a squadron coming into the ship's sector starts the dogfight (ARREND in game.asm)
    ('        LDA #$00        ; ($C7DC) the dogfight\n', 'DOGSTART:LDA #$00       ; ($C7DC) the dogfight\n'),
    # the stars keep the map's pixels while it is open (GPLOT, GERASE in game.asm)
    ('PLOTSTAR:\n        STX SAVEX\n        LDA STARX,X\n        STA POSX\n        LDA STARY,X\n        STA POSY\n        JSR PIXADDR\n'
     '        LDA (PTR),Y\n        ORA MASK3,X\n        STA (PTR),Y\n        LDX SAVEX\n        RTS\n',
     'PLOTSTAR:JMP GPLOT      ; (game)\n'),
    ('ERASESTAR:\n        STX SAVEX\n        LDA STARX,X\n        STA POSX\n        LDA STARY,X\n        STA POSY\n        JSR PIXADDR\n'
     '        LDA (PTR),Y\n        AND CLEARM,X\n        STA (PTR),Y\n        LDX SAVEX\n        RTS\n',
     'ERASESTAR:JMP GERASE    ; (game)\n'),
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
    icon = '        LDA COLC\n        STA (MP),Y\n'        # both icon cells: value 1 (the stars) white
    if mapsrc.count(icon) != 2:
        raise SystemExit('map: the icon cells\' colour writes not found')
    mapsrc = mapsrc.replace(icon, '        LDA COLC\n        ORA #$10        ; (game) the stars\n        STA (MP),Y\n')
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
        want = (end + 0x0F) & 0xFFF0    # (a page boundary here would waste what the map needs)
        if want == MAPCODE:
            return chunks, symbols
        MAPCODE = want
    raise SystemExit('the map code address does not settle')


def lz_pack(data):
    """Tokens for GUNPACK: $00-$7F n + 1 literals; $80-$FF a copy of (n & $7F) + 3
    bytes from distance d back (two bytes follow). Greedy, longest match."""
    out, lits, i, where = bytearray(), bytearray(), 0, {}
    def flush():
        while lits:
            n = min(len(lits), 128)
            out.append(n - 1); out.extend(lits[:n]); del lits[:n]
    while i < len(data):
        best, bestd = 0, 0
        for j in reversed(where.get(data[i:i + 3], [])[-64:]):
            n = 0
            while i + n < len(data) and n < 130 and data[j + n] == data[i + n]:
                n += 1
            if n > best:
                best, bestd = n, i - j
        if best >= 3:
            flush()
            out.append(0x80 | (best - 3)); out.append(bestd & 255); out.append(bestd >> 8)
            for k in range(i, i + best):
                where.setdefault(data[k:k + 3], []).append(k)
            i += best
        else:
            where.setdefault(data[i:i + 3], []).append(i)
            lits.append(data[i]); i += 1
    flush()
    return bytes(out)


def torp_frames(raw):
    """The torpedo's 32 frames of 128 bytes, each packed on its own (TORPA): $80 + n
    zero bytes, or n literal bytes."""
    out = bytearray()
    for f in range(32):
        b, i = raw[f * 128:f * 128 + 128], 0
        while i < len(b):
            if b[i] == 0:
                n = 0
                while i < len(b) and b[i] == 0 and n < 127:
                    i += 1; n += 1
                out.append(0x80 | n)
            else:
                j = i
                while j < len(b) and b[j] != 0 and j - i < 127:
                    j += 1
                out.append(j - i); out.extend(b[i:j]); i = j
    return bytes(out)


def main():
    chunks, symbols = assemble()
    if set(chunks) != {ENTRY, CODE2, MAPCODE, GLUE, HIGH, HIGH2}:
        raise SystemExit(f'unexpected assembly chunks: {[hex(c) for c in chunks]}')
    for start, limit in ((ENTRY, VDCDATA), (CODE2, MAPCODE), (MAPCODE, 0xC000), (GLUE, 0x6000), (HIGH, 0xD000), (HIGH2, 0xEDC0)):
        if start + len(chunks[start]) > limit:
            raise SystemExit(f'code from ${start:04X} ends at ${start + len(chunks[start]):04X}, past ${limit:04X}')

    body = bytearray(cockpit_build.basic_stub())
    p = lambda address, data: put(body, address, data)
    cockpit_build.place_assets(p)
    map_build.place_assets(p, VDC=VDCDATA, PL5=0x7FC0)   # (the planet's fifth frame: pointer $FF, behind the bottom strip)
    cockpit_build.place_assets(p)                   # the cockpit's picture wins where they meet
    for address, data in chunks.items():
        if address != HIGH2:
            p(address, data)
    # the $E000 image: code, the fighters' shape masters by type (type 1's come from
    # $2900 VDC area), type 2's streams, the torpedo's frames; packed into the
    # 3D view's bitmap, which GAMEINIT unpacks and clears
    ref = os.path.join(ROOT, 'c128-gui', 'ref')
    sprites = open(os.path.join(ref, 'sprites-4800.bin'), 'rb').read()
    order = [b + i for b in (0x20, 0x30, 0x40, 0x60, 0x70) for i in range(16)]
    shape = lambda s: sprites[order.index(s) * 64:order.index(s) * 64 + 64]
    # The VDC is disabled in the joined game; its data holds type-1 masters.
    # Unpacking may overlap their live sprite slots; GINIT2 restores them next.
    assert symbols["TSH1"] == VDCDATA
    assert chunks[MAPCODE][symbols["M_VDCON"] - MAPCODE] == 0, "TSH1 reuses disabled VDC data"
    p(symbols["TSH1"], b"".join(shape(s) for s in range(0x20, 0x2F)))
    image = bytearray(chunks[HIGH2])
    def at(name, data):
        off = symbols[name] - HIGH2
        image.extend(bytes(max(0, off + len(data) - len(image))))
        image[off:off + len(data)] = data
    at('TSH2', b''.join(shape(s) for s in range(0x3E, 0x45)))
    at('TSH3', b''.join(shape(s) for s in range(0x31, 0x39)))
    at('STR2X', open(os.path.join(ref, 'streams2-0600.bin'), 'rb').read())
    at('STR2Y', open(os.path.join(ref, 'streams2-8100.bin'), 'rb').read())
    at('TORPA', torp_frames(open(os.path.join(ref, 'torpedo-a000.bin'), 'rb').read()))
    at('TSHOT', shape(0x67) + shape(0x68))
    end = HIGH2 + len(image)
    assert end <= 0xFF00, f'the $E000 image ends at ${end:04X}'
    packed = bytes((end & 255, end >> 8)) + lz_pack(bytes(image))
    assert HIGH2SRC + len(packed) <= 0x7680, f'the packed $E000 image ({len(packed)} bytes) overlaps the cockpit art'
    p(HIGH2SRC, packed)
    # master copy of the colour matrix's view rows for MAPCLOSE (game.asm)
    p(symbols['MMAT'], bytes(body[0x4478 - LOAD:0x4478 - LOAD + 600]))

    with open(OUT, 'wb') as f:
        f.write(bytes((LOAD & 255, LOAD >> 8)) + body)
    ends = ', '.join(f'${a:04X}-${a + len(c) - 1:04X}' for a, c in sorted(chunks.items()))
    print(f'wrote {OUT} (${LOAD:04X}-${LOAD + len(body) - 1:04X}, code {ends}, entry ${symbols["START"]:04X})')
    return symbols


if __name__ == '__main__':
    main()
