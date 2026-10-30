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
; Motherships (STATE $80 / $FF) are not ported yet: those sectors are empty here.
; All squadrons fight as type 1 for now.

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
        LDA #$FF        ; SID voice 3 as noise: the map's random numbers ($D41B)
        STA $D40E
        STA $D40F
        LDA #$80
        STA $D412
        LDA $D012       ; the world: the map program's start layout ($20F1)
        ORA #$01
        STA M_SEED
        JSR GENONCE
        JSR SHOWSEC
        JMP SECTORIN

; C= in the cockpit (a new press): the map opens or closes.
MAPTOG: LDA MAPSHOWN
        BEQ MAPOPEN
        JMP MAPCLOSE

MAPOPEN:LDA #$01
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
MAPVB:  LDA #$00
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
g_vs1:  LDA $D012
        CMP #STARLIM
        BCS g_vs9
g_vs2:  JMP STARS
g_vs9:  RTS

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
        JSR SHOWSEC
        JMP SECTORIN
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
        LDA MAPSHOWN
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
        LDA MAPSHOWN
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
WORLD:  JMP M_TICKER

; In the 3D view's free time (at 1 MHz: the vertical blank is full in a fight): a step
; of the squadrons' move, if one is going on, and of a squadron coming in.
VIEWWORK:JSR MVSTEP
        JMP ARRSTEP

; Six sectors a frame of the squadrons' move (the map's MOVEPASS, in steps).
MVSTEP: LDA MVON
        BEQ g_mvs9
        LDA #6
        STA MVN
g_mvs1: JSR M_MOVECELL
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
        LDA #$00
        LDY M_STATE,X
        BEQ g_sin1      ; empty
        BMI g_sin1      ; a mothership: not ported yet
        LDA M_COUNT,X
g_sin1: STA SQCOUNT
        JMP ARRIVE

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
