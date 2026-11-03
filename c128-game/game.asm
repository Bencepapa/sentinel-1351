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
        LDA $D012       ; the world: the map program's start layout ($20F1)
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
g_mk3:  LDA #$80
        STA RCNT
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
g_vs1:  LDA APPR        ; (approaching, a rush's star steps do not fit after the wrap)
        BNE g_vs9
        LDA $D012
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
; The world's clock ($BE29). The original calls it from its main loops, which are not
; tied to the frame, so its rate depends on what the ship does; measured on a real
; machine's timing (JS machine with m.dma): a tick every 33 frames with the map open,
; 44 in flight (and in hyperspace), 54 in a fight, 200 while the tracking computer
; flies. (The map program ticks every 256 frames, about five times slower.)
WORLD:  LDA GENDONE     ; (the world exists)
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
VIEWWORK:LDA WTPEND
        BEQ g_vw1
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

; ---------------- $C000-$CFFF: RAM under the KERNAL (MMU $3E, set at START) ----------------
; The map's code ends at $BFF7, the glue's room is small: new code goes here. The
; game calls no KERNAL routine and runs with interrupts off; NMIRTI keeps RESTORE
; harmless while the KERNAL's vectors are not visible.

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
HSCANGO:LDA HTGTY       ; the destination's sector
        ASL A
        ASL A
        CLC
        ADC HTGTY
        ASL A
        CLC
        ADC HTGTX
        TAX
        LDA #$00
        LDY M_STATE,X
        BEQ g_sg1       ; empty
        BMI g_sg1       ; a mothership: not ported yet
        LDA M_COUNT,X
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
g_hv0:  JSR HENGINE
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
        LDA #$04        ; the engine falls ($B6CF)
        STA HESTP
        LDA #$00
        STA HEDIR
        JMP g_hvst
g_hv30: LDA HTIME       ; 3: decelerating
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
HYPMVB: LDA HMAP        ; the planet turns while the map is there
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
g_hm8:  LDA CRUN        ; the radar's circle being drawn (about 100 lines): no
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
        BNE HSTARS
        RTS
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
        BEQ g_hv9
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
; C set: no more time for the stars. When the radar runs in this vertical blank
; (the scanner's marks: about 50 lines from the wrap) they stop at line 296; the
; rest go on in the next frame.
HSTLATE:LDA HNORAD
        BNE g_hl8
        LDA EFRM
        AND #$01
        BEQ g_hl1
        LDA RADPEND
        BEQ g_hl8
g_hl1:  BIT $D011
        BPL g_hl8
        LDA $D012
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
        LDA HMAP
        BNE g_hp1
        LDA (PTR),Y
        ORA MASK3,X
        JMP g_hp2
g_hp1:  LDA (PTR),Y     ; over the map: value 1, on an empty pixel only
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
        LDA HMAP
        BEQ g_hq1
        LDA (PTR),Y     ; over the map: only a star's own value 1
        AND MASK3,X
        CMP MASK1,X
        BNE g_hq2
g_hq1:  LDA (PTR),Y
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
        LDA HD100       ; 0 or 1: '1' or a blank
        BEQ g_hd3
        LDA #$71
        BNE g_hd4
g_hd3:  LDA #$20
g_hd4:  LDX #16
        JSR HBIG
        LDA HD10
        ORA #$70
        LDX #18
        JSR HBIG
        LDA HD1
        ORA #$70
        LDX #20
        JMP HBIG
HCLRDIG:LDA #$20
        LDX #16
        JSR HBIG
        LDA #$20
        LDX #18
        JSR HBIG
        LDA #$20
        LDX #20
        JMP HBIG
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
