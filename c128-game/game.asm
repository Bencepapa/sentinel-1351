; Sentinel C128: the cockpit and the sector map as one program.
;
; This file is only the glue. c128-game/build.py joins three sources into one
; program: c128-gui/cockpit/cockpit.asm (its hooks INPUTV / VIEWVB / TICKHK /
; KILLHK / EMPTYHK and a few marked patches), c128-map/map.asm (every label it
; defines gets the prefix M_, its code goes right after the cockpit's code, its
; second-display data to $2900) and this file.
;
; As in the original, the map opens in the cockpit's 3D view: C= opens and
; closes it, the HUD, the radar, the guns and the scanner row stay. The view turns
; white and the map's grid draws in; meanwhile the fight goes on: the fighters fly
; behind the map's lines, enemy shots still hit the ship (no phasor and no
; steering while the map is open: the mouse moves the map's cursor). Fire on
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

GAMEINIT:               ; once, from the cockpit's START
        LDA #$FF        ; SID voice 3 as noise: the map's random numbers ($D41B)
        STA $D40E
        STA $D40F
        LDA #$80
        STA $D412
        LDA $D012       ; the world: the map program's start layout ($20F1)
        ORA #$01
        STA M_SEED
        JSR M_GENONCE
        JSR SHOWSEC
        JMP SECTORIN

; C= in the cockpit (a new press): the map opens or closes.
MAPTOG: LDA MAPSHOWN
        BEQ MAPOPEN
        JMP MAPCLOSE

MAPOPEN:LDA #$01
        STA MAPSHOWN
        STA VIEWBG      ; white
        LDA #$70        ; the fighters behind the map's lines
        STA MAPPRIO
        LDA #$00        ; no explosions over the map (their points would stay)
        STA EXPL
        STA EXPL2
        STA MJUMPF
        STA SHOTVIS
        STA M_ICONDONE  ; (nothing of the map before its set-up)
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
        LDA #$09        ; (pixel value 2, the cursor's boxes: brown, as in the
        STA (CDST),Y    ; original's map in flight)
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
        JMP M_RESET
g_wr9:  RTS

; The map's share of the vertical blank (2 MHz) while it is open.
MAPVB:  LDA WIPE
        BEQ g_mv0
        JMP WIPEROW
g_mv0:  JSR M_STEP      ; the grid's draw-in, then the icons
        JSR M_BLINK
        JSR M_PLANET
        LDA M_ICONDONE
        BEQ g_mv9
        JMP DRAWSOME
g_mv9:  RTS

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
        LDA #60
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
        JSR M_CURSOR
        LDA MJUMPF
        BEQ g_mi9
        LDA #$00
        STA MJUMPF
        JSR MAPCLOSE
        JSR SHOWSEC
        JMP SECTORIN
g_mi9:  RTS

; The world's clock, every frame (the map's TICKER: a tick every 256 frames).
WORLD:  JMP M_TICKER

; Row tables for WIPEROW (index WIPE-1: rows 3-17).
ROWLO:  .BYTE $C0,$00,$40,$80,$C0,$00,$40,$80,$C0,$00,$40,$80,$C0,$00,$40
ROWHI:  .BYTE $63,$65,$66,$67,$68,$6A,$6B,$6C,$6D,$6F,$70,$71,$72,$74,$75
ROWCL:  .BYTE $78,$A0,$C8,$F0,$18,$40,$68,$90,$B8,$E0,$08,$30,$58,$80,$A8
ROWCH:  .BYTE $00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$02,$02,$02,$02,$02

; Into the sector M_SELX / M_SELY: its squadron's ships (none for an empty or a
; mothership sector), then the cockpit's arrival (the approach, ARRIVE).
SECTORIN:
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
CPREV:  .BYTE 0         ; C= / SPACE held (edges only)
SPREV:  .BYTE 0
SKX:    .BYTE 0
DSI:    .BYTE 0
DSN:    .BYTE 0
DSK:    .BYTE 0
