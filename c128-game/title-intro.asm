INTROWELCOMESTEPS = 88
INTROHOLDTIME = 240

BRIEFRUN:
        JSR TITLEFONTRESTORE
        LDX #239
intro_fill:
        LDA #$60
        STA INTROROW,X
        LDA #1
        STA $D878,X
        DEX
        CPX #$FF
        BNE intro_fill
        INX
intro_rules:
        LDA #$61
        STA INTROROW,X
        LDA #$62
        STA INTROROW+39,X
        LDA #3
        STA $D878,X
        STA $D89F,X
        TXA
        CLC
        ADC #40
        TAX
        CPX #240
        BNE intro_rules
        LDA #0
        STA INTROARM
        STA INTROFINE
        STA INTROINDEX
        STA INTROPHASE
        LDA #INTROBASE
        STA INTROSPLIT
        LDA #INTROWELCOMESTEPS
        STA INTROCOUNT
        LDA #$13
        STA $D405
        LDA #$20
        STA $D406
        LDA #1
        STA INTROACTIVE
        JSR INTROIRQON

intro_frame:
        BIT $D011
        BPL intro_frame
intro_wrap:
        BIT $D011
        BMI intro_wrap
intro_vblank:
        LDA $D012      ; the ribbon IRQ uses WAITST's shared raster scratch
        CMP #245
        BCC intro_vblank
        LDA #0
        STA $D404
        LDA #$7F
        STA CIA1PA
        LDA CIA1PB
        TAY
        LDA #$BF
        STA CIA1PA
        TYA
        AND CIA1PA
        AND #$10
        BEQ intro_pressed
        STA INTROARM     ; release the selector's Fire before allowing a skip
        BNE intro_phase
intro_pressed:
        LDA INTROARM
        BEQ intro_phase
intro_finish:
        TYA              ; consume a held Space through the normal torpedo latch
        AND #$10
        BNE intro_quiet
        LDA #2
        STA TSPP
        JSR GSPACE
intro_quiet:
        JSR INTROIRQOFF
        JSR MUSICSTOP
        LDA #$0F
        STA $D418
        LDA #0
        STA INTROACTIVE
        JMP INTRORESTORE
intro_phase:
        LDX INTROPHASE
        BEQ intro_welcome
        DEX
        BEQ intro_open
        DEX
        BEQ intro_type
        DEX
        BEQ intro_hold
        DEC INTROSPLIT
        LDA INTROSPLIT
        CMP #INTROBASE
        BCC intro_finish
        JMP intro_sound

intro_hold:
        DEC INTROCOUNT
        BNE intro_again
        INC INTROPHASE
intro_again:
        JMP intro_frame

intro_welcome:
        LDA INTROFINE
        SEC
        SBC #2
        AND #7
        STA INTROFINE
        CMP #6
        BNE intro_again
        DEC INTROCOUNT
        BEQ intro_welcomed
        LDX #0
intro_shift:
        LDA LRROW+1,X
        STA LRROW,X
        INX
        CPX #39
        BNE intro_shift
        LDY INTROINDEX
        LDA BRIEFWELCOME,Y
        BEQ intro_again
        STA LRROW+39
        INC INTROINDEX
        AND #$1F
        BEQ intro_again
        LDA #$31
        BNE intro_sound
intro_welcomed:
        JSR LRCLEAR
        LDA #0
        STA INTROFINE
        INC INTROPHASE
        BNE intro_again

intro_open:
        INC INTROSPLIT
        LDA INTROSPLIT
        CMP #INTROEND
        BNE intro_sound
        INC INTROPHASE
        LDX #0
        STX INTROINDEX
        LDX #2
        STX INTROCOUNT
        BNE intro_sound

intro_type:
        DEC INTROCOUNT
        BNE intro_return
        LDA #2
        STA INTROCOUNT
        LDX INTROINDEX
        LDA BRIEFTEXT,X
        STA INTROROW,X
        INC INTROINDEX
        CPX #239
        BNE intro_click
        INC INTROPHASE
        LDX #INTROHOLDTIME
        STX INTROCOUNT
intro_click:
        CMP #$40
        BEQ intro_return
        CMP #$61
        BCS intro_return
        LDA #$48
intro_sound:
        STA $D401
        LDA #$11
        STA $D404
intro_return:
        JMP intro_frame

INTROPHASE: .BYTE 0
INTROCOUNT: .BYTE 0
INTROINDEX: .BYTE 0
BRIEFTEXT:
; BRIEFHEADERDATA
TITLELAST:
; BRIEFBODYDATA
