; Resident raster handlers. Only the split line and ribbon scroll change
; while TITLE owns the overlay slot. IRQs are off before it releases S1.
INTROTOP = 47
INTROBASE = 75
INTROEND = INTROBASE+48
INTROROW = $4878

INTROIRQON:
        LDA #0
        STA FAST
        LDA #$7F
        STA $DC0D
        STA $DD0D
        BIT $DC0D
        BIT $DD0D
        LDA #INTROTOP
        LDX #<intro_irq_top
        LDY #>intro_irq_top
        JSR intro_irq_vector
        LDA #1
        STA $D019
        STA $D01A
        CLI
        RTS

INTROIRQOFF:
        SEI
        LDA #0
        STA $D01A
        LDA #1
        STA $D019
        LDX #<NMIRTI
        LDY #>NMIRTI
        STX $FFFE
        STY $FFFF
        JMP ENDHIDE

intro_irq_top:
        PHA
        TXA
        PHA
        TYA
        PHA
        LDA #$1B
        STA $D011
        LDA #$08
        STA $D016
        LDA #$20
        STA $D018
        LDA #$0B
        STA BG
        LDA INTROSPLIT
        SEC
        SBC #2
        LDX #<intro_irq_view
        LDY #>intro_irq_view
        JMP intro_irq_next

intro_irq_view:
        PHA
        TXA
        PHA
        TYA
        PHA
        LDX #0
        LDA INTROSPLIT
intro_wait_split:
        CMP $D012
        BNE intro_wait_split
        STX BG
        LDA #$3B
        STA $D011
        LDA #$18
        STA $D018
        STA $D016
        LDA #230
        LDX #<intro_irq_ribbon
        LDY #>intro_irq_ribbon
        JMP intro_irq_next

intro_irq_ribbon:
        PHA
        TXA
        PHA
        TYA
        PHA
        LDA #233
        JSR WAITST
        LDA #$0B
        STA BG
        LDA #$1B
        STA $D011
        LDA #$20
        STA $D018
        LDA INTROFINE
        STA $D016
        LDA #242
        JSR WAITST
        LDA #0
        STA BG
        LDA #8
        STA $D016
        LDA #INTROTOP
        LDX #<intro_irq_top
        LDY #>intro_irq_top
intro_irq_next:
        JSR intro_irq_vector
        LDA #1
        STA $D019
        PLA
        TAY
        PLA
        TAX
        PLA
        RTI

intro_irq_vector:
        STA $D012
        STX $FFFE
        STY $FFFF
        RTS

INTRORESTORE:
        LDX #239
intro_restore:
        LDA COLORDATA+120,X
        STA $D878,X
        LDA #$60
        CPX #40
        BCS intro_restore_cell
        LDA #$11
intro_restore_cell:
        STA INTROROW,X
        DEX
        CPX #$FF
        BNE intro_restore
        JMP LRCLEAR

INTROSPLIT: .BYTE 0
INTROFINE:  .BYTE 0
INTROACTIVE:.BYTE 0
INTROARM:   .BYTE 0
