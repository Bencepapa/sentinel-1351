; TITLE runs with the raster IRQ off. It returns to resident code before S1
; can be reused. The raster polling loop draws a static cockpit.
TITLEPKG = $E963
TITLEPAGES = 6
FKEYF5 = $BF
TITLEARTSTAGE = $3400   ; init only, in the empty phasor path buffers
TITLECOLOR = $DB98
TITLELOGOBMP = $6A40    ; bitmap row 8, column 8 (24 cells wide, two rows)
TITLELOGOMAT = $4548
TITLEMENUMAT = $44A0   ; rows 4 through 15 in the bitmap matrix
TITLEMENUCOL = $D8A0

        * = TITLEPKG
TITLERUN:
        LDA #0
        STA VICENA
        STA BG
        STA BORDER
        STA TITLEARM
        STA TITLEFINE
        STA TITLEPOS
        STA TITLEMENU
        LDX #191
title_logo:
        LDA TITLELOGO,X
        STA TITLELOGOBMP,X
        LDA TITLELOGO+192,X
        STA TITLELOGOBMP+320,X
        DEX
        CPX #$FF
        BNE title_logo
        LDX #23
        LDA #$3E        ; cyan foreground and light-blue shadow
title_ink:
        STA TITLELOGOMAT,X
        STA TITLELOGOMAT+40,X
        DEX
        BPL title_ink
        LDX #39
title_blank:
        LDA #$40
        STA LRROW,X
        LDA #1
        STA TITLECOLOR,X
        DEX
        BPL title_blank
title_frame:
        BIT $D011
        BPL title_frame
title_wrap:
        BIT $D011
        BMI title_wrap
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
title_hud_edge:
        DEY
        BNE title_hud_edge
        LDA HUDBRD
        STA BORDER
        LDA #$0B
        STA BG
        LDA #74
        JSR WAITST
        LDA #1
        STA BG
        STA BORDER
        LDY #10
title_view_edge:
        DEY
        BNE title_view_edge
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
        LDA TITLEMENU
        BEQ title_view
        JSR title_menusplit
title_view:
        JSR TITLESCROLL
        LDA #194
        JSR WAITLN
        JSR SPRGUNS
        LDA #$09        ; just the two cockpit guns
        STA VICENA
        LDA #230
        JSR WAITLN
        LDA #0
        STA VICENA
        LDA #233
        JSR WAITST
        LDA #$0B
        STA BORDER
        STA BG
        LDA #$1B
        STA $D011
        LDA TITLEFINE   ; CSEL stays clear for the 38-column strip
        STA $D016
        LDA #$20
        STA $D018
        LDA #242
        JSR WAITST
        LDA #0
        STA BORDER
        STA BG
        LDA #8
        STA $D016
TITLEINPUT:
        JSR GPOTS
        JSR FKEYREAD
        TAY
        LDA CIA1PA
        EOR #$FF
        STA TITLEPORT
        LDX TITLEMENU
        BNE title_select
        AND #$10
        BNE title_start
        CPY #FKEYF5
        BEQ title_start
        CPY #FKEYF7
        BEQ title_start
title_arm:
        LDA #1
        STA TITLEARM
title_next:
        JMP title_frame
title_start:
        LDA TITLEARM
        BEQ title_next
        JSR title_openselect
        JMP title_frame
title_select:
        JSR title_move
        LDA TITLEPORT
        AND #$10
        BEQ title_arm
        LDA TITLEARM
        BEQ title_next
title_leave:
        JSR ENDHIDE
        LDX #191
        LDA #0
title_erase:
        STA TITLELOGOBMP,X
        STA TITLELOGOBMP+320,X
        DEX
        CPX #$FF
        BNE title_erase
        LDX #0
title_restore:
        LDA MMAT+40,X
        STA TITLEMENUMAT,X
        LDA MMAT+264,X
        STA TITLEMENUMAT+224,X
        LDA COLORDATA+160,X
        STA TITLEMENUCOL,X
        LDA COLORDATA+384,X
        STA TITLEMENUCOL+224,X
        INX
        BNE title_restore
        JMP LRCLEAR

; The view temporarily uses its matrix as a second text screen. The HUD,
; lower cockpit and scroller keep their usual display modes.
title_menusplit:
        LDA #82
        JSR WAITST
        LDA #$1B
        STA $D011
        LDA #8
        STA $D016
        LDA #$10
        STA $D018
        LDA #178
        JSR WAITST
        LDA #$3B
        STA $D011
        LDA #$18
        STA $D016
        STA $D018
        RTS

title_openselect:
        JSR ENDHIDE
        LDA #0
        STA TITLEARM
        STA TITLEDELAY
        LDA #8
        STA TITLEY
        LDX #239
title_menuclear:
        LDA #$40
        STA TITLEMENUMAT,X
        STA TITLEMENUMAT+240,X
        LDA #14
        STA TITLEMENUCOL,X
        STA TITLEMENUCOL+240,X
        DEX
        CPX #$FF
        BNE title_menuclear
        LDX #14
title_head:
        LDA TITLEHEADING,X
        STA TITLEMENUMAT+13,X
        LDA TITLEPROMPT,X
        STA TITLEMENUMAT+373,X
        DEX
        BPL title_head
        LDX #0
        LDY #0
title_menurow:
        LDA TITLEOPTIONLO,X
        STA title_label+1
        LDA TITLEOPTIONHI,X
        STA title_label+2
title_menuchar:
        LDA TITLELABELS,Y
        BMI title_menunext
title_label:
        STA $FFFF
        INC title_label+1
        INY
        BNE title_menuchar
title_menunext:
        INY
        INX
        CPX #5
        BCC title_menurow
        INC TITLEMENU
        LDX DIFF
        LDA #7
        JMP title_highlight

title_move:
        LDA MPRES
        BNE title_mouse
        LDA TITLEPORT
        AND #3
        BEQ title_joyidle
        CMP #3
        BEQ title_joyidle
        TAY
        LDA TITLEDELAY
        BEQ title_joystep
        DEC TITLEDELAY
        RTS
title_joyidle:
        LDA #0
        STA TITLEDELAY
        RTS
title_joystep:
        LDA #8
        STA TITLEDELAY
        LDX DIFF
        CPY #1
        BEQ title_joyup
        CPX #4
        BEQ title_movedone
        INX
        BNE title_joycenter
title_joyup:
        DEX
        BMI title_movedone
title_joycenter:
        TXA
        ASL A
        ASL A
        ASL A
        ASL A
        ORA #8
        STA TITLEY
        BNE title_recolor
title_mouse:
        LDA MDY
        BEQ title_movedone
        BMI title_mouseup
        CLC
        ADC TITLEY
        CMP #80
        BCC title_mousey
        LDA #79
        BNE title_mousey
title_mouseup:
        CLC
        ADC TITLEY
        BCS title_mousey
        LDA #0
title_mousey:
        STA TITLEY
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
title_recolor:
        CPX DIFF
        BEQ title_movedone
        TXA
        PHA
        LDX DIFF
        LDA #14
        JSR title_highlight
        PLA
        TAX
        STX DIFF
        LDA #7
title_highlight:
        PHA
        LDA TITLEOPTIONLO,X
        STA CDST
        LDA TITLEOPTIONHI,X
        CLC
        ADC #$94
        STA CDST+1
        PLA
        LDY #13
title_coloroption:
        STA (CDST),Y
        DEY
        BPL title_coloroption
title_movedone:
        RTS

TITLESCROLL:
        LDA TITLEFINE
        SEC
        SBC #1
        AND #7
        STA TITLEFINE
        CMP #7
        BNE title_scrolldone
        LDX #0
title_shift:
        LDA LRROW+1,X
        STA LRROW,X
        INX
        CPX #39
        BNE title_shift
        LDY TITLEPOS
        LDA TITLETEXT,Y
        BPL title_feed
        LDY #0
        LDA TITLETEXT,Y
title_feed:
        STA LRROW+39
        INY
        STY TITLEPOS
title_scrolldone:
        RTS

TITLEARM: .BYTE 0
TITLEFINE:.BYTE 0
TITLEPOS: .BYTE 0
TITLEMENU:.BYTE 0
TITLEPORT:.BYTE 0
TITLEY:   .BYTE 0
TITLEDELAY:.BYTE 0
TITLEOPTIONLO: .BYTE <$4500,<$4528,<$4550,<$4578,<$45A0
TITLEOPTIONHI: .BYTE >$4500,>$4528,>$4550,>$4578,>$45A0
; TITLEMENUDATA
TITLEART:
TITLETEXT:
; TITLECOPYDATA
TITLETEXTEND:
TITLELOGO:
; TITLELOGODATA
TITLEEND:
