; Gameplay notices share the cockpit's standing message row and SID sweep.
; The longer startup copy can finish during the visible frame.
STARTPLOT:
        CPX #0
        BEQ boot_laststar
        JMP PLOTSTAR
boot_laststar:
        JSR PLOTSTAR
        BIT $D011
        BMI boot_waittop
        LDA $D012
        CMP #48
        BCC boot_ready
boot_waitbottom:
        BIT $D011
        BPL boot_waitbottom
boot_waittop:
        BIT $D011
        BMI boot_waittop
boot_ready:
        RTS

MISSIONINIT:
        LDA #0
        STA NOTICEPEND
        STA CLEARTIME
        LDA #$FF
        STA SYSLAST
        JSR mission_disarm
        JMP SHOWSEC

SECTORNOTICE:
        LDA #27         ; the first VIEWWORK pass counts the kill frame itself
        STA CLEARTIME
        LDA #2
        BNE NOTICEREQUEST

GROUPNOTICE:
        STA APPR
        LDA #1
        BNE NOTICEREQUEST

APPROACHNOTICE:
        LDA #3
        BNE NOTICEREQUEST
TRACKNOTICE:
        LDA #4
        BNE NOTICEREQUEST
ENTERNOTICE:
        LDA #5
        BNE NOTICEREQUEST

HREAD:  LDA MSGON
        BNE mission_arm_done
        JMP lr7
HREADCLEAR:
        LDA MSGON
        BNE mission_arm_done
        JMP LRCLEAR
EMPTYROW:
        JSR SHOWTG
        LDA SQCOUNT
        BNE mission_arm_done
        LDA MSGON
        BEQ mission_arm_done
        PLA
        PLA
        RTS
MISSIONHIT:
        JSR SHIPHIT
        LDA SYSLAST
        BMI mission_arm_done
        CLC
        ADC #8
        LDX #$FF
        STX SYSLAST

; One pending write to the row, published in the next safe view slot.
; A later request replaces it even while the row is flashing or scrolling.
NOTICEREQUEST:
        STA NOTICEPEND
        LDA #<MISSIONFRAME
        STA missionjump+1
        LDA #>MISSIONFRAME
        STA missionjump+2
        LDA #1          ; GROUPNOTICE's caller also stores this in RELAYOUT
mission_arm_done:
        RTS

MISSIONREPAIRED:
        LDA #$FF
        STA SYSLAST
        JMP SHIPINIT

BASEMESSAGE:
        PHA             ; this scene prints at its own timed entry point
        LDA #0
        STA NOTICEPEND
        PLA
        JMP MSGSTAT

MISSIONEND:
        LDA NOTICEPEND
        CMP #$14        ; JARALOBA CEASES TO EXIST precedes the loss sequence
        BNE mission_end_reset
        JSR GBTEXT
mission_end_reset:
        LDA #0
        STA NOTICEPEND
        STA CLEARTIME
        JSR mission_disarm
        JMP ENDALARM

MISSIONFRAME:
        LDA ENDMODE
        ORA SHIPLOST
        BNE mission_cancel
        LDA MSSTATE
        CMP #4
        BCC mission_timer
        CMP #16         ; base positioning (16) can show damage from mines
        BCC mission_cancel   ; base exit and the docking report own the screen
mission_timer:
        LDA CLEARTIME
        BEQ mission_next
        LDA HYPON
        ORA HPEND
        BEQ mission_count
        LDA #0
        STA CLEARTIME
        BEQ mission_next
mission_count:
        DEC CLEARTIME
        BNE mission_next
        LDA MAPSHOWN
        BNE mission_next
        LDA TREQ
        ORA TPF
        ORA WIPE
        BNE mission_hold
        LDA $D012
        CMP #145
        BCS mission_hold
        JSR MAPOPEN
        JMP mission_done
mission_hold:
        INC CLEARTIME
mission_next:
        LDA NOTICEPEND
        BEQ mission_idle
        LDX $D012
        CPX #145
        BCS mission_done
        LDX #0
        STX NOTICEPEND
        JSR mission_print
mission_idle:
        LDA CLEARTIME
        ORA NOTICEPEND
        BNE mission_done
        JSR mission_disarm
mission_done:
        JMP ARRSTEP
mission_cancel:
        LDA #0
        STA NOTICEPEND
        STA CLEARTIME
        BEQ mission_idle

mission_print:
        CMP #$11
        BCC mission_foreground
        JMP GBTEXT
mission_foreground:
        CMP #3
        BCS mission_other
        CMP #2
        BEQ mission_clear
        LDA #<GROUPMESSAGE
        LDX #>GROUPMESSAGE
        LDY #25
        JMP mission_show
mission_clear:
        LDA #15
        STA MSGRATE
        LDA #$10
        STA MSGCOL
        LDA #<CLEARMESSAGE
        LDX #>CLEARMESSAGE
        LDY #32
        JMP MSGSTAT
mission_other:
        CMP #3
        BNE mission_not_approach
        JMP ALERT
mission_not_approach:
        CMP #4
        BNE mission_not_tracking
        JMP TRKMSG
mission_not_tracking:
        CMP #5
        BNE mission_damage
        JMP SECALERT
mission_damage:
        AND #7
        TAX
        LDA SYSHP,X     ; discard if a friendly repair already restored it
        BNE mission_damage_done
        STX WARNIDX
        LDA #$87
        STA MSGCOL
        LDA #5
        STA MSGRATE
        LDA #<WARNINGEND
        LDX #>WARNINGEND
        LDY #53
        JSR MSGSTAT
        JSR mission_systemtext
        JMP SNDSIREN
mission_damage_done:
        RTS

mission_disarm:
        LDA #<ARRSTEP
        STA missionjump+1
        LDA #>ARRSTEP
        STA missionjump+2
        RTS

mission_show:
        PHA
        LDA #5
        STA MSGRATE
        LDA #$27
        STA MSGCOL
        PLA
        JMP MSGSTAT

; The repair report already has the system names in screen codes.
mission_systemtext:
        LDX WARNIDX
        LDA MRLENS,X
        STA WARNLEN
        LDA #30         ; 40 columns minus the space and DESTROYED
        SEC
        SBC WARNLEN
        LSR A
        TAY
        LDA #0
mission_offset:
        DEX
        BMI mission_name
        CLC
        ADC MRLENS,X
        JMP mission_offset
mission_name:
        TAX
mission_letter:
        LDA MRTEXT,X
        STA LRROW,Y
        INX
        INY
        DEC WARNLEN
        BNE mission_letter
        LDX #0
mission_suffix:
        LDA WARNWORD,X
        STA LRROW,Y
        INY
        INX
        CPX #10
        BNE mission_suffix
        RTS

NOTICEPEND: .BYTE 0
WARNIDX: .BYTE 0
CLEARTIME:  .BYTE 0
WARNLEN:    .BYTE 0
WARNWORD:   .BYTE $40,$44,$45,$53,$54,$52,$4F,$59,$45,$44
WARNINGEND: .BYTE $FF
CLEARMESSAGE: .BYTE $40,$40,$40,$40,$40,$40,$40,$40,$40,$53,$45,$43,$54,$4F,$52,$40,$43,$4C,$45,$41,$52,$45,$44,$40,$43,$41,$50,$54,$41,$49,$4E,$FF
GROUPMESSAGE: .BYTE $40,$40,$40,$40,$40,$40,$40,$40,$40,$53,$51,$55,$41,$44,$52,$4F,$4E,$40,$44,$45,$53,$54,$52,$4F,$59,$45,$44,$40,$53,$49,$52,$FF

SCANROW:
        LDA MSGON
        BEQ scan_row_free
        PLA             ; return from the scanner without touching the message row
        PLA
        JSR scan_index
        LDA ENX+1,X
        JSR scan_digits
        STY LRDIG
        STX LRDIG+1
        JSR scan_index
        LDA ENY+1,X
        JSR scan_digits
        STY LRDIG+2
        STX LRDIG+3
        RTS
scan_index:
        LDA GSEL
        ASL A
        TAX
        RTS
scan_digits:
        JSR LRVAL
        TAY
        LDA LRTAB,Y
        JSR BCD
        JMP ld1
scan_row_free:
        LDA #$7B
        STA LRROW+9
        RTS
SCANZEROX:
        LDA MSGON
        BNE scan_zero_done
        LDA #$70
        STA LRROW+13
scan_zero_done:
        RTS
SCANZEROY:
        LDA MSGON
        BNE scan_zero_done
        LDA #$70
        STA LRROW+21
        RTS
