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
  $2900  type-1 masters (VDC is disabled); $3800-$3BBF type-2/3 masters,
         $3E00-$3FFF type-2 X streams. The map shares the cockpit address tables.
  $5E00  packed $E000 image, after glue and over sprite slots restored at init
  $0C60  resident mothership/message/repair code (BASIC's RAM: the game never returns)
  $D000  init-only packed STR2Y; $D100 low-code stream; $DF00 runtime tables
  $EA16  resident minefield code/art/slot backup, full through $F6F8
  $xx00  the map's code: right after the cockpit's second chunk
  $5300  the glue (game.asm), CPU RAM the VIC-IIe cannot use
  $C000  more of the glue, in the RAM under the KERNAL (MMU $3E: the game calls no
         KERNAL routine; the NMI and IRQ vectors point to an RTI)
"""

import os
import json
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
HIGH2SRC = 0x5E00        # packed image; overlaps type-1 slots restored by GINIT2
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

# The game never returns to BASIC (2026-11-17, the user's decision: RUN/STOP does
# nothing, BASIC's memory is the game's). What existed only for the exit becomes
# free space of the same size, so that no cockpit address moves: the cockpit's EXIT
# routine, and START's saves of the caller's state (it keeps SEI, the MMU and the VDC
# blanking; the dead SAV* variables stay where they are, in the reset snapshot).
EXIT_LINES = ['EXIT:   LDA #0', '        STA VICENA', '        STA $D404', '        STA $D418']
for _reg, _sav in (('$D011', 'SAV11'), ('$D016', 'SAV16'), ('$D018', 'SAV18'), ('VICENA', 'SAVENA'),
                   ('$D01B', 'SAV1B'), ('$D01D', 'SAV1D'), ('CIA2PA', 'SAVC2'), ('CIA1PA', 'SAVPA'),
                   ('BORDER', 'SAVBOR'), ('BG', 'SAVBG'), ('FAST', 'SAVFAST'), ('MMUCR', 'SAVMMU'),
                   ('PTR', 'SAVPTRL'), ('PTR+1', 'SAVPTRH')):
    EXIT_LINES += ['        LDA ' + _sav, '        STA ' + _reg]
EXIT_OLD = '\n'.join(EXIT_LINES + ['        CLI', '        RTS']) + '\n'
EXIT_FREE = 96          # EXIT-SPRCROSS
EXIT_NEW = ('EXIT:                   ; (game) no return to BASIC: these bytes are free\n'
            'CKEXITFREE:.BYTE ' + ','.join(['0'] * EXIT_FREE) + '\n')
START_SAVES = [('PTR+1', 'SAVPTRH'), ('CIA1PA', 'SAVPA'), ('CIA2PA', 'SAVC2'), ('$D011', 'SAV11'),
               ('$D016', 'SAV16'), ('$D018', 'SAV18'), ('VICENA', 'SAVENA'), ('BORDER', 'SAVBOR'),
               ('BG', 'SAVBG'), ('FAST', 'SAVFAST'), ('$D01B', 'SAV1B'), ('$D01D', 'SAV1D')]
START_OLD = ''.join(f'        LDA {r}\n        STA {s}\n' for r, s in START_SAVES)
START_FREE = 69         # 72 bytes of saves less the JMP
START_NEW = ('        JMP g_st1       ; (game) no return to BASIC: the caller\'s state is not saved\n'
             'CKSTARTFREE:.BYTE ' + ','.join(['0'] * START_FREE) + '\ng_st1:\n')

PATCHES_COCKPIT = [
    ('        JSR SECSTART    ; a squadron in the sector (c128-game: the map\'s start sector)\n',
     '        JSR GAMEINIT    ; (game) the world and the start sector\n'),
    # No return to BASIC (2026-11-17): the cockpit's EXIT (96 bytes) is free space,
    # SPRCROSS after it keeps its address (CKEXITFREE, see EXIT_FREE below).
    (EXIT_OLD, EXIT_NEW),
    # SPACE is the proton torpedo (TSPACE, game.asm GTORP), RUN/STOP does nothing (the
    # same bytes as before: the code after keeps its addresses, the frame without
    # RUN/STOP takes the same branch); C= opens and closes the map
    ('        LDA CIA1PB\n        AND #$10\n        BNE nospace\n        JMP EXIT\nnospace:LDA #$BF        ; port 2 pots for the next frame\n',
     '        LDA CIA1PB\n        BMI nostop      ; (game) RUN/STOP: nothing (no return to BASIC)\n        NOP\n        NOP\n        NOP\nnostop: AND #$10        ; SPACE: the torpedo (GSPACE while held)\n        BNE nospace\n        JSR GSPACE\n'
     'nospace:LDA #$00\n        STA SPREV\nnosp2:  JSR MAPKEY      ; (game) C= or the right mouse button: the map opens / closes\n'
     '        BNE nomapk\n        LDA CPREV\n        BNE nomap\n        LDA #$01\n        STA CPREV\n        JSR GMAPTOG\n'
     '        JMP nomap\nnomapk: LDA #$00\n        STA CPREV\n'
     'nomap:  LDA #$BF        ; port 2 pots for the next frame\n'),
    # the hooks
    ('INPUT:  JSR POTS', 'INPUT:  JSR GPOTS'),
    ('MAPINHK:RTS ', 'MAPINHK:JMP MAPIN '),
    ('MAPVBHK:RTS ', 'MAPVBHK:JMP MAPVB '),
    ('TICKHK: RTS ', 'TICKHK: JMP WORLD '),
    ('        STA CIA1PA\n        JMP frame\n', '        STA CIA1PA\n        JMP CLOCKFRAME\n'),
    ('        JSR FIREPH      ; the phasors,', '        JSR FKEYVIEW    ; the phasors,'),
    ('        LDA #194\n        JSR WAITLN\n', 'fkey_guns:LDA #194\n        JSR WAITLN\n'),
    ('        JSR SPRGUNS     ; sprites 0 and 3 become the two guns\n        JSR SWEEPSND\n',
     '        JSR SPRGUNS     ; sprites 0 and 3 become the two guns\n        JSR FKEYGUNS\n'),
    # Both explosion jobs already stop at line 204. Skip their call overhead
    # once that slot has passed, leaving time to reach the line-233 split.
    ('nofgt:\n        LDA #204\n        STA EXLIM\n        JSR EXPLODE\n        JSR EXPLODE2\n',
     'nofgt:  LDA $D012\n        CMP #204\n        BCS after_gun_explosions\n'
     '        JSR GUNEXPLOSIONS\n        NOP\nafter_gun_explosions:\n'),
    ('        LDA #230\n        JSR WAITLN\n', 'fkey_strip:LDA #230\n        JSR WAITLN\n'),
    ('        JSR SWEEPSND\n        LDA #242', '        JSR FKEYSWEEP\n        LDA #242'),
    ('        JSR INPUTV      ; vertical blank:', '        JSR FKEYINPUT   ; vertical blank:'),
    ('KILLHK: RTS             ; (c128-game: the map\'s COUNT follows)\n', 'KILLHK: JMP SECKILL     ; (game)\n'),
    ('EMPTYHK:JMP SECSTART    ; standalone: the next squadron arrives (c128-game: none)\n', 'EMPTYHK:RTS             ; (game) the sector is empty now\n'),
    ('        JSR EMPTYHK\n', '        JSR SECTORNOTICE\n'),
    ('        LDA #$01\n        STA APPR\n        STA RELAYOUT\n        LDA #$00\n        STA APRUN\n        LDA #$0F\n',
     '        LDA #$01\n        JSR GROUPNOTICE\n        STA RELAYOUT\n        LDA #$00\n        STA APRUN\n        LDA #$0F\n'),
    ('        JSR SHIPHIT     ; ($84D7)\n', '        JSR MISSIONHIT  ; ($84D7)\n'),
    ('        JMP TRKMSG\n', '        JMP TRACKNOTICE\n'),
    ('        JMP ALERT       ;', '        JMP APPROACHNOTICE ;'),
    ('arr2:   JSR SECALERT    ;', 'arr2:   JSR ENTERNOTICE  ;'),
    ('        JSR SHOWTG\n        LDA SQCOUNT\n        BNE arr2\n',
     '        JSR EMPTYROW\n        LDA SQCOUNT\n        BNE arr2\n'),
    ('        STA APDLY\n        JSR LRCLEAR\narr9:', '        STA APDLY\n        JSR HREADCLEAR\narr9:'),
    ('        JSR BLIPPOS\n        JSR LRCLEAR\n', '        JSR BLIPPOS\n        JSR HREADCLEAR\n'),
    # Scanner setup runs on schedule; the message only owns the text row.
    ('afl5:   LDA MSGON       ; ($C6DE) the scanner waits for a standing message;\n'
     '        BEQ afl3        ; a scrolling one goes\n'
     '        LDA MSGMODE\n        BEQ afl4\n        INC APDLY\n        RTS\n'
     'afl4:   JSR MSGSTOP\n',
     'afl5:   JMP afl3\n'
     '        .BYTE 0,0,0,0,0,0,0,0,0,0,0\n'
     'afl4:   .BYTE 0,0,0\n'),
    ('lr7:    LDA #$7B        ; ($3839) the readings: X (side), Y (up), Z (depth)\n        STA LRROW+9\n',
     'lr7:    JSR SCANROW\n        NOP\n        NOP\n'),
    ('        STA LRROW+13\n', '        JSR SCANZEROX\n'),
    ('        STA LRROW+21\n', '        JSR SCANZEROY\n'),
    ('stinit: JSR NEWSTAR\n        JSR PLOTSTAR\n', 'stinit: JSR NEWSTAR\n        JSR STARTPLOT\n'),
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
    mapsrc = patch(mapsrc, [('        STA DEAD,X\n        CPX #4\n',
                              '        JSR ENDPLANETFLAG\n        CPX #4\n')], 'planet end hook')
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
    # The bitmap-address tables are identical to the cockpit's. Sharing them
    # frees $3800-$3BBF for fighter masters; disabled VDC names at $3E00 hold STR2X.
    for name, old, new in [('YLO', 0x3800, 0x2D00), ('YHI', 0x3900, 0x2E00),
                           ('XLO', 0x3A00, 0x2F00), ('XHI', 0x3A28, 0x2F28)]:
        pattern = r'^%s\s*=\s*\$%04X' % (name, old)
        mapsrc, count = re.subn(pattern, '%s = $%04X' % (name, new), mapsrc, flags=re.M)
        assert count == 1, name
    mapsrc = mapsrc.replace('        STA LASTMSG', '        JSR BATTLEEVENT')
    mapsrc = prefix_map(mapsrc)
    # Same-size raster slots; repair rewrites these only while docked.
    cockpit = cockpit.replace('        LDA #$3B        ; multicolor bitmap:', 'MRMODE: LDA #$3B        ; multicolor bitmap:')
    cockpit = cockpit.replace('        LDA #$18\n        STA $D016\n        STA $D018', 'MRATTR: LDA #$18\n        STA $D016\n        STA $D018')
    cockpit = cockpit.replace('        LDY #10         ; (timed from line 74:', 'MRWAIT: LDY #10         ; (timed from line 74:')
    cockpit = cockpit.replace('        JSR SPRGUNS     ; sprites', 'MRGUN:  JSR SPRGUNS     ; sprites')
    # A docking refill must preserve the lifetime hit count ($F432/$F433).
    # BIT preserves both size and cycles of the initialization-only stores.
    cockpit = cockpit.replace('        STA HITS\n        STA HITS+1\n        JMP SHOWSH',
                              '        BIT HITS\n        BIT HITS+1\n        JMP SHOWSH')
    cockpit = cockpit.replace('        LDA #$30\n        STA SUBN', 'PHBUD: LDA #$30\n        STA SUBN')
    glue = read('c128-game', 'game.asm')
    # Blank before delays or snapshot writes, after START banks out BASIC ROM:
    # the helper at $52AC is inaccessible under BASIC's initial MMU mapping.
    # Five bytes replace LDA/STA without moving any cockpit symbol.
    cockpit = patch(cockpit, [('        LDA PTR\n        STA SAVPTRL',
                               'VDCENTRY:JSR ENDVDCBLANK\n        NOP\n        NOP'),
                              (START_OLD, START_NEW)], 'VDC startup')
    # Ending workspace is installed before GINIT2 consumes its $E000 staging.
    # All existing lower instructions and symbols retain their size/address.
    glue = glue.replace('JSR GINIT2      ;', 'JSR ENDINIT     ;', 1)
    glue = patch(glue, [('        JSR GENONCE\n        JSR SHOWSEC\n',
                         '        JSR GENONCE\n        JSR CLOCKINIT\n')], 'clock reset hook')
    cockpit = patch(cockpit, [('        STA SHIPLOST    ; ($8300)',
                               '        JSR ENDSHIPFLAG ; ($8300)')], 'ship end hook')
    cockpit = cockpit.replace('KILLHK: JMP SECKILL', 'KILLHK: JMP ENDKILL')
    glue = glue.replace('JSR MSOFF', 'JSR ENDMSOFF')
    glue = glue.replace('JSR MRGLYPHBACK', 'JSR ENDBASETALLY')
    cockpit = cockpit.replace('        LDY HUDE+2      ; OUT OF ENERGY',
                              '        JSR ENDENERGY   ; OUT OF ENERGY')
    glue = glue.replace('g_tp9:  DEC $485B', 'g_tp9:  JSR ENDPROTONUSED')
    glue = glue.replace('        LDY HUDE+3      ; the ones digit',
                        '        JSR ENDONE      ; the ones digit')
    # Same-size entry replacements; every existing lower symbol stays fixed.
    # The minefield is the MINES package in S1 (overlay.asm). A sector's arrival
    # (MSECTOR -> MSOFF) calls it through the trampoline OVMNOFF, which loads it if
    # it is missing; the base sequence's own calls after that are direct (no cycle
    # added in the timed positioning loop; audit_s1 lists them).
    glue = glue.replace('        JMP MSPOS\n', '        JMP MNVIEW\n')
    glue = glue.replace('        JSR MSPOSOFF\n', '        JSR OVMNOFF\n', 1)
    # Preserve every low-code address: helpers live in the minefield's high tail.
    glue = glue.replace('mp_pass:LDA $D012', 'mp_pass:JSR MNPASS')
    glue = glue.replace('        JSR STEER\nmp_depth:', '        JSR MNSTEER\nmp_depth:')
    glue = glue.replace('MSPREAD:JMP lr7', 'MSPREAD:JMP MNREAD')
    glue = glue.replace('        JSR APINIT\n        LDA EVIS', '        BIT APINIT\n        LDA EVIS')
    glue = glue.replace('g_tp6:  LDA TREQ', 'g_tp6:  JSR MNREQ')
    glue = patch(glue, [('g_ms0:  STA MSKIND\n        JSR MSPOSON\n', 'g_ms0:  STA MSKIND\n        JSR OVBASEIN\n')], 'base arrival')
    mine_source = read('c128-game', 'mines.asm')
    sprites = open(os.path.join(ROOT, 'c128-gui/ref/sprites-4800.bin'), 'rb').read()
    mine_raw = sprites[65*64:77*64]  # shape $71-$7C in the reference's order
    mine_packed = torp_frames(mine_raw)
    mine_source = mine_source.replace('; MNARTDATA', '.BYTE ' + ','.join(str(v) for v in mine_packed))
    tunnel = read('c128-game', 'tunnel.asm')
    saved = json.load(open(os.path.join(ROOT, 'briefs/ref/c64-minefield.state.json')))
    import base64
    original = base64.b64decode(saved['state']['arrays']['ram'])
    tunnel = tunnel.replace('; MTTABLEDATA', '.BYTE ' + ','.join(str(v) for v in original[0xF4F:0xF7F]))
    table = tunnel[tunnel.index('MTTABLE:'):]
    tunnel = tunnel[:tunnel.index('MTTABLE:')]
    mine_source = mine_source.replace('; TUNNELDATA', tunnel)
    mine_source = mine_source.replace('MNEXTRA:', table + '\nMNEXTRA:')
    mine_source = mine_source.replace('MNEXTRA:', '''MTINIT:
        JSR g_upb
        LDA #<MTSTAGE
        STA CSRC
        LDA #>MTSTAGE
        STA CSRC+1
        LDA #<MNEXTRA
        STA CDST
        LDA #>MNEXTRA
        STA CDST+1
        JMP g_upb
MTSTAGE = $DCE6
MNEXTRA:''')
    import itertools
    stream = bytes(v for value, group in itertools.groupby(open(os.path.join(ROOT, 'c128-gui/ref/streams-e800.bin'), 'rb').read()[256:1024]) for v in (len(list(group)), value))
    mine_source = mine_source.replace('; MNSTREAMDATA', '.BYTE ' + ','.join(str(v) for v in stream))
    glue = glue.replace('GINIT3END:', mine_source + '\nGINIT3END:')
    glue = glue.replace('        LDA #$D1\n        STA CSRC+1', '        LDA #$D0\n        STA CSRC+1')
    glue = glue.replace('        LDA #$00\n        STA CSRC\n        LDA #$D0\n        STA CSRC+1\n        LDA #<LOWSTART', '        LDA #$60\n        STA CSRC\n        LDA #$D0\n        STA CSRC+1\n        LDA #<LOWSTART')
    glue = glue.replace('        JSR g_upb\n        LDX #141', '        JSR MTINIT\n        LDX #141')
    global MAPCODE
    for _ in range(3):              # the map's code goes right after the cockpit's second chunk
        source = cockpit + '\n' + mapsrc.replace('        * = $1D00\n', '        * = $%04X\n' % MAPCODE) + '\n' + glue
        source += '\n' + ending_source(source, read) + '\n' + read('c128-game', 'end-loader.asm') + '\n' + read('c128-game', 'end-events.asm')
        source += '\n' + read('c128-game', 'bank1.asm') + '\nB1STUBLEN = B1STUBEND-256\n'
        source += '\n' + read('c128-game', 'overlay.asm')
        LISTING.clear()
        chunks, symbols = asm(source, LISTING)
        end = CODE2 + len(chunks[CODE2])
        want = (end + 0x0F) & 0xFFF0    # (a page boundary here would waste what the map needs)
        if want == MAPCODE:
            event_address = symbols['MSUNPACK']
            events = chunks.pop(event_address)
            assert symbols['ENDEVENTEND'] <= symbols['MSCOUNT'], 'ending events overlap live low code'
            low = bytearray(chunks[0x0C60])
            offset = event_address-0x0C60
            low[offset:offset+len(events)] = events
            chunks[0x0C60] = bytes(low)
            return chunks, symbols
        MAPCODE = want
    raise SystemExit('the map code address does not settle')


LISTING = []


def audit_s1(symbols):
    """Every resident instruction with an operand in S1 must be a trampoline's
    (overlay.asm): a call into S1 checks that its package is loaded. The slot's
    own code (GINIT3 at init, the packages) and the init staging are not resident."""
    init = (symbols['B1INITAT'], symbols['ENDSTUBIMG'])
    bad = []
    for pc, mn, mode, value in LISTING:
        if S1BASE <= pc < S1END or init[0] <= pc < init[1]:
            continue
        if mode in ('abs', 'abx', 'aby', 'ind') and S1BASE <= value < S1END:
            init_only = (value == symbols['GINIT3'] and symbols['GUNPK2'] <= pc < symbols['GUNPK2'] + 16) or \
                (symbols['ENDINIT'] <= pc < symbols['ELVADR'] and value in (symbols['B1INIT'], 0xEA00)) or \
                (value == symbols['MTINIT'] and symbols['MSUNPACK'] <= pc < symbols['MSPOS'])   # (retired MSUNPACK, overwritten by the events)
            # The base sequence after MSECTOR's check: MSVIEW's JMP MNVIEW (MSSTATE 16), and MSPOS
            # (called only from MINES) into MINES' helpers.
            in_sequence = value in (symbols['MNVIEW'], symbols['MNPASS'], symbols['MNSTEER'], symbols['MNREAD']) and                 symbols['MSVIEW'] <= pc < symbols['MSPOSEND']
            tramp = any(symbols[start] <= pc < symbols[end] for start, end in
                        (('OVTRAMP', 'OVTRAMPEND'), ('ENDTRAMP', 'ENDTRAMPEND'),
                         ('FKEYTUNNEL', 'FKEYTUNNELEND')))
            if not init_only and not in_sequence and not tramp:
                bad.append(f'${pc:04X} {mn} ${value:04X}')
    if bad:
        raise SystemExit('resident references into S1 outside the trampolines: ' + ', '.join(bad))


def ending_source(source, read):
    """Relocate the original rating instruction for instruction, including quirks."""
    from dis6502 import ops, L, fmt
    ref = json.loads(read('c128-game', 'end-reference.json'))
    data = bytes(ref['rating'])
    replacements = {0xE0: 'DIFF', 0xF34B: 'ENDVICTORY',
                    0x2089: 'M_CORN', 0x2085: 'M_INNER', 0x033C: 'M_STATE'}
    for old, name, count in ((0xF431, 'ENDPLANET', 1), (0xF432, 'ENDHITS', 2),
                             (0xF434, 'ENDKILLS', 2), (0xF436, 'ENDRENER', 3),
                             (0xF439, 'ENDRPROTON', 2), (0xF43B, 'ENDSHOTS', 2),
                             (0xF43D, 'ENDSCORE', 3)):
        for i in range(count):
            replacements[old+i] = name + (f'+{i}' if i else '')
    lines, pc = [], 0xF440
    while pc < 0xF5B3:
        op, mode = ops[data[pc-0xF440]]
        n = L[mode]
        raw = data[pc-0xF440:pc-0xF440+n]
        instruction = fmt(op, mode, raw, pc)
        if mode not in ('imm', 'imp', 'acc'):
            address = raw[1] if n == 2 else raw[1] | raw[2] << 8
            if mode == 'rel':
                address = (pc+2+(raw[1] if raw[1]<128 else raw[1]-256)) & 65535
            target = replacements.get(address)
            if 0xF440 <= address < 0xF5B8:
                target = f'er_{address:04x}'
            if target:
                instruction = re.sub(r'\$[0-9A-F]+', target, instruction)
        lines.append(f'er_{pc:04x}: {instruction}')
        pc += n
    lines += ['er_f5b3: .BYTE 3,4,5,6,7',
              'ENDRATING: JMP er_f440',
              'ENDVICTORY: .BYTE 0']
    text = read('c128-game', 'ending.asm').replace('; ENDRATINGDATA', '\n'.join(lines))
    text = text.replace('ENDCOREEND:', read('c128-game', 'controllers.asm') + '\n'
                        + read('c128-game', 'mission-messages.asm') + '\nENDCOREEND:')
    text = text.replace('; FUNCTIONKEYDATA', read('c128-game', 'function-keys.asm'))
    for name, value in [('ENDDEATHTEXT', ' THE BATTLE IS OVER'),
                        ('ENDLOSTTEXT', '  JARALOBA IS LOST')]:
        text = text.replace('; '+name+'DATA', '.BYTE '+','.join(map(str, value.encode()+b'\0')))
    ranks = bytes(v for i in range(0,104,13) for v in ref['ranks'][i:i+13].ljust(13).encode()+b'\0')
    # The four death reports live in bank 1; ENDSCENE unpacks them into the
    # text screen's hidden rows (restored from its master at reset).
    reports = bytes(v for header in ref['headers'] for j in range(0,100,20) for v in header[j:j+20]+[0])
    heads = [ENDHEADS + 105*i for i in range(4)]
    text = text.replace('; ENDHEADERDATA', 'ENDHEADERLO: .BYTE '+','.join(str(a & 255) for a in heads)
                        + '\nENDHEADERHI: .BYTE '+','.join(str(a >> 8) for a in heads))
    # Snapshot reset state and self-modified slots. Tables, code and existing
    # high/low resident blocks are never moved. The matrix/HUD text screen and
    # the cockpit art/bottom sprite slots hold their load-time bytes at the
    # snapshot (checked by the tests): their packed masters are in the payload.
    ranges = [(0xE000, 'MNART', 0xE000), ('MNARTEND', 'MINEFREE', 'MNARTEND'), (0x0C60, 3481, 0)]
    for line in source.splitlines():
        match = re.match(r'^(\w+):\s*\.BYTE\s+([^;]+)', line)
        if match:
            name, values = match.groups()
            count = len(values.split(','))
            # State scalars/short vectors; immutable art and large buffers are
            # rebuilt by their existing initialization paths.
            if count <= 2 and name not in ('SAVFAST','SAVMMU'):
                ranges.append((name, count, 0))
    # Addresses written by scene hooks; saved as instruction bytes too.
    for name, count in [('sprcj',3),('shpj',3),('torpj',3),('vv2',3),('g_vs2',3),
                        ('VBWORK',6),('MRMODE',2),('MRATTR',2),('MRWAIT',2),
                        ('MRGUN',3),('iv1',3),('shj',3),('plshp',3),
                        ('sprmc',2),('sprxe',2),('g_hk2',8),('nov3',3),
                        ('gplmode',3),('germode',3)]:
        ranges.append((name,count,0))
    # Filter by address after assembling the original joined source alone.
    # END references in that source require placeholders during this address pass.
    placeholder = '\n'.join(n+' = $0200' for n in
        ('ELREG','ENDINIT','ENDVIEW','ENDBORROW','ENDENER','ENDPROTONUSED','ENDONE',
         'ENDSECTOR','ENDHIDE','ENDSHOW','ENDKILL','ENDMSOFF','ENDSHIPFLAG','ENDPLANETFLAG','ENDBASETALLY',
         'OVMNOFF','MNREQ','OVBASEIN','CLOCKFRAME','CLOCKINIT','FKEYVIEW','FKEYGUNS',
         'FKEYSWEEP','FKEYINPUT','FKEYREPAIR','GPOTS','GMAPPOTS','GMAPCENTER','GMAPBUTTONS','HENGARM',
         'SECTORNOTICE','GROUPNOTICE','MISSIONHIT','MISSIONREPAIRED','STARTPLOT','NOTICEREQUEST','BASEMESSAGE',
         'TRACKNOTICE','APPROACHNOTICE','ENTERNOTICE','HREAD','HREADCLEAR','EMPTYROW',
         'SCANROW','SCANZEROX','SCANZEROY'))
    _, sym = asm(source+'\n'+placeholder)
    packed_ranges, used = [], set()
    readonly = [(0xE960,0xEA16), (sym['MSUNPACK'],sym['MSPOS']),
                (sym['MNSTREAM'],sym['MNEXTRAEND'])]
    for address, length, minus in ranges:
        if isinstance(address,str):
            address = sym[address]
            if isinstance(length,int) and (address < 0x1D00 or address >= 0xD000):
                continue
        if isinstance(length,str):
            length = sym[length]-(sym[minus] if isinstance(minus,str) else minus)
        for a in range(address,address+length):
            if any(lo <= a < hi for lo,hi in readonly):
                continue
            if a not in used:
                if packed_ranges and packed_ranges[-1][0]+packed_ranges[-1][1] == a:
                    packed_ranges[-1][1] += 1
                else:
                    packed_ranges.append([a,1])
                used.add(a)
    # The payload: the victory text (the original's 11 rows from $D100, then the
    # rank's row, written at run time), the reports and the display masters.
    win = bytes(ref['win']) + b' '*20
    assert len(win) == 240
    masters = display_masters()
    # Death reads the whole stream. Victory reads the two rank batches on separate frames.
    rank_text = ENDHEADS + 420
    rank_half = rank_text + 56
    reports_stream = rle_stream([(ENDHEADS, reports), (rank_text, ranks[:56]), (rank_half, ranks[56:])])
    ranks_at = len(rle_stream([(ENDHEADS, reports)])) - 3
    rank_half_at = len(rle_stream([(ENDHEADS, reports), (rank_text, ranks[:56])])) - 3
    payload = win + reports_stream + rle_stream([(0x4400, masters[0]), (0x7680, masters[1])])
    pages = (len(payload)+255)//256
    # Spend spare bytes on the gaps between states: fewer descriptors leave more
    # workspace. (The budget is still the 16K VDC's of 2026-11-17, when the store
    # moved to bank 1: the same descriptors, the same bytes restored at a reset.)
    spare = 0x4000-0xA60-len(used)-pages*256-255-ENDVDCRESERVE
    assert spare >= 0, f'ending snapshot budget short by {-spare} bytes'
    ordered = sorted(packed_ranges)
    gaps = sorted((ordered[i+1][0]-ordered[i][0]-ordered[i][1], i) for i in range(len(ordered)-1))
    bridged = set()
    for gap, i in gaps:
        if gap > spare:
            break
        lo, hi = ordered[i][0]+ordered[i][1], ordered[i+1][0]
        if hi > 0xD000 and lo < 0xE000:
            continue    # never through I/O (and the low-RAM backup beneath it)
        bridged.add(i)
        spare -= gap
    merged = []
    for i, (a, n) in enumerate(ordered):
        if i-1 in bridged:
            merged[-1][1] = a+n-merged[-1][0]
        else:
            merged.append([a, n])
    # S1 (overlay.asm) is left out: its package is reloaded from bank 1 at a reset
    # (MINES' image is taken with the snapshot). The bytes restored elsewhere are the
    # same as before S1 existed (the gaps were chosen with it).
    clipped = []
    for a, n in merged:
        for lo, hi in ((a, min(a+n, S1BASE)), (max(a, S1END), a+n)):
            if lo < hi:
                clipped.append([lo, hi-lo])
    merged = clipped
    assert not any(a < S1END and a+n > S1BASE for a, n in merged)
    snapshot = sum(n for a,n in merged)
    vpay = (ENDB1SNAP+snapshot+255) & 0xFF00
    assert vpay + pages*256 <= ENDB1LIMIT, f'bank 1: the payload ends at ${vpay + pages*256:04X}'
    PAYLOAD[:] = payload + bytes(pages*256-len(payload))
    descriptors = []
    for a,n in merged:
        descriptors += [a&255,a>>8,n&255,n>>8]
    # Bank-1 addresses (bank1.asm): the snapshot at ENDB1SNAP, the payload after it.
    constants = {'ENDSTAGE': ENDSTAGE, 'ENDPKGSTAGE': ENDPKGSTAGE, 'ENDPKG': ENDPKG, 'ENDBPAY': vpay, 'ENDVTEXT': vpay, 'ENDVRANK': vpay+220,
                 'ENDVHEAD': vpay+240, 'ENDVRANKS': vpay+240+ranks_at, 'ENDVRANKHALF': vpay+240+rank_half_at,
                 'ENDRANKTEXT': rank_text, 'ENDRANKHALF': rank_half, 'ENDVMASTER': vpay+240+len(reports_stream),
                 'ENDPAYPAGES': pages, 'ENDB1END': vpay+pages*256, 'ENDB1SNAP': ENDB1SNAP, 'ENDB1SNAPEND': ENDB1SNAP+snapshot,
                 'ENDPAYLEN': len(payload), 'ENDHEADS': ENDHEADS, 'B1INITAT': ENDSTAGE+pages*256}
    # (the constants first: the package's origin, * = ENDPKG, needs ENDPKG defined)
    return '\n'.join(f'{k} = {v}' for k, v in constants.items()) + '\n' + \
        text.replace('; ENDRANGEDATA', '.BYTE '+','.join(map(str,descriptors))) + '\n'


ENDHEADS = 0x4900           # hidden text-screen rows 6-16 while an ending runs
ENDVDCRESERVE = 0           # bytes kept free; the rest bridges the smallest snapshot gaps
ENDB1SNAP = 0x2C00          # bank 1: the reset snapshot, then the payload (bank1.asm)
ENDPKG = 0xE970             # the ENDING package's run address in S1 (ending.asm)
ENDPKGSTAGE = 0xE900        # load-time staging: the core at $E000, the package, the payload
ENDSTAGE = 0xF100
ENDB1LIMIT = 0x6400         # bank 1: the first byte after the snapshot and payload area (B1STREAM)
S1BASE, S1END = 0xE960, 0xF6F9   # the slot (overlay.asm)
PAYLOAD = bytearray()


def display_masters():
    """Load-time bytes of $4400-$4BFF and $7680-$7FFF (assets only)."""
    body = bytearray(cockpit_build.basic_stub())
    p = lambda address, data: put(body, address, data)
    cockpit_build.place_assets(p)
    map_build.place_assets(p, VDC=VDCDATA, PL5=0x7FC0)
    cockpit_build.place_assets(p)
    return (bytes(body[0x4400-LOAD:0x4C00-LOAD]), bytes(body[0x7680-LOAD:0x8000-LOAD]))


def rle_stream(segments):
    """ENDUNPACK's format: 0, address (a new destination; high byte 0 ends);
    1-$7F literal bytes; $81-$FF a run of the next byte ($80 less)."""
    out = bytearray()
    for dest, data in segments:
        out += bytes((0, dest & 255, dest >> 8))
        literal = bytearray()
        def flush():
            for k in range(0, len(literal), 127):
                part = literal[k:k+127]
                out.append(len(part))
                out.extend(part)
            literal.clear()
        i = 0
        while i < len(data):
            j = i
            while j < len(data) and data[j] == data[i] and j-i < 127:
                j += 1
            if j-i >= 3:
                flush()
                out.extend((0x80 + j-i, data[i]))
                i = j
            else:
                literal.append(data[i])
                i += 1
        flush()
    return bytes(out + bytes(3))


def rle_unpack(stream):
    """Python model of ENDUNPACK, for the build's check: {address: byte}."""
    out, i, dest = {}, 0, 0
    while True:
        t = stream[i]; i += 1
        if t == 0:
            dest = stream[i] | stream[i+1] << 8; i += 2
            if dest < 256:
                return out
        elif t < 0x80:
            for v in stream[i:i+t]:
                out[dest] = v; dest += 1
            i += t
        else:
            for _ in range(t-0x80):
                out[dest] = stream[i]; dest += 1
            i += 1


def lz_pack(data):
    """Shortest token stream for GUNPACK's literal/back-reference format.

    Dynamic programming avoids greedy matches that split a longer later match.
    Runtime decoder and its cost are unchanged.
    """
    size = len(data)
    matches, where = [], {}
    for i in range(size):
        best, distance = 0, 0
        key = data[i:i + 3]
        for j in reversed(where.get(key, [])[-256:]):
            n = 0
            while n < 130 and i + n < size and data[j + n] == data[i + n]:
                n += 1
            if n > best:
                best, distance = n, i - j
                if best == min(130, size - i):
                    break
        matches.append((best, distance))
        where.setdefault(key, []).append(i)
    costs, choices = [0] * (size + 1), [None] * size
    for i in range(size - 1, -1, -1):
        length = min(range(1, min(128, size - i) + 1), key=lambda n: n + 1 + costs[i + n])
        cost, choice = length + 1 + costs[i + length], (length, 0)
        best, distance = matches[i]
        for n in range(3, best + 1):
            if 3 + costs[i + n] < cost:
                cost, choice = 3 + costs[i + n], (n, distance)
        costs[i], choices[i] = cost, choice
    out, i = bytearray(), 0
    while i < size:
        n, distance = choices[i]
        if distance:
            out.extend((0x80 | (n - 3), distance & 255, distance >> 8))
        else:
            out.append(n - 1)
            out.extend(data[i:i + n])
        i += n
    return bytes(out)


def torp_frames(raw):
    """The torpedo's 32 frames of 128 bytes, each packed on its own (TORPA): $80 + n
    zero bytes, or n literal bytes. Minimize each frame with dynamic programming;
    short zero runs may be cheaper inside literals. The runtime format is unchanged."""
    assert len(raw) % 128 == 0
    out = bytearray()
    for f in range(len(raw) // 128):
        b = raw[f * 128:f * 128 + 128]
        costs, choices = [0] * 129, [None] * 128
        for i in range(127, -1, -1):
            n = min(range(1, min(48, 128 - i) + 1), key=lambda n: n + 1 + costs[i + n])
            costs[i], choices[i] = n + 1 + costs[i + n], (n, False)
            if b[i] == 0:
                z = 1
                while i + z < 128 and z < 61 and b[i + z] == 0:
                    z += 1
                for n in range(1, z + 1):
                    if 1 + costs[i + n] < costs[i]:
                        costs[i], choices[i] = 1 + costs[i + n], (n, True)
        i = 0
        while i < 128:
            n, zero = choices[i]
            out.append(0x80 | n if zero else n)
            if not zero:
                out.extend(b[i:i + n])
            i += n
    return bytes(out)


def repair_assets():
    """Original $9245/$9497 text and $3580's two beam paths, without scratch dumps."""
    names = ('PHASOR CANNONS', 'LONG RANGE SCANNER', 'SHORT RANGE SCANNER',
             'STELLAR GRID', 'AUTOMATIC TRACKING COMPUTER', 'HYPERSPACE COORDINATOR',
             'LONG RANGE SCAN SEQUENCER', 'COMMUNICATIONS MODULE')
    text = ''.join(names).encode('ascii')
    lengths = bytes(len(n) for n in names)
    # $3580 includes the starting point, takes a minor step only when error > 76,
    # and the beam uses the first 76 of the 77 generated points.
    left = bytes(60 - (45 * i + 37) // 76 for i in range(76))
    right = bytes(100 + (46 * i + 37) // 76 for i in range(76))
    return text + b'@@@REPAIREDOPERATIONAL' + lengths + left + right


def main():
    chunks, symbols = assemble()
    # Baseline taken before the low-RAM rearrangement: existing lower code,
    # tables and constants must never drift when extending the high chunk.
    with open(os.path.join(HERE, 'fixed-symbols.json'), encoding='ascii') as f:
        fixed = json.load(f)
    for name, address in fixed.items():
        assert symbols.get(name) == address, f'fixed symbol {name} moved from ${address:04X}'
    if set(chunks) != {ENTRY, CODE2, MAPCODE, GLUE, HIGH, HIGH2, 0x0C60, 0xE960, 0x3D60, 0x3BD8, 0x3768, 0x3BC0, 0x2CDE, 0x2FEE, 0x33E8, 0x28D7, 0xBFC3, 0x3BD1, 0x3681, 0x0200, 0x1C10, 0x5258,
                       0x0100, symbols['B1INITAT'], symbols['OVBASE'], ENDPKG}:
        raise SystemExit(f'unexpected assembly chunks: {[hex(c) for c in chunks]}')
    for start, limit in ((0x5258, 0x5300), (ENTRY, 0x28D7), (CODE2, MAPCODE), (MAPCODE, 0xBFC3), (GLUE, HIGH2SRC), (HIGH, 0xD000), (HIGH2, 0xF6F9), (0x3D60, 0x3E00), (0x3BD8, 0x3C00), (0x3768, 0x3800), (0x3BC0, 0x3BD8), (0x2CDE, 0x2D00), (0x2FEE, 0x3000), (0x33E8, 0x3400), (0x28D7, 0x2900), (0xBFC3, 0xC000), (0x3BD1, 0x3BD8), (0x3681, 0x3690)):
        if start + len(chunks[start]) > limit:
            raise SystemExit(f'code from ${start:04X} ends at ${start + len(chunks[start]):04X}, past ${limit:04X}')
    assert HIGH2 + len(chunks[HIGH2]) == 0xE960
    assert symbols['ENDCOREEND'] <= 0x0C60
    assert symbols['CLOCKEND'] <= symbols['HENGARM'] < symbols['HENGEND'] <= symbols['ENDCOREEND']
    assert symbols['ENDCOREEND'] - 0x0200 <= ENDPKGSTAGE - 0xE000 == symbols['ENDCOREPAGES'] * 256, 'resident core staging overlaps ENDING'
    assert 0x0557 <= symbols['CLOCKINIT'] < symbols['CLOCKEND'] <= symbols['ENDCOREEND'], 'the clock must fit after the ending core'
    assert symbols['ENDPKGSTART'] == ENDPKG and symbols['ENDINGEND'] <= symbols['MINEFREE'], 'the ENDING package outgrows S1'
    assert ENDPKGSTAGE + symbols['ENDPKGPAGES'] * 256 <= ENDSTAGE and len(chunks[ENDPKG]) <= symbols['ENDPKGPAGES'] * 256
    assert symbols['B1ENDING'] >= symbols['B1MINES'] + 13 * 256 and symbols['B1ENDING'] + symbols['ENDPKGPAGES'] * 256 <= 0xFF00
    assert symbols['ENDLOADEREND'] <= ENTRY, 'ending loader overlaps cockpit entry'
    assert 0xE960 + len(chunks[0xE960]) == symbols['MINEFREE']
    assert symbols['MNSTART'] == 0xEA16
    assert symbols['MINEEND'] - symbols['MNSTART'] >= 3072
    assert symbols['MINEFREE'] <= symbols['MINEEND']
    assert symbols['MNARTEND'] - symbols['MNART'] == len(torp_frames(open(os.path.join(ROOT, 'c128-gui/ref/sprites-4800.bin'), 'rb').read()[65*64:77*64]))
    assert symbols['MNBACKEND'] - symbols['MNBACK'] == 768
    assert 0x6000 + 12 * 64 <= 0x63C0
    assert symbols['LOWSTART'] == 0x0C60
    # The block began at $0C60-$19F8; small additions follow it into BASIC's free
    # ML area ($19F9-$1BFF; nothing of BASIC's is kept: no return to BASIC).
    assert symbols['LOWEND'] == symbols['LOWSTART'] + len(chunks[0x0C60]) <= 0x1C00
    assert len(chunks[0x0C60]) == symbols['LOWPAGES'] * 256 + symbols['LOWTAIL']
    assert symbols['MSPOSEND'] - symbols['MSPOS'] == 245
    assert symbols['ETEND'] == 0x19F9 and symbols['ETEND'] <= symbols['LOWEND']
    # Bank 1 (bank1.asm): the copy stub in common RAM below the stack, the layout.
    # (No return to BASIC: no backups, BASIC 7's string area at the top is not kept.)
    stub = chunks[0x0100]
    assert len(stub) == symbols['B1STUBLEN'] and 0x0100 + len(stub) <= 0x0180, 'the stub outgrows its page'
    assert 0x0400 <= symbols['ENDB1SNAP'], 'bank 1: common RAM below $0400'
    assert symbols['ENDB1SNAPEND'] <= symbols['ENDBPAY'] and symbols['ENDB1END'] <= ENDB1LIMIT
    b1init = chunks[symbols['B1INITAT']]
    assert symbols['B1INITAT'] + len(b1init) == symbols['ENDSTUBIMG']
    assert symbols['ENDSTUBIMG'] + len(stub) <= symbols['OVLIMG'] == symbols['ENDSTUBIMG'] + 128
    assert symbols['OVLIMG'] + symbols['OVAREALEN'] <= 0xFF00
    # The space the exit to BASIC left: same size, nothing after it moved.
    assert symbols['CKEXITFREE'] == symbols['EXIT'] and symbols['CKEXITFREE'] + EXIT_FREE == symbols['SPRCROSS']
    assert symbols['CKSTARTFREE'] + START_FREE == symbols['g_st1'] == symbols['VDCENTRY'] + 5 + 3 + START_FREE
    assert symbols['VDCFREE'] + 5 == symbols['ARROWS'] == 0x52C5, 'ARROWS/ARPIX (issue #18 timing) moved'
    # The overlay manager (overlay.asm) after the low block, in BASIC's free ML area.
    ovl = chunks[symbols['OVBASE']]
    assert symbols['LOWEND'] < symbols['OVBASE'] and symbols['OVBASE'] + symbols['OVAREALEN'] == symbols['OVAREAEND'] == 0x1C00
    assert symbols['OVEND'] == symbols['OVBASE'] + len(ovl) <= symbols['OVAREAEND'] and symbols['OVAREALEN'] > 256
    # S1 and its packages: MINES at $EA16 (unchanged), its image fits the bank-1 area.
    assert (symbols['S1BASE'], symbols['S1END']) == (S1BASE, S1END) == (0xE960, symbols['MINEEND'])
    assert symbols['MNSTART'] == 0xEA16 and symbols['MNEXTRAEND'] <= symbols['MINEFREE'] <= S1END
    assert symbols['MNEXTRAEND'] - symbols['MNSTART'] <= 13 * 256 and symbols['B1MINES'] + 13 * 256 <= 0xFF00
    assert symbols['B1STREAM'] >= ENDB1LIMIT and symbols['B1STREAM'] + 768 <= symbols['B1MINES']
    audit_s1(symbols)

    body = bytearray(cockpit_build.basic_stub())
    p = lambda address, data: put(body, address, data)
    cockpit_build.place_assets(p)
    map_build.place_assets(p, VDC=VDCDATA, PL5=0x7FC0)   # (the planet's fifth frame: pointer $FF, behind the bottom strip)
    cockpit_build.place_assets(p)                   # the cockpit's picture wins where they meet
    for address, data in chunks.items():
        if address not in (HIGH2, 0xE960, 0x0C60, 0x0200, 0x0100, symbols['OVBASE'], ENDPKG):
            p(address, data)
    p(symbols['ENDSTUBIMG'], chunks[0x0100])      # B1INIT copies it to $0100
    # B1INIT copies the overlay manager's whole area (OVBASE-$1BFF) from here
    p(symbols['OVLIMG'], chunks[symbols['OVBASE']] + bytes(symbols['OVAREALEN'] - len(chunks[symbols['OVBASE']])))
    # The packed $E000 image: code, torpedo frames and borrowed shot shapes.
    # Fighter masters / STR2X are loaded directly into reclaimed lower RAM.
    ref = os.path.join(ROOT, 'c128-gui', 'ref')
    sprites = open(os.path.join(ref, 'sprites-4800.bin'), 'rb').read()
    order = [b + i for b in (0x20, 0x30, 0x40, 0x60, 0x70) for i in range(16)]
    shape = lambda s: sprites[order.index(s) * 64:order.index(s) * 64 + 64]
    # The VDC is disabled in the joined game; its data holds type-1 masters.
    # Unpacking may overlap their live sprite slots; GINIT2 restores them next.
    assert symbols["TSH1"] == VDCDATA
    assert chunks[MAPCODE][symbols["M_VDCON"] - MAPCODE] == 0, "TSH1 reuses disabled VDC data"
    assert (symbols['TSH2'], symbols['TSH3'], symbols['STR2X']) == (0x3800, 0x39C0, 0x3E00)
    assert all(symbols['M_' + n] == symbols[n] for n in ('YLO', 'YHI', 'XLO', 'XHI'))
    assert symbols['TSH3'] + 512 <= symbols['M_VLAB']
    assert symbols['STR2X'] + 512 <= 0x4000
    # Check the actual assets as well as shared addresses before reclaiming tables.
    for old, shared, size in ((0x3800, 0x2D00, 200), (0x3900, 0x2E00, 200),
                              (0x3A00, 0x2F00, 40), (0x3A28, 0x2F28, 40)):
        assert body[old - LOAD:old - LOAD + size] == body[shared - LOAD:shared - LOAD + size]
    p(symbols["TSH1"], b"".join(shape(s) for s in range(0x20, 0x2F)))
    # Original repair text and paths in verified table/master padding; never sprites.
    repair = repair_assets()
    assert len(repair) == 340
    assert symbols['MRDATA'] == 0x2F50 and symbols['MRDATA'] + 158 <= 0x2FEE
    assert symbols['MRWORDS'] == 0x2CC0 and symbols['MRWORDS'] + 30 <= 0x2CDE
    assert symbols['MBLEFT'] == 0x36D0 and symbols['MBLEFT'] + 152 == 0x3768
    assert symbols['TSH1'] + 15 * 64 == 0x2CC0
    assert symbols['DIGF'] + 64 == symbols['MBLEFT']
    assert symbols['LRTAB'] + 129 == 0x3681
    assert symbols['MRGAPEND'] <= symbols['DIGF']
    assert symbols['XHI'] + 40 == symbols['MRDATA']
    assert symbols['COLORDATA'] + 1000 == 0x33E8
    assert 0x3D60 >= symbols['M_DIRTY'] + 60
    assert 0x3D60 + len(chunks[0x3D60]) <= symbols['STR2X']
    # Beam pixels have value 1; clean cockpit art contains no such pixels.
    # Therefore deleting only 01 pixels restores the exact art, without a backup.
    art = cockpit_build.clean_radar(open(os.path.join(ref, 'cockpit-art.bin'), 'rb').read()[3000:4600])
    assert all((v >> shift) & 3 != 1 for v in art for shift in (0, 2, 4, 6))
    assert symbols['MRARTSTEPEND'] <= symbols['MRGLYPH']
    assert symbols['MRGLYPH'] + 8 <= symbols['TSH1']
    p(symbols['MRGLYPH'], bytes(body[0x41F8 - LOAD:0x4200 - LOAD]))
    p(symbols['MRDATA'], repair[:158])
    p(symbols['MRWORDS'], repair[158:188])
    p(symbols['MBLEFT'], repair[188:340])
    image = bytearray(chunks[HIGH2])
    image.extend(chunks[0xE960])
    def at(name, data):
        off = symbols[name] - HIGH2
        image.extend(bytes(max(0, off + len(data) - len(image))))
        image[off:off + len(data)] = data
    p(symbols['TSH2'], b''.join(shape(s) for s in range(0x3E, 0x45)))
    p(symbols['TSH3'], b''.join(shape(s) for s in range(0x31, 0x39)))
    p(symbols['STR2X'], open(os.path.join(ref, 'streams2-0600.bin'), 'rb').read())
    extra = bytes(image[symbols['MNEXTRA']-HIGH2:symbols['MNEXTRAEND']-HIGH2])
    at('MNEXTRA', bytes(len(extra)))
    at('TORPA', torp_frames(open(os.path.join(ref, 'torpedo-a000.bin'), 'rb').read()))
    at('TSHOT', shape(0x67) + shape(0x68))
    assert bytes(image[symbols['MNART']-HIGH2:symbols['MNARTEND']-HIGH2]) == torp_frames(b''.join(shape(s) for s in range(0x71, 0x7D)))
    frames = open(os.path.join(ref, 'torpedo-a000.bin'), 'rb').read()
    addresses = []
    offset = symbols['TORPA']
    for i in range(32):
        addresses.append(offset)
        # Same per-frame encoding as the player stream.
        offset += len(torp_frames(frames[i*128:(i+1)*128]))
    assert offset <= symbols['TSHOT']
    # Once all streams have returned, the decoder becomes read/write tables.
    # UPEND/GSEED and GUNPK2 stay intact; no sprite region is reclaimed here.
    assert symbols['ETLO'] == symbols['GUNPACK']
    assert symbols['ETHI'] == symbols['ETLO'] + 32
    runtime = bytearray(bytes(a & 255 for a in addresses) + bytes(a >> 8 for a in addresses))
    defaults = [('ETSTATE', 0), ('ETN', 0), ('ETACC', 0), ('ETC', 0),
                ('MSSTATE', 0), ('MSKIND', 0), ('MSROW', 0), ('MSRAD', 1),
                ('MSBIAS', 1), ('MSCLOCK', 0), ('MSRUN', 0), ('MSRX', 0),
                ('MSRY', 0), ('MSD', 0), ('MSD1', 0), ('MSD2', 0), ('MSABS', 0),
                ('MSPHASE', 0), ('MSPCOUNT', 1), ('MSCPEND', 0), ('MSCLEFT', 0),
                ('MSCRIGHT', 0), ('MSCROW', 0), ('MSCEND', 0), ('MSCOFF', 0),
                ('MSCN', 0), ('MSPACC', 0), ('MSPCOLOR', 0x11), ('MSPROW', 14),
                ('MSKILLED', 0), ('MSLOCK', 0)]
    for name, value in defaults:
        assert symbols[name] == symbols['GUNPACK'] + len(runtime)
        runtime.append(value)
    assert symbols['MSDELAY'] == symbols['GUNPACK'] + len(runtime)
    runtime.extend((6,6,6,6,6,6,6,6,6,6,6,6,6,6,7,6,7,6,7,6,
                   7,7,7,7,7,8,7,8,7,8,8,8,8,8,9,8,8,9,8,9,9))
    for name in ('MRPHUND', 'MRINDEX', 'MRSIDE', 'MRCLOCK', 'MRCOL', 'MROFF'):
        assert symbols[name] == symbols['GUNPACK'] + len(runtime)
        runtime.append(0)
    assert len(runtime) == 142  # GINIT3's exact backwards copy
    assert symbols['GUNPACK'] + len(runtime) <= symbols['UPEND']
    p(0xDF00, runtime)
    # Third stream: the complete relocated block, including positioning and
    # enemy-proton code. Everything loaded is below the KERNAL's $FF00 limit.
    low_end = symbols['LOWEND']
    low_stream = bytes((low_end & 255, low_end >> 8)) + lz_pack(bytes(chunks[0x0C60]))
    assert 0xD100 + len(low_stream) <= 0xDF00, 'low stream overlaps staged runtime tables'
    p(0xD060, low_stream)
    assert 0xD060 + len(low_stream) <= symbols['MTSTAGE'], f'low stream ends at ${0xD060 + len(low_stream):04X}, past MTSTAGE'
    extra_stream = bytes((symbols['MNEXTRAEND'] & 255, symbols['MNEXTRAEND'] >> 8)) + lz_pack(extra)
    print(f'low stream ${0xD060:04X}-${0xD060 + len(low_stream) - 1:04X}, tunnel stream ${symbols["MTSTAGE"]:04X}-${symbols["MTSTAGE"] + len(extra_stream) - 1:04X} ({0xDF00 - symbols["MTSTAGE"] - len(extra_stream)} bytes before $DF00)')
    assert symbols['MTSTAGE'] + len(extra_stream) <= 0xDF00, f'tunnel stream {len(extra_stream)} overlaps runtime tables'
    p(symbols['MTSTAGE'], extra_stream)
    end = HIGH2 + len(image)
    assert end <= 0xFF00, f'the $E000 image ends at ${end:04X}'
    assert end & 255 == 0, 'GUNPK2 relies on the first stream ending at a page'
    packed = bytes((end & 255, end >> 8)) + lz_pack(bytes(image))
    # The second stream: STR2Y, unpacked over the packed data's start once it is read.
    assert symbols['STR2Y'] == HIGH2SRC and HIGH2SRC + len(packed) >= HIGH2SRC + 512
    second = bytes((0x00, (HIGH2SRC + 512) >> 8)) + lz_pack(open(os.path.join(ref, 'streams2-8100.bin'), 'rb').read())
    # Init-only RAM beneath I/O; GINIT3 selects MMU $3F to read it.
    assert 0xD000 + len(second) <= 0xD100
    assert 0xD000 + len(second) <= 0xD060
    p(0xD000, second)
    assert HIGH2SRC + len(packed) <= 0x7680, f'the packed $E000 image ({len(packed)} bytes) overlaps the cockpit art'
    p(HIGH2SRC, packed)
    # Consumed by ENDINIT before the high decoder overwrites this staging.
    # Native LOAD can reach the whole payload (never beyond $FF00).
    p(0xE000, chunks[0x0200])           # ENDINIT copies the core to $0200
    p(ENDPKGSTAGE, chunks[ENDPKG])      # B1INIT puts it into bank 1 (B1ENDING)
    # Then the ending payload, which B1INIT puts into bank 1 before GINIT2.
    assert symbols['ENDSTAGE'] == ENDSTAGE and len(PAYLOAD) == symbols['ENDPAYPAGES'] * 256
    p(symbols['ENDSTAGE'], bytes(PAYLOAD))
    assert symbols['ENDBPAY'] & 255 == 0 and symbols['ENDVRANK'] == symbols['ENDVTEXT'] + 220
    assert symbols['B1INITAT'] == symbols['ENDSTAGE'] + len(PAYLOAD)
    assert ENDHEADS >= 0x4828 + 40 * 3 and ENDHEADS + 420 <= 0x4800 + 40 * 21, 'reports outside hidden text rows'
    # Numbers: ENDNUMSRC offsets from ENDHITS.
    assert [symbols[n] - symbols['ENDHITS'] for n in ('ENDRENER', 'ENDHITS', 'ENDKILLS', 'ENDRPROTON', 'ENDSHOTS')] == [4, 0, 2, 7, 9]
    # master copy of the colour matrix's view rows for MAPCLOSE (game.asm)
    p(symbols['MMAT'], bytes(body[0x4478 - LOAD:0x4478 - LOAD + 600]))
    # The reset unpacks these display masters instead of snapshotting them:
    # they must be exactly the program's own bytes there.
    vm = symbols['ENDVMASTER'] - symbols['ENDBPAY']
    unpacked = rle_unpack(PAYLOAD[vm:])
    assert sorted(unpacked) == list(range(0x4400, 0x4C00)) + list(range(0x7680, 0x8000))
    assert all(body[a - LOAD] == v for a, v in unpacked.items()), 'display masters differ from the PRG'
    reports = rle_unpack(PAYLOAD[240:vm])
    assert sorted(reports) == list(range(ENDHEADS, ENDHEADS + 532))

    # The KERNAL's LOAD stops at $FF00 (its store loop ends when AEL reaches $FF),
    # so nothing may be placed there: the tail above is staged beneath I/O instead.
    assert LOAD + len(body) <= 0xFF00, f'the PRG ends at ${LOAD + len(body) - 1:04X}, past the KERNAL LOAD limit'
    with open(OUT, 'wb') as f:
        f.write(bytes((LOAD & 255, LOAD >> 8)) + body)
    ends = ', '.join(f'${a:04X}-${a + len(c) - 1:04X}' for a, c in sorted(chunks.items()))
    print(f'memory left: high {symbols["MINEEND"] - symbols["MINEFREE"]} bytes (${symbols["MINEFREE"]:04X}-${symbols["MINEEND"]-1:04X}, all modes), packed {0x7680 - HIGH2SRC - len(packed)} bytes, glue {HIGH2SRC - GLUE - len(chunks[GLUE])} bytes; low stream {len(low_stream)} bytes')
    print(f'clock: ${symbols["CLOCKINIT"]:04X}-${symbols["CLOCKEND"]-1:04X}, '
          f'{symbols["CLOCKDIV"]-symbols["CLOCKINIT"]} code bytes, {symbols["CLOCKEND"]-symbols["CLOCKDIV"]} data bytes')
    print(f'ending memory: core $0200-${symbols["ENDCOREEND"]-1:04X}, {0xC60-symbols["ENDCOREEND"]} bytes free after it (to $0C5F); '
          f'ENDING package ${ENDPKG:04X}-${symbols["ENDINGEND"]-1:04X} ({symbols["ENDINGEND"]-ENDPKG} bytes), MINES ${symbols["MNSTART"]:04X}-${symbols["MNEXTRAEND"]-1:04X}; '
          f'overlay manager ${symbols["OVBASE"]:04X}-${symbols["OVEND"]-1:04X}, {0x1C00-symbols["OVEND"]} bytes free after it; '
          f'loader {ENTRY-symbols["ENDLOADEREND"]} bytes free; '
          f'bank 1: snapshot ${symbols["ENDB1SNAP"]:04X}-${symbols["ENDB1SNAPEND"]-1:04X}, payload ${symbols["ENDBPAY"]:04X} {symbols["ENDPAYLEN"]} bytes in {symbols["ENDPAYPAGES"]} pages, '
          f'{(symbols["ENDRANGESEND"] - 2 - symbols["ENDRANGES"]) // 4} snapshot ranges; stub $0100-${0x0100+len(stub)-1:04X}, init ${symbols["B1INITAT"]:04X}-${symbols["ENDSTUBIMG"]+len(stub)-1:04X}')
    # Bank 1's free areas: everything but common RAM, the store, the packages, the
    # MMU registers (seen in every bank) and the vectors (NMIB1).
    used1 = [(0, 0x400), (symbols['ENDB1SNAP'], symbols['ENDB1END']), (symbols['B1STREAM'], symbols['B1STREAM'] + 768),
             (symbols['B1MINES'], symbols['B1MINES'] + 13 * 256), (symbols['B1ENDING'], symbols['B1ENDING'] + symbols['ENDPKGPAGES'] * 256),
             (0xFF00, 0xFF05), (0xFFFA, 0x10000)]
    free1, at1 = [], 0
    for lo, hi in sorted(used1):
        if lo > at1:
            free1.append((at1, lo))
        at1 = max(at1, hi)
    print(f'no return to BASIC: free cockpit EXIT ${symbols["CKEXITFREE"]:04X}-${symbols["CKEXITFREE"]+EXIT_FREE-1:04X} ({EXIT_FREE}), '
          f'START saves ${symbols["CKSTARTFREE"]:04X}-${symbols["g_st1"]-1:04X} ({START_FREE}), helper ${symbols["VDCFREE"]:04X}-${symbols["VDCFREE"]+4:04X} (5); '
          f'bank 1 free ' + ', '.join(f'${lo:04X}-${hi-1:04X}' for lo, hi in free1) + f' ({sum(hi-lo for lo, hi in free1)} bytes)')
    print(f'wrote {OUT} (${LOAD:04X}-${LOAD + len(body) - 1:04X}, code {ends}, entry ${symbols["START"]:04X})')
    return symbols


if __name__ == '__main__':
    main()
