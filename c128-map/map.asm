; Native C128 test of Sentinel's sector-map grid draw-in (original: $B094-$B269).
; Horizontal lines grow from alternating sides one pixel per frame, a 16 frame
; silent pause follows, then the vertical lines grow from top and bottom.
; The beeping is the original two-voice SID setup ($B26D) with voice 1's gate
; toggled every second frame ($B2BC).
; Pixels use Sentinel's protected multicolor plot ($EF53): value 2 is kept.

SCREEN  = $4400
BITMAP  = $6000
COLOR   = $D800
CIA1PA  = $DC00
CIA1PB  = $DC01
CIA2PA  = $DD00
VICENA  = $D015
BORDER  = $D020
BG      = $D021
FAST    = $D030
MMUCR   = $FF00
YLO     = $2600
YHI     = $2700
XLO     = $2800
XHI     = $2828
POTX    = $D419
POTY    = $D41A
PTR     = $FB
MP      = $FD
STATE   = $2900
COUNT   = $2940

        * = $1D00
START:  SEI
        LDA MMUCR
        STA SAVMMU
        LDA #$0E        ; bank 0 RAM + I/O + KERNAL ROM
        STA MMUCR
        LDA PTR
        STA SAVPTRL
        LDA PTR+1
        STA SAVPTRH
        LDA MP
        STA SAVMPL
        LDA MP+1
        STA SAVMPH
        LDA CIA1PA
        STA SAVPA
        LDA CIA2PA
        STA SAVC2
        LDA $D011
        STA SAV11
        LDA $D016
        STA SAV16
        LDA $D018
        STA SAV18
        LDA VICENA
        STA SAVENA
        LDA BORDER
        STA SAVBOR
        LDA BG
        STA SAVBG
        LDA FAST
        STA SAVFAST
        AND #$FE
        STA FAST

        LDA CIA2PA
        AND #$FC
        ORA #$02        ; VIC bank 1: $4000-$7FFF
        STA CIA2PA
        LDA #$3B        ; display on, 25 rows, bitmap mode
        STA $D011
        LDA #$18        ; 40 columns, multicolor mode
        STA $D016
        LDA #$18        ; screen $4400, bitmap $6000
        STA $D018
        LDA VICENA
        AND #$FE
        STA VICENA
        LDA #0
        STA BORDER
        STA BG

        ; Pixel value 3 comes from color RAM: yellow. Values 1/2 are unused.
        LDX #0
clears: LDA #$00
        STA SCREEN,X
        STA SCREEN+256,X
        STA SCREEN+512,X
        STA SCREEN+768,X
        LDA #$07
        STA COLOR,X
        STA COLOR+256,X
        STA COLOR+512,X
        STA COLOR+768,X
        INX
        BNE clears

        LDA $D012       ; vary the random squadron layout between runs
        ORA #$01
        STA SEED
        LDA #$BF        ; let the SID settle on port 2 before the first read
        STA CIA1PA
        LDX #16
settle1:LDY #0
settle2:DEY
        BNE settle2
        DEX
        BNE settle1
        LDA POTX
        STA OLDX
        LDA POTY
        EOR #$FF
        STA OLDY
        JSR RESET

frame:  LDA $D012
        CMP #$FF
        BEQ frame
waitff: LDA $D012
        CMP #$FF
        BNE waitff

        JSR STEP
        JSR POTS        ; 1351 deltas (port 2 pots were selected last frame)

        LDA #$7F        ; SPACE exits
        STA CIA1PA
        LDA CIA1PB
        AND #$10
        BNE nospace
        JMP EXIT
nospace:LDA #$FB        ; R replays the sweep with a new random layout
        STA CIA1PA
        LDA CIA1PB
        AND #$02
        BNE norep
        JSR RESET
        LDA #$BF
        STA CIA1PA
        JMP frame
norep:  LDA #$FF        ; port 2 joystick / mouse buttons
        STA CIA1PA
        LDA CIA1PA
        AND #$1F
        STA JB
        LDA #$BF        ; select port 2 pots for the next frame
        STA CIA1PA
        JSR CURSOR
        JMP frame

EXIT:   LDA #0
        STA $D404
        STA $D40B
        STA $D418
        LDA SAV11
        STA $D011
        LDA SAV16
        STA $D016
        LDA SAV18
        STA $D018
        LDA SAVENA
        STA VICENA
        LDA SAVC2
        STA CIA2PA
        LDA SAVPA
        STA CIA1PA
        LDA SAVBOR
        STA BORDER
        LDA SAVBG
        STA BG
        LDA SAVFAST
        STA FAST
        LDA SAVMMU
        STA MMUCR
        LDA SAVPTRL
        STA PTR
        LDA SAVPTRH
        STA PTR+1
        LDA SAVMPL
        STA MP
        LDA SAVMPH
        STA MP+1
        CLI
        RTS

; Clear the bitmap, reset the sweep fronts (original setup $B0A2) and sound.
RESET:  LDA #<BITMAP
        STA PTR
        LDA #>BITMAP
        STA PTR+1
        LDX #32
        LDY #0
        TYA
clearb: STA (PTR),Y
        INY
        BNE clearb
        INC PTR+1
        DEX
        BNE clearb
        LDA #$11
        STA FX
        LDA #$8A
        STA FR
        LDA #$23
        STA FT
        LDA #$84
        STA FB
        LDA #0
        STA PHASE
        STA ICONDONE
        STA CURINIT
        STA DELAY
        LDA #1
        STA FIREPREV
        LDX #0          ; icon colors live in the color matrix: clear it
clrmat: LDA #0
        STA SCREEN,X
        STA SCREEN+256,X
        STA SCREEN+512,X
        STA SCREEN+768,X
        INX
        BNE clrmat
        JMP SNDINIT

; One frame of the draw-in.
STEP:   LDA PHASE
        BEQ HORIZ
        CMP #1
        BEQ PAUSEP
        CMP #2
        BEQ stepv
        CMP #3
        BNE steprt
        JMP ICONS
stepv:  JMP VERTP
steprt: RTS

; Seven horizontal lines, 2 px thick: even rows from the left front,
; odd rows from the right front (original $B12F-$B165).
HORIZ:  JSR SNDTOG
        LDX #6
hl:     TXA
        AND #1
        BNE hr
        LDA FX
        JMP hset
hr:     LDA FR
hset:   STA POSX
        LDA YS,X
        STA POSY
        STX SAVEX
        JSR PLOTPIX
        INC POSY
        JSR PLOTPIX
        LDX SAVEX
        DEX
        BPL hl
        INC FX
        DEC FR
        LDA FX
        CMP #$8B
        BCC hret
        LDA #1
        STA PHASE
        LDA #$10
        STA PAUSE
hret:   RTS

; 16 silent frames between the two sweeps (original $B1A5-$B1B7).
PAUSEP: JSR SNDTOG
        DEC PAUSE
        BEQ pend
        LDA #0
        STA $D404
        STA $D40B
        RTS
pend:   LDA #2
        STA PHASE
        JSR SNDINIT
        JMP VERT

; Eleven vertical lines, 2 px wide: even columns from the top front,
; odd columns from the bottom front (original $B1C5-$B268).
VERTP:  JSR SNDTOG
VERT:   LDX #10
vl:     LDA VX,X
        STA POSX
        TXA
        AND #1
        BNE vb
        LDA FT
        JMP vset
vb:     LDA FB
vset:   STA POSY
        STX SAVEX
        JSR PLOTPIX
        INC POSX
        JSR PLOTPIX
        LDX SAVEX
        DEX
        BPL vl
        INC FT
        DEC FB
        LDA FT
        CMP #$85
        BCC vret
        LDA #3
        STA PHASE
        LDA #0
        STA $D404
        STA $D40B
vret:   RTS

; ---- map cursor -----------------------------------------------------
; Original $21C8 / $2384. The cursor is a brown box (pixel value 2) drawn over
; the borders of a sector; erasing it redraws the border in yellow (value 3).
; The selected sector (the player's position, start 4,2) keeps its box.
; Differences from the original: a move is accepted as soon as the 24 frame
; cooldown is over (the original only samples the stick every 24th frame).
CURSOR: LDA ICONDONE
        BNE cur1
        RTS
cur1:   LDA CURINIT
        BNE cur2
        LDA #1
        STA CURINIT
        LDA #4
        STA CURX
        STA SELX
        LDA #2
        STA CURY
        STA SELY
        LDA #0          ; fire not pressed yet
        STA BC          ; (BC/BR/BV set below)
        LDA SELX
        STA BC
        LDA SELY
        STA BR
        LDA #1
        STA BV
        JSR BOX
cur2:   LDA DELAY
        BEQ cur3
        DEC DELAY
cur3:   LDA MPRES       ; with a mouse, its motion becomes directions (original MSYN)
        BEQ curjoy
        LDA #$1F
        LDY MDY
        BEQ cmy0
        BMI cmyu
        AND #$FD        ; back = down
        JMP cmy0
cmyu:   AND #$FE        ; forward = up
cmy0:   LDY MDX
        BEQ cmx0
        BMI cmxl
        AND #$F7        ; right
        JMP cmx0
cmxl:   AND #$FB        ; left
cmx0:   AND #$0F
        STA TMPB
        LDA JB
        AND #$10        ; the mouse's left button is fire
        ORA TMPB
        STA JB
curjoy: LDA JB
        AND #$0F
        CMP #$0F
        BEQ curfire     ; no direction
        LDA DELAY
        BNE curfire
        JMP CURMOVE
curfire:LDA JB
        AND #$10
        BNE fireup
        LDA FIREPREV
        BNE firehd
        LDA #1
        STA FIREPREV
        JMP SELECT
fireup: LDA #0
        STA FIREPREV
firehd: RTS

CURMOVE:LDA CURX
        STA OLDCX
        LDA CURY
        STA OLDCY
        LDA JB
        LSR A           ; bit 0: up
        BCS nu
        DEC CURY
        BPL nu
        LDX #5
        STX CURY
nu:     LSR A           ; bit 1: down
        BCS nd
        INC CURY
        LDX CURY
        CPX #6
        BNE nd
        LDX #0
        STX CURY
nd:     LSR A           ; bit 2: left
        BCS nl
        DEC CURX
        BPL nl
        LDX #9
        STX CURX
nl:     LSR A           ; bit 3: right
        BCS nr
        INC CURX
        LDX CURX
        CPX #10
        BNE nr
        LDX #0
        STX CURX
nr:     LDA OLDCX       ; erase the old box unless it is the selected sector
        CMP SELX
        BNE erold
        LDA OLDCY
        CMP SELY
        BEQ skiper
erold:  LDA OLDCX
        STA BC
        LDA OLDCY
        STA BR
        LDA #0
        STA BV
        JSR BOX
skiper: LDA CURX        ; draw the new box unless it is the selected sector
        CMP SELX
        BNE drnew
        LDA CURY
        CMP SELY
        BEQ skipdr
drnew:  LDA CURX
        STA BC
        LDA CURY
        STA BR
        LDA #1
        STA BV
        JSR BOX
skipdr: LDA SELX       ; repair the selected sector's box: a shared edge of the
        STA BC          ; old box may have been erased (original $2231)
        LDA SELY
        STA BR
        LDA #1
        STA BV
        JSR BOX
        JSR BLIP
        LDA #$18
        STA DELAY
        RTS

; Fire moves the selected sector to the cursor.
SELECT: LDA CURX
        CMP SELX
        BNE selgo
        LDA CURY
        CMP SELY
        BNE selgo
        RTS
selgo:  LDA SELX
        STA BC
        LDA SELY
        STA BR
        LDA #0
        STA BV
        JSR BOX
        LDA CURX
        STA SELX
        STA BC
        LDA CURY
        STA SELY
        STA BR
        LDA #1
        STA BV
        JSR BOX
        JMP BLIP

; Box around sector BC/BR, value 2 (BV=1) or value 3 (BV=0).
BOX:    LDX BC
        LDA CELLX,X
        ASL A
        ASL A
        SEC
        SBC #3
        STA BX1
        CLC
        ADC #12
        STA BX2
        LDX BR
        LDA CELLY,X
        ASL A
        ASL A
        ASL A
        SEC
        SBC #5
        STA BY1
        CLC
        ADC #16
        STA BY2
        LDA #0
        STA BK
bkh:    LDA BX1
        CLC
        ADC BK
        STA POSX
        LDA BY1
        STA POSY
        JSR PLOTBOX
        INC POSY
        JSR PLOTBOX
        LDA BY2
        STA POSY
        JSR PLOTBOX
        INC POSY
        JSR PLOTBOX
        INC BK
        LDA BK
        CMP #13
        BNE bkh
        LDA #0
        STA BK
bkv:    LDA BY1
        CLC
        ADC BK
        STA POSY
        LDA BX1
        STA POSX
        JSR PLOTBOX
        INC POSX
        JSR PLOTBOX
        LDA BX2
        STA POSX
        JSR PLOTBOX
        INC POSX
        JSR PLOTBOX
        INC BK
        LDA BK
        CMP #17
        BNE bkv
        RTS

; Unprotected pixel set to value 2 (BV=1) or value 3 (BV=0), like $EF45.
PLOTBOX:JSR PIXADDR
        LDA (PTR),Y
        AND CLEARM,X
        STA TMPB
        LDA BV
        BNE pbtwo
        LDA TMPB
        ORA MASK3,X
        JMP pbst
pbtwo:  LDA TMPB
        ORA MASK2,X
pbst:   STA (PTR),Y
        RTS

; Original $223D: short click on a cursor move.
BLIP:   LDA #0
        STA $D404
        STA $D406
        STA $D402
        LDA #8
        STA $D403
        LDA #1
        STA $D405
        LDA #$8F
        STA $D401
        LDA #$41
        STA $D404
        RTS

; Commodore 1351 pots -> MDX/MDY (same as Sentinel's MOVCHK).
POTS:   LDA POTX
        CMP #$FF        ; X pot stuck at $FF: no mouse plugged in
        BEQ nomouse
        LDA #1
        BNE setmp
nomouse:LDA #0
setmp:  STA MPRES
        LDA POTX
        LDY OLDX
        JSR MOVCHK
        STA MDX
        TYA
        STA OLDX
        LDA POTY
        EOR #$FF
        LDY OLDY
        JSR MOVCHK
        STA MDY
        TYA
        STA OLDY
        RTS

MOVCHK: STY OLDV
        TAY
        SEC
        SBC OLDV
        ASL A
        CMP #$80
        ROR A
        CMP #$FF
        BEQ mvzero
        CMP #$80
        ROR A
        BEQ mvzero
        RTS
mvzero: LDY OLDV
        LDA #0
        RTS

; ---- sector icons ---------------------------------------------------
; Sector state follows the original tables: STATE ($033C) $00 empty,
; $80 orange mothership, $FF blue mothership, $01-$03 squadron type (color);
; COUNT ($0378) is the squadron size: 1-3 draws one icon, 4-6 two, 7+ three.
; DRAWCELL can be called for any single cell, so later animation (moving
; squadrons, blinking motherships) only has to change STATE/COUNT and redraw.
ICONS:  LDA ICONDONE
        BNE iconret
        JSR GENERATE
        JSR DRAWALL
        LDA #1
        STA ICONDONE
iconret:RTS

; Motherships at the four corners (orange) and near them (blue) as in the
; original layout, plus randomly placed squadrons of different types.
GENERATE:
        LDX #59
        LDA #0
genclr: STA STATE,X
        STA COUNT,X
        DEX
        BPL genclr
        LDY #3
gencor: LDX CORN,Y
        LDA #$80
        STA STATE,X
        LDA #1
        STA COUNT,X
        DEY
        BPL gencor
        LDY #3
geninn: LDX INNER,Y
        LDA #$FF
        STA STATE,X
        DEY
        BPL geninn
        LDA #16
        STA NSQ
gensq:  JSR RANDOM
        AND #$3F
        CMP #60
        BCS gensq
        TAX
        LDA STATE,X
        BNE gensq
        STX IDX
        JSR RANDOM
        AND #$03
        TAY
        LDA STSEL,Y
        LDX IDX
        STA STATE,X
        JSR RANDOM
        AND #$0F
        TAY
        LDA CNTSEL,Y
        STA COUNT,X
        DEC NSQ
        BNE gensq
        RTS

DRAWALL:LDA #0
        STA IDX
        STA ROW
drow:   LDA #0
        STA COL
dcol:   JSR DRAWCELL
        INC IDX
        INC COL
        LDA COL
        CMP #10
        BNE dcol
        INC ROW
        LDA ROW
        CMP #6
        BNE drow
        RTS

; Draw the icon of sector IDX at grid cell ROW/COL (original $2301/$22F0/$232E).
DRAWCELL:
        LDX IDX
        LDA STATE,X
        BNE dc1
        RTS
dc1:    CMP #$80
        BNE dc2
        LDA #1          ; orange saucer, glyph $67, color $18
        LDY #$18
        JMP dcset
dc2:    CMP #$FF
        BNE dc3
        LDA #0          ; blue saucer, glyph $66, color $16
        LDY #$16
        JMP dcset
dc3:    TAX
        DEX
        LDY CT,X
        LDX IDX
        LDA COUNT,X
        CMP #4
        BCC dc4
        CMP #7
        BCC dc5
        LDA #4          ; three icons, glyph $6A
        JMP dcset
dc5:    LDA #3          ; two icons, glyph $69
        JMP dcset
dc4:    LDA #2          ; one icon, glyph $68
dcset:  STA GLY
        STY COLC
        ; cell offset = cy*40 + cx
        LDX ROW
        LDA CELLY,X
        STA OFFL
        LDA #0
        STA OFFH
        ASL OFFL
        ROL OFFH
        ASL OFFL
        ROL OFFH
        ASL OFFL
        ROL OFFH
        LDA OFFL
        STA TL
        LDA OFFH
        STA TH
        ASL OFFL
        ROL OFFH
        ASL OFFL
        ROL OFFH
        CLC
        LDA OFFL
        ADC TL
        STA OFFL
        LDA OFFH
        ADC TH
        STA OFFH
        LDX COL
        CLC
        LDA OFFL
        ADC CELLX,X
        STA OFFL
        BCC dcnc
        INC OFFH
dcnc:   ; color matrix: both icon cells get the color code
        CLC
        LDA OFFL
        ADC #<SCREEN
        STA MP
        LDA OFFH
        ADC #>SCREEN
        STA MP+1
        LDY #0
        LDA COLC
        STA (MP),Y
        INY
        STA (MP),Y
        ; bitmap address = BITMAP + offset*8
        ASL OFFL
        ROL OFFH
        ASL OFFL
        ROL OFFH
        ASL OFFL
        ROL OFFH
        CLC
        LDA OFFL
        ADC #<BITMAP
        STA PTR
        LDA OFFH
        ADC #>BITMAP
        STA PTR+1
        ; expand the 8x8 glyph: high nibble -> left cell, low nibble -> right
        LDA GLY
        ASL A
        ASL A
        ASL A
        STA GX
        LDA #0
        STA RR
dgl:    LDA RR
        CLC
        ADC GX
        TAX
        LDA GLYPHS,X
        STA SRC
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA EXPT,X
        LDY RR
        STA (PTR),Y
        LDA SRC
        AND #$0F
        TAX
        LDA EXPT,X
        PHA
        LDA RR
        CLC
        ADC #8
        TAY
        PLA
        STA (PTR),Y
        INC RR
        LDA RR
        CMP #8
        BNE dgl
        RTS

RANDOM: LDA SEED
        ASL A
        BCC randok
        EOR #$1D
randok: STA SEED
        RTS

; Original $B26D: voice 1 and 2 pulse waves, gate on, volume 15.
SNDINIT:LDA #0
        STA $D404
        STA $D40B
        STA $D400
        STA $D407
        STA $D402
        STA $D409
        LDA #$2B
        STA $D401
        LDA #$12
        STA $D408
        LDA #$01
        STA $D403
        LDA #$0A
        STA $D40A
        LDA #0
        STA $D405
        STA $D40C
        LDA #$80
        STA $D406
        LDA #$20
        STA $D40D
        LDA #$0F
        STA $D418
        LDA #$41
        STA $D404
        STA $D40B
        STA SNDVAL
        LDA #2
        STA SNDCNT
        RTS

; Original $B2BC: toggle voice 1's gate every second frame.
SNDTOG: DEC SNDCNT
        BNE sndret
        LDA #2
        STA SNDCNT
        LDA SNDVAL
        EOR #$01
        STA SNDVAL
        STA $D404
sndret: RTS

; Sentinel's protected multicolor pixel plot ($EF53): pixel value 2 is kept.
PLOTPIX:
        JSR PIXADDR
        LDA (PTR),Y
        AND MASK3,X
        CMP MASK2,X
        BEQ plotret
        LDA (PTR),Y
        AND CLEARM,X
        ORA MASK3,X
        STA (PTR),Y
plotret:RTS

PIXADDR:
        LDY POSY
        LDA YLO,Y
        STA PTR
        LDA YHI,Y
        CLC
        ADC #$60
        STA PTR+1
        LDA POSX
        LSR A
        LSR A
        TAX
        LDA XLO,X
        CLC
        ADC PTR
        STA PTR
        LDA XHI,X
        ADC PTR+1
        STA PTR+1
        LDY #0
        LDA POSX
        AND #$03
        TAX
        RTS

CLEARM: .BYTE $3F,$CF,$F3,$FC
MASK2:  .BYTE $80,$20,$08,$02
MASK3:  .BYTE $C0,$30,$0C,$03
; Original tables $B08A (rows) and $B07F (columns), in multicolor pixels.
YS:     .BYTE 35,51,67,83,99,115,131
VX:     .BYTE 17,29,41,53,65,77,89,101,113,125,137

; Glyph shapes copied from the game's character set ($4330-$4357):
; blue saucer, orange saucer, 1/2/3 squadron icons.
GLYPHS: .BYTE $00,$18,$7E,$E7,$FF,$7E,$3C,$00
        .BYTE $00,$3C,$7E,$E7,$FF,$7E,$3C,$00
        .BYTE $00,$00,$08,$1C,$08,$00,$00,$00
        .BYTE $00,$20,$70,$20,$00,$04,$0E,$04
        .BYTE $10,$38,$10,$02,$07,$42,$E0,$40
; nibble -> 4 multicolor pixels of value 2 (original $9BB8 / $EE52 tables)
EXPT:   .BYTE $00,$02,$08,$0A,$20,$22,$28,$2A,$80,$82,$88,$8A,$A0,$A2,$A8,$AA
CELLX:  .BYTE 5,8,11,14,17,20,23,26,29,32
CELLY:  .BYTE 5,7,9,11,13,15
CT:     .BYTE $1E,$1D,$14
CORN:   .BYTE 0,9,50,59
INNER:  .BYTE 12,17,42,47
STSEL:  .BYTE 1,2,3,2
CNTSEL: .BYTE 1,1,2,2,3,3,4,5,6,7,8,9,1,2,3,5
SEED:   .BYTE $A7
JB:     .BYTE $1F
MPRES:  .BYTE 0
MDX:    .BYTE 0
MDY:    .BYTE 0
OLDX:   .BYTE 0
OLDY:   .BYTE 0
OLDV:   .BYTE 0
CURINIT:.BYTE 0
DELAY:  .BYTE 0
CURX:   .BYTE 0
CURY:   .BYTE 0
SELX:   .BYTE 0
SELY:   .BYTE 0
OLDCX:  .BYTE 0
OLDCY:  .BYTE 0
BC:     .BYTE 0
BR:     .BYTE 0
BV:     .BYTE 0
BK:     .BYTE 0
BX1:    .BYTE 0
BX2:    .BYTE 0
BY1:    .BYTE 0
BY2:    .BYTE 0
TMPB:   .BYTE 0
ICONDONE:.BYTE 0
NSQ:    .BYTE 0
IDX:    .BYTE 0
ROW:    .BYTE 0
COL:    .BYTE 0
GLY:    .BYTE 0
GX:     .BYTE 0
RR:     .BYTE 0
SRC:    .BYTE 0
COLC:   .BYTE 0
OFFL:   .BYTE 0
OFFH:   .BYTE 0
TL:     .BYTE 0
TH:     .BYTE 0
FX:     .BYTE 0
FR:     .BYTE 0
FT:     .BYTE 0
FB:     .BYTE 0
PHASE:  .BYTE 0
PAUSE:  .BYTE 0
SNDCNT: .BYTE 0
SNDVAL: .BYTE 0
FIREPREV:.BYTE 0
POSX:   .BYTE 0
POSY:   .BYTE 0
SAVEX:  .BYTE 0
SAVPA:  .BYTE 0
SAVC2:  .BYTE 0
SAV11:  .BYTE 0
SAV16:  .BYTE 0
SAV18:  .BYTE 0
SAVENA: .BYTE 0
SAVBOR: .BYTE 0
SAVBG:  .BYTE 0
SAVFAST:.BYTE 0
SAVMMU: .BYTE 0
SAVPTRL:.BYTE 0
SAVPTRH:.BYTE 0
SAVMPL: .BYTE 0
SAVMPH: .BYTE 0
