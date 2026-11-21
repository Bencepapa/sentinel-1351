; Resident raster handlers. Only the split line and ribbon scroll change
; while TITLE owns the overlay slot. IRQs are off before it releases S1.
INTROTOP = 47
INTROBASE = 74
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

; The handlers repeat the title loop's split sequences exactly (same WAITST lines, the
; HUD's border edge at line 56, the view's white edge line): without the border
; writes the HUD loses its side blocks and frame.
intro_irq_top:
        PHA
        TXA
        PHA
        TYA
        PHA
        LDA #56
        JSR WAITST
        LDA #1
        STA BG
        STA BORDER
        LDA #$1B
        STA $D011
        LDA #$08
        STA $D016
        LDA #$20
        STA $D018
        LDY #20
intro_hud_edge:
        DEY
        BNE intro_hud_edge
        LDA HUDBRD
        STA BORDER
        LDA #$0B
        STA BG
        LDA INTROSPLIT
        SEC
        SBC #5
        LDX #<intro_irq_view
        LDY #>intro_irq_view
        JMP intro_irq_next

intro_irq_view:
        PHA
        TXA
        PHA
        TYA
        PHA
        LDA INTROSPLIT
        CMP #75         ; the bad line 75 would stretch WAITST's tail: the first steps wait at 78
        BCC intro_viewline
        CMP #78
        BCS intro_viewline
        LDA #78
intro_viewline:
        JSR WAITST
        LDA #1
        STA BG
        STA BORDER
        LDY #10
intro_view_edge:
        DEY
        BNE intro_view_edge
        LDA #$3B
        STA $D011
        LDA #$18
        STA $D016
        STA $D018
        BIT VIEWBG
        NOP
        LDA #0
        STA BG
        STA BORDER
        LDA #194
        LDX #<intro_irq_guns
        LDY #>intro_irq_guns
        JMP intro_irq_next

; Below the view the cockpit's guns, as the title's loop shows them.
intro_irq_guns:
        PHA
        TXA
        PHA
        TYA
        PHA
        JSR SPR7
        JSR SPRGUNS
        AND #$8B
        STA VICENA
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
        LDA #0
        STA VICENA
        LDA #233
        JSR WAITST
        LDA INTROFINE   ; $D016 first, as the title loop (no x shake)
        STA $D016
        LDA #$0B
        STA BORDER
        STA BG
        LDA #$1B
        STA $D011
        LDA #$20
        STA $D018
        LDA #242
        JSR WAITST
        LDA #0
        STA BORDER
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
