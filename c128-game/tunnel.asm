; C64 $0E20/$0EE5: mirrored boundaries and raster colours.
MTFRAME:
        SEI
        LDA #0
        STA $D01A
        LDA MAPSHOWN
        ORA WIPE
        ORA HYPON
        BNE mt_done
        INC MTPHASE
        JSR MTPAINT
        LDA MTPHASE
        AND #15
        CLC
        ADC #48
        TAX
        LDY #0
mt_lines:
        LDA MTTABLE,X
        CLC
        ADC #82
        STA MTLINES,Y
        LDA #227
        SEC
        SBC MTTABLE,X
        STA MTLINES+7,Y
        TXA
        SEC
        SBC #16
        TAX
        INY
        CPY #4
        BNE mt_lines
; Reverse the four lower entries (stored above in spare scratch slots).
        LDX #0
        LDY #3
mt_reverse:
        LDA MTLINES+7,X
        STA MTLINES+4,Y
        INX
        DEY
        BPL mt_reverse
        LDA #0
        STA MTINDEX
        LDA #<MTIRQ
        STA $FFFE
        LDA #>MTIRQ
        STA $FFFF
        LDA MTLINES
        SEC
        SBC #1
        STA $D012
        LDA #$7F
        STA $DC0D
        STA $DD0D
        LDA $DC0D
        LDA $DD0D
        LDA #1
        STA $D019
        STA $D01A
        CLI
mt_done:RTS
MTIRQ:
        PHA
        TXA
        PHA
mt_do:  LDX MTINDEX
        LDA MTCOLORS,X
mt_write:STA $D021
        STA $D020
        INC MTINDEX
        LDX MTINDEX
        CPX #8
        BEQ mt_last
        LDA MTLINES,X
        SEC
        SBC #1
        CMP $D012
        BCC mt_do
        BEQ mt_do
        STA $D012
        LDA #1
        STA $D019
mt_irqret:PLA
        TAX
        PLA
        RTI
mt_last:
        LDA #0
        STA $D01A
        BEQ mt_irqret
MTSHOT:
        LDA MAPSHOWN
        ORA WIPE
        ORA HYPON
        BNE mt_shotret
        LDA SHOTON
        BEQ mt_shotret
        LDA FIREFLAG
        BEQ mt_shotret
        LDA #16
        STA SUBN
mt_shotloop:
        JSR SHOTSTEP
        DEC SUBN
        BNE mt_shotloop
mt_shotret:RTS
MTRESET:
        LDA #32
        STA PHBUD+1
        LDA #0
        STA MTPHASE
        STA MTAGE
        RTS
MTPAINT:
        LDA MTPHASE
        AND #15
        CMP #0
        BNE mt_ageok
        LDA MTAGE
        CMP #4
        BCS mt_ageok
        INC MTAGE
mt_ageok:
        LDA MTPHASE
        LSR A
        LSR A
        LSR A
        LSR A
        AND #3
        LDX MNKIND
        BEQ mt_kind
        ORA #4
mt_kind:TAX
        LDA MTAGE
        LDY MSROW
        CPY #3
        BNE mt_fade
        LDA MSCLOCK
        LSR A
        LSR A
        LSR A
        LSR A
mt_fade:STA MTLEVEL
        LDY #0
mt_paint:
        LDA MSROW
        CMP #3
        BNE mt_entryfade
        CPY MTLEVEL
        LDA #0
        BCS mt_black
        BCC mt_colour
mt_entryfade:
        TYA
        CLC
        ADC MTLEVEL
        CMP #4
        LDA #0
        BCC mt_black
mt_colour:LDA MTPALETTE,X
mt_black:
        STA MTINK,Y
        INX
        TXA
        AND #3
        BNE mt_nowrap
        TXA
        SEC
        SBC #4
        TAX
mt_nowrap:
        INY
        CPY #4
        BNE mt_paint
        LDA MTINK
        STA VIEWBG
        LDA MTINK+1
        STA MTCOLORS
        STA MTCOLORS+6
        LDA MTINK+2
        STA MTCOLORS+1
        STA MTCOLORS+5
        LDA MTINK+3
        STA MTCOLORS+2
        STA MTCOLORS+4
        LDA MTINK
        STA MTCOLORS+7
        RTS
MTAGE: .BYTE 0
MTLEVEL: .BYTE 0
MTINK: .BYTE 0,0,0,0
MTPALETTE: .BYTE 9,6,11,4,7,13,10,3
MTPHASE: .BYTE 0
MTINDEX: .BYTE 0
MTLINES: .BYTE 0,0,0,0,0,0,0,0,0,0,0
MTCOLORS: .BYTE 9,6,11,0,11,6,9,0
MTTABLE:
; MTTABLEDATA

