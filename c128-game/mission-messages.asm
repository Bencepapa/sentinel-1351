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
        STA NOTICECOUNT
        STA NOTICEREAD
        STA NOTICEWRITE
        STA CLEARTIME
        LDA #$FF
        STA SYSLAST
        JSR mission_disarm
        JMP SHOWSEC

SECTORNOTICE:
        LDA #2
        BNE NOTICEQUEUE

GROUPNOTICE:
        STA APPR
        LDA #1
        BNE NOTICEQUEUE

APPROACHNOTICE:
        LDA #3
        BNE gorganitor_notice
TRACKNOTICE:
        LDA #4
        JMP NOTICEQUEUE
ENTERNOTICE:
        LDA #5
gorganitor_notice:
        LDX SYSHP+4     ; a working tracking computer announces its own engagement
        BEQ gorganitor_queue
        RTS
gorganitor_queue:
        JMP NOTICEQUEUE

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
GBTGATE:
        LDA MSGON
        ORA NOTICECOUNT
        BNE mission_arm_done
        JMP GBTEXT

MISSIONHIT:
        JSR SHIPHIT
        JMP mission_queue_damage

; Keep the original timing of mine hits. Transfer the warning when the base
; releases the message row.
MISSIONBASEOFF:
        STA shpj
        LDA SYSLAST
        BPL mission_queue_damage
        LDA NOTICECOUNT
        BNE mission_arm
        RTS
mission_queue_damage:
        LDA SYSLAST
        BMI mission_arm_done
        CLC
        ADC #8
        LDX #$FF
        STX SYSLAST

NOTICEQUEUE:
        LDX NOTICECOUNT
        CPX #8
        BCS mission_arm_done
        INC NOTICECOUNT
        LDX NOTICEWRITE
        STA NOTICEBUF,X
        INX
        TXA
        AND #7
        STA NOTICEWRITE
        LDA #1          ; GROUPNOTICE's caller also stores this in RELAYOUT
mission_arm:
        PHA
        LDA #<MISSIONFRAME
        STA missionjump+1
        LDA #>MISSIONFRAME
        STA missionjump+2
        PLA
mission_arm_done:
        RTS

MISSIONREPAIRED:
        LDA #$FF        ; the report just repaired any queued system
        STA SYSLAST
        JMP SHIPINIT

mission_idle:
        JMP ARRSTEP
mission_finish:
        JSR mission_disarm
        JMP ARRSTEP
MISSIONFRAME:
        LDA NOTICECOUNT
        ORA CLEARTIME
        BEQ mission_finish
        LDA ENDMODE
        ORA SHIPLOST
        ORA MSSTATE
        BNE mission_finish
        LDA $D012
        CMP #145
        BCS mission_idle
        LDA CLEARTIME
        BEQ mission_next
        LDA HYPON
        ORA HPEND
        BEQ mission_wait
        LDA #0
        STA CLEARTIME
        BEQ mission_next
mission_wait:
        DEC CLEARTIME
        BNE mission_next
        LDA TREQ
        ORA TPF
        ORA WIPE
        BEQ mission_open
        INC CLEARTIME
        BNE mission_next
mission_open:
        LDA MAPSHOWN
        BNE mission_next
        JSR MAPOPEN
        JMP mission_done
mission_next:
        LDA MSGON
        ORA MSSTATE
        BNE mission_done
        LDA NOTICECOUNT
        BEQ mission_done
        DEC NOTICECOUNT
        LDX NOTICEREAD
        LDA NOTICEBUF,X
        PHA
        INX
        TXA
        AND #7
        STA NOTICEREAD
        PLA
        CMP #3
        BCS mission_other
        CMP #2
        BEQ mission_clear
        LDA #<GROUPMESSAGE
        LDX #>GROUPMESSAGE
        LDY #25
        JSR mission_show
        JMP mission_done
mission_clear:
        LDA #26         ; the C64's 55 foreground polls take 26 PAL frames
        STA CLEARTIME
        LDA #15
        STA MSGRATE
        LDA #$81
        STA MSGCOL
        LDA #<CLEARMESSAGE
        LDX #>CLEARMESSAGE
        LDY #32
        JSR MSGSTAT
        JMP mission_done
mission_other:
        CMP #3
        BNE mission_not_approach
        JSR ALERT
        JMP mission_done
mission_not_approach:
        CMP #4
        BNE mission_not_tracking
        JSR TRKMSG
        JMP mission_done
mission_not_tracking:
        CMP #5
        BNE mission_damage
        JSR SECALERT
        JMP mission_done
mission_damage:
        AND #7
        TAX
        LDA SYSHP,X     ; a repair may have completed while this notice was queued
        BNE mission_done
        STX WARNIDX
        LDA #<WARNINGEND
        LDX #>WARNINGEND
        LDY #53
        JSR mission_show
        JSR mission_systemtext
        JSR SNDSIREN
mission_done:
        JMP ARRSTEP

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
        LDA #$81
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

NOTICECOUNT: .BYTE 0
NOTICEREAD: .BYTE 0
NOTICEWRITE: .BYTE 0
NOTICEBUF: .BYTE 0,0,0,0,0,0,0,0
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
