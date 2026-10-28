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
PTR     = $FB

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

        JSR RESET

frame:  LDA $D012
        CMP #$FF
        BEQ frame
waitff: LDA $D012
        CMP #$FF
        BNE waitff

        JSR STEP

        LDA #$7F        ; SPACE exits
        STA CIA1PA
        LDA CIA1PB
        AND #$10
        BNE nospace
        JMP EXIT
nospace:LDA #$FF        ; fire on port 2 restarts, once the sweep is done
        STA CIA1PA
        LDA CIA1PA
        AND #$10
        BNE nofire
        LDA FIREPREV
        BNE firedn
        LDA PHASE
        CMP #3
        BNE firedn
        LDA #1
        STA FIREPREV
        JSR RESET
        JMP frame
nofire: LDA #0
        STA FIREPREV
        JMP frame
firedn: LDA #1
        STA FIREPREV
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
        LDA #1
        STA FIREPREV
        JMP SNDINIT

; One frame of the draw-in.
STEP:   LDA PHASE
        BEQ HORIZ
        CMP #1
        BEQ PAUSEP
        CMP #2
        BNE steprt
        JMP VERTP
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
