; Native C128 flight-kernel test based on Sentinel's squadron-marker renderer.
; The seven-pixel draw/erase walk and protected multicolor-pixel semantics
; correspond to the original routines at $3166/$3138 and $EF53/$EEE6.

SCREEN  = $4400
BITMAP  = $6000
COLOR   = $D800
POTX    = $D419
POTY    = $D41A
CIA1PA  = $DC00
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

        ; Bitmap colors: pixel value 2 is blue and protected from markers;
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

        LDX #COUNT-1
first:  LDA STARSX,X
        STA POSX
        LDA STARSY,X
        STA POSY
        JSR DRAW7
        DEX
        BPL first

frame:  LDA $D012
        CMP #$FF
        BEQ frame
waitff: LDA $D012
        CMP #$FF
        BNE waitff

        LDX #COUNT-1
erase:  LDA STARSX,X
        STA POSX
        LDA STARSY,X
        STA POSY
        JSR ERASE7
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
        JSR DRAW7
        DEX
        BPL draw

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
; vanishing point. Boundary crossings respawn close to that point.
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

respawn:JSR RANDOM
        AND #$1F
        SEC
        SBC #16
        CLC
        ADC VPX
        STA STARSX,X
        JSR RANDOM
        AND #$1F
        SEC
        SBC #16
        CLC
        ADC VPY
        STA STARSY,X
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
SAVBOR: .BYTE 0
SAVBG:  .BYTE 0
SAVFAST:.BYTE 0
SAVMMU: .BYTE 0
SAVPTRL:.BYTE 0
SAVPTRH:.BYTE 0
