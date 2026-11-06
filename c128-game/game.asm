; Sentinel C128: the cockpit and the sector map as one program.
;
; This file is only the glue. c128-game/build.py joins three sources into one
; program: c128-gui/cockpit/cockpit.asm (its hooks INPUTV / VIEWVB / TICKHK /
; KILLHK / EMPTYHK and a few marked patches), c128-map/map.asm (every label it
; defines gets the prefix M_, its code goes right after the cockpit's code, its
; second-display data to $2900) and this file.
;
; As in the original, the map opens in the cockpit's 3D view: C= opens and
; closes it, the HUD, the radar, the guns and the scanner row stay. The view is
; wiped and the map's grid draws in; meanwhile the fight goes on: the star field
; moves on behind the map, the fighters fly behind its lines, enemy shots still
; hit the ship (no phasor and no steering while the map is open: the mouse moves
; the map's cursor and turns the stars). Fire on
; another sector jumps there at once (hyperspace comes later). The world's clock
; (the map's TICKER: squadrons move, motherships attack) runs all the time; the
; map's icons are only drawn while it is open.
;
; In a sector the map's STATE / COUNT decide what is there: a squadron of COUNT
; ships is approached group by group (the cockpit's long range scanner), each
; kill lowers the map's COUNT, the last one empties the sector on the map.
; Motherships (STATE $80 / $FF) approach as biased concentric rings (MSECTOR).
; Friendly docking/repair and proton destruction follow the approach; mines and enemy weapons are later work.

HUDSEC  = $4865         ; the HUD's sector digits (row 2, column 21)
MATRIX  = $4400         ; the bitmap's colour matrix
CDST    = $FD           ; pointers (the map's MP and PTR)
CSRC    = $FB
MMAT    = $5000         ; master copy of the matrix rows 3-17 (600 bytes, build.py;
                        ; CPU RAM the VIC-IIe cannot use)
PLMAT   = $45A2         ; the planet's three cells (row 10, columns 18-20): matrix,
PLCOL   = $D9A2         ; colour RAM,
PLBMP   = $6D10         ; bitmap
STARLIM = 28            ; the stars start before line 256 + this

        * = $5300       ; the glue: CPU RAM the VIC-IIe cannot use (after MMAT)

GAMEINIT:               ; once, from the cockpit's START
        LDA $D012       ; (the world's seed: before the unpacking, whose time varies)
        STA GSEED
        JSR GINIT2      ; the $E000 code and data (at the glue's end: these 38 bytes
        JMP g_gi9       ; keep the code after them where it was, as the fight's tight
        .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
g_gi9:                  ; timing was measured with it)
        LDA #<NMIRTI    ; NMI (RESTORE) and IRQ/BRK vectors in the RAM under the KERNAL
        STA $FFFA
        STA $FFFE
        LDA #>NMIRTI
        STA $FFFB
        STA $FFFF
        LDA #$FF        ; SID voice 3 as noise: the map's random numbers ($D41B)
        STA $D40E
        STA $D40F
        LDA #$80
        STA $D412
        LDA GSEED       ; the world: the map program's start layout ($20F1)
        ORA #$01
        STA M_SEED
        JSR GENONCE
        JSR SHOWSEC
        JMP SECTORIN

; Z set: the map's key is down: C=, or with a mouse its right button, held alone for
; 5 frames as in the 1351 patch (both buttons: not until they are released).
MAPKEY: LDA CIA1PB
        AND #$20
        BEQ g_mk9
        LDA MPRES
        ORA M_MPRES
        BEQ g_mk8
        LDA #$FF        ; port 2: the right button is wired to UP
        STA CIA1PA
        LDA CIA1PA
        AND #$11
        BEQ g_mk3       ; both
        CMP #$10
        BEQ g_mk1       ; right alone
        LDA #$00        ; released
        STA RCNT
        BEQ g_mk8
g_mk1:  LDA RCNT
        BMI g_mk8
        CMP #MAPDLY
        BCC g_mk2
        LDA #$00        ; (long enough)
        RTS
g_mk2:  INC RCNT
        BNE g_mk8
g_mk3:  JSR GBOTH       ; (RCNT $80; and a torpedo, $E000: the same bytes as before)
        NOP
        NOP
g_mk8:  LDA #$01
g_mk9:  RTS
RCNT:   .BYTE 0
MAPDLY  = 5

; C= in the cockpit (a new press): the map opens or closes.
MAPTOG: LDA HYPON       ; (not in hyperspace)
        ORA HPEND
        BNE g_mt9
        LDA MAPSHOWN
        BEQ MAPOPEN
        JMP MAPCLOSE
g_mt9:  RTS

MAPOPEN:LDA M_SELX      ; where a jump would start
        STA HFROMX
        LDA M_SELY
        STA HFROMY
        LDA #$01
        STA MAPSHOWN    ; (the view's background stays black, as in the original)
        LDA #$70        ; the fighters behind the map's lines
        STA MAPPRIO
        LDA #$00        ; no explosions over the map (their points would stay)
        STA EXPL
        STA EXPL2
        STA MJUMPF
        STA SHOTVIS
        STA SHOTON      ; the shot stops ($1428: $B8 clears $D0-$D2): voice 1 is the map's
        STA SHOTARM     ; beeps, sprite 1 its planet
        STA FIREFLAG
        STA HITWIN
        STA SNDON       ; (the siren and the other sweeps too: they write voice 1 every
        STA SNDGATE     ; frame, over the map's beeps)
        STA $D404
        STA M_ICONDONE  ; (nothing of the map before its set-up)
        STA CST
        LDA #$FF        ; no cursor box drawn yet
        STA DRX
        LDA #$00
        STA PTON        ; (the pointer once the map's cursor is there)
        LDA POTX        ; the map's mouse starts from here
        STA M_OLDX
        LDA POTY
        EOR #$FF
        STA M_OLDY
        LDA #15         ; the view is wiped a row a frame, then the map starts
        STA WIPE
        RTS

MAPCLOSE:
        LDA #$00
        STA QN          ; (boxes not drawn yet: the view is wiped anyway)
        STA MAPSHOWN
        STA VIEWBG
        STA MAPPRIO
        STA $D404       ; the map's beeps
        STA $D40B
        LDA POTX        ; the crosshair's mouse starts from here
        STA OLDX
        LDA POTY
        EOR #$FF
        STA OLDY
        LDA #15         ; the view is wiped back a row a frame (then the stars)
        STA WIPE
        LDA APPR        ; the scanner's row, if it is in use
        BEQ g_mc3
        JSR LRCLEAR
g_mc3:  RTS

; One row of the 3D view a frame (WIPE = 15 .. 1: rows 17 .. 3): its bitmap
; cleared; its colours the map's (yellow lines, the matrix free for the icons)
; or, closing, the cockpit's again. Open: colour RAM 7 (lines), matrix $09 (boxes
; brown, the icons set their own cells).
WIPEROW:LDX WIPE
        LDA ROWLO-1,X
        STA CDST
        LDA ROWHI-1,X
        STA CDST+1
        LDA #$00
        LDY #$00
g_wr1:  STA (CDST),Y
        INY
        BNE g_wr1
        INC CDST+1
g_wr2:  STA (CDST),Y
        INY
        CPY #64
        BNE g_wr2
        LDA ROWCL-1,X   ; colour RAM / matrix offset of the row
        TAY
        LDA ROWCH-1,X
        STA CDST+1
        STY CDST
        LDA MAPSHOWN
        BEQ g_wr5
        LDA #$D8        ; open: colour RAM 7, matrix 0
        CLC
        ADC CDST+1
        STA CSRC+1
        LDA CDST
        STA CSRC
        LDA #$44
        CLC
        ADC CDST+1
        STA CDST+1
        LDY #39
g_wr3:  LDA #$07
        STA (CSRC),Y
        LDA #$19        ; (pixel value 1, the stars: white; value 2, the cursor's
        STA (CDST),Y    ; boxes: brown, as in the original's map in flight)
        DEY
        BPL g_wr3
        JMP g_wr6
g_wr5:  LDY #39         ; closed: from COLORDATA and the matrix master
        LDA CDST
        STA CSRC
        LDA #$30        ; COLORDATA = $3000
        CLC
        ADC CDST+1
        STA CSRC+1
g_wr7:  LDA (CSRC),Y
        PHA
        LDA CSRC+1
        CLC
        ADC #$A8        ; $30xx -> $D8xx
        STA CSRC+1
        PLA
        STA (CSRC),Y
        LDA CSRC+1
        SEC
        SBC #$A8
        STA CSRC+1
        DEY
        BPL g_wr7
        LDA CDST        ; the matrix row from MMAT ($5000 + offset - 120)
        SEC
        SBC #120
        STA CSRC
        LDA CDST+1
        SBC #$00
        CLC
        ADC #>MMAT
        STA CSRC+1
        LDA #$44
        CLC
        ADC CDST+1
        STA CDST+1
        LDY #39
g_wr8:  LDA (CSRC),Y
        STA (CDST),Y
        DEY
        BPL g_wr8
g_wr6:  DEC WIPE
        BNE g_wr9
        LDA MAPSHOWN    ; the last row: the map's set-up and draw-in begin
        BEQ g_wr9
        LDA #$10        ; the planet's three cells: all black but the stars
        STA PLMAT       ; (the original's $FB95-$FBA8)
        STA PLMAT+1
        STA PLMAT+2
        LDA #$00
        STA PLCOL
        STA PLCOL+1
        STA PLCOL+2
        JMP M_RESET
g_wr9:  RTS

; The map's share of the vertical blank (2 MHz) while it is open or wiping. The
; star field goes on in the same bitmap (GPLOT, GERASE keep the map's pixels), after
; the map's work: a busy frame leaves it out, the stars move on in the next one.
MAPVB:  LDA WIPE
        BNE g_vh1
        LDA HYPON       ; hyperspace: the path, the map's erase and the stars here,
        BEQ g_vh1       ; the rest in the view's time
        JMP HYPMVB
g_vh1:  LDA WIPE        ; the radar's circle being drawn (about 100 lines, VBWORK):
        BNE g_vh2       ; the map waits a frame
        LDA CRUN
        ORA CPEND
        BEQ g_vh2
        RTS
g_vh2:  LDA #$00
        STA MBUSY
        JSR MAPVB1
        LDA MBUSY       ; a box or icons drawn: no time for the stars
        BNE g_vs9
        BIT $D011       ; late, or wrapped: no time for the stars either
        BMI g_vs1
        LDA $D012
        CMP #243
        BCC g_vs9
        BCS g_vs2
g_vs1:  JSR MVSRAD      ; (approaching, a rush's star steps; the radar's frame: after
        BNE g_vs9       ; the wrap the radar needs the time)
        LDA $D012
        CMP #STARLIM
        BCS g_vs9
g_vs2:  JMP STARS
g_vs9:  RTS

MVSRAD: LDA APPR        ; A <> 0: approaching, or the radar runs in this blank
        BNE g_mr9
        LDA RADPEND
        BNE g_mr9
        LDA EFRM
        AND #$01
        EOR #$01
g_mr9:  RTS

MAPVB1: LDA WIPE
        BEQ g_mv0
        JMP WIPEROW
g_mv0:  LDX #23         ; no lines or box under the planet: the original only
        LDA #$00        ; turns them black, and a hit flash shows them
g_mvp:  STA PLBMP,X
        DEX
        BPL g_mvp
        JSR M_STEP      ; the grid's draw-in, then the icons
        JSR M_BLINK
        JSR M_PLANET
        LDA QN          ; a queued box this frame, or a step of the cursor's box,
        BEQ g_mv2       ; else icons
        INC MBUSY
        JMP QDO
g_mv2:  JSR CFOL
        BCC g_mv1
        INC MBUSY
        RTS
g_mv1:  LDA M_ICONDONE
        BEQ g_mv9
        JSR DRAWSOME
        LDA DSN         ; (3: no cell was drawn)
        CMP #$03
        BEQ g_mv9
        INC MBUSY
g_mv9:  RTS

; The cursor's box follows the map's CURX / CURY a step a frame: erase the box
; drawn (unless it is the ship's sector), draw the new one, repair the ship's
; sector's box (a shared edge may have gone), as the original's $2213-$223A. A
; fast mouse skips the sectors in between. C set: a box was drawn this frame.
CFOL:   LDA M_CURINIT
        BEQ g_cf0
        LDA CST
        BNE g_cf2
        LDA M_CURX
        CMP DRX
        BNE g_cf1
        LDA M_CURY
        CMP DRY
        BNE g_cf1
g_cf0:  CLC
        RTS
g_cf1:  LDA M_CURX      ; a new target: erase the drawn box first
        STA TGX
        LDA M_CURY
        STA TGY
        LDA #$01
        STA CST
        LDA DRX
        BMI g_cf9       ; (none drawn)
        CMP M_SELX
        BNE g_cf3
        LDA DRY
        CMP M_SELY
        BEQ g_cf9       ; (the ship's sector keeps its box)
g_cf3:  LDA DRX
        STA M_BC
        LDA DRY
        STA M_BR
        LDA #$00
        STA M_BV
        JSR FBOX
        SEC
        RTS
g_cf2:  CMP #$01
        BNE g_cf4
g_cf5:  LDA #$02        ; the new box
        STA CST
        LDA TGX
        STA DRX
        STA M_BC
        LDA TGY
        STA DRY
        STA M_BR
        LDA #$01
        STA M_BV
        JSR FBOX
        JSR M_BLIP
        SEC
        RTS
g_cf4:  LDA #$00        ; the ship's sector's box again
        STA CST
        LDA M_SELX
        STA M_BC
        LDA M_SELY
        STA M_BR
        LDA #$01
        STA M_BV
        JSR FBOX
        SEC
        RTS
g_cf9:  JMP g_cf5       ; (nothing to erase: the new box at once)
CST:    .BYTE 0
DRX:    .BYTE $FF       ; the box drawn ($FF: none)
DRY:    .BYTE 0
TGX:    .BYTE 0
TGY:    .BYTE 0

; The map's cursor boxes (its BOX, $2384): a move erases the old box, draws the
; new one and repairs the ship's sector's box. Queued here and drawn one a frame
; in the vertical blank, by FBOX (the same pixels, the address worked out once a
; row): drawn at once they took most of a frame.
QBOX:   LDX QN
        CPX #16
        BCC g_qb1
        JMP FBOX        ; (a full queue: at once)
g_qb1:  LDA M_BC
        STA QC,X
        LDA M_BR
        STA QR,X
        LDA M_BV
        STA QV,X
        INC QN
        RTS
QDO:    LDA QC
        STA M_BC
        LDA QR
        STA M_BR
        LDA QV
        STA M_BV
        LDX #$00
g_qd1:  INX
        CPX QN
        BCS g_qd2
        LDA QC,X
        STA QC-1,X
        LDA QR,X
        STA QR-1,X
        LDA QV,X
        STA QV-1,X
        JMP g_qd1
g_qd2:  DEC QN
FBOX:   LDX M_BC        ; corner: x = CELLX * 4 - 3, y = CELLY * 8 - 5
        LDA M_CELLX,X
        ASL A
        ASL A
        SEC
        SBC #3
        STA FX1
        LDX M_BR
        LDA M_CELLY,X
        ASL A
        ASL A
        ASL A
        SEC
        SBC #5
        STA FY1
        LDA #$00        ; value 3 (BV = 0) or 2 (BV = 1)
        LDY M_BV
        BEQ g_fb1
        LDA #$04
g_fb1:  STA FMO
        LDX #$03        ; the sides' 4 columns: byte offset and mask index once
g_fb0:  LDA FX1
        CLC
        ADC FCOLD,X
        STA FT
        LSR A
        LSR A
        TAY
        LDA XLO,Y
        STA FOFL,X
        LDA XHI,Y
        STA FOFH,X
        LDA FT
        AND #$03
        ORA FMO
        STA FMI,X
        DEX
        BPL g_fb0
        LDA FY1         ; the top and bottom edges: 13 pixels, 2 rows each
        STA FY
        JSR FHROW
        INC FY
        JSR FHROW
        LDA FY1
        CLC
        ADC #16
        STA FY
        JSR FHROW
        INC FY
        JSR FHROW
        LDA FY1         ; the sides: 2 pixels at both ends, 17 rows
        STA FY
        LDA #17
        STA FK
g_fb2:  JSR FROW
        LDX #$03
g_fb3:  CLC
        LDA FRL
        ADC FOFL,X
        STA CDST
        LDA FRH
        ADC FOFH,X
        STA CDST+1
        LDY FMI,X
        LDA FCLR,Y
        STA FT
        LDA FSET,Y
        LDY #$00
        STA FK2
        LDA (CDST),Y
        AND FT
        ORA FK2
        STA (CDST),Y
        DEX
        BPL g_fb3
        INC FY
        DEC FK
        BNE g_fb2
        RTS
FHROW:  JSR FROW        ; 13 pixels from FX1: the address once, then along
        LDA FX1
        LSR A
        LSR A
        TAY
        CLC
        LDA XLO,Y
        ADC FRL
        STA CDST
        LDA XHI,Y
        ADC FRH
        STA CDST+1
        LDA FX1
        AND #$03
        ORA FMO
        TAX
        LDA #13
        STA FK2
        LDY #$00
g_fh1:  LDA (CDST),Y
        AND FCLR,X
        ORA FSET,X
        STA (CDST),Y
        INX
        TXA
        AND #$03
        BNE g_fh2
        LDX FMO         ; the next byte (8 further)
        CLC
        LDA CDST
        ADC #8
        STA CDST
        BCC g_fh2
        INC CDST+1
g_fh2:  DEC FK2
        BNE g_fh1
        RTS
FROW:   LDY FY          ; the row's bitmap address
        LDA YLO,Y
        STA FRL
        LDA YHI,Y
        CLC
        ADC #$60
        STA FRH
        RTS
FCOLD:  .BYTE 0,1,12,13
FOFL:   .BYTE 0,0,0,0
FOFH:   .BYTE 0,0,0,0
FMI:    .BYTE 0,0,0,0
FCLR:   .BYTE $3F,$CF,$F3,$FC,$3F,$CF,$F3,$FC
FSET:   .BYTE $C0,$30,$0C,$03,$80,$20,$08,$02
QN:     .BYTE 0
QC:     .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
QR:     .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
QV:     .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
FX1:    .BYTE 0
FY1:    .BYTE 0
FY:     .BYTE 0
FK:     .BYTE 0
FK2:    .BYTE 0
FXX:    .BYTE 0
FRL:    .BYTE 0
FRH:    .BYTE 0
FT:     .BYTE 0
FMO:    .BYTE 0

; The icons a few at a time: up to 3 marked cells a frame (DRAWALL at once, with
; the second display's copy, takes more than a vertical blank).
MARKALL:LDX #59         ; every occupied cell
g_ma1:  LDA M_STATE,X
        ORA M_COUNT,X
        BEQ g_ma2
        LDA #$01
        STA M_DIRTY,X
g_ma2:  DEX
        BPL g_ma1
        RTS
DRAWSOME:
        LDA #$03
        STA DSN
        LDA #12         ; (a dozen cells looked at a frame: all of them take 14 lines)
        STA DSK
g_ds1:  LDX DSI
        LDA M_DIRTY,X
        BEQ g_ds2
        LDA #$00
        STA M_DIRTY,X
        STX M_IDX
        TXA             ; row and column
        LDY #$00
g_ds3:  CMP #10
        BCC g_ds4
        SBC #10
        INY
        BNE g_ds3
g_ds4:  STA M_COL
        STY M_ROW
        LDA #$01        ; (an emptied cell is blanked)
        STA M_MODE
        JSR M_DRAWCELL
        LDA #$00
        STA M_MODE
        DEC DSN
        BEQ g_ds5
g_ds2:  INC DSI
        LDA DSI
        CMP #60
        BCC g_ds6
        LDA #$00
        STA DSI
g_ds6:  DEC DSK
        BNE g_ds1
        RTS
g_ds5:  INC DSI
        LDA DSI
        CMP #60
        BCC g_ds7
        LDA #$00
        STA DSI
g_ds7:  RTS

; The map's input while it is open: the mouse / joystick move its cursor, fire on
; another sector jumps there.
MAPIN:  JSR M_POTS
        LDA #$FF        ; port 2: joystick / mouse buttons
        STA CIA1PA
        LDA CIA1PA
        AND #$1F
        STA M_JB
        LDA #$BF
        STA CIA1PA
        LDA M_JB        ; the stars turn with the stick, or with the mouse's motion
        ORA #$E0        ; (the original's MSYN: motion as joystick directions)
        LDX M_MPRES
        BEQ g_mj9
        LDA #$FF
        LDX M_MDY
        BEQ g_mj1
        BMI g_mj0
        AND #$FD
        BNE g_mj1
g_mj0:  AND #$FE
g_mj1:  LDX M_MDX
        BEQ g_mj9
        BMI g_mj2
        AND #$F7
        BNE g_mj9
g_mj2:  AND #$FB
g_mj9:  STA JOYG
        JSR M_CURSOR
        LDA MJUMPF
        BEQ g_mi9
        LDX #$00
        STX MJUMPF
        CMP #$02        ; the ship's own sector: the map closes, no jump
        BEQ g_mi8
        JSR MAPCLOSE
        LDA #$00        ; the map stays on the screen: its path is plotted, its lines
        STA WIPE        ; erased while the ship accelerates (no wipe)
        LDA #$01        ; hyperspace, then the sector (started in the 3D view's time:
        STA HPEND       ; here, at 1 MHz under the strip, it made the frame late)
        STA HMAP
        LDA #$04        ; (the path's phase: no star field over the map)
        STA HYPON
        RTS
g_mi8:  JMP MAPCLOSE
g_mi9:  RTS

; A star (original $EF30, $EF1B). In the view: value 3 on any pixel. Behind the
; map: value 1, only on an empty pixel, and only a value 1 is erased.
GPLOT:  STX SAVEX
        LDA STARX,X
        STA POSX
        LDA STARY,X
        STA POSY
        JSR PIXADDR
gplmode:LDA MAPSHOWN
        ORA WIPE
        BNE g_pl1
        LDA (PTR),Y
        ORA MASK3,X
        JMP g_pl2
g_pl1:  LDA (PTR),Y
        AND MASK3,X
        BNE g_pl3
        LDA (PTR),Y
        ORA MASK1,X
g_pl2:  STA (PTR),Y
g_pl3:  LDX SAVEX
        RTS
GERASE: STX SAVEX
        LDA STARX,X
        STA POSX
        LDA STARY,X
        STA POSY
        JSR PIXADDR
germode:LDA MAPSHOWN
        ORA WIPE
        BEQ g_er1
        LDA (PTR),Y
        AND MASK3,X
        CMP MASK1,X
        BNE g_er2
g_er1:  LDA (PTR),Y
        AND CLEARM,X
        STA (PTR),Y
g_er2:  LDX SAVEX
        RTS

GENONCE:LDA GENDONE     ; the start layout only once
        BNE g_gon1
        INC GENDONE
        JMP M_GENERATE
g_gon1: RTS
GENDONE:.BYTE 0


; The world's clock, every frame (the map's TICKER: a tick every 256 frames).
; The world's clock ($BE29). The original calls it from its main loops, which are not
; tied to the frame, so its rate depends on what the ship does; measured on a real
; machine's timing (JS machine with m.dma): a tick every 33 frames with the map open,
; 44 in flight (and in hyperspace), 54 in a fight, 200 while the tracking computer
; flies. (The map program ticks every 256 frames, about five times slower.)
WORLD:  JSR GCOLCYC     ; types 2 and 3: the colours
        LDA GENDONE     ; (the world exists)
        BEQ g_wd9
        LDA HYPON       ; no tick while the path is plotted and the ship accelerates
        CMP #$01        ; (the original's $B3F6 loop does not call $BE29)
        BEQ g_wd9
        CMP #$04
        BEQ g_wd9
        DEC WTCNT
        BNE g_wd9
        LDA #33
        LDX MAPSHOWN
        BNE g_wd1
        LDA #200
        LDX TRUN
        BNE g_wd1
        LDA #54
        LDX ALIVE
        BNE g_wd1
        LDX ALIVE+1
        BNE g_wd1
        LDX ALIVE+2
        BNE g_wd1
        LDA #44
g_wd1:  STA WTCNT
        INC WTPEND      ; the tick itself in the 3D view's free time (VIEWWORK): in the
g_wd9:  RTS             ; vertical blank it made fights' frames late
WTPEND: .BYTE 0
WTCNT:  .BYTE 44

; In the 3D view's free time (at 1 MHz: the vertical blank is full in a fight): a step
; of the squadrons' move, if one is going on, and of a squadron coming in.
VIEWWORK:               ; (shpj: JSR GSHLOAD while the squadron's shapes load, else
shpj:   BIT GSHLOAD     ; a BIT that costs a fight's tight frame only 4 cycles)
        LDA WTPEND
        BEQ g_vw1
        LDA $D012       ; (the tick takes ~40 lines: late, the next frame)
        CMP #126
        BCS g_vw1
        LDA #$00
        STA WTPEND
        JSR M_TICK
g_vw1:  JSR HVIEW
        JSR HYPVIEW
        JSR MVSTEP
        JMP ARRSTEP

; Six sectors a frame of the squadrons' move (the map's MOVEPASS, in steps).
MVSTEP: LDA MVON
        BEQ g_mvs9
        LDA #6
        STA MVN
g_mvs1: LDA $D012       ; (late in the view: the rest next frame)
        CMP #170
        BCS g_mvs9
        JSR M_MOVECELL
        DEC M_PCOL
        BPL g_mvs2
        LDA #9
        STA M_PCOL
        DEC M_PROW
        BPL g_mvs2
        LDA #0
        STA MVON
        JMP M_MVCOMMIT
g_mvs2: DEC MVN
        BNE g_mvs1
g_mvs9: RTS
MVON:   .BYTE 0
MVN:    .BYTE 0

; The squadrons' move has ended ($BEDF): one in the ship's sector, and no fight or
; approach going on, comes in.
SQINCHK: LDA ARRFX
        ORA HYPON       ; (not in hyperspace: the original's $BA)
        ORA HPEND
        ORA APPR
        ORA ALIVE
        ORA ALIVE+1
        ORA ALIVE+2
        ORA LYACT
        ORA SQCOUNT
        BNE g_ac9
        JSR SECIDX
        LDA M_STATE,X
        BMI g_ac9
        LDA M_COUNT,X
        BEQ g_ac9
        JSR GSQTYPE     ; (its shapes load while its points rush in)
        LDA #$01
        STA ARRFX
g_ac9:  RTS

; It comes in ($1AF2-$1C55): 24 points, 8 for each of the three fighters, rush to
; their places in 19 steps; each point is 2 pixels tall, in empty pixels only. The
; original takes about 3 frames a step: here 8 points a frame. Then the fighters.
ARRSTEP:LDA ARRFX
        BNE g_as0
        RTS
g_as0:  CMP #$01
        BNE g_as3
        LDX #23         ; the start: around each place ($1B19), with its sound ($1C58)
g_as1:  TXA
        LSR A
        LSR A
        LSR A
        TAY
        TXA
        AND #$07
        STX ARI
        TAX
        LDA ARDX,X
        CLC
        ADC ARTX,Y
        STA ARK
        LDA ARDY,X
        CLC
        ADC ARTY,Y
        LDX ARI
        STA ARPY,X
        LDA ARK
        STA ARPX,X
        DEX
        BPL g_as1
        LDA #23
        STA ARI
        LDA #19
        STA ARSTP
        LDA #$02
        STA ARRFX
        LDA #$00
        STA $D404
        STA $D406
        LDA #$64
        STA $D401
        LDA #$B4
        STA $D405
        LDA #$81
        STA $D404
        RTS
g_as3:  LDA #$08
        STA ARN
g_as4:  JSR ARERASE
        LDA ARRFX
        CMP #$02
        BNE g_as5
        LDX ARI
        TXA
        AND #$07
        TAY
        LDA ARPX,X
        CLC
        ADC ARSX,Y
        STA ARPX,X
        LDA ARPY,X
        CLC
        ADC ARSY,Y
        STA ARPY,X
        JSR ARPLOT
g_as5:  DEC ARI
        BPL g_as6
        LDA #23
        STA ARI
        LDA ARRFX
        CMP #$03
        BNE g_as7
        JMP ARREND      ; (the last points erased)
g_as7:  DEC ARSTP
        BNE g_as6
        LDA #$03        ; the last step: only erased
        STA ARRFX
g_as6:  DEC ARN
        BNE g_as4
        RTS

ARSET:  LDX ARI         ; point ARI; only in the 3D view (above and below it the
        LDA ARPX,X      ; bitmap holds shapes and art). C set: outside
        STA POSX
        LDA ARPY,X
        STA POSY
        CMP #26
        BCC g_ast
        CMP #141
        RTS
g_ast:  SEC
        RTS
ARERASE:JSR ARSET
        BCS g_ae9
        JSR ARE1
        INC POSY
ARE1:   JSR PIXADDR
        LDA (PTR),Y
        AND MASK3,X
        CMP MASK1,X
        BNE g_ae9
        LDA (PTR),Y
        AND CLEARM,X
        STA (PTR),Y
g_ae9:  RTS
ARPLOT: JSR ARSET
        BCS g_ap9
        JSR ARP1
        INC POSY
ARP1:   JSR PIXADDR
        LDA (PTR),Y
        AND MASK3,X
        BNE g_ap9
        LDA (PTR),Y
        ORA MASK1,X
        STA (PTR),Y
g_ap9:  RTS

; The fighters ($1B60-$1B92, $1C24-$1C55): at least 3 ships, one group, the dogfight
; and the warning.
ARREND: JSR SECIDX
        JSR GSQTYPE
        LDA M_COUNT,X
        CMP #$03
        BCS g_ar1
        LDA #$03
        STA M_COUNT,X
g_ar1:  STA SQCOUNT
        LDA #$01
        STA M_DIRTY,X
        LDA SQCOUNT
        JSR SHOWTG
        JSR NEWWAVE
        LDX #$05
g_ar2:  LDA ARENX,X
        STA ENX,X
        LDA ARENY,X
        STA ENY,X
        LDA ARENZ,X
        STA ENZ,X
        DEX
        BPL g_ar2
        LDA #$00
        STA ARRFX
        STA CURG
        STA GSIZE+1
        STA GSIZE+2
        LDA #$03
        STA GSIZE
        JMP DOGSTART

ARTX:   .BYTE $41,$5F,$50       ; the places, x and y ($1AEA, $1AED)
ARTY:   .BYTE $55,$64,$73
ARDX:   .BYTE $28,$27,$00,$D9,$D8,$D9,$00,$27   ; the points' start around a place
ARDY:   .BYTE $00,$B1,$B0,$B1,$00,$4F,$50,$4F   ; ($1A99, $1AA2)
ARSX:   .BYTE $FE,$FE,$00,$02,$02,$02,$00,$FE   ; their steps ($1AAA, $1AB2)
ARSY:   .BYTE $00,$04,$04,$04,$00,$FC,$FC,$FC
ARENX:  .BYTE $8E,$88,$C6,$88,$BC,$88           ; the fighters' places
ARENY:  .BYTE $7D,$88,$8C,$88,$9B,$88
ARENZ:  .BYTE $10,$88,$10,$88,$10,$88
ARPX:   .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
ARPY:   .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
ARRFX:  .BYTE 0         ; 1 starting, 2 flying, 3 the last erase
ARI:    .BYTE 0
ARN:    .BYTE 0
ARK:    .BYTE 0
ARSTP:  .BYTE 0

; Row tables for WIPEROW (index WIPE-1: rows 3-17).
ROWLO:  .BYTE $C0,$00,$40,$80,$C0,$00,$40,$80,$C0,$00,$40,$80,$C0,$00,$40
ROWHI:  .BYTE $63,$65,$66,$67,$68,$6A,$6B,$6C,$6D,$6F,$70,$71,$72,$74,$75
ROWCL:  .BYTE $78,$A0,$C8,$F0,$18,$40,$68,$90,$B8,$E0,$08,$30,$58,$80,$A8
ROWCH:  .BYTE $00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$02,$02,$02,$02,$02

; Into the sector M_SELX / M_SELY: its squadron's ships (none for an empty or a
; mothership sector), then the cockpit's arrival (the approach, ARRIVE).
SECTORIN:
        LDA #$00        ; (a squadron's coming in is off: the map's wipe clears it)
        STA ARRFX
        JSR SECIDX
        JSR MSECTOR     ; sector kind; mothership work uses the dormant shape hook
        LDA #$00
        LDY M_STATE,X
        BEQ g_sin1      ; empty
        BMI g_sin1      ; a mothership: scanner and rings, no squadron
        LDA M_COUNT,X
g_sin1: STA SQCOUNT
        JMP MSARRIVE

; A kill ($3CD9): the map's COUNT follows; at 0 the squadron is gone ($3CDE).
SECKILL:STX SKX
        JSR SECIDX
        LDA M_COUNT,X
        BEQ g_sk9
        DEC M_COUNT,X
        BNE g_sk8
        LDA #$00
        STA M_STATE,X
g_sk8:  LDA #$01        ; redrawn at the next tick if the map is open
        STA M_DIRTY,X
g_sk9:  LDX SKX
        RTS

SECIDX: LDA M_SELY      ; X = row * 10 + column
        ASL A
        ASL A
        CLC
        ADC M_SELY
        ASL A
        CLC
        ADC M_SELX
        TAX
        RTS

SHOWSEC:LDX M_SELX      ; SECTOR cc.rr on the HUD: column and row from 1
        INX
        TXA
        ORA #$70
        STA HUDSEC+1
        LDX M_SELY
        INX
        TXA
        ORA #$70
        STA HUDSEC+4
        RTS

MJUMPF: .BYTE 0         ; the map chose another sector
MBUSY:  .BYTE 0         ; this frame's map work was long
CPREV:  .BYTE 0         ; C= / SPACE held (edges only)
SPREV:  .BYTE 0
SKX:    .BYTE 0
DSI:    .BYTE 0
DSN:    .BYTE 0
DSK:    .BYTE 0

; ---------------- $C000-$CFFF: RAM under the KERNAL (MMU $3E, set at START) ----------------
; The map's code ends at $BFF7, the glue's room is small: new code goes here. The
; game calls no KERNAL routine and runs with interrupts off; NMIRTI keeps RESTORE
; harmless while the KERNAL's vectors are not visible.

; The map's beeps (its SNDTOG, $B2BC; BLIP, $223D): voices 1 and 2 set up whole every
; time, not just gated. A fight goes on with the map open and its sounds play over
; the beeps (as in the original); this way the beeps come back right after them.
GSNDTOG:DEC M_SNDCNT
        BNE g_gt9
        LDA #$02
        STA M_SNDCNT
        LDA #$00        ; (the map's SNDINIT, $B26D, without its gates)
        STA $D400
        STA $D407
        STA $D402
        STA $D409
        STA $D405
        STA $D40C
        LDA #$2B
        STA $D401
        LDA #$12
        STA $D408
        LDA #$01
        STA $D403
        LDA #$0A
        STA $D40A
        LDA #$80
        STA $D406
        LDA #$20
        STA $D40D
        LDA #$0F
        STA $D418
        LDA #$41
        STA $D40B
        LDA M_SNDVAL
        EOR #$01
        STA M_SNDVAL
        STA $D404
g_gt9:  RTS
GBLIP:  LDA #$00
        STA $D404
        STA $D406
        STA $D402
        STA $D400
        LDA #$08
        STA $D403
        LDA #$01
        STA $D405
        LDA #$8F
        STA $D401
        LDA #$0F
        STA $D418
        LDA #$41
        STA $D404
        RTS

; (the arrival: the planet's frame back, the crosshair alone)
HPL5BACK:
        LDA #<SPRCROSS  ; the crosshair alone again
        STA sprcj+1
        LDA #>SPRCROSS
        STA sprcj+2
        LDX #62
mt_pb1:  LDA HSHPL5,X
        STA $7FC0,X
        DEX
        BPL mt_pb1
        LDX #HMN-1      ; (the meteors gone)
        LDA #$00
mt_pb2:  STA HMACT,X
        DEX
        BPL mt_pb2
        RTS

GINIT2:
        JSR GUNPK2      ; the code and data for $E000, packed in the 3D view's bitmap
        LDX #$00        ; type 1 masters in the disabled VDC data, restored below
g_gi2:  LDA $2900,X     ; restore type 1 from TSH1 after unpacking over its slots
        STA $6000,X
        LDA $2A00,X
        STA $6100,X
        LDA $2B00,X
        STA $6200,X
        CPX #$C0
        BCS g_gi1
        LDA $2C00,X
        STA $6300,X
g_gi1:  INX
        BNE g_gi2
        LDA #$63        ; the view's bitmap cleared: $63C0-$767F (18 pages and 192)
        STA CDST+1
        LDA #$C0
        STA CDST
        LDY #$00
        LDX #$12
        TYA
g_gi4:  STA (CDST),Y
        INY
        BNE g_gi4
        INC CDST+1
        DEX
        BNE g_gi4
        LDY #$BF
g_gi5:  STA (CDST),Y
        DEY
        CPY #$FF
        BNE g_gi5
        RTS

; The packed code and data for $E000 (build.py): two bytes, the end address; then
; tokens: $00-$7F a run of n + 1 literal bytes, $80-$FF a copy of (n & $7F) + 3
; bytes from an earlier place, its distance back in the next two bytes.
GUNPACK:LDA #<PACKSRC
        STA CSRC
        LDA #>PACKSRC
        STA CSRC+1
        LDA #<HIGH2
        STA CDST
        LDA #>HIGH2
        STA CDST+1
g_upb:  LDY #$00
        LDA (CSRC),Y
        STA UPEND
        JSR g_up8
        LDA (CSRC),Y
        STA UPEND+1
        JSR g_up8
g_up1:  LDA CDST        ; the end?
        CMP UPEND
        BNE g_up2
        LDA CDST+1
        CMP UPEND+1
        BNE g_up2
        RTS
g_up2:  LDA (CSRC),Y
        JSR g_up8
        TAX
        BMI g_up4
        INX             ; literals
g_up3:  LDA (CSRC),Y
        STA (CDST),Y
        JSR g_up8
        JSR g_up9
        DEX
        BNE g_up3
        BEQ g_up1
g_up4:  TXA             ; a copy
        AND #$7F
        CLC
        ADC #$03
        TAX
        SEC
        LDA CDST
        SBC (CSRC),Y
        STA g_up5+1
        JSR g_up8
        LDA CDST+1
        SBC (CSRC),Y
        STA g_up5+2
        JSR g_up8
g_up5:  LDA $FFFF
        STA (CDST),Y
        INC g_up5+1
        BNE g_up6
        INC g_up5+2
g_up6:  JSR g_up9
        DEX
        BNE g_up5
        BEQ g_up1
g_up8:  INC CSRC
        BNE g_up7
        INC CSRC+1
g_up7:  RTS
g_up9:  INC CDST
        BNE g_up7
        INC CDST+1
        RTS
UPEND:  .BYTE 0,0
GSEED:  .BYTE 0
; STR2Y is staged beneath I/O ($D000) and unpacked over the first stream's
; start ($5E00, read already), so the $E000 code may run up to TORPA.
GUNPK2: JSR GUNPACK
        LDA #>STR2Y     ; (CDST's low byte is 0: the first stream ends at a page)
        STA CDST+1
        JMP MSUNPACK
HIGH2   = $E000
PACKSRC = $5E00

        * = $C000

NMIRTI: RTI

; ---------------- hyperspace ($B3E0-$B78A) ----------------
; Three phases, as the original's: accelerating (the stars speed up, $B3F6), the jump
; ($B55D: the stars draw lines, the energy runs out ten times as fast, the countdown
; of the steps left over the radar) and decelerating ($B6CF). The jump has one step per
; point of the flight path the map plots ($2B14 / $3580: the longer of 12 x columns
; and 16 x rows); a step takes 38 passes of the original's loop, 13.5 frames on a real
; machine. The meteors, the deflector, the plotted path, positioning and the abort come
; in later steps. Runs in the vertical blank (VIEWVB -> MAPVB -> HYPVB, 2 MHz).
HYPSTART:
        LDA #$00        ; the old sector's fight ends
        STA SQCOUNT
        JSR ARRIVE
        JSR TRKEND
        LDA HFROMX      ; the steps: max(12 x |columns|, 16 x |rows|)
        SEC
        SBC M_SELX
        BCS g_hy1
        EOR #$FF
        ADC #$01
g_hy1:  STA HT
        ASL A           ; x 12
        ADC HT
        ASL A
        ASL A
        STA HSTEPS
        LDA HFROMY
        SEC
        SBC M_SELY
        BCS g_hy2
        EOR #$FF
        ADC #$01
g_hy2:  ASL A           ; x 16
        ASL A
        ASL A
        ASL A
        CMP HSTEPS
        BCC g_hy3
        STA HSTEPS
g_hy3:  LDA M_SELX      ; the destination waits for the arrival ($FCB8 / $FCD0 set
        STA HTGTX       ; $92 / $93 only then): during the jump the ship is still in
        LDA M_SELY      ; its old sector, which the hunters chase, which does not move
        STA HTGTY
        JSR HPATHINIT
        JSR HRADCLR
        LDA #$08        ; the icons go first, a row a frame from the bottom, then
        STA HICR        ; the two boxes are drawn whole
        LDA HFROMX
        STA M_SELX
        LDA HFROMY
        STA M_SELY
        LDA #$01        ; the map's lines erased from both sides ($B094 with $B077 set)
        STA HMW
        STA HMCI
        LDA #$11
        STA HMFX
        LDA #$8A
        STA HMFR
        JMP M_SNDINIT   ; the path's beeps ($B26D)

; A row of the map's icons erased (row HICR): their two cells' pixels cleared, their
; colours the map's ($19: white stars, brown boxes), as the original clears them
; before it plots the path.
HICONS: LDX HICR
        CPX #$02
        BCS g_ic9
        LDA #$01        ; the boxes, a frame each: the ship's sector, then the
        STA M_BV        ; destination's (under the planet too: black there until the
        LDA HFROMX      ; path is complete)
        LDY HFROMY
        CPX #$01
        BEQ g_ic8
        LDA HTGTX
        LDY HTGTY
g_ic8:  STA M_BC
        STY M_BR
        JMP FBOX        ; (at once: M_BOX queues it for the open map)
g_ic9:  DEX
        DEX
        LDA #$00        ; the row's offset: CELLY x 40
        STA HOFH
        LDA M_CELLY,X
        ASL A
        ASL A
        ASL A
        STA HT8
        ASL A
        ROL HOFH
        ASL A
        ROL HOFH
        CLC
        ADC HT8
        STA HOFL
        BCC g_ic0
        INC HOFH
g_ic0:  LDX #9
g_ic1:  CLC             ; the cell's offset
        LDA HOFL
        ADC M_CELLX,X
        STA CDST
        STA CSRC
        LDA HOFH
        ADC #$00
        STA CSRC+1
        ADC #$44        ; the colour matrix ($4400)
        STA CDST+1
        LDY #$01
        LDA #$19
        STA (CDST),Y
        DEY
        STA (CDST),Y
        ASL CSRC        ; the bitmap ($6000 + offset x 8)
        ROL CSRC+1
        ASL CSRC
        ROL CSRC+1
        ASL CSRC
        ROL CSRC+1
        CLC
        LDA CSRC+1
        ADC #$60
        STA CSRC+1
        LDA #$00
        LDY #15
g_ic2:  STA (CSRC),Y
        DEY
        BPL g_ic2
        DEX
        BPL g_ic1
        RTS

; The jump begins ($B58B-$B5C8): the scanner goes to long range ($3194), the
; destination's squadron is split into groups and laid out ($3D79, LYSTEP in the
; vertical blank), then put level with the ship ($1D/$1F/$21 = $88; at the easy
; levels the first group straight ahead, $17 = $88, $23 = $94) and the blip starts
; ($3736). An empty destination shows readings of 0.
HSCANGO:JSR HMINIT
        LDA HTGTY       ; the destination's sector
        ASL A
        ASL A
        CLC
        ADC HTGTY
        ASL A
        CLC
        ADC HTGTX
        TAX
        JSR GSQTYPE     ; (its shapes load during the jump)
        LDA #$00
        LDY M_STATE,X
        BEQ g_sg1       ; empty
        NOP
        NOP
        JSR MSCOUNT
g_sg1:  STA SQCOUNT
        LDA #$00
        STA GSEL
        STA NUMT
        STA HPACC
        LDA #$01        ; (the radar's mode in the vertical blank: in the view's
        STA LRMODE      ; time it ran late)
        STA HVBJ
        JSR LRCLEAR
        LDA SQCOUNT
        BEQ g_sg2
        LDA #$01        ; laying out
        STA HSCAN
        JMP LAYOUT
g_sg2:  LDA #$00        ; empty: no groups, the readings 0
        STA GSIZE
        STA GSIZE+1
        STA GSIZE+2
        LDA #$88
        STA ENX+1
        STA ENY+1
        STA ENZ+1
        LDA #$02
        STA HSCAN
        JMP lr7

; The jump's frame: the layout's end, positioning ($9A95, every 2 passes: about
; 1.4 a frame), the readings ($3776, every 16 passes: every 6 frames).
HSCANF: LDA HSCAN
        CMP #$01
        BNE g_sf3
        LDA LYACT       ; the layout done: level with the ship, the blip
        BNE g_sf9
        LDA #$88
        STA ENY+1
        STA ENY+3
        STA ENY+5
        LDA DIFF
        CMP #$02
        BCS g_sf1
        LDA #$88
        STA ENX+1
        LDA #$94
        STA ENZ+1
g_sf1:  LDA #$03        ; (no blip, no choosing a group with fire: the original's
        STA HSCAN       ; tracking sprite comes on arrival)
        RTS
g_sf3:  CMP #$03
        BNE g_sf9
        JSR HJPOS
        CLC
        LDA HPACC
        ADC #$66
        STA HPACC
        BCC g_sf4
        JSR HJPOS
g_sf4:  DEC HRDC
        BPL g_sf9
        LDA #$05
        STA HRDC
        JMP lr7         ; (the readings only: no blip, fire does not choose)
g_sf9:  RTS

; Positioning ($9A95): the stick moves every group: up / down its depth by $40
; (nearer / farther, $2C27), left / right its side by $40 ($2BEF). A slot with no
; group keeps depth 0 ($B600).
HJPOS:  LDX #$04
g_po1:  LDA JOY
        STA HJT
        LSR HJT
        BCS g_po2
        LDA #$40
        JSR ADDZ
g_po2:  LSR HJT
        BCS g_po3
        LDA #$C0
        JSR ADDZ
g_po3:  LSR HJT
        BCS g_po4
        LDA #$40
        JSR ADDX
g_po4:  LSR HJT
        BCS g_po5
        LDA #$C0
        JSR ADDX
g_po5:  DEX
        DEX
        BPL g_po1
        LDX #$04
        LDY #$02
g_po6:  LDA GSIZE,Y
        BNE g_po7
        STA ENZ+1,X
g_po7:  DEX
        DEX
        DEY
        BPL g_po6
        RTS

; The arrival: the radar back to close range, the sector entered (SECTORIN); the
; groups stay where hyperspace put them (the original's slots are not laid out
; again), the approach begins with them.
HARRIVE:LDA HSCAN
        BEQ g_hz3
        LDX #17         ; the slots and the groups' sizes kept
g_hz1:  LDA ENX,X
        STA HSLOT,X
        DEX
        BPL g_hz1
        LDX #$02
g_hz2:  LDA GSIZE,X
        STA HSLOT+18,X
        DEX
        BPL g_hz2
g_hz3:  JSR SECTORIN
        LDA HSCAN
        CMP #$03
        BNE g_hz6
        LDA APPR        ; (an approach: the same squadron)
        BEQ g_hz6
        LDX #17
g_hz4:  LDA HSLOT,X
        STA ENX,X
        DEX
        BPL g_hz4
        LDX #$02
g_hz5:  LDA HSLOT+18,X
        STA GSIZE,X
        DEX
        BPL g_hz5
        LDA #$00
        STA RELAYOUT
        LDA #$01        ; the radar stays long range with its marks (ARRIVE sets 0;
        STA LRMODE      ; the approach's scanner switches to it again, APFRAME)
        BNE g_hz7
g_hz6:  LDA HSCAN       ; no approach: the radar back to close range, its marks gone
        BEQ g_hz7
        LDA #$00
        STA LRMODE
        JSR HRADCLR
        JSR HRMODE
g_hz7:  LDA #$00
        STA HSCAN
        RTS

; RADMODE without its beep: in hyperspace the radar changes range silently.
HRMODE: LDY LRMODE
        LDA RTAB,Y
        STA RXLO
        LDA RTAB+2,Y
        STA RXHI
        LDA RTAB+4,Y
        STA RZLO
        LDA RTAB+6,Y
        STA RZHI
        LDA #$04        ; long: plot 4, erase 8; close: plot 8, erase 4
        LDX #$08
        CPY #$00
        BNE g_rm1
        LDA #$08
        LDX #$04
g_rm1:  STA CRAD1
        STX CRAD2
        LDA #$02        ; (the circles in the next vertical blanks, CIRCLES)
        STA CPEND
        LDA #$01        ; the colour band moves
        STA SHACT
        RTS

; The map's planet, a frame every 8th call (its PLANET): $39-$3C, then the fifth
; frame, the original's unused $3D (pointer M_PL5 here), which fills the gap
; between $3C and $39.
GPLANET:INC M_PCNT
        LDA M_PCNT
        AND #$07
        BNE g_gp9
        LDX M_PFRM
        CPX #M_PL5
        BEQ g_gp1
        INX
        CPX #$3D
        BCC g_gp2
        LDX #M_PL5
        BNE g_gp2
g_gp1:  LDX #$39
g_gp2:  STX M_PFRM
        STX $47F9
        JMP M_VDCPLDEF
g_gp9:  RTS

; ---------------- meteors, dodging, the deflector ($288F, $B8D9, $270D) ----------------
; Five meteors on sprites 1, 2, 4, 5, 6 ($2850): each waits a random delay, then
; appears near the middle and grows through shapes $66-$71 while it drifts outward,
; faster the farther it is from the middle ($2A79, $2AB8). At full size it hits the
; ship ($2947): the flash, a system hit unless the deflector is on ($84D7), the
; rattle ($0912), the burst ($C3F3) and the second explosion where it was. The
; original calls $288F 3 times a pass, about 8.4 times a frame. The stick (or the
; hyperspace cursor) pushes them away, more the bigger they are ($B8D9, every 16
; passes: every 6th frame, the directions of those frames). Fire holds the
; deflector ($270D): the view's colour RAM green, which shows the shield's lines
; (plotted in colour 3, black otherwise), no hits, 15 energy a call (10 a frame).
HMINIT: LDX #HMN-1
mt_mi1:  JSR RANDOM
        STA HMDLY,X
        LDA #$00
        STA HMACT,X
        DEX
        BPL mt_mi1
        STA HDEF
        STA HMACC
        LDA #$FF
        STA HDJ
        LDA #$06
        STA HDJC
        LDX #62         ; shape $66 into pointer $FF (the planet's fifth frame there
        LDA #$00        ; until now; HPL5BACK puts it back): two pixels, $04 / $08
mt_mi2:  STA $7FC0,X
        DEX
        BPL mt_mi2
        LDA #$04
        STA $7FC1
        LDA #$08
        STA $7FC4
        LDA #<HSPRC     ; the meteors' sprites from now on
        STA sprcj+1
        LDA #>HSPRC
        STA sprcj+2
        RTS
HMFRAME:CLC             ; 8.4 calls of $288F a frame, counted off at once (late in
        LDA HMACC       ; the view: added to the next frame's)
        ADC #$66
        STA HMACC
        LDA HMK
        ADC #$08
        CMP #16
        BCC mt_mf0
        LDA #16
mt_mf0:  STA HMK
        LDA $D012
        CMP #156
        BCS mt_mf0a
        JSR HMALL
        LDA #$00
        STA HMK
mt_mf0a:
        LDA JOY         ; dodging: the directions of 6 frames
        AND HDJ
        STA HDJ
        DEC HDJC
        BNE mt_mf2
        LDA $D012       ; (no time: the next frame)
        CMP #160
        BCC mt_mf1b
        INC HDJC
        BNE mt_mf2
mt_mf1b: LDA #$06
        STA HDJC
        JSR HDODGE
        LDA #$FF
        STA HDJ
mt_mf2:  LDA HYPON       ; the deflector: in the jump only
        CMP #$02
        BNE mt_mf9
        JMP HDEFL
mt_mf9:  RTS

; HMK calls of $288F for every meteor: a waiting one counts its delay down by HMK,
; a flying one takes a step each time its pace counter would reach 0.
HMALL:  LDX #HMN-1
mt_mc1:  LDA HMK
        STA HMR
        LDA HMACT,X
        BNE mt_mc5
        LDA HMDLY,X     ; waiting
        CMP HMR
        BEQ mt_mc0
        BCC mt_mc0
        SEC
        SBC HMR
        STA HMDLY,X
        JMP mt_mc9
mt_mc0:  LDA #$01        ; it appears
        STA HMDLY,X
        STA HMACT,X
        STA HMALT,X
        JSR RANDOM
        AND #$3F
        ADC #$7B
        STA HMX,X
        JSR RANDOM
        AND #$3F
        ADC #$61
        STA HMY,X
        LDA #$00
        STA HMXH,X
        LDA #$66
        STA HMSHP,X
        LDA #$0B
        STA HMGC,X
        STA HMGR,X
        LDY DIFF
        LDA HMSPD,Y
        STA HMSD,X
        STA HMSR,X
        JMP mt_mc9
mt_mc5:  LDA HMSD,X      ; its pace: a step when the count reaches 0
        CMP HMR
        BEQ mt_mc6
        BCC mt_mc6
        SEC
        SBC HMR
        STA HMSD,X
        LDA HC26        ; (the multicolour shimmers: $290B DEC $D026)
        SEC
        SBC HMR
        STA HC26
        JMP mt_mc9
mt_mc6:  LDA HMR
        SEC
        SBC HMSD,X
        STA HMR
        DEC HMALT,X     ; (the original speeds up once: its $2844 never reaches 0
        BEQ mt_mc7       ; again)
        LDA #$02
        STA HMALT,X
        LDA HMSR,X
        JMP mt_mc8
mt_mc7:  LDA HMSR,X
        SEC
        SBC #$01
        CMP #$04
        BCS mt_mc8
        LDA #$04
mt_mc8:  STA HMSR,X
        STA HMSD,X
        DEC HMGC,X      ; it grows
        BNE mt_mc3
        LDA HMGR,X
        STA HMGC,X
        INC HMSHP,X
        DEC HMGR,X
        BNE mt_mc3
        JSR HMHIT       ; full size: it hits the ship
        JMP mt_mcx
mt_mc3:  JSR HMMOVE
        JMP mt_mc5      ; (more calls left this frame?)
mt_mc9:  DEX
        BMI mt_mcr
        JMP mt_mc1
mt_mcr: RTS
mt_mcx:  LDA #$FE        ; ($2A54) gone, a long wait
        STA HMDLY,X
        LDA #$00
        STA HMACT,X
        JMP mt_mc9

; A step outward ($29B6-$2A52): x by its place (the table at $2A79, while x < 256),
; y by its place ($2AB8); out of the view: gone.
HMMOVE: LDA HMXH,X
        BNE mt_mm2
        LDA HMX,X
        LDY #$00
mt_mm1:  CMP HMXL,Y
        BCC mt_mm1a
        INY
        CPY #$06
        BNE mt_mm1
mt_mm1a: LDA HMXV,Y
        STA HMVX,X
mt_mm2:  LDA HMVX,X
        BMI mt_mm4
        CLC
        ADC HMX,X
        STA HMX,X
        BCS mt_mm3
        LDA HMXH,X
        BEQ mt_mm5
        LDA HMX,X
        CMP #$30
        BCC mt_mm5
        JMP mt_mmx
mt_mm3:  LDA #$01
        STA HMXH,X
        JMP mt_mm5
mt_mm4:  AND #$7F
        STA HT
        SEC
        LDA HMX,X
        SBC HT
        STA HMX,X
        BCC mt_mm4a
        CMP #$23
        BCS mt_mm5
        JMP mt_mmx
mt_mm4a: LDA HMXH,X
        BNE mt_mm4b
        JMP mt_mmx
mt_mm4b: LDA #$00
        STA HMXH,X
mt_mm5:  LDA HMY,X       ; y
        LDY #$00
mt_mm6:  CMP HMYL,Y
        BCC mt_mm7
        INY
        CPY #$06
        BNE mt_mm6
mt_mm7:  LDA HMYV,Y
        STA HMVY,X
        BMI mt_mm8
        CLC
        ADC HMY,X
        STA HMY,X
        CMP #$DF
        BCS mt_mmx
        RTS
mt_mm8:  AND #$7F
        STA HT
        SEC
        LDA HMY,X
        SBC HT
        STA HMY,X
        CMP #$24
        BCC mt_mmx
        RTS
mt_mmx:  PLA             ; out of the view: gone (from HMCALL's slot)
        PLA
        JMP mt_mcx

; Full size ($2947): the ship is hit unless the deflector is on; the rattle, the
; burst, the second explosion where the meteor was.
HMHIT:  STX HMXS
        LDA HDEF        ; deflected: no flash, no sound, no damage, only the burst
        BNE mt_mh2a     ; of points (the deflector's tone stays on voice 1)
        LDA HMBIT,X
        STA HITFL       ; ($DD) the flash
        INC HSHIPP      ; ($84D7, in the vertical blank)
        LDA #$01        ; ($0912) the rattle: 3 sweeps up from $0Bxx
        STA SNDDIR
        LDA #$0B
        STA SNDHI0
        LDA #$40
        LDX #$03
        LDY #$1E
        JSR SNDGO
        LDA #$0F        ; ($C3F3) the burst, voice 2
        STA $D418
        LDA #$00
        STA $D407
        STA $D40B
        STA $D40D
        LDA #$12
        STA $D408
        LDA #$1A
        STA $D40C
        LDA #$81
        STA $D40B
mt_mh2a: LDX HMXS
        LDA EXPL2       ; the second explosion, unless one runs ($2960)
        BNE mt_mh9
        STA EXPB2
        LDA HMVX,X
        ASL A
        STA EVX02
        LDA HMVY,X
        ASL A
        STA EVY02
        LDA #$01
        STA EXPL2
        LDA HMXH,X      ; x / 2 - 6, y - $1E, inside the view
        LSR A
        LDA HMX,X
        ROR A
        SEC
        SBC #$06
        STA EXPX2
        CMP #$05
        BCC mt_mh8
        CMP #$91
        BCS mt_mh8
        LDA HMY,X
        SEC
        SBC #$1E
        STA EXPY2
        CMP #$05
        BCC mt_mh8
        CMP #$C3
        BCC mt_mh9
mt_mh8:  LDA #$00
        STA EXPL2
mt_mh9:  RTS

; The deflector ($270D): fire switches it on (the view green: the shield's lines show,
; a tone on voice 1); held, it costs 10 energy a frame and the tone wavers; released,
; it goes.
HDEFL:  LDA JOY
        AND #$10
        ORA HSHL        ; (only with the shield's lines complete: a short jump
        BNE HDEFOFF     ; finishes them in its first frames)
        LDA HDEF
        BNE mt_df1
        LDA #$01        ; on
        STA HDEF
        LDA #$0D
        STA HCOLV
        LDA #$01
        STA HCOLJ
        LDA #$00
        STA HDPW
        STA SNDON       ; (a rattle still sweeping voice 1 stops)
        LDA #$08
        STA HDPWH
mt_df1:  JSR HDTONE      ; ($2722 JSR $274C: every call, so no other sound keeps voice 1)
mt_df2:  LDX #10         ; held: the energy
mt_df3:  TXA
        PHA
        LDA #$01
        JSR HENERGY
        PLA
        TAX
        DEX
        BNE mt_df3
        INC HDPW        ; ($2770) the pulse width moves, the pitch wavers
        LDA HDPW
        STA $D402
        AND #$0F
        BNE mt_df4
        INC HDPWH
        LDA HDPWH
        STA $D403
mt_df4:  JSR RANDOM
        AND #$03
        CLC
        ADC #$04
        STA $D401
        RTS
HDTONE: LDA #$00        ; ($274C) the tone: pulse, $08xx (pulse width and pitch moved
        STA $D405       ; by HDEFL)
        LDA HDPW
        STA $D402
        LDA HDPWH
        STA $D403
        LDA #$F0
        STA $D406
        LDA #$41
        STA $D404
        LDA #$0F
        STA $D418
        RTS
HDEFOFF:LDA HDEF
        BEQ mt_do9
        LDA #$00        ; off: the tone stops, the view black again
        STA HDEF
        STA $D404
        STA HCOLV
        LDA #$01
        STA HCOLJ
mt_do9:  RTS

; The radar's marks go: in hyperspace it shows no ships (the radar's pass is left
; out there, its last marks stood still).
HRADCLR:LDY #$02
g_rc1:  LDA RBON,Y
        BEQ g_rc2
        LDA #$00
        STA RBON,Y
        LDA RBX,Y
        STA POSX
        LDA RBY,Y
        STA POSY
        JSR MERASE
g_rc2:  DEY
        BPL g_rc1
        RTS

; The path on the map ($2B14, $3580): from the ship's sector to the destination, a
; brown 2 x 2 point a frame, max(12 x columns, 16 x rows) + 1 of them.
HPATHINIT:
        LDA HFROMX      ; x = 12 x column + 24, y = 16 x row + 44 ($2075, $207F)
        JSR HPCX
        STA HPX
        LDA HTGTX
        JSR HPCX
        LDX #$01
        SEC
        SBC HPX
        BCS g_pi1
        EOR #$FF
        ADC #$01
        LDX #$FF
g_pi1:  STA HPDX
        STX HPSX
        LDA HFROMY
        JSR HPCY
        STA HPY
        LDA HTGTY
        JSR HPCY
        LDX #$01
        SEC
        SBC HPY
        BCS g_pi2
        EOR #$FF
        ADC #$01
        LDX #$FF
g_pi2:  STA HPDY
        STX HPSY
        CMP HPDX        ; points: the longer axis + 1
        BCS g_pi3
        LDA HPDX
g_pi3:  STA HPN
        INC HPN
        LSR A
        STA HPERR
        LDA #$01
        STA HPATH
        RTS
HPCX:   STA HT
        ASL A
        ADC HT
        ASL A
        ASL A
        ADC #24
        RTS
HPCY:   ASL A
        ASL A
        ASL A
        ASL A
        ADC #44
        RTS

; A point of the path (vertical blank): value 2 (brown, $EF45), then a step along
; the line; voice 1's gate toggles every other frame ($2BAA).
HPSTEP: LDA HPX
        STA POSX
        LDA HPY
        STA POSY
        JSR HP2
        INC POSX
        JSR HP2
        INC POSY
        JSR HP2
        DEC POSX
        JSR HP2
        JSR M_SNDTOG
        DEC HPN
        BNE g_ps1
        LDA #$00        ; done
        STA HPATH
        RTS
g_ps1:  LDA HPDX
        CMP HPDY
        BCC g_ps3
        CLC             ; x the longer axis
        LDA HPX
        ADC HPSX
        STA HPX
        CLC
        LDA HPERR
        ADC HPDY
        BCS g_ps2
        CMP HPDX
        BCC g_ps6
g_ps2:  SBC HPDX
        STA HPERR
        CLC
        LDA HPY
        ADC HPSY
        STA HPY
        RTS
g_ps3:  CLC             ; y the longer axis
        LDA HPY
        ADC HPSY
        STA HPY
        CLC
        LDA HPERR
        ADC HPDX
        BCS g_ps4
        CMP HPDY
        BCC g_ps6
g_ps4:  SBC HPDY
        STA HPERR
        CLC
        LDA HPX
        ADC HPSX
        STA HPX
        RTS
g_ps6:  STA HPERR
        RTS
HP2:    JSR PIXADDR
        LDA (PTR),Y
        AND CLEARM,X
        ORA M_MASK2,X
        STA (PTR),Y
        RTS

; A frame of the map's erase ($B0F2 with $B077 set): the horizontal lines from both
; ends inward, a pixel column a frame, stepping over the vertical lines; 32 frames'
; pause; the vertical lines from top and bottom. Brown pixels (the path, the boxes)
; stay ($EEE6). Then the view is wiped clean.
HMSTEP: LDA HMW
        CMP #$02
        BEQ g_ms20
        BCS g_ms30
        LDX #6          ; 1: even rows from the left front, odd from the right
g_ms11: STX SAVEX
        TXA
        LSR A
        LDA HMFX
        BCC g_ms12
        LDA HMFR
g_ms12: STA POSX
        LDA M_YS,X
        STA POSY
        JSR HME
        INC POSY
        JSR HME
        LDX SAVEX
        DEX
        BPL g_ms11
        LDY HMFX
        INY
        DEC HMFR
        LDX HMCI
        TYA
        CMP M_VX,X
        BNE g_ms13
        INY
        INY
        DEC HMFR
        DEC HMFR
        INC HMCI
g_ms13: STY HMFX
        CPY #$8B
        BCC g_ms9
        LDA #$02
        STA HMW
        LDA #$20
        STA HMPC
g_ms9:  RTS
g_ms20: DEC HMPC        ; 2: the pause
        BNE g_ms9
        LDA #$03
        STA HMW
        LDA #$23
        STA HMFT
        LDA #$84
        STA HMFB
g_ms30: LDX #10         ; 3: even columns from the top front, odd from the bottom
g_ms31: STX SAVEX
        LDA M_VX,X
        STA POSX
        TXA
        LSR A
        LDA HMFT
        BCC g_ms32
        LDA HMFB
g_ms32: STA POSY
        JSR HME
        INC POSX
        JSR HME
        LDX SAVEX
        DEX
        BPL g_ms31
        DEC HMFB
        INC HMFT
        LDA HMFT
        CMP #$85
        BCC g_ms9
        LDA #$00        ; over: the rest (the path, the boxes, the icons) wiped
        STA HMW
        STA HMAP
        LDA #15
        STA WIPE
        LDA #$01        ; then the deflector's lines (HSHIELD)
        STA HSHPEND
        RTS
HME:    JSR PIXADDR
        LDA (PTR),Y
        AND MASK3,X
        CMP M_MASK2,X
        BEQ g_me9
        LDA (PTR),Y
        AND CLEARM,X
        STA (PTR),Y
g_me9:  RTS

; The acceleration begins when the path is complete (the original: $B3F6 when $2B11
; ends): the stars start as dots, voices 1 and 2 stop, the engine sound ($10DF).
HACCEL: LDA #$19        ; the path is complete: under the planet its brown shows
        STA PLMAT       ; too (the planet's cells take the map's colours)
        STA PLMAT+1
        STA PLMAT+2
        LDX #HNS-1
g_ha1:  JSR HNEW
        JSR HPLOT
        DEX
        BPL g_ha1
        LDA #$01
        STA HYPON
        LDA #233        ; accelerating ($B3F6: 233 frames on a real machine)
        STA HTIME
        LDA #$02        ; 0.5 pixels a frame
        STA HSPD
        LDA #$00
        STA HSACC
        STA HACC
        STA HENC
        STA ENGON       ; the flight's engine bursts stop ($10DF: $C376)
        STA $D404
        STA $D40B
        STA $D412
        STA $D410
        STA HPWL
        STA HEFL
        LDA #$02
        STA HEFH
        STA $D40F
        LDA #$00
        STA $D40E
        LDA #$05
        STA $D411
        LDA #$F0
        STA $D414
        LDA #$60
        STA $D413
        LDA #$0F
        STA $D418
        LDA #$81
        STA $D412
        LDA #$04        ; rising ($B413)
        STA HESTP
        STA HEDIR
        LDA #$03
        STA HPWS
        RTS

; The engine in hyperspace ($1123, a frame): voice 3's noise rises or falls by HESTP,
; its pulse width moves by 3, turning at each page of the pitch.
HENGINE:LDA HEDIR
        BNE g_en2
        SEC
        LDA HEFL
        SBC HESTP
        STA HEFL
        BCS g_en3
        DEC HEFH
        JMP g_en1
g_en2:  CLC
        LDA HEFL
        ADC HESTP
        STA HEFL
        BCC g_en3
        INC HEFH
g_en1:  LDA HPWS
        EOR #$FF
        CLC
        ADC #$01
        STA HPWS
g_en3:  LDA HEFH
        STA $D40F
        LDA HEFL
        STA $D40E
        CLC
        LDA HPWL
        ADC HPWS
        STA HPWL
        STA $D410
        RTS

; The upper HUD's border pulses through the grays in hyperspace ($09B7: $F8 or $BA);
; a sweep that plays pulses it itself (SNDTICK).
; VBWORK after the radar: in hyperspace nothing more (the original's hyperspace loop
; has no steering, enemy fire or approach), out of VBWORK; else LDA APPR.
HVBR:   LDA HYPON
        BEQ g_vr1
        PLA
        PLA
        RTS
g_vr1:  LDA APPR
        RTS

HBRDSET:LDX HYPON       ; (SNDTICK's light blue: not in hyperspace)
        BNE g_bd9
        STA HUDBRD
        RTS
HBORD:  LDA SNDON
        BNE g_bd9
        LDX SNDPI
        LDA PULSE,X
        STA HUDBRD
        DEC SNDPI
        BPL g_bd9
        LDA #$22
        STA SNDPI
g_bd9:  RTS

HYPVB:  LDA HYPON
        CMP #$04
        BNE g_hv0
        LDA HPATH       ; 4: the path on the map
        BNE g_hv01
        JMP HACCEL
g_hv01: RTS
g_hv0:  JSR HDGSTEP     ; (a digit of the countdown)
        JSR HENGINE
        JSR HBORD
        LDA HYPON
        CMP #$02
        BEQ g_hv20
        BCS g_hv30
        LDA HTIME       ; 1: accelerating: a quarter pixel faster every 20 frames,
        CMP #20         ; up to 3 pixels a frame ($F209 $41 -> $03)
        BCC g_hv11
        AND #$0F
        BNE g_hv11
        LDA HSPD
        CMP #12
        BCS g_hv11
        INC HSPD
g_hv11: LDA #10         ; energy: a unit every 10 frames
        JSR HENERGY
        DEC HTIME
        BNE g_hv01
        LDA #$02        ; the jump
        STA HYPON
        LDA HSTEPS
        STA HCNT
        JSR HDIGITS
        LDA #$00        ; the engine's pitch holds ($B567); the rush ($1349)
        STA HESTP
        JSR SNDRUSH
        JMP HSCANGO
g_hv20: JSR HSCANF      ; 2: the jump: the scanner, positioning
        JSR HMFRAME     ; the meteors, dodging, the deflector
        LDA #$01        ; a unit a frame
        JSR HENERGY
        CLC             ; a step every 13.5 frames
        LDA HACC
        ADC #19
        STA HACC
        BCC g_hv01
        DEC HCNT
        BEQ g_hv21
        JSR HDIGITS
        JMP g_hvst
g_hv21: JSR HCLRDIG     ; over: decelerating, 120 frames
        LDA #$03
        STA HYPON
        LDA #120
        STA HTIME
        JSR HDEFOFF     ; (the deflector only in the jump)
        JSR HPL5BACK    ; the meteors gone ($B6D6: sprites 0, 3, 7 only)
        LDA #$04        ; the engine falls ($B6CF)
        STA HESTP
        LDA #$00
        STA HEDIR
        JMP g_hvst
g_hv30: LDA HTIME       ; 3: decelerating (no meteors: $B6CF does not call $288F)
        AND #$07
        BNE g_hv31
        LDA HSPD
        CMP #$03
        BCC g_hv31
        DEC HSPD
g_hv31: LDA #10
        JSR HENERGY
        DEC HTIME
        BNE g_hvst
        JSR HZERO       ; (the cursor's digits 000)
        JSR HPL5BACK
        LDA #$00        ; arrived: the view wiped clean (its colours back), the sector
        STA HYPON
        STA $D412       ; the hyperspace engine off, the flight's back
        LDA #$01
        STA ENGON
        LDA #$0E
        STA HUDBRD
        LDA #15
        STA WIPE
        LDA HTGTX       ; now the ship is in the new sector
        STA M_SELX
        LDA HTGTY
        STA M_SELY
        JSR SHOWSEC
        JMP HARRIVE
g_hvst: RTS

; Hyperspace's phase, in the 3D view's free time (VIEWWORK, every frame): the start,
; the speed, the energy, the countdown, the arrival.
HYPVIEW:LDX #$00        ; the crosshair hidden (HCRY: decided here, its slot is timed)
        LDA HYPON
        BEQ g_hc1
        JSR HCURON
        BNE g_hc1
        INX
g_hc1:  STX HCHIDE
        LDA MAPSHOWN    ; sprite 1 the map's planet (the cockpit's SPRCROSS)
        ORA HMAP
        STA MAPSPR
        LDA #$00        ; the radar's pass: not in hyperspace until the scanner
        LDX HYPON       ; runs (VBWORK)
        BEQ g_hw1
        LDX HSCAN
        CPX #$03
        BEQ g_hw1
        LDA #$01
g_hw1:  STA HNORAD
        LDA HPEND
        BEQ g_hvp
        LDA #$00
        STA HPEND
        JMP HYPSTART
g_hvp:  LDA HYPON
        BEQ g_hv9
        JMP HYPVB
g_hv9:  RTS

; Hyperspace's stars, in the vertical blank (MAPVB, 2 MHz: at 1 MHz in the view they
; ran into the gun split): HSPD quarter pixels a frame. A dot is erased and plotted
; once a frame, only a line needs every pixel.
HYPMVB: LDA HSHIPP      ; a meteor's hit on the ship (too long for the view's time)
        BEQ g_hmh
        DEC HSHIPP
        JMP SHIPHIT
g_hmh:  LDA HMAP        ; the planet turns while the map is there
        BEQ g_hm9
        JSR M_PLANET
g_hm9:  LDA HVBJ        ; a job of the scanner's: the radar's mode, the blip
        BEQ g_hm8       ; (instead of the stars this frame)
        LDX #$00
        STX HVBJ
        CMP #$01
        BNE g_hm7
        JSR HRADCLR     ; (the marks go with the long range)
        JMP HRMODE
g_hm7:  RTS
g_hm8:  LDA HSHPEND     ; the wipe done: the view's colour RAM 0, the shield's lines
        BEQ g_hm5
        LDA #$00
        STA HSHPEND
        STA HCOLV
        LDA #$01
        STA HCOLJ
        STA HSHL
g_hm5:  LDA HCOLJ       ; the view's colour RAM (the deflector's green, or 0)
        BEQ g_hm4
        LDA #$00
        STA HCOLJ
        JMP HCOLFILL
g_hm4:  LDA CRUN        ; the radar's circle being drawn (about 100 lines): no
        ORA CPEND       ; time for the stars
        BEQ g_hm6
        RTS
g_hm6:  LDA HICR
        BEQ g_hm0
        DEC HICR
        JSR HICONS
        JMP g_hm1
g_hm0:  LDA HPATH
        BEQ g_hm1
        JSR HPSTEP
g_hm1:  LDA HMW
        BEQ g_hm2
        JSR HMSTEP
g_hm2:  LDA LYACT       ; the destination's groups laid out: a group a frame,
        BEQ g_hm3       ; instead of the stars
        JMP LYSTEP
g_hm3:  LDA HYPON
        CMP #$04
        BNE g_hm3b
        RTS
g_hm3b: LDA HSHL        ; the shield's lines, a few pixels a frame in the acceleration;
        BEQ g_hm3c      ; after it the rest instead of the stars
        LDA HYPON
        CMP #$01
        BEQ g_hm3d
        JMP HSHSTEP
g_hm3d: JSR HSHSTEP
g_hm3c: JMP HSTARS
HSTARS: CLC
        LDA HSACC
        ADC HSPD
        STA HSACC
        LSR A
        LSR A
        STA HSN
        LDA HSACC
        AND #$03
        STA HSACC
        LDA HSN
        BNE g_hsn1
        RTS
g_hsn1:
        LDA #HNS        ; (from where the last frame stopped)
        STA HSCNT
        LDX HSROT
g_hss1: JSR HSTLATE
        BCS g_hssx
        JSR HSTAR
        DEX
        BPL g_hss2
        LDX #HNS-1
g_hss2: DEC HSCNT
        BNE g_hss1
g_hssx: STX HSROT
        RTS
; C set: no more time for the stars: past line 296 (the radar and the rest of the
; vertical blank need up to 50 lines from the wrap); the rest go on in the next
; frame.
HSTLATE:BIT $D011       ; (always: the radar and the rest of the vertical blank
        BMI g_hl1       ; need up to 50 lines from the wrap)
        LDA $D012
        CMP #243
        BCS g_hl8
        SEC             ; wrapped: no time
        RTS
g_hl1:  LDA $D012
        CMP #40
        RTS
g_hl8:  CLC
        RTS

; A = frames per energy unit
HENERGY:INC HENC
        CMP HENC
        BEQ g_he1
        BCS g_he9
g_he1:  LDA #$00
        STA HENC
        LDY HUDE+3      ; the ones digit, borrowing into ENERGY10 ($F8A1)
        DEY
        CPY #$6F
        BEQ g_he2
        STY HUDE+3
g_he9:  RTS
g_he2:  LDA HUDE        ; (0000 stays)
        ORA HUDE+1
        ORA HUDE+2
        CMP #$70
        BEQ g_he9
        LDY #$79
        STY HUDE+3
        JMP ENERGY10

; A new star X ($F1D1): anywhere in a 128 x 128 square around the vanishing point; in
; the jump it draws its line on the way out (no erase) and erases it on a second run.
HNEW:   JSR RANDOM
        AND #$7F
        CLC
        ADC #16
        STA HSX,X
        STA HSX0,X
g_hn1:  JSR RANDOM
        AND #$7F
        CLC
        ADC #36
        CMP #142
        BCS g_hn1
        STA HSY,X
        STA HSY0,X
        LDA #$00
        STA HSE,X
        STA HSD,X
        LDA HSX,X       ; direction away from (79, 99)
        SEC
        SBC #79
        BCS g_hn2
        EOR #$FF
        ADC #$01
        INC HSD,X       ; bit 0: x goes left
g_hn2:  STA HSAX,X
        LDA HSY,X
        SEC
        SBC #99
        BCS g_hn3
        EOR #$FF
        ADC #$01
        PHA
        LDA HSD,X
        ORA #$02        ; bit 1: y goes up
        STA HSD,X
        PLA
g_hn3:  STA HSAY,X
        ORA HSAX,X
        BNE g_hn4
        INC HSAX,X      ; (the centre itself: to the right)
g_hn4:  LDA #$00
        LDY HYPON
        CPY #$02
        BNE g_hn5
        LDA #$01
g_hn5:  STA HSTR,X
        RTS

; Star X for a frame (HSN pixels; $F16D-$F2CD). HSTR: 0 a dot (erased and plotted
; once), 1 drawing its line (every pixel plotted), 2 erasing it again from its start
; (every pixel erased; $F233: the original's second run).
HSTAR:  LDA HSN
        STA HSK
        LDA HSTR,X
        BEQ g_sa0
        CMP #$01
        BEQ g_sa1
g_sa2:  JSR HERASE      ; 2: erasing the line
        JSR HBRES
        BCS g_sanew
        DEC HSK
        BNE g_sa2
        RTS
g_sa1:  JSR HBRES       ; 1: drawing the line
        BCS g_saend
        JSR HPLOT
        DEC HSK
        BNE g_sa1
        RTS
g_saend:LDA #$02        ; at the edge: back to its start, erasing
        STA HSTR,X
        LDA #$00
        STA HSE,X
        LDA HSX0,X
        STA HSX,X
        LDA HSY0,X
        STA HSY,X
        RTS
g_sa0:  JSR HERASE      ; 0: a dot
g_sa3:  JSR HBRES
        BCS g_sanew
        DEC HSK
        BNE g_sa3
        JMP HPLOT
g_sanew:JSR HNEW
        JMP HPLOT
; One Bresenham step of star X; C set: out of the view.
HBRES:  LDA HSAX,X      ; the longer axis every time, the other by slope
        CMP HSAY,X
        BCC g_hb5
        JSR HSTX
        CLC
        LDA HSE,X
        ADC HSAY,X
        BCS g_hb2
        CMP HSAX,X
        BCC g_hb3
g_hb2:  SBC HSAX,X
        STA HSE,X
        JSR HSTY
        JMP g_hb6
g_hb3:  STA HSE,X
        JMP g_hb6
g_hb5:  JSR HSTY
        CLC
        LDA HSE,X
        ADC HSAX,X
        BCS g_hb7
        CMP HSAY,X
        BCC g_hb8
g_hb7:  SBC HSAY,X
        STA HSE,X
        JSR HSTX
        JMP g_hb6
g_hb8:  STA HSE,X
g_hb6:  LDA HSX,X       ; in the view: x 2-157, y 26-141
        CMP #2
        BCC g_hbo
        CMP #158
        BCS g_hbo
        LDA HSY,X
        CMP #26
        BCC g_hbo
        CMP #142
        RTS
g_hbo:  SEC
        RTS
HSTX:   LDA HSD,X
        LSR A
        BCS g_hx1
        INC HSX,X
        RTS
g_hx1:  DEC HSX,X
        RTS
HSTY:   LDA HSD,X
        AND #$02
        BNE g_hy5
        INC HSY,X
        RTS
g_hy5:  DEC HSY,X
        RTS
HPLOT:  STX SAVEX
        LDA HSX,X
        STA POSX
        LDA HSY,X
        STA POSY
        JSR PIXADDR
g_hp1:  LDA (PTR),Y     ; value 1, on an empty pixel only (the map, the shield)
        AND MASK3,X
        BNE g_hp3
        LDA (PTR),Y
        ORA MASK1,X
g_hp2:  STA (PTR),Y
g_hp3:  LDX SAVEX
        RTS
HERASE: STX SAVEX
        LDA HSX,X
        STA POSX
        LDA HSY,X
        STA POSY
        JSR PIXADDR
        LDA (PTR),Y     ; only a star's own value 1
        AND MASK3,X
        CMP MASK1,X
        BNE g_hq2
        LDA (PTR),Y
        AND CLEARM,X
        STA (PTR),Y
g_hq2:  LDX SAVEX
        RTS

; The countdown over the radar ($B635): the steps left - 1, two digits twice as wide
; at text row 17, columns 18-21, and a 1 at 16-17 from 100 on ($0813, $0816).
HDIGITS:LDA HCNT
        SEC
        SBC #$01
        LDX #$FF        ; hundreds
        SEC
g_hd1:  INX
        SBC #100
        BCS g_hd1
        ADC #100
        STX HD100
        LDX #$FF
        SEC
g_hd2:  INX
        SBC #10
        BCS g_hd2
        ADC #10
        STA HD1
        STX HD10
        LDA #$00
        STA HDCLR
        LDA #$03        ; drawn a digit a frame (HDGSTEP: with the meteors' sprites
        STA HDGP        ; all three at once ran past line 194)
        RTS
HCLRDIG:LDA #$01
        STA HDCLR
        LDA #$03
        STA HDGP
        RTS
HDGSTEP:LDA HDGP
        BEQ g_dg9
        LDA $D012
        CMP #170
        BCS g_dg9
        DEC HDGP
        LDX HDGP
        LDA #$20
        LDY HDCLR
        BNE g_dg3
        CPX #$02
        BNE g_dg1
        LDA HD100       ; 0 or 1: '1' or a blank
        BEQ g_dg0
        LDA #$71
        BNE g_dg3
g_dg0:  LDA #$20
        BNE g_dg3
g_dg1:  CPX #$01
        BNE g_dg2
        LDA HD10
        ORA #$70
        BNE g_dg3
g_dg2:  LDA HD1
        ORA #$70
g_dg3:  STA HDGCH
        LDA HDGCOL,X
        TAX
        LDA HDGCH
        JMP HBIG
g_dg9:  RTS
HDGCOL: .BYTE 20,18,16
HDGP:   .BYTE 0
HDCLR:  .BYTE 0
HDGCH:  .BYTE 0
; Character A of the font ($4000) into text row 17, columns X and X+1, each bit two
; pixels wide (value 3, light blue in colour RAM).
HBIG:   STX HBX
        LDY #$00        ; the glyph: $4000 + A x 8
        STY CSRC+1
        ASL A
        ROL CSRC+1
        ASL A
        ROL CSRC+1
        ASL A
        ROL CSRC+1
        STA CSRC
        LDA CSRC+1
        CLC
        ADC #$40
        STA CSRC+1
        LDA HBX         ; the bitmap: $7540 + X x 8
        ASL A
        ASL A
        ASL A
        CLC
        ADC #$40
        STA CDST
        LDA #$75
        ADC #$00
        STA CDST+1
        LDY #$07
g_hb1:  LDA (CSRC),Y
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA HEXP,X
        STA (CDST),Y
        LDA (CSRC),Y
        AND #$0F
        TAX
        LDA HEXP,X
        STY HT
        PHA
        TYA
        CLC
        ADC #$08
        TAY
        PLA
        STA (CDST),Y
        LDY HT
        DEY
        BPL g_hb1
        LDX HBX
        LDA #$0E
        STA $DAA8,X     ; (colour RAM, row 17)
        STA $DAA9,X
        RTS
HEXP:   .BYTE $00,$03,$0C,$0F,$30,$33,$3C,$3F,$C0,$C3,$CC,$CF,$F0,$F3,$FC,$FF

HCRY:   LDX HCHIDE      ; the crosshair hidden in hyperspace, as in the original;
        BEQ g_cr1       ; with a mouse it is the hyperspace cursor there (HYPVIEW)
        LDA #$00
g_cr1:  STA $D001
        RTS

HNS     = 10            ; stars ($F0B4: 10)
HYPON:  .BYTE 0         ; 1 accelerating, 2 the jump, 3 decelerating
HPEND:  .BYTE 0         ; a jump chosen on the map, to start
MAPSPR: .BYTE 0         ; MAPSHOWN or HMAP: sprite 1 is the planet
HVBJ:   .BYTE 0         ; the scanner's job for the vertical blank: 1 RADMODE, 2 APINIT
HSCAN:  .BYTE 0         ; the scanner in the jump: 1 laying out, 2 empty, 3 on
HNORAD: .BYTE 0         ; the radar's pass left out (VBWORK)
HPACC:  .BYTE 0
HRDC:   .BYTE 0
HJT:    .BYTE 0
HSLOT:  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
HICR:   .BYTE 0         ; icon rows left to erase
HOFL:   .BYTE 0
HOFH:   .BYTE 0
HT8:    .BYTE 0
HMAP:   .BYTE 0         ; the map's pixels still on the screen (the stars keep them)
HPATH:  .BYTE 0         ; the path being plotted
HPX:    .BYTE 0
HPY:    .BYTE 0
HPDX:   .BYTE 0
HPDY:   .BYTE 0
HPSX:   .BYTE 0
HPSY:   .BYTE 0
HPERR:  .BYTE 0
HPN:    .BYTE 0
HMW:    .BYTE 0         ; the map's erase: 1 horizontal lines, 2 pause, 3 vertical
HMFX:   .BYTE 0
HMFR:   .BYTE 0
HMCI:   .BYTE 0
HMFT:   .BYTE 0
HMFB:   .BYTE 0
HMPC:   .BYTE 0
HEFL:   .BYTE 0         ; the engine: voice 3's pitch, step, direction, pulse width
HEFH:   .BYTE 0
HESTP:  .BYTE 0
HEDIR:  .BYTE 0
HPWL:   .BYTE 0
HPWS:   .BYTE 0
HFROMX: .BYTE 4
HFROMY: .BYTE 2
HTGTX:  .BYTE 0
HTGTY:  .BYTE 0
HSTEPS: .BYTE 0
HCNT:   .BYTE 0
HTIME:  .BYTE 0
HSPD:   .BYTE 0
HSACC:  .BYTE 0
HSN:    .BYTE 0
HSK:    .BYTE 0
HSCNT:  .BYTE 0
HSROT:  .BYTE HNS-1
HACC:   .BYTE 0
HENC:   .BYTE 0
HBX:    .BYTE 0
HD100:  .BYTE 0
HD10:   .BYTE 0
HD1:    .BYTE 0
HSX:    .BYTE 0,0,0,0,0,0,0,0,0,0
HSY:    .BYTE 0,0,0,0,0,0,0,0,0,0
HSX0:   .BYTE 0,0,0,0,0,0,0,0,0,0
HSY0:   .BYTE 0,0,0,0,0,0,0,0,0,0
HSAX:   .BYTE 0,0,0,0,0,0,0,0,0,0
HSAY:   .BYTE 0,0,0,0,0,0,0,0,0,0
HSE:    .BYTE 0,0,0,0,0,0,0,0,0,0
HSD:    .BYTE 0,0,0,0,0,0,0,0,0,0
HSTR:   .BYTE 0,0,0,0,0,0,0,0,0,0

; A test of a mouse cursor for hyperspace (H switches it on and off in flight).
; As the 1351 patch does off the cockpit, the mouse's motion is the joystick for
; this frame only (MSYN); the crosshair moves with the mouse and, as soon as the
; mouse rests, springs back toward the centre, as if hyperspace pulled the
; controls back. It changes colour, and its three digits spin. With a joystick
; nothing changes.
HINPUT: LDA #$F7        ; H: column 3, row 5 (a new press)
        STA CIA1PA
        LDA CIA1PB
        AND #$20
        BNE g_hk1
        LDA HKPREV
        BNE g_hk2
        INC HKPREV
        LDA HTEST
        EOR #$01
        STA HTEST
        JMP g_hk2
g_hk1:  LDA #$00
        STA HKPREV
g_hk2:  LDA #$BF        ; port 2 again: its pots are read next
        STA CIA1PA
        JSR INPUT
        LDA HYPON       ; hyperspace: no phasor (fire is the deflector there, later)
        BEQ g_hk3
        LDA #$00
        STA FIREFLAG
g_hk3:
        JSR HCURON
        BNE g_hi0a
        JMP g_hi9
g_hi0a: LDA JRAW        ; the motion as directions, this frame only
        ORA #$01        ; (the right button is wired to UP)
        LDX MDY
        BEQ g_hi1
        BMI g_hi0
        AND #$FD
        BNE g_hi1
g_hi0:  AND #$FE
g_hi1:  LDX MDX
        BEQ g_hi3
        BMI g_hi2
        AND #$F7
        BNE g_hi3
g_hi2:  AND #$FB
g_hi3:  STA JOY
        STA JOYG
        LDA MDX         ; resting: back toward the centre, a quarter a frame
        ORA MDY
        BNE g_hi6
        LDA CURX
        LDX CEN
        JSR HSPRING
        STA CURX
        LDA CURY
        LDX YCEN
        JSR HSPRING
        STA CURY
        LDA CURX
        CLC
        ADC #$2D
        STA XPOS
        LDA #$00
        ROL A
        STA XMSB
g_hi6:  RTS

; The test cursor's looks, in the 3D view's free time (VIEWWORK): at 1 MHz in the
; input's slot they pushed the vertical blank past its end.
HVIEW:  JSR HCURON
        BNE g_hv1
        LDA NUMCOL
        STA HCOLOR
        RTS
g_hv1:  INC HFRM        ; the colour, a step every 4th frame
        LDA HFRM
        LSR A
        LSR A
        AND #$07
        TAX
        LDA HCOLS,X
        STA HCOLOR
        LDA HYPON       ; decelerating: the digits count down 999 -> 000
        CMP #$03
        BNE g_hi6a
        JMP HDOWN
g_hi6a: LDA #$02        ; the digits spin
        STA HDIG
g_hi7:  JSR RANDOM
        AND #$0F
        CMP #10
        BCC g_hi8
        SBC #6
g_hi8:  TAY
        LDX HDIG
        JSR DIGIT
        DEC HDIG
        BPL g_hi7
        RTS
g_hi9:
        RTS
; The cursor's digits while decelerating: HTIME (120 .. 1) x 8.33, so 999 at the
; start, 000 at the arrival.
HDOWN:  LDA HTIME
        STA HDL
        LDA #$00
        STA HDH
        ASL HDL         ; x 8
        ROL HDH
        ASL HDL
        ROL HDH
        ASL HDL
        ROL HDH
        LDA HTIME       ; + / 3
        LDX #$FF
        SEC
g_dn1:  INX
        SBC #$03
        BCS g_dn1
        TXA
        CLC
        ADC HDL
        STA HDL
        BCC g_dn2
        INC HDH
g_dn2:  LDX #$FF        ; hundreds
g_dn3:  INX
        SEC
        LDA HDL
        SBC #100
        TAY
        LDA HDH
        SBC #$00
        BCC g_dn4
        STA HDH
        STY HDL
        BCS g_dn3
g_dn4:  CPX #10         ; (at most 999)
        BCC g_dn5
        LDX #9
        LDA #99
        STA HDL
g_dn5:  TXA
        TAY
        LDX #$00
        JSR DIGIT
        LDA HDL
HZDIG:  JSR BCD         ; A (0-99): tens, ones
        LDY BCDT
        LDX #$01
        JSR DIGIT
        LDY BCDO
        LDX #$02
        JMP DIGIT
; 000 under the cursor (the arrival)
HZERO:  LDY #$00
        LDX #$00
        JSR DIGIT
        LDA #$00
        JMP HZDIG

; A = position, X = centre: A moved a quarter of the way (at least 1) to the centre.
HSPRING:STA HPOS
        STX HCEN
        SEC
        SBC HCEN
        BEQ g_hs9
        BCC g_hs1
        LSR A           ; above: position - (d / 4 + 1)
        LSR A
        CLC
        ADC #$01
        STA HT
        LDA HPOS
        SEC
        SBC HT
        RTS
g_hs1:  EOR #$FF        ; below: position + ((centre - position) / 4 + 1)
        ADC #$01
        LSR A
        LSR A
        CLC
        ADC #$01
        CLC
        ADC HPOS
        RTS
g_hs9:  LDA HPOS
        RTS
HCOLS:  .BYTE $0E,$0E,$03,$01,$03,$0E,$06,$06
HTEST:  .BYTE 0
HKPREV: .BYTE 0
HFRM:   .BYTE 0
HDIG:   .BYTE 0
HCEN:   .BYTE 0
HPOS:   .BYTE 0
HT:     .BYTE 0
HCOLOR: .BYTE 1
HCHIDE: .BYTE 0
HDL:    .BYTE 0
HDH:    .BYTE 0

; ---------------- more code: the RAM under the KERNAL at $E000 ----------------
; Loaded packed at $5E00 (restored sprite slots and the view, wiped before shown)
; and moved here by GAMEINIT; the second stream and the positioning tail are
; staged beneath I/O and read under MMU $3F during init only.
        * = $E000
TSH1    = $2900         ; type-1 masters (15 shapes), restored to live slots at init
TSH2    = $3800         ; type-2 masters (7), reclaimed duplicate map address tables
TSH3    = $39C0         ; type-3 masters (8), ending at $3BC0
STR2X   = $3E00         ; type-2 X streams (512), reclaimed disabled-VDC system names
STR2Y   = $5E00         ; type-2 Y streams (512): the second packed stream (GUNPK2)
TORPA   = $F600         ; packed proton frames ($A000-$AFFF in the original)
TSHOT   = $FE80         ; original shot shapes $67/$68, borrowed by the proton

; ---------------- the proton torpedo ($BAD4-$BC86) ----------------
; SPACE (or both mouse buttons) asks for it ($FDE5 -> $BACE). With none left a click
; ($BC6F); else one less on the HUD ($849E), the launch's noise ($BBB2), and for 32
; steps (one every 16 passes: 0.79 a frame) the pre-drawn rotating torpedo flies up
; the view on sprites 1 and 2, twice as wide, white ($BB1B): each step unpacks the
; next 128 bytes of its animation ($A000-$AFFF, TORPA) into their shapes. Meanwhile
; no phasor. At the end ($BB70) the blast ($BBE4): every fighter in view goes down
; ($BC88), the view turns orange ($BA99 $08) and rings grow from its middle (x $50,
; y $64, radius +6 up to $28), plotted, then erased.
; SPACE held (the cockpit's key scan) or both mouse buttons (MAPKEY): a new press asks
; for a torpedo; GTORP runs from then on (torpj).
GSPACE: LDA TSPP
        BNE g_gs3
        INC TREQ
g_gs3:  LDA #$02        ; (held: counted down by GTORP)
        STA TSPP
        BNE g_gb2
GBOTH:  LDA #$80        ; (MAPKEY's own: both buttons)
        STA RCNT
        LDA TMBP
        BNE g_gb1
        INC TREQ
g_gb1:  LDA #$02
        STA TMBP
g_gb2:  LDA #$20        ; GTORP every frame
        STA torpj
        RTS

GTORP:  LDA TSPP        ; the keys' holds run out two frames after release
        BEQ g_tp1
        DEC TSPP
g_tp1:  LDA TMBP
        BEQ g_tp2
        DEC TMBP
g_tp2:  LDA TPF         ; nothing left to do: off again
        ORA TREQ
        ORA TSPP
        ORA TMBP
        BNE g_tp4
        LDA #$2C
        STA torpj
        RTS
g_tp4:  LDA MAPSHOWN    ; (not over the map, nor in hyperspace)
        ORA WIPE
        ORA HYPON
        ORA HPEND
        BEQ g_tp5
        LDA #$00
        STA TREQ
        RTS
g_tp5:  LDA TPF         ; (each part works while there is time, and goes on in the
        BEQ g_tp6       ; next frame: a fight leaves the vertical blank little)
        CMP #$01
        BEQ g_tp7
        CMP #$02
        BEQ g_tpk
        CMP #$04
        BEQ g_tpb
        CMP #$06
        BCC g_tpcol
        JMP MSFLASH
g_tpcol:JMP TCOL        ; 3, 5: the view's colours
g_tp7:  JMP TFLY
g_tpk:  JMP TKILL
g_tpb:  JMP TBLAST
g_tp6:  LDA TREQ
        BNE g_tp8
        RTS
g_tp8:  LDA #$00
        STA TREQ
        LDA $485B       ; protons left (the HUD's digits, $545A / $545B)
        CMP #$70
        BNE g_tp9
        LDA $485A
        CMP #$70
        BNE g_tp9
        LDA MRPHUND
        BNE g_tp9
        LDA #$00        ; none: a click ($BC6F)
        STA $D404
        STA $D406
        LDA #$14
        STA $D401
        LDA #$3A
        STA $D405
        LDA #$21
        STA $D404
        RTS
g_tp9:  DEC $485B       ; one less ($8450, $849E)
        LDA $485B
        CMP #$6F
        BNE g_tpa
        LDA #$79
        STA $485B
        DEC $485A
        LDA $485A
        CMP #$6F
        BNE g_tpa
        LDA #$79
        STA $485A
        DEC MRPHUND
g_tpa:  LDA #$0A        ; the launch ($BBB2): noise on voices 1 and 2
        STA $D401
        LDA #$80
        STA $D404
        STA $D40B
        LDA #$04
        STA $D408
        LDA #$0F
        STA $D418
        LDA #$89
        STA $D405
        LDA #$6B
        STA $D40C
        LDA #$00
        STA $D406
        STA $D40D
        LDA #$81
        STA $D404
        STA $D40B
        LDA #$01        ; the flight
        STA TPF
        LDA #32
        STA TPN
        LDA #<TORPA
        STA TPSRC
        LDA #>TORPA
        STA TPSRC+1
        LDA #$C8
        STA TPY1
        LDA #$DD
        STA TPY2
        LDA #$00
        STA TPACC
        STA TPSP
        STA TPO
        STA SHOTVIS     ; (the phasor shot goes, $1428)
        STA SHOTON
        STA SHOTARM
        STA FIREFLAG
        LDA #<HTSPR     ; the torpedo's sprites after the crosshair's
        STA sprcj+1
        LDA #>HTSPR
        STA sprcj+2
        INC TPSP        ; (its first frame now)
        RTS

TFLY:   LDA #$00        ; no phasor while it flies
        STA FIREFLAG
        STA SHOTARM
        CLC             ; a step every 16 passes: 0.79 a frame
        LDA TPACC
        ADC #$CA
        STA TPACC
        BCC g_tf1
        INC TPSP
g_tf1:  LDA TPO         ; a frame being unpacked, or one due
        BNE g_tf2
        LDA TPSP
        BEQ g_tf9
g_tf2:  JSR TDEC
        BCC g_tf9       ; (not all of it yet)
        LDA #$00        ; the frame complete: it shows, a step up
        STA TPO
        DEC TPSP
        BPL g_tf3
        STA TPSP
g_tf3:  DEC TPY1
        DEC TPY1
        DEC TPY2
        DEC TPY2
        DEC TPN
        BNE g_tf9
        JMP TEND
g_tf9:  RTS

; The next of its animation's frames into $F3 / $F4 ($7CC0-$7D3F; tokens: $80 + n
; zeros, or n literals), a token at a time while there is time; C set when done.
TDEC:   LDA TPSRC
        STA CSRC
        LDA TPSRC+1
        STA CSRC+1
g_td1:  LDX TPO
        CPX #128
        BCS g_td8
        LDA FAST        ; after the PAL frame wraps, bit 8 alone is not enough
        AND #$01
        BEQ g_tdview
        BIT $D011
        BMI g_td2       ; PAL lines 256-311, before the frame wraps
        LDA $D012
        CMP #243
        BCS g_td2
        CMP #16         ; wrapped blank: reserve the shape restore and world hook
        BCS g_td9
        BCC g_td2
g_tdview:LDA $D012
        CMP #142        ; longest token is 61 zero / 48 literal bytes
        BCS g_td9
g_td2:
        LDY #$00
        LDA (CSRC),Y
        STA TPB
        INY
        LDA TPB
        BMI g_td4
g_td3:  LDA (CSRC),Y    ; literals
        STA $7CC0,X
        INY
        INX
        DEC TPB
        BNE g_td3
        BEQ g_td6
g_td4:  AND #$7F        ; zeros
        STA TPB
        LDA #$00
g_td5:  STA $7CC0,X
        INX
        DEC TPB
        BNE g_td5
g_td6:  STX TPO
        TYA             ; the source on
        CLC
        ADC CSRC
        STA CSRC
        BCC g_td1
        INC CSRC+1
        BCS g_td1
g_td8:  JSR g_td9
        SEC
        RTS
g_td9:  LDA CSRC
        STA TPSRC
        LDA CSRC+1
        STA TPSRC+1
        CLC
        RTS

; The end of the flight ($BB70): its sprites go, the shot's shapes back, silence,
; the blast's noise ($C3D0); then the kills, the colour, the rings.
TEND:   LDA #<SPRCROSS
        STA sprcj+1
        LDA #>SPRCROSS
        STA sprcj+2
        LDX #127
g_te1:  LDA TSHOT,X
        STA $7CC0,X
        DEX
        BPL g_te1
        LDA #$00
        STA $D404
        STA $D40B
        LDA #$0F        ; ($C3D0) the blast's noise on voice 2
        STA $D418
        LDA #$00
        STA $D407
        STA $D40B
        STA $D40D
        LDA #$04
        STA $D408
        LDA #$7B
        STA $D40C
        LDA #$81
        STA $D40B
        LDA #$02
        STA TPF
        LDA #$03        ; the fighters to look at
        STA TPKX
        JMP MSBLAST

; ($BC88) every fighter in view goes down: one at a time, while there is time.
TKILL:  LDA #28
        JSR TLATE
        BCS g_tk9
        DEC TPKX
        BMI g_tk8
        LDX TPKX
        LDA ALIVE,X
        BEQ TKILL
        LDA EVIS
        AND ENBIT,X
        BEQ TKILL
        TXA
        ASL A
        TAY
        LDA EXPL        ; (one explosion at a time: the first one's)
        BNE g_tk2
        JSR hk1
        JMP TKILL
g_tk2:  LDA #$00
        STA ALIVE,X
        LDA #$01        ; far away in every direction
        STA ENX+1,Y
        STA ENY+1,Y
        STA ENZ+1,Y
        JSR KILL
        LDX TPKX
        LDA EVIS
        AND ENMASK,X
        STA EVIS
        JMP TKILL
g_tk8:  LDA #$03        ; the view orange ($BA99 $08)
        STA TPF
        LDA #$08
        STA HCOLV
        JMP TCOL0
g_tk9:  RTS

; The view's colour RAM, rows 4-16, to HCOLV, a row at a time while there is time; then
; the rings (TPF 3) or the end (TPF 5).
TCOL0:  LDA #$00
        STA TPCR
        LDA #$A0
        STA TPCP
        LDA #$D8
        STA TPCP+1
        RTS
TCOL:   LDA #34
        JSR TLATE
        BCS g_tc9
        LDA TPCR
        CMP #13
        BCS g_tc5
        LDA TPCP
        STA CDST
        LDA TPCP+1
        STA CDST+1
        LDA HCOLV
        LDY #39
g_tc1:  STA (CDST),Y
        DEY
        BPL g_tc1
        CLC
        LDA TPCP
        ADC #40
        STA TPCP
        BCC g_tc2
        INC TPCP+1
g_tc2:  INC TPCR
        JMP TCOL
g_tc5:  LDA TPF         ; done
        CMP #$03
        BNE g_tc6
        LDA #$04        ; the rings
        STA TPF
        LDA #4
        STA TPR
        LDA #$01
        STA TPPASS
        JMP TRING0
g_tc6:  LDA #$00        ; over
        STA TPF
g_tc9:  RTS

; The blast's rings ($3635 / $364C): radius TPR, centre x $50, y $64; 6 steps of the
; circle a frame, all eight octants (value 3, brown kept; the second pass erases).
TBLAST: LDA #$0C
        STA TPK
g_tb1:  LDA #40         ; (the time: a step at a time)
        JSR TLATE
        BCC g_tb0
        RTS
g_tb0:  LDA TRY         ; y > x: the ring is done
        CMP TRX
        BEQ g_tb2
        BCS TRNEXT
g_tb2:  LDA TRY         ; (every other step plotted: half the time, the ring still
        LSR A           ; whole to the eye)
        BCS g_tb2a
        JSR TPLOT8
g_tb2a: INC TRY         ; the midpoint step
        LDA TRD
        BMI g_tb3
        DEC TRX
        LDA TRY         ; d += 2 (y - x) + 1
        SEC
        SBC TRX
        ASL A
        SEC
        ADC TRD
        STA TRD
        JMP g_tb4
g_tb3:  LDA TRY         ; d += 2 y + 1
        ASL A
        SEC
        ADC TRD
        STA TRD
g_tb4:  DEC TPK
        BNE g_tb1
        RTS
; C set: past line 256 + A, or wrapped: no time left in this vertical blank.
TLATE:  STA TPLIM
        BIT $D011
        BMI g_tl1
        LDA $D012
        CMP #243
        BCS g_tl8
        SEC
        RTS
g_tl1:  LDA $D012
        CMP TPLIM
        RTS
g_tl8:  CLC
        RTS
TRNEXT: CLC             ; the next ring: 6 more
        LDA TPR
        ADC #$06
        STA TPR
        CMP #$29
        BCC TRING0
        LDA TPPASS      ; the second pass erases them
        CMP #$01
        BNE g_tn1
        INC TPPASS
        LDA #4
        STA TPR
        JMP TRING0
g_tn1:  LDA #$05        ; over: the view's colours back (TCOL)
        STA TPF
        LDA #$01
        STA HCOLV
        JMP TCOL0
TRING0: LDA TPR         ; x = r, y = 0, d = 1 - r
        STA TRX
        LDA #$00
        STA TRY
        SEC
        LDA #$01
        SBC TPR
        STA TRD
        RTS
TPLOT8: LDA TRX         ; (x, y) and (y, x) in the four quadrants
        LDY TRY
        JSR TPLOT4
        LDA TRY
        LDY TRX
TPLOT4: STA TPDX
        STY TPDY
        CLC
tpcx1:  LDA #$50
        ADC TPDX
        STA POSX
        CLC
tpcy1:  LDA #$64
        ADC TPDY
        STA POSY
        JSR TPLOT1
        SEC
tpcx2:  LDA #$50
        SBC TPDX
        STA POSX
        JSR TPLOT1
        SEC
tpcy2:  LDA #$64
        SBC TPDY
        STA POSY
        JSR TPLOT1
        CLC
tpcx3:  LDA #$50
        ADC TPDX
        STA POSX
TPLOT1: JSR PIXADDR
        LDA (PTR),Y
        AND MASK3,X
        CMP M_MASK2,X
        BEQ g_pl9
        LDA (PTR),Y
        AND CLEARM,X
        LDY TPPASS
        CPY #$02
        BEQ g_pl8
        ORA MASK3,X
g_pl8:  LDY #$00
        STA (PTR),Y
g_pl9:  RTS

; The torpedo on sprites 1 and 2 (after SPRCROSS, while it flies; sprcj): x $A0,
; white, twice as wide, single colour, in front.
HTSPR:  JSR SPRCROSS
        LDA #SHOTPTR
        STA SPRPTR+1
        LDA #SHOTPTR+1
        STA SPRPTR+2
        LDA #$A0
        STA $D002
        STA $D004
        LDA TPY1
        STA $D003
        LDA TPY2
        STA $D005
        LDA #$01
        STA $D028
        STA $D029
        LDA $D010
        AND #$F9
        STA $D010
        LDA $D01C
        AND #$F9
        STA $D01C
        LDA $D017
        AND #$F9
        STA $D017
        LDA $D01B
        AND #$F9
        STA $D01B
        LDA $D01D
        ORA #$06
        STA $D01D
        LDA VICENA
        ORA #$06
        STA VICENA
        RTS

TSPACE: .BYTE $10       ; SPACE's bit (0 while held), from the cockpit's key scan
TSPP:   .BYTE 0
TMBP:   .BYTE 0
TREQ:   .BYTE 0
TPF:    .BYTE 0         ; 1 flying, 2 the kills, 3 the colour, 4 the rings, 5 the colour back
TPN:    .BYTE 0
TPSRC:  .BYTE 0,0
TPY1:   .BYTE 0
TPY2:   .BYTE 0
TPACC:  .BYTE 0
TPK:    .BYTE 0
TPB:    .BYTE 0
TPO:    .BYTE 0
TPR:    .BYTE 0
TPPASS: .BYTE 0
TRX:    .BYTE 0
TRY:    .BYTE 0
TRD:    .BYTE 0
TPDX:   .BYTE 0
TPDY:   .BYTE 0
TPLIM:  .BYTE 0
TPKX:   .BYTE 0
TPCR:   .BYTE 0
TPCP:   .BYTE 0,0
TPSP:   .BYTE 0

; ---------------- squadron types 2 and 3 ($FFAF, $2E86 / $2EBE / $2F18) ----------------
; The squadron's type (SQTYPE, from the map's STATE: 1 the twin-pod fighters, 2 the
; spiky ships, 3 the lens ships) picks the fighters' shapes, streams and looks. The
; three types share the fighters' sprite slots ($80-$8E): GSHLOAD copies the type's
; shapes there a shape a frame from their masters at $E600 (16, 7 or 8 shapes),
; meanwhile the approach goes on. Types 2 and 3: multicolour (6 / 2), twice as wide;
; their colours step every frame, white on their last hit ($2EC4).
GSQTYPE:LDA M_STATE,X   ; X = the sector: 1-3 a squadron's type
        BEQ g_sq9
        BMI g_sq9
        STA SQTYPE
        CMP SHLT        ; its shapes to load: VIEWWORK calls GSHLOAD
        BEQ g_sq9
        LDA #$20
        STA shpj
g_sq9:  RTS

GSHLOAD:LDA SHLT        ; the slots hold SQTYPE's shapes?
        CMP SQTYPE
        BEQ g_sl9
        LDA $D012       ; (time: in the 3D view's, before line 150)
        CMP #150
        BCS g_sl9
        LDX SQTYPE
        LDA SHLK        ; shape SHLK: from the master to $6000 + SHLK x 64
        LSR A
        LSR A
        STA CDST+1
        LDA SHLK
        ROR A
        ROR A
        ROR A
        AND #$C0
        STA CDST
        CLC
        ADC SHMLO-1,X
        STA CSRC
        LDA CDST+1
        ADC SHMHI-1,X
        STA CSRC+1
        LDA CDST+1
        CLC
        ADC #$60
        STA CDST+1
        LDY #63
g_sl1:  LDA (CSRC),Y
        STA (CDST),Y
        DEY
        BPL g_sl1
        INC SHLK
        LDA SHLK
        CMP SHMN-1,X
        BCC g_sl9
        LDA #$00        ; all of them
        STA SHLK
        STX SHLT
        LDA #$2C        ; (VIEWWORK: a BIT again)
        STA shpj
g_sl9:  RTS
SHMLO:  .BYTE <TSH1,<TSH2,<TSH3
SHMHI:  .BYTE >TSH1,>TSH2,>TSH3
SHMN:   .BYTE 15,7,8

; The type's set-up when a wave starts (NEWWAVE, after its colours): multicolour and
; width of sprites 4-6 by self-modifying SPRENEMY's AND / ORA (sprmc, sprxe: the same
; time for every type), the multicolours 6 / 2.
GTYPE:  LDA ETYPE
        CMP #$02
        BCS g_ty1
        LDA #$29        ; AND #$8F: single colour, not expanded
        LDX #$8F
        BNE g_ty2
g_ty1:  LDA #$06
        STA $D025
        LDA #$02
        STA $D026
        LDA #$09        ; ORA #$70: multicolour, twice as wide
        LDX #$70
g_ty2:  STA sprmc
        STA sprxe
        STX sprmc+1
        STX sprxe+1
        LDX #$05        ; PLACE's shape: type 1's own code, else JSR GESHP
        LDA ETYPE
        CMP #$02
        BCS g_ty4
g_ty3:  LDA PLSH1,X
        STA plshp,X
        DEX
        BPL g_ty3
        RTS
g_ty4:  LDA PLSH2,X
        STA plshp,X
        DEX
        BPL g_ty4
        RTS
PLSH1:  .BYTE $38,$A9,$2F,$ED,<ZT,>ZT   ; SEC / LDA #$2F / SBC ZT
PLSH2:  .BYTE $20,<GESHP,>GESHP,$EA,$EA,$EA

; Types 2 and 3: each fighter's colour steps every frame, white once it can take only
; one more hit ($2EC4, every placement in the original).
GCOLCYC:
torpj:  BIT GTORP       ; the proton torpedo (JSR while asked for or under way: a BIT
                        ; costs the tight frames only 4 cycles)
        LDA APPR        ; approaching: sprite 4 is the scanner's blip, single colour
        BEQ g_cc0       ; and narrow whatever fought last (NEWWAVE's GTYPE sets the
        LDA #$29        ; next type's looks)
        STA sprmc
        STA sprxe
        LDA #$8F
        STA sprmc+1
        STA sprxe+1
        RTS
g_cc0:  LDA ETYPE
        CMP #$02
        BCC g_cc9
        LDA ALIVE
        ORA ALIVE+1
        ORA ALIVE+2
        BEQ g_cc9
        LDX #$02
g_cc1:  LDY $D02B,X
        DEY
        LDA EHITS,X
        CMP #$02
        BCS g_cc2
        LDY #$01
g_cc2:  TYA
        STA $D02B,X
        DEX
        BPL g_cc1
g_cc9:  RTS

; The x / y streams' first page by type ($FF15 / $FF18): type 2 its own tables
; (the original's $0600 and $8100, copied to STR2X / STR2Y).
GSTRX:  LDY #>STREAMS
        LDA ETYPE
        CMP #$02
        BNE g_gs1
        LDY #>STR2X
g_gs1:  RTS
GSTRY:  LDY #>STREAMS+2
        LDA ETYPE
        CMP #$02
        BNE g_gs2
        LDY #>STR2Y
g_gs2:  RTS

; The shape from the depth (ZT, 0-15): type 1 $2F - ZT ($2E86); types 2 and 3 from
; their tables ($2EAE, $2F08), as the slot holding it: $20 + its place in the type's
; shapes (ENPTR: slot $80 + that).
GESHP:  LDX ZT          ; (types 2 and 3 only)
        LDA ETYPE
        CMP #$03
        BEQ g_es3
        LDA T2K,X
        RTS
g_es3:  LDA T3K,X
        RTS
T2K:    .BYTE $26,$26,$26,$25,$25,$25,$24,$24,$23,$23,$22,$22,$21,$21,$20,$20
T3K:    .BYTE $27,$27,$26,$26,$25,$25,$24,$24,$23,$23,$22,$22,$21,$21,$20,$20
SQTYPE: .BYTE 1
SHLT:   .BYTE 1         ; the type whose shapes the slots hold
SHLK:   .BYTE 0

; (meteors, continued)
; Dodging ($B8D9): each meteor pushed away from the stick's directions by twice
; its growth; out of the view: gone.
HDODGE: LDA HDJ
        AND #$0F
        CMP #$0F
        BNE mt_dd0
        RTS
mt_dd0:  LDX #HMN-1
mt_dd1:  LDA HMACT,X
        BEQ mt_dd9
        LDA HMSHP,X
        SEC
        SBC #$66
        ASL A
        STA HT
        LDA HDJ
        STA HJT
        LSR HJT         ; up: the meteors up
        BCS mt_dd2
        SEC
        LDA HMY,X
        SBC HT
        STA HMY,X
        CMP #$4A
        BCC mt_ddx
mt_dd2:  LSR HJT         ; down
        BCS mt_dd3
        CLC
        LDA HMY,X
        ADC HT
        STA HMY,X
        CMP #$BE
        BCS mt_ddx
mt_dd3:  LSR HJT         ; left: the meteors right
        BCS mt_dd4
        CLC
        LDA HMX,X
        ADC HT
        STA HMX,X
        BCC mt_dd4
        LDA HMXH,X
        BNE mt_ddx
        LDA #$01
        STA HMXH,X
mt_dd4:  LSR HJT         ; right: the meteors left
        BCS mt_dd9
        SEC
        LDA HMX,X
        SBC HT
        STA HMX,X
        BCS mt_dd9
        LDA HMXH,X
        BEQ mt_ddx
        LDA #$00
        STA HMXH,X
        JMP mt_dd9
mt_ddx:  LDA #$FE
        STA HMDLY,X
        LDA #$00
        STA HMACT,X
mt_dd9:  DEX
        BMI mt_ddr
        JMP mt_dd1
mt_ddr: RTS

; The view's colour RAM, rows 4-16 ($2794): HCOLV (0, or the deflector's $0D).
HCOLFILL:
        LDA HCOLV
        LDY #39
mt_cf1a: STA $D8A0,Y
        STA $D8C8,Y
        STA $D8F0,Y
        STA $D918,Y
        STA $D940,Y
        STA $D968,Y
        STA $D990,Y
        STA $D9B8,Y
        STA $D9E0,Y
        STA $DA08,Y
        STA $DA30,Y
        STA $DA58,Y
        STA $DA80,Y
        DEY
        BPL mt_cf1a
        RTS

; The shield's seven lines ($26D0, $3580): colour 3, brown kept ($EF6B), drawn a few
; pixels a frame: HSHL = the line (1-7), then 0.
HSHSTEP:LDA HSHLEFT     ; a line under way?
        BNE mt_sh2
        LDX HSHL        ; the next line's ends
        DEX
        CPX #$07
        BCC mt_sh0
        LDA #$00
        STA HSHL
        RTS
mt_sh0:  LDA HSHX0,X
        STA HSX0P
        LDA HSHY0,X
        STA HSY0P
        LDA HSHX1,X
        SEC
        SBC HSX0P
        STA HSDXP       ; (x always rises)
        LDY #$01
        LDA HSHY1,X
        SEC
        SBC HSY0P
        BCS mt_sh1
        EOR #$FF
        ADC #$01
        LDY #$FF
mt_sh1:  STA HSDYP
        STY HSSYP
        CMP HSDXP       ; pixels: the longer side + 1
        BCS mt_sh1a
        LDA HSDXP
mt_sh1a: STA HSHLEFT
        INC HSHLEFT
        LSR A
        STA HSERRP
mt_sh2:  LDA #32         ; up to 32 pixels a frame while accelerating (the stars are
        LDX HYPON       ; dots), else 64 instead of the stars: complete when the jump
        CPX #$01        ; begins, as the original's at $B5C6 (while there is time)
        BEQ mt_sh2a
        LDA #64
mt_sh2a: STA HSK2
mt_sh3:  BIT $D011       ; (lines 243-285 only: past the wrap, no time)
        BMI mt_sh3b
        LDA $D012
        CMP #243
        BCS mt_sh3a
        RTS
mt_sh3b: LDA $D012
        CMP #30
        BCC mt_sh3a
        RTS
mt_sh3a: LDA HSX0P
        STA POSX
        LDA HSY0P
        STA POSY
        JSR PIXADDR
        LDA (PTR),Y
        AND MASK3,X
        CMP M_MASK2,X
        BEQ mt_sh4
        LDA (PTR),Y
        ORA MASK3,X
        STA (PTR),Y
mt_sh4:  DEC HSHLEFT
        BEQ mt_sh8
        LDA HSDXP       ; a step
        CMP HSDYP
        BCC mt_sh6
        INC HSX0P       ; x the longer side
        CLC
        LDA HSERRP
        ADC HSDYP
        BCS mt_sh5
        CMP HSDXP
        BCC mt_sh5a
mt_sh5:  SBC HSDXP
        STA HSERRP
        CLC
        LDA HSY0P
        ADC HSSYP
        STA HSY0P
        JMP mt_sh7
mt_sh5a: STA HSERRP
        JMP mt_sh7
mt_sh6:  CLC             ; y the longer side
        LDA HSY0P
        ADC HSSYP
        STA HSY0P
        CLC
        LDA HSERRP
        ADC HSDXP
        BCS mt_sh6a
        CMP HSDYP
        BCC mt_sh6b
mt_sh6a: SBC HSDYP
        STA HSERRP
        INC HSX0P
        JMP mt_sh7
mt_sh6b: STA HSERRP
mt_sh7:  DEC HSK2
        BEQ mt_shr
        JMP mt_sh3
mt_shr: RTS
mt_sh8:  INC HSHL        ; the line done: the next one next frame
        RTS
HSHX0:  .BYTE $00,$4F,$00,$4F,$00,$00,$00
HSHY0:  .BYTE $28,$87,$87,$28,$28,$57,$87
HSHX1:  .BYTE $4F,$9F,$4F,$9F,$9F,$9F,$9F
HSHY1:  .BYTE $87,$28,$28,$87,$28,$57,$87

; The meteors on their sprites (after SPRCROSS, line 78): positions, shapes ($66 at
; pointer $FF, $67-$70 at $F3-$FC), red, multicolour ($0B / shimmering), twice the
; size; behind the bitmap when low ($2B02) or while the deflector is on ($2AB8).
HSPRC:  JSR SPRCROSS    ; (called instead of it in the jump and the deceleration:
                        ; HMINIT / HPL5BACK set the JSR at sprcj)
        LDA #$00
        STA HSEN
        STA HSMSB
        STA HSPRI
        LDX #HMN-1
mt_sp1:  LDA HMACT,X
        BEQ mt_sp5
        LDY HMREG,X     ; position
        LDA HMX,X
        STA $D000,Y
        LDA HMY,X
        STA $D001,Y
        LDA HSEN
        ORA HMBIT,X
        STA HSEN
        LDA HMXH,X
        BEQ mt_sp2
        LDA HSMSB
        ORA HMBIT,X
        STA HSMSB
mt_sp2:  LDA HDEF        ; behind: the deflector, or low on the screen
        BNE mt_sp3
        LDA HMY,X
        CMP #$A8
        BCC mt_sp4
mt_sp3:  LDA HSPRI
        ORA HMBIT,X
        STA HSPRI
mt_sp4:  LDA HMSHP,X     ; the shape
        LDY #$FF
        CMP #$67
        BCC mt_sp4a
        CMP #$71
        BCC mt_sp4b
        LDA #$70
mt_sp4b: CLC
        ADC #$8C        ; (SHOTPTR - $67)
        TAY
mt_sp4a: TYA
        LDY HMSPN,X
        STA SPRPTR,Y
mt_sp5:  DEX
        BMI mt_sp6
        JMP mt_sp1
mt_sp6:
        LDA VICENA
        AND #$89
        ORA HSEN
        STA VICENA
        LDA $D010
        AND #$89
        ORA HSMSB
        STA $D010
        LDA $D01B
        AND #$89
        ORA HSPRI
        STA $D01B
        LDA $D01C
        ORA #$76
        STA $D01C
        LDA $D017
        ORA #$76
        STA $D017
        LDA $D01D
        ORA #$76
        STA $D01D
        LDA #$02
        STA $D028
        STA $D029
        STA $D02B
        STA $D02C
        STA $D02D
        LDA #$0B
        STA $D025
        LDA HC26
        STA $D026
mt_sp9:  RTS

HMN     = 5
HMREG:  .BYTE $02,$04,$08,$0A,$0C   ; sprites 1, 2, 4, 5, 6: register offsets
HMSPN:  .BYTE 1,2,4,5,6
HMBIT:  .BYTE $02,$04,$10,$20,$40
HMSPD:  .BYTE $0A,$08,$07,$07,$06   ; ($284B) the pace by difficulty
HMXL:   .BYTE $60,$7C,$98,$B8,$D0,$E8
HMXV:   .BYTE $82,$81,$81,$00,$01,$01,$02
HMYL:   .BYTE $58,$61,$71,$91,$A1,$A8
HMYV:   .BYTE $83,$82,$81,$00,$01,$02,$03
HMACT:  .BYTE 0,0,0,0,0
HMDLY:  .BYTE 0,0,0,0,0
HMX:    .BYTE 0,0,0,0,0
HMXH:   .BYTE 0,0,0,0,0
HMY:    .BYTE 0,0,0,0,0
HMSHP:  .BYTE 0,0,0,0,0
HMGC:   .BYTE 0,0,0,0,0
HMGR:   .BYTE 0,0,0,0,0
HMSD:   .BYTE 0,0,0,0,0
HMSR:   .BYTE 0,0,0,0,0
HMALT:  .BYTE 0,0,0,0,0
HMVX:   .BYTE 0,0,0,0,0
HMVY:   .BYTE 0,0,0,0,0
HMACC:  .BYTE 0
HMK:    .BYTE 0
HSHIPP: .BYTE 0
HMR:    .BYTE 0
HMXS:   .BYTE 0
HC26:   .BYTE 6
HDEF:   .BYTE 0
HDPW:   .BYTE 0
HDPWH:  .BYTE 0
HDJ:    .BYTE $FF
HDJC:   .BYTE 6
HCOLV:  .BYTE 0
HCOLJ:  .BYTE 0
HSHPEND:.BYTE 0
HSHL:   .BYTE 0
HSHLEFT:.BYTE 0
HSX0P:  .BYTE 0
HSY0P:  .BYTE 0
HSDXP:  .BYTE 0
HSDYP:  .BYTE 0
HSSYP:  .BYTE 0
HSERRP: .BYTE 0
HSK2:   .BYTE 0
HSEN:   .BYTE 0
HSMSB:  .BYTE 0
HSPRI:  .BYTE 0
HSHPL5:
        .BYTE $00,$00,$00,$00,$18,$00,$01,$FF,$80,$06,$7B,$60,$18,$D9,$98,$31,$8C,$CC,$7F,$8C,$FE
        .BYTE $63,$FF,$C6,$C6,$0C,$63,$C6,$0C,$63,$FE,$0C,$7F,$C7,$FF,$E3,$C6,$0C,$63,$63,$0C,$66
        .BYTE $7F,$0C,$FE,$31,$FF,$8C,$18,$D9,$98,$07,$FF,$60,$01,$FF,$80,$00,$18,$00,$00,$00,$00

; A <> 0: the hyperspace cursor is on: a mouse, and the jump under way once the
; map has gone (the acceleration, the jump, the deceleration) or the H test.
HCURON: LDA HYPON
        BEQ g_cu1
        CMP #$04        ; (the path on the map: not yet)
        BEQ g_cu1
        LDA HMAP        ; (nor while the map, the planet or the wipe are still there)
        ORA WIPE
        BNE g_cu2
        LDA #$01
        AND MPRES
        RTS
g_cu2:  LDA #$00
        RTS
g_cu1:  LDA HTEST
        AND MPRES
        RTS
H2END:

; Mothership sector ($FD3B, $8C44); work in the view through shpj, no idle cost.
; Fighter masters and STR2X use lower RAM; new code fits below TORPA ($F600).
MSECTOR:
        LDA #<MAPCLOSE
        STA g_mi8+1
        LDA #>MAPCLOSE
        STA g_mi8+2
        LDA #$00
        STA MSLOCK
        STA MSKILLED
        JSR MSOFF
        LDA M_STATE,X
        BMI g_ms0
        JMP GSQTYPE
MSOFF:
        JSR MSPOSOFF
        LDA #$20
        STA mscent
        LDA #$01
        STA msmode+1
        LDA #<STARS
        STA vv2+1
        STA g_vs2+1
        LDA #>STARS
        STA vv2+2
        STA g_vs2+2
        LDA #$00
        STA MSSTATE
        STA MSCPEND
        LDA #<MAPSHOWN
        STA gplmode+1
        STA germode+1
        LDA #>MAPSHOWN
        STA gplmode+2
        STA germode+2
        LDA #<GSHLOAD
        STA shpj+1
        LDA #>GSHLOAD
        STA shpj+2
        LDA #$2C
        STA shpj
        RTS
g_ms0:  STA MSKIND
        JSR MSPOSON
        LDA #<MSVB
        STA vv2+1
        STA g_vs2+1
        LDA #>MSVB
        STA vv2+2
        STA g_vs2+2
        LDA #$01
        STA MSSTATE
        LDA #<MSVIEW
        STA shpj+1
        LDA #>MSVIEW
        STA shpj+2
        LDA #$20
        STA shpj
        LDA #<MSSTATE
        STA gplmode+1
        STA germode+1
        LDA #>MSSTATE
        STA gplmode+2
        STA germode+2
        RTS

MSVIEW: LDA $D012       ; a phasor can consume the view slot: defer heavy work
        CMP #150
        BCC g_mstime
        RTS
g_mstime:LDA MSSTATE
        CMP #16
        BNE g_msnormal
        JMP MSPOS
g_msnormal:
        CMP #$04
        BCC g_msactive
        JMP MSFINISH
g_msactive:LDA MAPSHOWN
        ORA WIPE
        ORA HYPON
        BEQ g_mvgo
        LDA #$01        ; closing the map wipes the rings: approach again
        STA MSSTATE
        RTS
g_mvgo: LDA MSSTATE
        CMP #$01
        BNE g_msv2
        LDA #$00
        STA MSROW
        STA MSCLOCK
        STA MSRUN
        STA MSCPEND
        STA MSPACC
        LDA #14
        STA MSPROW
        LDA #$11
        STA MSPCOLOR
        JSR M_RND
        AND #$3F
        CLC
        ADC #$01
        STA MSPCOUNT
        JSR M_RND
        AND #$01
        STA MSPHASE
        LDA #$01
        STA MSRAD
        STA MSBIAS
        LDA #16
        STA MSSTATE
        LDA #$87
        STA MSGCOL
        LDA #$14        ; (the original's 5 per loop pass: 20 frames in the measured base entry)
        STA MSGRATE
        LDA #<MSFRIEND
        LDX #>MSFRIEND
        LDY MSKIND
        CPY #$80
        BNE g_msm
        LDA #<MSHOSTILE
        LDX #>MSHOSTILE
g_msm:  LDY #$0A
        JSR MSGSTAT
        LDA MSKIND
        CMP #$80
        BNE g_msret
        LDA #$00        ; $0921, same sweep as SECALERT; friendly has no sweep
        STA SNDDIR
        LDA #$50
        STA SNDHI0
        LDA #$40
        LDX #$08
        LDY #$1E
        JMP SNDGO
g_msret:RTS
g_msv2: CMP #$02
        BNE g_msv3
        LDX MSROW       ; one row a frame: keep the cockpit and radar intact
        LDA ROWCL+1,X
        STA CDST
        LDA ROWCH+1,X
        CLC
        ADC #$44
        STA CDST+1
        LDA #$11        ; $953F: value 2 is white (the growing central opening)
g_msc0: LDY #39
g_msc1: STA (CDST),Y
        DEY
        BPL g_msc1
        LDA CDST+1
        CLC
        ADC #$94
        STA CDST+1
        LDA #$06
        LDX MSKIND
        CPX #$80
        BNE g_msc2
        LDA #$02
g_msc2: LDY #39
g_msc3: STA (CDST),Y
        DEY
        BPL g_msc3
        INC MSROW
        LDA MSROW
        CMP #14
        BCC g_msret
        INC MSSTATE
        JMP MSRING

g_msv3: JSR MSPSTEP
; The enemy entry sweep formerly overlapped the rings. After positioning it has
; ended; reserve one frame in sixteen to retain the original DMA growth rate.
g_msclock:LDA MSKIND
        ASL A
        BNE g_msclocktick
        LDA EFRM
        AND #$0F
        BEQ g_msret
g_msclocktick:INC MSCLOCK
        LDA MSRUN
        BNE g_msd
        LDX MSRAD
        LDA MSCLOCK
        CMP MSDELAY,X
        BCC g_msret
        LDA #$00
        STA MSCLOCK
        LDA #$28
        LDX MSKIND
        CPX #$80
        BNE g_msend
        LDA #$22
g_msend:CMP MSRAD
        BNE g_msgrow
        INC MSSTATE     ; endpoint: friendly docking or enemy return (MSFINISH)
        RTS
g_msgrow:
        INC MSRAD
        INC MSBIAS
        LDA MSKIND
        CMP #$80
        BNE g_msnew
        INC MSBIAS
        INC MSBIAS
g_msnew:JMP MSRING
g_msd:  LDA TPF         ; do not interfere with the player's torpedo's scratch
        BEQ g_msd1
        RTS
g_msd1: JMP MSSTEP

MSRING:
mscent: JSR MSCINIT
        LDA MSRAD
        STA MSRX
        LDA #$80
        STA MSD
        LDA #$00
        STA MSRY
        INC MSRUN
        RTS

; Original $3635/$364C: biased circle, not a standard midpoint circle.
; Two octants through TPLOT4, centre $50/$64, value 3, brown pixels preserved.
MSSTEP: LDA $D012
        CMP #174
        BCC g_msstep
        RTS
g_msstep:CLC
        LDA MSD
        ADC MSRY
        ADC MSRY
        ADC #$01
        STA MSD1
        SEC
        SBC MSRX
        SBC MSRX
        CLC
        ADC MSBIAS
        STA MSD2
msmode: LDA #$01
        STA TPPASS
        LDA MSRX
        LDY MSRY
msplot1:JSR TPLOT4
        LDA MSRY
        LDY MSRX
msplot2:JSR TPLOT4
        LDA MSD1
        STA MSD
        INC MSRY
        LDA MSD2
        BMI g_msa
        SEC
        LDA #$80
        SBC MSD2
        JMP g_msb
g_msa: AND #$7F
g_msb: STA MSABS
        LDA MSD
        BMI g_msc
        SEC
        LDA #$80
        SBC MSD
        JMP g_mse
g_msc: AND #$7F
g_mse: CMP MSABS
        BCC g_msf
        BEQ g_msf
        LDA MSD2
        STA MSD
        DEC MSRX
g_msf: LDA MSRX
        CMP MSRY
        BCC g_msdone
        JMP MSSTEP
g_msdone:LDA #$00
        STA MSRUN
g_msout:RTS

MSSTATE:.BYTE 0         ; 0 idle, 1 init, 2 colours, 3 rings, 4 end, 5 wipe, 6 death; 16 scanner
MSKIND: .BYTE 0         ; $80 hostile ($E2=1), $FF friendly ($E2=0)
MSROW:  .BYTE 0
MSRAD:  .BYTE 1
MSBIAS: .BYTE 1         ; original operand $3674: +3 hostile, +1 friendly
MSCLOCK:.BYTE 0
MSRUN:  .BYTE 0
MSRX:   .BYTE 0
MSRY:   .BYTE 0
MSD:    .BYTE 0
MSD1:   .BYTE 0
MSD2:   .BYTE 0
MSABS:  .BYTE 0
; DMA-enabled original: growth intervals ~6 frames initially, ~9 at full size.
; Torpedo animation's extra time is excluded (not part of this task).
MSDELAY:.BYTE 6,6,6,6,6,6,6,6,6,6,6,6,6,6,7,6,7,6,7,6
        .BYTE 7,7,7,7,7,8,7,8,7,8,8,8,8,8,9,8,8,9,8,9,9
MSFRIEND:.BYTE $40,$40,$40,$40,$40,$40,$40,$40,$40,$40
        .BYTE $45,$4E,$54,$45,$52,$49,$4E,$47,$40,$42,$41,$53,$45,$40,$53,$45,$43,$54,$4F,$52,$40,$FF
MSHOSTILE:.BYTE $40,$40,$40,$40,$40,$40
        .BYTE $47,$4F,$52,$47,$41,$4E,$49,$54,$4F,$52,$40,$42,$41,$53,$45,$53,$54,$41,$52,$40,$44,$45,$54,$45,$43,$54,$45,$44,$40,$FF
MSEND:

; $8F05 / $B39A: nested rectangle outlines fill the opening from radius 12.
; For n=r-12: x=75-ceil(n/2), y=100-ceil(n/2), width=10+n,
; height=1+n. B39A includes both edges (width+1 by height+1 pixels).
; Queue a filled equivalent; the blank draws rows, while circles keep their cadence.
MSCINIT:LDA MSRAD
        CMP #12
        BCS g_mcinit
        RTS
g_mcinit:SEC
        SBC #12
        STA MSCN
        CLC
        ADC #$01
        LSR A
        STA MSCOFF
        SEC
        LDA #75
        SBC MSCOFF
        STA MSCLEFT
        CLC
        ADC MSCN
        ADC #10
        STA MSCRIGHT
        SEC
        LDA #100
        SBC MSCOFF
        STA MSCROW
        CLC
        ADC MSCN
        ADC #$01
        STA MSCEND
        LDA #$01
        STA MSCPEND
        RTS

; Switched JMP slots vv2 / g_vs2; idle flight/fights still jump straight to STARS.
; Centre updates replace stars for a blank; deadline leaves the radar its time.
MSVB:   LDA MSCPEND
        BEQ g_mcvpalette
        LDA MAPSHOWN
        ORA WIPE
        ORA HYPON
        ORA TPF
        BEQ g_mcvrow
        JMP STARS
g_mcvpalette:LDA MSPROW
        CMP #14
        BCS g_mcvstars
        JSR MSPAINT
        RTS
g_mcvstars:JMP STARS
g_mcvrow:LDA #16
        JSR TLATE
        BCC g_mcvdraw
        RTS
g_mcvdraw:LDA MSCLEFT
        STA POSX
        LDA MSCROW
        STA POSY
        JSR PIXADDR
        SEC
        LDA MSCRIGHT
        SBC MSCLEFT
        CLC
        ADC #$01
        STA MSCN
        LDY #$00
        CPX #$00
        BEQ g_mcvfull
; Partial first/last byte; multicolour bitmap bytes are eight bytes apart.
g_mcvpart:LDA (PTR),Y
        AND CLEARM,X
        ORA MASK2,X
        STA (PTR),Y
        DEC MSCN
        BEQ g_mcveol
        INX
        CPX #$04
        BCC g_mcvpart
        LDX #$00
        TYA
        CLC
        ADC #$08
        TAY
g_mcvfull:LDA MSCN
        CMP #$04
        BCC g_mcvpart
        LDA #$AA
        STA (PTR),Y
        SEC
        LDA MSCN
        SBC #$04
        STA MSCN
        BEQ g_mcveol
        TYA
        CLC
        ADC #$08
        TAY
        JMP g_mcvfull
g_mcveol:INC MSCROW
        LDA MSCROW
        CMP MSCEND
        BCC g_mcvrow
        BEQ g_mcvrow
        LDA #$00
        STA MSCPEND
        RTS
MSCPEND:.BYTE 0
MSCLEFT:.BYTE 0
MSCRIGHT:.BYTE 0
MSCROW: .BYTE 0
MSCEND: .BYTE 0
MSCOFF: .BYTE 0
MSCN:   .BYTE 0
MSCENDCODE:

; $953F every 32 passes: four calls per radius interval, frame-locked.
MSPSTEP:CLC
        LDA MSPACC
        ADC #$04
        STA MSPACC
        LDX MSRAD
        CMP MSDELAY,X
        BCC g_mpout
        SBC MSDELAY,X
        STA MSPACC
MSPCALL:DEC MSPCOUNT
        BNE g_mpcol
        LDA #25
        STA MSPCOUNT
        LDA MSPHASE
        EOR #$01
        STA MSPHASE
        BEQ g_mpcol
        LDA #$00        ; a white phase must repaint rows left from the flicker
        STA MSPROW
g_mpcol:LDA #$11
        LDX MSKIND
        CPX #$80
        BNE g_mpset
        LDX MSPHASE
        BNE g_mpset
        JSR M_RND
        AND #$0F
        ORA #$10
g_mpset:CMP MSPCOLOR
        BEQ g_mpout
        STA MSPCOLOR
        LDA MSPROW
        CMP #14
        BCC g_mpout
        LDA #$00
        STA MSPROW
g_mpout:RTS
MSPAINT:LDA TPF
        ORA MAPSHOWN
        ORA WIPE
        ORA HYPON
        BNE g_mppout
g_mpprow:LDA MSPROW
        CMP #14
        BCS g_mppout
        LDA #12
        JSR TLATE
        BCS g_mppout
        LDX MSPROW
        LDA ROWCL+1,X
        STA CDST
        LDA ROWCH+1,X
        CLC
        ADC #$44
        STA CDST+1
        LDA MSPCOLOR
        LDY #39
g_mppfill:STA (CDST),Y
        DEY
        BPL g_mppfill
        INC MSPROW
        JMP g_mpprow
g_mppout:RTS

; $BB81: sample the phase at the end of flight; a miss preserves the base.
MSBLAST:LDA MSSTATE
        BEQ g_msbout
        CMP #$05
        BCS g_msbout
        LDA MSRAD
        CMP #12
        BCC g_msbmiss
        LDA MSPHASE
        BEQ g_msbmiss
        LDA #$01
        STA MSKILLED
        LDA #$04
        STA MSSTATE
        LDA #$00
        STA MSCPEND
        RTS
g_msbmiss:LDA #$06
        STA TPF
        LDA #$08
        STA HCOLV
        JMP TCOL0
g_msbout:RTS
MSFLASH:LDA TPF
        PHA
        JSR TCOL
        PLA
        LDX TPF
        BNE g_msfout
        CMP #$06
        BNE g_msfout
        LDA #$07
        STA TPF
        LDA #$06
        LDX MSKIND
        CPX #$80
        BNE g_msfc
        LDA #$02
g_msfc: STA HCOLV
        JMP TCOL0
g_msfout:RTS

; Finish states: 4 wait for proton, 5 wipe, 6 erasing rings; 7+ friendly docking.
MSFINISH:LDA TPF
        BEQ g_msfgo
        RTS
g_msfgo:LDA MSKILLED
        BNE g_msfkill
        JMP MRSTART
g_msfkill:LDA MSSTATE
        CMP #$04
        BNE g_msfwait
        LDA #<MSDESTROYED
        LDX #>MSDESTROYED
        LDY #$10
        STY MSGCOL
        LDY #20
        STY MSGRATE
        LDY #15
        JSR MSGSTAT
        LDA #$00
        STA MSCPEND
        STA EXPL
        STA EXPL2
        LDA #15
        STA WIPE
        INC MSSTATE
        RTS
g_msfwait:LDA WIPE
        BEQ g_msfrdy
        RTS
g_msfrdy:LDA MSSTATE
        CMP #$05
        BNE g_msfdraw
        LDA #$2C
        STA mscent
        LDA #$02
        STA msmode+1
        LDA #$01
        STA MSRAD
        STA MSBIAS
        LDA #$00
        STA MSRUN
        STA EXPB
        STA EXPB2
        STA EVX0
        STA EVY0
        STA EVX02
        STA EVY02
        LDA #$50
        STA EXPX
        STA EXPX2
        LDA #$64
        STA EXPY
        STA EXPY2
        STA EXPL
        STA EXPL2
        JSR MSRING
        INC MSSTATE
        RTS
g_msfdraw:LDA MSRUN
        BEQ g_msfnext
        JMP MSSTEP
g_msfnext:LDA MSRAD
        CMP #$2C
        BCC g_msfmore
        JMP MSRETURN
g_msfmore:INC MSRAD
        INC MSBIAS
        JMP MSRING
MSRETURN:JSR SECIDX
        LDA MSKILLED
        BEQ g_msrmap
        LDA #$00
        STA M_STATE,X
        STA M_COUNT,X
        STA M_NEWST,X
        STA M_NEWCT,X
        LDA #$01
        STA M_DIRTY,X
        TXA
        LDY #$03
g_msrdi:CMP M_INNER,Y
        BNE g_msrdi1
        LDX MSKIND
        CPX #$FF
        BNE g_msrkl
        LDA #$01
        STA M_DEAD,Y
        BNE g_msrkl
g_msrdi1:DEY
        BPL g_msrdi
g_msrkl:JSR MSOFF       ; destroyed: its empty sector can be chosen straight away
        JMP MAPOPEN
g_msrmap:JSR MSOFF
        LDA #$01
        STA MSLOCK
        LDA #<g_mi9
        STA g_mi8+1
        LDA #>g_mi9
        STA g_mi8+2
        JMP MAPOPEN

; SURROUND's STA LASTMSG slots become JSRs, preserving A/X/Y/status.
GBTQUEUE:PHP
        PHA
        TXA
        PHA
        TSX
        LDA $0102,X
        BEQ g_gbqfull
        LDX GBTCOUNT
        CPX #$08
        BCS g_gbqfull
        INC GBTCOUNT
        LDX GBTIN
        STA GBTBUF,X
        INX
        TXA
        AND #$07
        STA GBTIN
g_gbqfull:PLA
        TAX
        PLA
        STA M_LASTMSG
        PLP
        RTS
; VDCMSG's idle LDA/BEQ/RTS is unchanged in size and cost.
GBTEXT: LDY GBTOUT
        LDA GBTBUF,Y
        SEC
        SBC #$01
        TAX
        INY
        TYA
        AND #$07
        STA GBTOUT
        DEC GBTCOUNT
        LDA GBTLO,X
        PHA
        LDA GBTHI,X
        TAX
        PLA
        LDY #$87
        STY MSGCOL
        LDY #15
        STY MSGRATE
        JSR MSGSTAT
        JMP SNDSIREN
GBTLO:  .BYTE <GBMSG1,<GBMSG2,<GBMSG3,<GBMSG4
GBTHI:  .BYTE >GBMSG1,>GBMSG2,>GBMSG3,>GBMSG4
MSPHASE:.BYTE 0
MSPCOUNT:.BYTE 1
MSPACC: .BYTE 0
MSPCOLOR:.BYTE $11
MSPROW: .BYTE 14
MSKILLED:.BYTE 0
MSLOCK: .BYTE 0
GBTCOUNT:.BYTE 0
GBTIN:  .BYTE 0
GBTOUT: .BYTE 0
GBTBUF: .BYTE 0,0,0,0,0,0,0,0
MSDESTROYED: .BYTE $40,$40,$40,$40,$40,$40,$40,$40,$42,$41,$53,$45,$53,$54,$41,$52,$40,$44,$45,$53,$54,$52,$4F,$59,$45,$44,$40,$43,$41,$50,$54,$41,$49,$4E,$FF
GBMSG1: .BYTE $40,$40,$40,$40,$40,$40,$4D,$4F,$54,$48,$45,$52,$53,$48,$49,$50,$40,$45,$4E,$47,$41,$47,$45,$44,$40,$49,$4E,$40,$42,$41,$54,$54,$4C,$45,$FF
GBMSG2: .BYTE $40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$4D,$4F,$54,$48,$45,$52,$53,$48,$49,$50,$40,$44,$45,$53,$54,$52,$4F,$59,$45,$44,$FF
GBMSG3: .BYTE $40,$40,$40,$40,$40,$40,$40,$40,$40,$4A,$41,$52,$41,$4C,$4F,$42,$41,$40,$49,$53,$40,$53,$55,$52,$52,$4F,$55,$4E,$44,$45,$44,$FF
GBMSG4: .BYTE $40,$40,$40,$40,$40,$40,$40,$40,$4A,$41,$52,$41,$4C,$4F,$42,$41,$40,$43,$45,$41,$53,$45,$53,$40,$54,$4F,$40,$45,$58,$49,$53,$54,$FF
MSDEND:
; Friendly docking ($918E/$92E3). All hooks are changed only while active.
; Text/path data uses verified table/master padding, never sprite slots.
MRDATA  = $2F50
MRTEXT  = $2F50
MRWORDS = $2CC0
MRLENS  = $2CD6
MBLEFT  = $36D0
MBRIGHT = $371C
MBTAIL  = $3BC0
MRSTART:LDA MSKIND
        CMP #$FF
        BEQ g_mrstart
        JMP MSRETURN
g_mrstart:LDA #<MRVIEW
        STA shpj+1
        LDA #>MRVIEW
        STA shpj+2
        LDA #<MBEAM
        STA vv2+1
        STA g_vs2+1
        LDA #>MBEAM
        STA vv2+2
        STA g_vs2+2
        LDA #$60
        STA GSPACE
        STA MAPTOG
        STA LAUNCHD
        LDA #$00
        STA SNDON
        STA MSRUN
        STA MRSIDE
        LDA #$FF
        STA MRINDEX
        LDA #$07
        STA MSSTATE
        STA MRCLOCK
        LDA #$01
        STA MSRAD
        STA MSBIAS
        JMP MBSET
MRVIEW:LDA $D012
        CMP #150
        BCS g_mrout
        LDA MSSTATE
        CMP #7
        BEQ MBEAM
        CMP #11
        BCC g_mrrun
        JMP MRCLEAN
g_mrrun:JSR MRREPAIR    ; advance the frame clock before optional noise work
        JMP MRNOISE
g_mrout:RTS
MBEAM:  JSR MBDEAD
        CMP #168
        BCS g_mbout
        LDA MSRUN
        BEQ g_mbnext
        JSR MSSTEP
        LDA MSRUN
        BEQ MBEAM
        RTS
g_mbout:RTS
g_mbnext:LDA MRSIDE
        EOR #$01
        STA MRSIDE
        BEQ g_mbring
        INC MRINDEX
        LDA MRINDEX
        CMP #76
        BNE g_mbmore
        JMP MRINIT
g_mbmore:
        DEC MRCLOCK
        BNE g_mbring
        LDA #10
        STA MRCLOCK
        INC MSRAD
g_mbring:LDA #$2C
        STA mscent
        LDA MRSIDE
        BNE g_mbquiet
        JSR MRBEEP
g_mbquiet:JSR MBPLOT
        JSR MSRING
        JMP MBEAM
; Temporarily move the existing circle plotter; only empty pixels get value 1.
MBPLOT: LDX MRINDEX
        TXA
        CLC
        ADC #110
        STA tpcy1+1
        STA tpcy2+1
        LDA MBLEFT,X
        LDY MRSIDE
        BNE g_mbleft
        LDA MBRIGHT,X

g_mbleft:STA tpcx1+1
        STA tpcx2+1
        STA tpcx3+1
        RTS
MBSET:  LDA #<MBADDR
        STA TPLOT1+1
        LDA #>MBADDR
        STA TPLOT1+2
        LDA #$20
        STA MSSTEP
        LDA #<MBDEAD
        STA MSSTEP+1
        LDA #>MBDEAD
        STA MSSTEP+2
        LDA #<MBZERO
        STA TPLOT1+9
        LDA #>MBZERO
        STA TPLOT1+10
        LDA #$D0
        STA TPLOT1+11
        LDA #<MASK1
        STA g_pl8-2
        LDA #>MASK1
        STA g_pl8-1
        RTS
MBRESTORE:LDA #<PIXADDR
        STA TPLOT1+1
        LDA #>PIXADDR
        STA TPLOT1+2
        LDA #$AD
        STA MSSTEP
        LDA #$12
        STA MSSTEP+1
        LDA #$D0
        STA MSSTEP+2
        LDA #<g_msret
        STA vv2+1
        STA g_vs2+1
        LDA #>g_msret
        STA vv2+2
        STA g_vs2+2
        LDA #<M_MASK2
        STA TPLOT1+9
        LDA #>M_MASK2
        STA TPLOT1+10
        LDA #$F0
        STA TPLOT1+11
        LDA #<MASK3
        STA g_pl8-2
        LDA #>MASK3
        STA g_pl8-1
        LDA #$50
        STA tpcx1+1
        STA tpcx2+1
        STA tpcx3+1
        LDA #$64
        STA tpcy1+1
        STA tpcy2+1
        RTS
MRINIT: JSR MBRESTORE
        LDA #$2C        ; the radar's sweep (colour band) off: the report has no
        STA VBWORK      ; radar, as in the original (BIT in place of both JSRs)
        STA VBWORK+3
        LDA #$20
        STA mscent
        LDA #$7B        ; black (an invalid mode) while the old rows are cleared:
        STA MRMODE+1    ; text shows only when they are (MRTEXTON)
        LDA #5
        STA MRWAIT+1
        LDA #$20
        STA MRATTR
        LDA #<MRVIDEO
        STA MRATTR+1
        LDA #>MRVIDEO
        STA MRATTR+2
        LDX #4
        LDA #$EA
g_mrmode:STA MRATTR+3,X
        DEX
        BPL g_mrmode
        LDA #$60
        STA SPRCROSS
        STA SPRGUNS
        LDA #0
        STA VICENA
        LDA #<MRNOISE
        STA vv2+1
        STA g_vs2+1
        LDA #>MRNOISE
        STA vv2+2
        STA g_vs2+2
        LDA #0
        STA MRINDEX
        STA MRCOL
        STA MROFF
        STA MRACC
        STA MREN
        STA MSGON
        STA MSGFINE
        LDA #21
        STA MRROW
        LDA #8
        STA MSSTATE
        LDX #7
g_mrhp:LDA SYSHP,X
        STA MRHP,X
        DEX
        BPL g_mrhp
        RTS
g_mrtype:CMP #9
        BNE g_mrscan
; Original typewriter: 158 characters in 63 frames (2.5/frame).
        LDA MRACC
        CLC
        ADC #5
        STA MRACC
g_mrchar:LDA MRACC
        CMP #2
        BCC g_mrout2
        SBC #2
        STA MRACC
        LDX MRINDEX
        JSR MRADDR
        LDY MRCOL
        LDX MROFF
        LDA MRTEXT,X
        STA (CDST),Y
        JSR MRBEEP
        INC MROFF
        INC MRCOL
        LDX MRINDEX
        LDA MRCOL
        CMP MRLENS,X
        BCC g_mrchar
        LDA #0
        STA MRCOL
        INC MRINDEX
        LDA MRINDEX
        CMP #8
        BCC g_mrchar
        LDA #0
        STA MRINDEX
        LDA #50
        STA MRROW
        LDA MRHP
        JSR MRDELAY
        CLC
        ADC #53
        STA MRCLOCK
        INC MSSTATE
        LDA #0
        STA $D40B
        STA $D407
        STA $D40D
        LDA #$12
        STA $D408
        LDA #5
        STA $D40C
        LDA #$11
        STA $D40B
        RTS
g_mrout2:RTS
g_mrscan:LDA MRROW
        BEQ g_mrscanned
        DEC MRROW
g_mrscanned:JSR MRFLASH
        JSR MRCHARGE
        LDA MRINDEX
        CMP #8
        BEQ g_mrwait
        DEC MRCLOCK
        BNE g_mrout2
        LDX MRINDEX
        JSR MRADDR
        LDY #29
        LDX MRINDEX
        LDA MRHP,X
        LDX #11
        CMP #0
        BNE g_mrok
        LDX #0
g_mrok: LDA MRWORDS,X
        STA (CDST),Y
        INX
        INY
        CPY #40
        BCC g_mrok
        JSR GBLIP
        LDX MRINDEX
        LDA #1
        STA MRHP,X
        INC MRINDEX
        LDX MRINDEX
        LDA MRHP,X
        JSR MRDELAY
        STA MRCLOCK
        RTS
g_mrwait:LDA MREN
        BNE g_mrfinish
        RTS
g_mrfinish:INC MRCOL
        LDA MRCOL
        CMP #3
        BCC g_mrout2
        JSR MRBLACK
        LDA #15
        STA WIPE
        INC MSSTATE
        RTS
MRTEXTON:JSR MRBLOCKS     ; the rows are clear: the report's text mode on
        LDA #$1B
        STA MRMODE+1
        RTS

MRCOMPLETE:
        LDA #$20        ; the radar's sweep back on
        STA VBWORK
        STA VBWORK+3
; Original INC $8450 is byte-wide (wrap at 255); joined HUD keeps two digits.
        INC $485B
        LDA $485B
        CMP #$7A
        BCC g_mrproton
        LDA #$70
        STA $485B
        INC $485A
        LDA $485A
        CMP #$7A
        BCC g_mrproton
        LDA #$70
        STA $485A
        INC MRPHUND
g_mrproton:LDA MRPHUND
        CMP #2
        BNE g_mrship
        LDA $485A
        CMP #$75
        BNE g_mrship
        LDA $485B
        CMP #$76
        BNE g_mrship
        LDA #0
        STA MRPHUND
        LDA #$70
        STA $485A
        STA $485B
g_mrship:JSR SHIPINIT
        LDA #$3B
        STA MRMODE+1
        LDX #7
g_mrnormal:LDA MRNORMAL,X
        STA MRATTR,X
        DEX
        BPL g_mrnormal
        LDA #10
        STA MRWAIT+1
        LDA #$AD
        STA SPRCROSS
        STA SPRGUNS
        LDA #$AD
        STA GSPACE
        STA MAPTOG
        STA LAUNCHD
        JMP MSRETURN
; Original report: rows 4,6,..18, name column 0, status column 29.
MRPHUND:.BYTE 0         ; hundreds of the byte-wide proton supply (HUD shows last two digits)
MRINDEX:.BYTE 0
MRSIDE: .BYTE 0
MRCLOCK:.BYTE 0
MRCOL:  .BYTE 0
MROFF:  .BYTE 0
MRACC:  .BYTE 0
MREN:   .BYTE 0
MRTMP:  .BYTE 0
MRROW:  .BYTE 0
MRDELAY:BEQ g_mrdbad
        LDA #28
        RTS
g_mrdbad:LDA #81
g_mrdret:RTS
; One full palette update fits the otherwise empty view slot.
MRFLASH:INC MRBLINK
        LDA MRBLINK
        CMP #20
        BCC g_mrflout
        LDA #0
        STA MRBLINK
        LDA MRNIB
        EOR #1
        STA MRNIB
        LDX #7
g_mrflrow:JSR MRADDR
        LDA CDST+1
        CLC
        ADC #$90
        STA CDST+1
        LDX MRFLROW
        LDA MRHP,X
        BEQ g_mrflbad
        LDA #$DD
        BNE g_mrflcolor
g_mrflbad:LDA #$72
g_mrflcolor:LDY MRNIB
        BNE g_mrflput
        LSR A
        LSR A
        LSR A
        LSR A
g_mrflput:AND #15
        LDY #39
g_mrflfill:STA (CDST),Y
        DEY
        BPL g_mrflfill
        DEC MRFLROW
        LDX MRFLROW
        BPL g_mrflrow
        LDA #7
        STA MRFLROW
g_mrflout:RTS
MREND:


; Original $8C44-$8D56 preliminary positioning. Five loop passes/frame,
; $9054 settling ~194 DMA frames, then $0F7F's five-count wait ~70 frames.
; Both init-only load streams are staged beneath I/O; the KERNAL's LOAD cannot
; reach $FF00-$FFFF (its store loop ends when the address reaches $FF), so the
; positioning tail is copied from $D100 while the RAM beneath I/O is selected.
MSPOSSRC = $D100
MSUNPACK:
        LDA #$00
        STA CSRC
        LDA #$D0
        STA CSRC+1
        LDA #$3F        ; second stream and the tail: RAM beneath I/O, init only
        STA $FF00
        JSR g_upb
        LDX #$00
mp_copy:LDA MSPOSSRC,X
        STA MSPOS,X
        INX
        CPX #245
        BNE mp_copy
        LDA #$3E
        STA $FF00
        RTS
MSCOUNT:LDA M_STATE,X
        BMI mp_basecount
        LDA M_COUNT,X
        RTS
mp_basecount:LDA #$01
        RTS
MSPOSON:LDA #<MSSTATE
        STA HVBR+1
        LDA #>MSSTATE
        STA HVBR+2
        RTS
MSPOSOFF:LDA #<HYPON
        STA HVBR+1
        LDA #>HYPON
        STA HVBR+2
        LDA #$00
        RTS
MSPREAD:JMP lr7
MSPDRIFT:
        SEC
        JSR EDRIFT
        JMP MSPREAD
MSARRIVE:
        JSR ARRIVE
        LDA MSSTATE
        BEQ mp_return
        LDA HSCAN
        BEQ mp_default
        LDX #17
mp_restore:LDA HSLOT,X
        STA ENX,X
        DEX
        BPL mp_restore
        RTS
mp_default:
        LDA #$88
        STA ENX+1
        STA ENY+1
        LDA #$94
        STA ENZ+1
mp_return:RTS

MSPOS:  LDA MAPSHOWN
        ORA WIPE
        ORA HYPON
        BNE mp_return
        LDA MSROW
        BNE mp_run
        INC MSROW
        LDA #$01
        STA LRMODE
        STA GSIZE
        JSR RADMODE
        JSR APINIT
        LDA EVIS
        AND #$EF
        STA EVIS
        LDA #$00
        STA BLIPON
        STA MSCLOCK
        STA MSRUN
        STA APCNT
        STA FLATCH
        RTS
mp_run: CMP #$02
        BCS mp_wait
        LDA #$05
        STA MSRUN
mp_pass:LDA $D012
        CMP #140
        BCS mp_return
        DEC APCNT
        LDA APCNT
        AND #$1F
        BNE mp_steer
        JSR MSPDRIFT
mp_steer:
        LDA APCNT
        AND #$03
        BNE mp_depth
        LDA FLATCH
        BNE mp_depth
        LDX #$00
        JSR DIST
        BMI mp_unlocked
        LDA #$01
        STA INFRONT
        LDA LRDIG
        ORA LRDIG+1
        ORA LRDIG+2
        ORA LRDIG+3
        CMP #$70
        BNE mp_unlocked
        INC FLATCH
        LDA #$07
        STA HUDBRD
        BNE mp_depth
mp_unlocked:
        JSR STEER
mp_depth:
        JSR ZSTEP
        LDX #$00
        JSR DIST
        BMI mp_next
        LDA DSTH
        CMP #$06
        BCS mp_next
        INC MSROW
        LDA #194
        STA MSCLOCK
        RTS
mp_next:DEC MSRUN
        BNE mp_pass
        RTS
mp_wait:LDA MSCLOCK
        AND #$03
        BNE mp_waittick
        JSR MSPDRIFT
mp_waittick:DEC MSCLOCK
        BEQ mp_expire
        RTS
mp_expire:
        INC MSROW
        LDA #70
        STA MSCLOCK
        LDA MSROW
        CMP #$04
        BCS mp_done
        RTS
mp_done:LDA #$00
        STA MSROW
        JSR MSPOSOFF
        STA GSIZE
        STA ENZ+1
        STA LRMODE
        STA MSRUN
        LDA EVIS
        AND #$EF
        STA EVIS
        JSR HRADCLR
        JSR RADMODE
        LDA #$02
        STA MSSTATE
        RTS

MSPOSEND:
        * = $3D60
MRCHARGE:LDA MREN
        BNE g_mrcout
        LDX #9
g_mrcdigit:STX MRTMP
        LDX #3
g_mrcarry:INC HUDE,X
        LDA HUDE,X
        CMP #$7A
        BCC g_mrcnext
        LDA #$70
        STA HUDE,X
        DEX
        BPL g_mrcarry
        LDY #3
        LDA #$79
g_mrcfull:STA HUDE,Y
        DEY
        BPL g_mrcfull
        INC MREN
        RTS
g_mrcnext:LDX MRTMP
        DEX
        BNE g_mrcdigit
g_mrcout:RTS
MRBEEP: LDA #0
        STA $D404
        STA $D406
        STA $D400
        LDA #$62
        STA $D401
        LDA #2
        STA $D405
        LDA #$11
        STA $D404
        RTS
MRADDR:TXA
        ASL A
        CLC
        ADC #4
        JMP MRROWADDR
MRNORMAL:.BYTE $A9,$18,$8D,$16,$D0,$8D,$18,$D0
        .BYTE 0,0
MRGUNS:
MRVIDEO:LDA #8
        STA $D016
        LDA #$20
        STA $D018
        RTS
        .BYTE 0,0,0,0,0
MRFONT:
MRRESTORE:LDX #200
g_mrrcolor:LDA COLORDATA+719,X
        STA $DACF,X
        DEX
        BNE g_mrrcolor
        JSR MRGLYPHBACK
        RTS
MRNBUDGET:LDA FAST
        AND #1
        BEQ g_mnbview
        LDY #52
        LDA #8
        JSR TLATE
        BCS g_mnbret
        TYA
        STA MRNCOUNT
g_mnbret:RTS
g_mnbview:LDA #40
        STA MRNCOUNT
        CLC
        RTS
MRLOWEND:


        * = $3BD8
MBDEAD: BIT $D011
        BMI g_mbdvb
        LDA $D012
        CMP #243
        BCC g_mbdret
g_mbdvb:LDA #24
        JSR TLATE
        LDA #0
        BCC g_mbdret
        LDA #174
g_mbdret:RTS
; Rays reach the guns; y>=184 is hidden by text and holds live shot sprites.
MBADDR: LDA POSY
        CMP #184
        BCC g_mbaddr
        NOP
        NOP
        NOP
        PLA
        PLA
        RTS
g_mbaddr:JMP PIXADDR
MBLOWEND:

        * = $3768
MRNOISE:LDA MSSTATE
        CMP #11
        BNE g_mnnmode
        JMP MRBLACK
g_mnnmode:CMP #10
        BNE g_mnnret
        LDA MRCLOCK
        CMP #1
        BEQ g_mnnret
        LDA MRROW
        BNE g_mnngo
        LDX MRINDEX
        CPX #8
        BCS g_mnnret
        LDA MRHP,X
        BNE g_mnnret
        LDA MRCLOCK
        CMP #50
        BCS g_mnnret
g_mnngo:JSR MBDEAD
        CMP #100
        BCS g_mnnret
        LDA MRCLOCK
        AND #3
        BNE g_mnnquiet
        JSR MRBEEP
g_mnnquiet:JSR MRNBUDGET
        BCS g_mnnret
g_mnnloop:JSR M_RND
        AND #15
        TAX
        JSR M_RND
        STA $DB2C,X
        AND #15
        TAX
        JSR M_RND
        STA $DB54,X
        DEC MRNCOUNT
        BNE g_mnnloop
g_mnnret:RTS
MRROWADDR: ; A = physical row (3..23); $4800 + A*40, no high-byte overflow.
        STA CDST
        ASL A
        ASL A
        CLC
        ADC CDST
        ASL A
        STA CDST
        LDA #0
        ASL CDST
        ROL A
        ASL CDST
        ROL A
        CLC
        ADC #$48
        STA CDST+1
        RTS
MRGLYPH = $28F8
MRGLYPHSET:LDX #7
        LDA #$FF
g_mrglyphset:STA $41F8,X
        DEX
        BPL g_mrglyphset
        RTS
MRGLYPHBACK:LDX #7
g_mrglyphback:LDA MRGLYPH,X
        STA $41F8,X
        DEX
        BPL g_mrglyphback
        RTS
MRHP:   .BYTE 0,0,0,0,0,0,0,0
MRFIXEND:

        * = $3BC0
MRBLOCKS:LDX #15
        LDA #$3F
g_mrblocks:STA $4B2C,X
        STA $4B54,X
        DEX
        BPL g_mrblocks
        JMP MRGLYPHSET
MRBLOCKEND:
        * = $3BD1
MBZERO: .BYTE 0,0,0,0
MRBLINK:.BYTE 0
MRNIB:  .BYTE 0
MRFLROW:.BYTE 7


        * = $2CDE
MRCLEAN:LDA MRROW
        CMP #7
        BCC g_mrcart
        CMP #8
        BCS g_mrcview
        JSR MRRESTORE
        INC MRROW
g_mrcview:LDA WIPE
        BNE g_mrcdone
        JMP MRCOMPLETE
g_mrcdone:RTS
g_mrcart:JMP MRART
MRCLEANEND:

        * = $2FEE
MRART: CLC
        ADC #$76
        STA CDST+1
        LDA #$80
        STA CDST
        JMP MRARTLOOP
MRARTEND:

        * = $33E8
MRARTLOOP:LDY MRARTY
        LDX #0
        LDA MRROW
        CMP #6
        BNE g_mrartlen
        LDX #64
g_mrartlen:STX MRARTN
        JMP MRARTSTEP
MRARTN:.BYTE 0
MRARTY:.BYTE 0
MRARTLOOPEND:


        * = $BFC3
MRREPAIR:LDA MSSTATE
        CMP #8
        BEQ g_mrclrgo
        JMP g_mrtype
g_mrclrgo:
 ; Clear report rows 3..22, including the cockpit/radar area, in text mode.
        LDA MRROW
        CLC
        ADC #2
        JSR MRROWADDR
        LDY #39
        LDA #$60
g_mrclr:STA (CDST),Y
        DEY
        BPL g_mrclr
        LDA CDST+1
        CLC
        ADC #$90
        STA CDST+1
        LDY #39
        LDA #13
g_mrcol:STA (CDST),Y
        DEY
        BPL g_mrcol
        DEC MRROW
        BNE g_mrclearout
        JSR MRTEXTON
        INC MSSTATE
g_mrclearout:RTS
MRCLEAREND:

        * = $28D7
MRARTSTEP:LDA (CDST),Y   ; a 01 pixel becomes 00: AND with (v >> 1) | $AA
        LSR A
        ORA #$AA
        AND (CDST),Y
        STA (CDST),Y
        INY
        CPY MRARTN
        BEQ g_mrastd
        TYA             ; 64 bytes a call: the rest in the next frames
        AND #$3F
        BNE MRARTSTEP
g_mrasty:STY MRARTY
        RTS
g_mrastd:INC MRROW
        LDY #0
        BEQ g_mrasty
MRARTSTEPEND:

        * = $3681
MRNCOUNT:.BYTE 0
MRBLACK:LDA #$7B        ; ECM+BMM: an invalid mode, black, with the bad lines (timing) kept
        STA MRMODE+1
        LDA #5 
        STA MRWAIT+1
        RTS
MRGAPEND:
