; Native C128 flight-kernel test with a point-star perspective field.
; The retained seven-pixel squadron-marker walk and protected multicolor-pixel
; semantics correspond to the original routines at $3166/$3138 and $EF53/$EEE6.

SCREEN  = $4400
BITMAP  = $6000
COLOR   = $D800
POTX    = $D419
POTY    = $D41A
CIA1PA  = $DC00
CIA2PA  = $DD00
VICENA  = $D015
VICMSB  = $D010
VICYEXP = $D017
VICPRI  = $D01B
VICMC   = $D01C
VICXEXP = $D01D
BORDER  = $D020
BG      = $D021
SPR1COL = $D028
FAST    = $D030
MMUCR   = $FF00
SPRPTR1 = $47F9
SPRDATA = $5FC0
YLO     = $2600
YHI     = $2700
XLO     = $2800
XHI     = $2828
LASERX  = $2900
LASERY  = $2A00
PTR     = $FB
COUNT   = 12

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
        LDA VICMSB
        STA SAVMSB
        LDA VICYEXP
        STA SAVYEXP
        LDA VICPRI
        STA SAVPRI
        LDA VICMC
        STA SAVMC
        LDA VICXEXP
        STA SAVXEXP
        LDA $D002
        STA SAVS1X
        LDA $D003
        STA SAVS1Y
        LDA SPR1COL
        STA SAVS1COL
        LDA SPRPTR1
        STA SAVS1PTR
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
        AND #$FC
        STA VICENA
        LDA #0
        STA BORDER
        STA BG

        LDX #63
        LDA #0
clearsp:STA SPRDATA,X
        DEX
        BPL clearsp
        LDA #$80        ; narrow five-row multicolor laser bolt
        STA SPRDATA
        STA SPRDATA+3
        STA SPRDATA+6
        STA SPRDATA+9
        STA SPRDATA+12
        LDA #$7F
        STA SPRPTR1
        LDA VICMC
        ORA #$02
        STA VICMC
        LDA VICYEXP
        AND #$FD
        STA VICYEXP
        LDA VICXEXP
        AND #$FD
        STA VICXEXP
        LDA VICPRI
        AND #$FD
        STA VICPRI
        LDA #7
        STA SPR1COL

        ; Clear the 8K bitmap.
        LDA #<BITMAP
        STA PTR
        LDA #>BITMAP
        STA PTR+1
        LDX #32
        LDY #0
        LDA #0
clearb: STA (PTR),Y
        INY
        BNE clearb
        INC PTR+1
        DEX
        BNE clearb

        ; Bitmap colors: pixel value 2 is blue and protected from stars;
        ; pixel value 3 is light gray from color RAM.
        LDX #0
        LDA #$16
clears: STA SCREEN,X
        STA SCREEN+256,X
        STA SCREEN+512,X
        STA SCREEN+768,X
        LDA #$0F
        STA COLOR,X
        STA COLOR+256,X
        STA COLOR+512,X
        STA COLOR+768,X
        LDA #$16
        INX
        BNE clears

        LDA #$BF
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

        LDA OLDX
        EOR OLDY
        EOR SEED
        BNE seedok
        LDA #$A7
seedok: STA SEED
        JSR INITSTARS

        LDX #COUNT-1
first:  LDA STARSX,X
        STA POSX
        LDA STARSY,X
        STA POSY
        JSR DRAWPOINT
        DEX
        BPL first

frame:  LDA $D012
        CMP #$FF
        BEQ frame
waitff: LDA $D012
        CMP #$FF
        BNE waitff

        LDA FAST        ; 2 MHz in the border: every star is redrawn before the
        ORA #$01        ; frame wraps
        STA FAST

        LDX #COUNT-1
erase:  LDA STARSX,X
        STA POSX
        LDA STARSY,X
        STA POSY
        JSR ERASEPOINT
        DEX
        BPL erase

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

        JSR MOVEVP
        LDX #COUNT-1
move:   JSR MOVESTAR
        DEX
        BPL move

        LDX #COUNT-1
draw:   LDA STARSX,X
        STA POSX
        LDA STARSY,X
        STA POSY
        JSR DRAWPOINT
        DEX
        BPL draw

        LDA FAST        ; 1 MHz again before the display window
        AND #$FE
        STA FAST

        JSR LASER

        LDA CIA1PA
        AND #$11
        BNE frame

        LDA SAV11
        STA $D011
        LDA SAV16
        STA $D016
        LDA SAV18
        STA $D018
        LDA SAVENA
        STA VICENA
        LDA SAVMSB
        STA VICMSB
        LDA SAVYEXP
        STA VICYEXP
        LDA SAVPRI
        STA VICPRI
        LDA SAVMC
        STA VICMC
        LDA SAVXEXP
        STA VICXEXP
        LDA SAVS1X
        STA $D002
        LDA SAVS1Y
        STA $D003
        LDA SAVS1COL
        STA SPR1COL
        LDA SAVS1PTR
        STA SPRPTR1
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
        CLI
        RTS

; Move the vanishing point with the mouse, keeping resets on screen.
MOVEVP: LDA MDX
        BMI mvxneg
        LDA VPX
        CLC
        ADC MDX
        CMP #121
        BCC mvxstore
mvxhi:  LDA #120
        BNE mvxstore
mvxneg: LDA VPX
        CLC
        ADC MDX
        BCC mvxlo
        CMP #40
        BCS mvxstore
mvxlo:  LDA #40
mvxstore:
        STA VPX

        LDA MDY
        BMI mvyneg
        LDA VPY
        CLC
        ADC MDY
        CMP #151
        BCC mvystore
mvyhi:  LDA #150
        BNE mvystore
mvyneg: LDA VPY
        CLC
        ADC MDY
        BCC mvylo
        CMP #50
        BCS mvystore
mvylo:  LDA #50
mvystore:
        STA VPY
        RTS

; One simple perspective step: points move away from the mouse-controlled
; vanishing point. Boundary crossings respawn at random screen positions.
MOVESTAR:
        LDA STARSX,X
        CMP VPX
        BCC mxleft
        CLC
        ADC SPEED,X
        CMP #157
        BCS respawn
        BCC mxstore
mxleft: SEC
        SBC SPEED,X
        BCC respawn
        CMP #2
        BCC respawn
mxstore:STA STARSX,X

        LDA STARSY,X
        CMP VPY
        BCC myup
        CLC
        ADC SPEED,X
        CMP #197
        BCS respawn
        BCC mystore
myup:   SEC
        SBC SPEED,X
        BCC respawn
        CMP #2
        BCC respawn
mystore:STA STARSY,X
        RTS

respawn:
RANDOMPOS:
randx:  JSR RANDOM
        CMP #155
        BCS randx
        CLC
        ADC #2
        STA STARSX,X
randy:  JSR RANDOM
        CMP #195
        BCS randy
        CLC
        ADC #2
        STA STARSY,X
        RTS

INITSTARS:
        LDX #COUNT-1
initone:JSR RANDOMPOS
        DEX
        BPL initone
        RTS

RANDOM: LDA SEED
        ASL A
        BCC randok
        EOR #$1D
randok: STA SEED
        RTS

; Commodore 1351 delta conversion, identical to Sentinel's MOVCHK logic.
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

; The original laser also builds an X/Y point list and advances sprite 1
; through it. This isolated version aims from the lower center at the current
; mouse-controlled vanishing point and deliberately omits collision and sound.
LASER:  LDA LASERACTIVE
        BNE STEPLASER
        LDA CIA1PA
        AND #$10
        BNE laserret
        JSR STARTLASER
STEPLASER:
        LDY LASERPOS
        CPY LASERLEN
        BCS ENDLASER
        LDA LASERX,Y
        ASL A
        STA LASERXLO
        LDA #0
        ROL A
        STA LASERXHI
        LDA LASERXLO
        CLC
        ADC #24
        STA $D002
        LDA LASERXHI
        ADC #0
        BEQ laserlo
        LDA VICMSB
        ORA #$02
        BNE lasermsb
laserlo:LDA VICMSB
        AND #$FD
lasermsb:
        STA VICMSB
        LDA LASERY,Y
        CLC
        ADC #50
        STA $D003
        TYA
        CLC
        ADC #3
        STA LASERPOS
laserret:
        RTS

ENDLASER:
        LDA VICENA
        AND #$FD
        STA VICENA
        LDA #0
        STA LASERACTIVE
        RTS

STARTLASER:
        LDA #80
        STA LINEX
        LDA #188
        STA LINEY
        LDA VPX
        STA TARGETX
        LDA VPY
        STA TARGETY
        JSR GENLASER
        LDA #0
        STA LASERPOS
        LDA #1
        STA LASERACTIVE
        LDA VICENA
        ORA #$02
        STA VICENA
        RTS

; Bresenham point-list generator corresponding to the role of Sentinel's
; $3580 routine. Coordinates are kept in the harness's 160x200 bitmap space.
GENLASER:
        LDA #1
        STA STEPX
        STA STEPY
        LDA TARGETX
        CMP LINEX
        BCS gxright
        LDA LINEX
        SEC
        SBC TARGETX
        STA DELTAX
        LDA #$FF
        STA STEPX
        BNE gydelta
gxright:SEC
        SBC LINEX
        STA DELTAX
gydelta:LDA TARGETY
        CMP LINEY
        BCS gydown
        LDA LINEY
        SEC
        SBC TARGETY
        STA DELTAY
        LDA #$FF
        STA STEPY
        BNE chooseaxis
gydown: SEC
        SBC LINEY
        STA DELTAY

chooseaxis:
        LDA DELTAX
        CMP DELTAY
        BCC ymajor
        STA MAJOR
        LDA DELTAY
        STA MINOR
        LDA STEPX
        STA MAJORX
        LDA #0
        STA MAJORY
        STA MINORX
        LDA STEPY
        STA MINORY
        JMP genstart
ymajor:LDA DELTAY
        STA MAJOR
        LDA DELTAX
        STA MINOR
        LDA #0
        STA MAJORX
        STA MINORY
        LDA STEPY
        STA MAJORY
        LDA STEPX
        STA MINORX

genstart:
        LDA MAJOR
        LSR A
        STA ERRORLO
        LDA #0
        STA ERRORHI
        STA LASERLEN
        LDA MAJOR
        BEQ gendone

genloop:LDA LINEX
        CLC
        ADC MAJORX
        STA LINEX
        LDA LINEY
        CLC
        ADC MAJORY
        STA LINEY
        LDA ERRORLO
        CLC
        ADC MINOR
        STA ERRORLO
        LDA ERRORHI
        ADC #0
        STA ERRORHI
        BNE dominor
        LDA ERRORLO
        CMP MAJOR
        BCC storepoint
        BEQ storepoint
dominor:
        LDA ERRORLO
        SEC
        SBC MAJOR
        STA ERRORLO
        LDA ERRORHI
        SBC #0
        STA ERRORHI
        LDA LINEX
        CLC
        ADC MINORX
        STA LINEX
        LDA LINEY
        CLC
        ADC MINORY
        STA LINEY
storepoint:
        LDX LASERLEN
        LDA LINEX
        STA LASERX,X
        LDA LINEY
        STA LASERY,X
        INC LASERLEN
        LDA LASERLEN
        CMP MAJOR
        BCC genloop
gendone:RTS

; Pixel routines use X as a mask index, so preserve the star-array index.
ERASEPOINT:
        STX SAVEX
        JSR ERASEPIX
        LDX SAVEX
        RTS

DRAWPOINT:
        STX SAVEX
        JSR PLOTPIX
        LDX SAVEX
        RTS

; Original Sentinel seven-pixel hostile-squadron marker walk (a small H).
ERASE7:STX SAVEX
        STY SAVEY
        JSR ERASEPIX
        INC POSY
        JSR ERASEPIX
        INC POSY
        JSR ERASEPIX
        INC POSX
        INC POSX
        JSR ERASEPIX
        DEC POSY
        JSR ERASEPIX
        DEC POSY
        JSR ERASEPIX
        DEC POSX
        INC POSY
        JSR ERASEPIX
        LDX SAVEX
        LDY SAVEY
        RTS

DRAW7: STX SAVEX
        STY SAVEY
        JSR PLOTPIX
        INC POSY
        JSR PLOTPIX
        INC POSY
        JSR PLOTPIX
        INC POSX
        INC POSX
        JSR PLOTPIX
        DEC POSY
        JSR PLOTPIX
        DEC POSY
        JSR PLOTPIX
        DEC POSX
        INC POSY
        JSR PLOTPIX
        LDX SAVEX
        LDY SAVEY
        RTS

; Preserve multicolor value 2, just like Sentinel's $EEE6/$EF53 primitives.
ERASEPIX:
        JSR PIXADDR
        LDA (PTR),Y
        AND MASK3,X
        CMP MASK2,X
        BEQ pixret
        LDA (PTR),Y
        AND CLEARM,X
        STA (PTR),Y
pixret: RTS

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

; Table-assisted equivalent of Sentinel's bitmap address calculation.
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
SPEED:  .BYTE 1,1,1,1,2,2,2,2,3,3,3,3
STARSX: .BYTE 76,83,70,91,60,101,48,112,35,128,20,143
STARSY: .BYTE 96,104,88,112,76,124,63,137,48,152,32,168

VPX:    .BYTE 80
VPY:    .BYTE 100
SEED:   .BYTE $A7
POSX:   .BYTE 0
POSY:   .BYTE 0
MDX:    .BYTE 0
MDY:    .BYTE 0
OLDX:   .BYTE 0
OLDY:   .BYTE 0
OLDV:   .BYTE 0
SAVEX:  .BYTE 0
SAVEY:  .BYTE 0
SAVPA:  .BYTE 0
SAVC2:  .BYTE 0
SAV11:  .BYTE 0
SAV16:  .BYTE 0
SAV18:  .BYTE 0
SAVENA: .BYTE 0
SAVMSB: .BYTE 0
SAVYEXP:.BYTE 0
SAVPRI: .BYTE 0
SAVMC:  .BYTE 0
SAVXEXP:.BYTE 0
SAVS1X: .BYTE 0
SAVS1Y: .BYTE 0
SAVS1COL:.BYTE 0
SAVS1PTR:.BYTE 0
SAVBOR: .BYTE 0
SAVBG:  .BYTE 0
SAVFAST:.BYTE 0
SAVMMU: .BYTE 0
SAVPTRL:.BYTE 0
SAVPTRH:.BYTE 0
LASERACTIVE:.BYTE 0
LASERPOS:.BYTE 0
LASERLEN:.BYTE 0
LASERXLO:.BYTE 0
LASERXHI:.BYTE 0
LINEX:  .BYTE 0
LINEY:  .BYTE 0
TARGETX:.BYTE 0
TARGETY:.BYTE 0
DELTAX: .BYTE 0
DELTAY: .BYTE 0
STEPX:  .BYTE 0
STEPY:  .BYTE 0
MAJOR:  .BYTE 0
MINOR:  .BYTE 0
MAJORX: .BYTE 0
MAJORY: .BYTE 0
MINORX: .BYTE 0
MINORY: .BYTE 0
ERRORLO:.BYTE 0
ERRORHI:.BYTE 0
