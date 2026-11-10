; C64 $0E20/$0EE5: mirrored boundaries and raster colours.
; MTFRAME runs in the blank (MNVB) and falls through into the shot/sprite
; servicing that used to be the separate MTSHOT call.
MTFRAME:
        LDA MAPSHOWN
        ORA WIPE
        ORA HYPON
        BEQ mt_active
        CLI
        RTS
mt_active:
        INC MTPHASE
        LDA MTPHASE
        AND #15
        CLC
        ADC #48
        TAX
        LDY #0
mt_lines:
        LDA MTTABLE-16,X
        CLC
        ADC #81
        STA MTLINES,Y
        LDA #226
        SEC
        SBC MTTABLE-16,X
        STA MTLINES+7,Y
        TXA
        SEC
        SBC #16
        TAX
        INY
        CPY #3
        BNE mt_lines
; MTLINES+3 / +10 hold the constant middle strip (149 / 158).
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
; The tunnel replaces the cockpit's line-76 hit flash (C64 $139A-$13C8).
        STA FLASHC
        LDA #<MTIRQ
        STA $FFFE
        LDA #>MTIRQ
        STA $FFFF
        LDA MTLINES
        STA $D012
; Paint after arming the first compare: the 300-cycle palette update must
; not make the first line of this frame miss its raster deadline.
        LDA MTPHASE
        AND #15
        BEQ mt_paintframe
        CMP #1
        BNE mt_flashing
        LDA MTAGE
        BEQ mt_paintframe
mt_flashing:
        LDA HITFL       ; a flash step's frame is repainted the next frame
        BEQ mt_painted
mt_paintframe:
        JSR MTPAINT
mt_painted:
; A ship hit ($1311): each flash step shows one frame of a single colour over
; every band and the middle strip; the strip and the faded (black) bands keep
; it until the next step: white, orange, white, yellow, white, black.
        LDX FLN
        CPX MTFLN
        BEQ mt_noflash
        STX MTFLN
        CPX #6
        BCS mt_noflash
        LDA MTFLTAB,X
        STA MTBLACK
        STA VIEWBG
        LDX #7
mt_fill:STA MTCOLORS,X
        DEX
        BPL mt_fill
mt_noflash:
        LDA #1
        STA $D019
        STA $D01A
        CLI
; The last settling stage lasts until the exit fade's level 5 (C64 $8D3E):
; its clock is held (bit 2 keeps it above 0, the low bits still pace the
; drift) and then expires; the mine sprites are restored from level 4.
        LDX MTEXIT
        BEQ mt_shotcheck
        LDA MSCLOCK
        ORA #4
        CPX #5
        BCC mt_hold
        LDA #1
mt_hold:STA MSCLOCK
        CPX #4
        BCC mt_shotcheck
        JSR MNRESTORE
; Shots (was MTSHOT).
mt_shotcheck:
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
MTIRQ:
        PHA
        TXA
        PHA
mt_do:  LDX MTINDEX
        LDA MTCOLORS,X
mt_write:STA $D021
        STA $D020
        INX
        STX MTINDEX
        CPX #8
        BEQ mt_last
; A boundary on the next line is waited for here (C64 $0F08: close
; boundaries share an IRQ): a compare set for it could already be too late.
mt_near:LDA MTLINES,X
        SEC
        SBC #1
        CMP $D012
        BCC mt_do
        BEQ mt_near
        ADC #0
        STA $D012
        LDA #1
        STA $D019
mt_irqret:
        PLA
        TAX
        PLA
        RTI
mt_last:
        LDA #0
        STA $D01A
        BEQ mt_irqret
MTRESET:
        SEI
        LDA #32
        STA PHBUD+1
        LDA #$7F
        STA $DC0D
        STA $DD0D
        LDA #0
        STA MTPHASE
        STA MTAGE
        STA MTEXIT
        STA MTBLACK
        STA MTCOLORS+3
        CLI
        RTS
; Every 16 frames ($0FD6 / $0F80): the entry fade reveals one more band,
; inner first; in the last settling stage (C64 $9097 arms $0F7F) the exit
; fade blackens one more band, inner first, in step with the colour shift.
MTPAINT:
        LDA MTPHASE
        AND #15
        BNE mt_ageok
        LDA MTAGE
        CMP #4
        BCS mt_exitstep
        INC MTAGE
mt_exitstep:
        LDA MSROW
        CMP #3
        BNE mt_ageok
        INC MTEXIT
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
        LDY #0
mt_paint:
        TYA
        CLC
        ADC MTEXIT
        CMP #4
        BCS mt_black
        TYA
        ADC MTAGE
        CMP #4
        BCC mt_black
        LDA MTPALETTE,X
        BCS mt_ink
mt_black:
        LDA MTBLACK
mt_ink: STA MTINK,Y
        INX
        TXA
        AND #3
        BNE mt_nowrap
        DEX
        DEX
        DEX
        DEX
mt_nowrap:
        INY
        CPY #4
        BNE mt_paint
        LDA MTINK
        STA VIEWBG
        STA MTCOLORS+7
        LDA MTINK+1
        STA MTCOLORS
        STA MTCOLORS+6
        LDA MTINK+2
        STA MTCOLORS+1
        STA MTCOLORS+5
        LDA MTINK+3
        STA MTCOLORS+2
        STA MTCOLORS+4
        RTS
MTAGE: .BYTE 0
MTEXIT: .BYTE 0
MTBLACK: .BYTE 0
MTFLN: .BYTE $FF
MTFLTAB: .BYTE 0,1,7,1,8,1
MTINK: .BYTE 0,0,0,0
MTPALETTE: .BYTE 9,6,11,4,7,13,10,3
MTPHASE: .BYTE 0
MTINDEX: .BYTE 0
MTLINES: .BYTE 0,0,0,149,0,0,0,0,0,0,158
MTCOLORS: .BYTE 9,6,11,0,11,6,9,0
MTTABLE:
; MTTABLEDATA
