; Native C128 40-column smoke test for the Sentinel 1351 input path.
; Started from BASIC 7 with SYS 7424 ($1D00).

SCREEN  = $0400
COLOR   = $D800
VICX    = $D000
VICY    = $D001
VICMSB  = $D010
VICENA  = $D015
BORDER  = $D020
VICMEM  = $D018
FAST    = $D030
POTX    = $D419
POTY    = $D41A
CIA1PA  = $DC00
CIA2PA  = $DD00
MMUCR   = $FF00

        * = $1D00
START:  SEI
        LDA CIA1PA
        STA SAVPA
        LDA CIA2PA
        STA SAVC2
        LDA VICMEM
        STA SAVMEM
        LDA VICENA
        STA SAVENA
        LDA VICMSB
        STA SAVMSB
        LDA $07F8
        STA SAVPTR
        LDA FAST
        STA SAVFAST
        AND #$FE        ; keep the VIC-visible part at 1 MHz
        STA FAST

        LDA CIA2PA
        ORA #$03        ; VIC bank 0
        STA CIA2PA
        LDA #$14        ; screen $0400, standard character ROM
        STA VICMEM
        LDA #$BF        ; select control port 2 for SID POT sampling
        STA CIA1PA

        LDX #0
        LDA #$20
clear:  STA SCREEN,X
        STA SCREEN+256,X
        STA SCREEN+512,X
        STA SCREEN+768,X
        LDA #$01
        STA COLOR,X
        STA COLOR+256,X
        STA COLOR+512,X
        STA COLOR+768,X
        LDA #$20
        INX
        BNE clear

        LDX #0
copy:   LDA TITLE,X
        BEQ copied
        STA SCREEN+40,X
        LDA #$07
        STA COLOR+40,X
        INX
        BNE copy
copied: LDX #0
copy2:  LDA INFO,X
        BEQ copied2
        STA SCREEN+120,X
        LDA #$0D
        STA COLOR+120,X
        INX
        BNE copy2
copied2:
        LDX #0
copy3:  LDA STATUS,X
        BEQ copied3
        STA SCREEN+200,X
        LDA #$0D
        STA COLOR+200,X
        INX
        BNE copy3
copied3:
        LDA MMUCR
        LDY #210
        JSR HEXOUT
        LDA SAVFAST
        LDY #219
        JSR HEXOUT

        LDA #160
        STA XPOS
        STA VICX
        LDA #0
        STA XPOSHI
        LDA #120
        STA YPOS
        STA VICY
        LDA VICMSB
        AND #$FE
        STA VICMSB
        LDA #$90        ; sprite data at $2400 in VIC bank 0
        STA $07F8
        LDA #$01
        STA $D027
        LDA VICENA
        ORA #$01
        STA VICENA

        ; Let the SID POT converter settle before taking the baseline.
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

frame:  LDA $D012
        CMP #$FF
        BEQ frame
waitff: LDA $D012
        CMP #$FF
        BNE waitff

        LDA POTX
        STA RAWX
        LDY OLDX
        JSR MOVCHK
        STA DX
        TYA
        STA OLDX

        LDA POTY
        STA RAWY
        EOR #$FF        ; same Y inversion as the Sentinel patch
        LDY OLDY
        JSR MOVCHK
        STA DY
        TYA
        STA OLDY

        LDA RAWX
        LDY #127
        JSR HEXOUT
        LDA RAWY
        LDY #133
        JSR HEXOUT
        LDA DX
        LDY #146
        JSR HEXOUT
        LDA DY
        LDY #152
        JSR HEXOUT

        JSR APPLYX
        JSR APPLYY

        LDA CIA1PA
        TAX
        AND #$10
        BNE noleft
        LDA #$02
        BNE setborder
noleft: LDA #$06
setborder:
        STA BORDER
        TXA
        AND #$11        ; both 1351 buttons: return to BASIC
        BEQ exit
        JMP frame

exit:
        LDA SAVPTR
        STA $07F8
        LDA SAVMSB
        STA VICMSB
        LDA SAVENA
        STA VICENA
        LDA SAVMEM
        STA VICMEM
        LDA SAVC2
        STA CIA2PA
        LDA SAVPA
        STA CIA1PA
        LDA SAVFAST
        STA FAST
        CLI
        RTS

; Commodore 1351 delta conversion used by the Sentinel patch.
; A = new 7-bit POT value, Y = old value. Returns signed delta in A and
; the value to retain as the next baseline in Y. Ignores +/-1 jitter.
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

; Add the signed mouse delta to a 9-bit VIC-IIe X position and clamp it
; to the visible playfield. The range is $018-$140 (24-320).
APPLYX:LDA XPOS
        CLC
        ADC DX
        STA NEWX
        LDA DX
        BMI xnegative
        LDA XPOSHI
        ADC #0
        TAY
        CMP #2
        BCS xmax
        CMP #1
        BNE xstore
        LDA NEWX
        CMP #$41
        BCS xmax
        BCC xstore
xnegative:
        LDA XPOSHI
        ADC #$FF
        TAY
        BMI xmin
        CMP #2
        BCS xmax
        CMP #1
        BEQ xstore
        LDA NEWX
        CMP #24
        BCC xmin
        BCS xstore
xmin:   LDY #0
        LDA #24
        BNE xsaved
xmax:   LDY #1
        LDA #$40
        BNE xsaved
xstore: LDA NEWX
xsaved: STA XPOS
        STY XPOSHI
        STA VICX
        LDA VICMSB
        AND #$FE
        CPY #0
        BEQ xmsb
        ORA #$01
xmsb:   STA VICMSB
        RTS

; Add signed Y motion and clamp it to raster positions 50-229.
APPLYY:LDA DY
        BMI ynegative
        CLC
        ADC YPOS
        BCS ymax
        CMP #230
        BCS ymax
        BCC ystore
ynegative:
        CLC
        ADC YPOS
        BCC ymin
        CMP #50
        BCC ymin
        BCS ystore
ymin:   LDA #50
        BNE ystore
ymax:   LDA #229
ystore: STA YPOS
        STA VICY
        RTS

; Print A as two screen-code hexadecimal digits at SCREEN,Y.
HEXOUT: PHA
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA HEXDIG,X
        STA SCREEN,Y
        INY
        PLA
        AND #$0F
        TAX
        LDA HEXDIG,X
        STA SCREEN,Y
        RTS

; Screen codes. The zero byte terminates each copied string.
TITLE:  .BYTE $03,$31,$32,$38,$20,$0E,$01,$14,$09,$16,$05,$20,$31,$33,$35,$31
        .BYTE $20,$13,$0D,$0F,$0B,$05,$20,$14,$05,$13,$14,$00
INFO:   .BYTE $12,$01,$17,$20,$18,$3A,$20,$30,$30,$20,$19,$3A,$20,$30,$30,$20
        .BYTE $20,$04,$05,$0C,$14,$01,$20,$18,$3A,$20,$30,$30,$20,$19,$3A,$20
        .BYTE $30,$30,$00
STATUS: .BYTE $0D,$0D,$15,$20,$06,$06,$30,$30,$3A,$20,$30,$30,$20,$04,$30,$33
        .BYTE $30,$3A,$20,$30,$30,$20,$20,$0C,$3D,$12,$05,$04,$20
        .BYTE $02,$0F,$14,$08,$3D,$05,$18,$09,$14,$00
HEXDIG: .BYTE $30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$01,$02,$03,$04,$05,$06

SAVPA:  .BYTE $00
SAVC2:  .BYTE $00
SAVMEM: .BYTE $00
SAVENA: .BYTE $00
SAVMSB: .BYTE $00
SAVPTR: .BYTE $00
SAVFAST:.BYTE $00
OLDX:   .BYTE $00
OLDY:   .BYTE $00
RAWX:   .BYTE $00
RAWY:   .BYTE $00
DX:     .BYTE $00
DY:     .BYTE $00
XPOS:   .BYTE $00
XPOSHI: .BYTE $00
YPOS:   .BYTE $00
NEWX:   .BYTE $00
OLDV:   .BYTE $00

        * = $2400
; 24x21 high-resolution crosshair for sprite 0.
SPRITE: .BYTE $00,$10,$00,$00,$10,$00,$00,$10,$00,$00,$10,$00,$00,$10,$00
        .BYTE $00,$10,$00,$00,$10,$00,$00,$10,$00,$00,$10,$00,$00,$10,$00
        .BYTE $FF,$FF,$FF
        .BYTE $00,$10,$00,$00,$10,$00,$00,$10,$00,$00,$10,$00,$00,$10,$00
        .BYTE $00,$10,$00,$00,$10,$00,$00,$10,$00,$00,$10,$00,$00,$10,$00
