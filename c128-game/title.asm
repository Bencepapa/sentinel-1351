; TITLE runs with the raster IRQ off and returns to resident code before S1
; can be reused. The HUD and bitmap use the same splits as the cockpit.
TITLEPKG = $E963
TITLEPAGES = 13
TITLEDECODE = $0D00    ; init only, before the resident low block is unpacked
FKEYF5 = $BF
TITLEMIDSTAGE = $3400   ; init only, in the empty phasor path buffers
TITLETAILSTAGE = $4478  ; init only, in the bitmap matrix (restored from MMAT)
TITLETAILBLANK = $46D0  ; the remaining staging rows have uniform ink
TITLETAILBLANKLEN = 160
TITLEEXTRASTAGE = $4878 ; init only, in the hidden text rows (800 bytes, rows 3-22)
TITLELASTSTAGE = $75E0  ; init only, between the high archive and cockpit art
TITLECOLOR = $DB98
TITLEPUNCTFONT = $40F8 ; eight spare glyphs, restored before the briefing
TITLELOGOBMP = $6A20    ; row 8, column 4, 32 cells wide and four rows
TITLELOGOMAT = $4544
TITLEMAT = $4478       ; first row of the view's matrix
TITLECONFIRMFRAMES = 155
TITLEPREPAGE = 100
TITLERIBBONAGE = 3     ; the ribbon starts here (the original's $9BE5 three frames after the accept)

        * = TITLEPKG
TITLERUN:
        JSR TITLESETUP
        LDA #0
        STA VICENA
        STA BG
        STA BORDER
        STA TITLEARM
        STA TITLEFINE
        STA TITLEPOS
        STA TITLEMENU
        STA TITLEAGE
        STA SHX
        STA SHY
        STA SHOTVIS
        STA SHOTON
        STA SHOTARM
        STA FIREFLAG
        LDA #$80
        STA SEED
        LDX #7
title_seedstars:
        JSR NEWSTAR
        DEX
        BPL title_seedstars
        LDA #1
        STA NT0
        LDA #$6E
        STA SCANX
        LDA #$1E
        JSR title_fillview
        LDX #0
        JSR title_print
        JSR title_blankrow
title_white:
        STA TITLECOLOR,X
        INX
        CPX #40
        BNE title_white
title_sync:
        BIT $D011       ; the tune starts when the picture is complete ($0A68), at a frame's top
        BPL title_sync  ; (its 39 init writes belong to one frame, as the original's)
title_syncwrap:
        BIT $D011
        BMI title_syncwrap
        JSR MUSICINIT

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
        BNE title_aim
        JSR TITLESCROLL
        JSR MUSICTICK
        JMP title_lower
title_aim:
        JSR title_sprites
        LDA TITLEMENU
        CMP #2
        BNE title_lower
        JSR RIBTICK     ; update the row and fine scroll before this frame's strip
        JSR ENGTICK     ; the hum's burst every sixth frame, as the original's fades
        NOP             ; (three NOPs of slack here move the title run's cycle phase: two suite
        NOP             ; tests, the fight's splits and the map's C= close, are phase-sensitive)
        NOP
        LDA TITLEAGE
        BNE title_fly
        JSR CHARGESND
        JSR LAUNCH
        JMP title_guns
title_fly:
        LDA SHOTON
        BEQ title_lower
        JSR phfly        ; advance the cockpit phasor with its normal sub-ticks
        JSR SWEEPSND
        JSR SWEEPSND
        JSR SWEEPSND
        JMP title_guns
title_lower:
        JSR title_stars
title_guns:
        LDA #194
        JSR WAITLN
        JSR SPR7
        JSR SPRGUNS
        AND #$8B        ; cockpit guns, radar sweep and any phasor
        STA VICENA
        JSR SWEEPSND
        LDA #230
        JSR WAITLN
        LDA #0
        STA VICENA
        LDA #233
        JSR WAITST
        LDA TITLEFINE   ; first (CSEL stays clear for the 38-column strip): written after
        STA $D016       ; line 233 began, the fine scroll jittered across its first pixels
        LDA #$0B        ; (an x shake); at the end of line 232 it moves lines 233-234 whole
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
        JSR SWEEPSND
        INC SCANX
        INC SCANX
        LDA SCANX
        CMP #$E0
        BCC TITLEINPUT
        LDA #$60
        STA SCANX
TITLEINPUT:
        LDA TITLEMENU
        CMP #2
        BEQ title_confirm
        JSR GPOTS
        JSR FKEYREAD
        TAY
        LDA CIA1PA
        EOR #$FF
        STA TITLEPORT
        LDX TITLEMENU
        BNE title_select
        JSR title_colors
        LDA TITLEPORT
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
        LDA #0
        STA TITLEARM
        INC TITLEMENU
        JMP title_frame

title_confirm:
        INC TITLEAGE
        LDA TITLEAGE
        CMP #3
        BNE title_fade
        JSR title_hideoptions
        LDA #$1F
        STA $D418
title_fade:
        LDA TITLEAGE
        CMP #TITLECONFIRMFRAMES
        BCS title_leave
        LDA TITLEAGE
        CMP #TITLERIBBONAGE
        BNE title_prepare
        JSR RIBINIT
title_prepare:
        LDA TITLEAGE
        SEC
        SBC #TITLEPREPAGE
        CMP #6
        BCS title_prepared
        JSR BRIEFPREP   ; one row a frame
title_prepared:
title_fadecolor:
        LDA TITLEAGE
        CMP #10
        BCC title_next
        DEC TITLEWAIT
        BNE title_next
        LDA #2
        ; The later C64 loop takes about 2-3 frames per step.
        LDX TITLEAGE
        CPX #29
        BCC title_fadeset
        LDA TITLEINK
        AND #1
        CLC
        ADC #2
title_fadeset:
        STA TITLEWAIT
        JSR title_nextink
        LDX TITLEAGE
        CPX #TITLECONFIRMFRAMES-5
        BCC title_inkok
        LDA #$10        ; the retained label goes too ($86FA), a few frames before the briefing
title_inkok:
        LDX DIFF
        JSR title_optionink
        JMP title_frame

title_leave:            ; the view, the stars and the ribbon go on into the briefing
        LDA #0
        STA SHOTS
        STA SHOTS+1
        LDA #$7E
        STA CURX
        LDA #$81
        STA CURY
        LDA #$79
        STA HUDE+2
        JSR SHIPINIT
        JMP BRIEFRUN

title_openselect:
        JSR MUSICSTOP
        LDA #1          ; the engine's hum ($C38E): a burst now, then sustained until
        STA ENGON       ; the confirm's ticks (the original's count then is 2; the ticks run in
        STA ENGC        ; the frame's body now)
        JSR ENGBURST
        LDA #2
        STA ENGC
        LDA #$1F        ; ($18EA)
        STA $D418
        JSR ENDHIDE
        JSR GVIEWCLEAR
        LDA #$19
        JSR title_fillview
        JSR title_blankrow
        STX TITLEFINE
        STX TITLEARM
        STX TITLEAGE
        STX DIFF
        LDA #1
        STA TITLEWAIT
        LDA #2
        STA TITLEINK
        LDA #$7E
        STA CURX
        LDA #$5E
        STA CURY
        LDX #TITLEOPTIONINDEX
        JSR title_print
        INC TITLEMENU
        LDX #0
        LDA #$17
        JMP title_optionink

; Blank the ink during the phasor flash. Only the selected row gets fresh ink.
title_hideoptions:
        LDX #4
title_hideone:
        LDA #$10
        JSR title_optionink
        DEX
        BPL title_hideone
        RTS

title_move:
        LDA MPRES
        BEQ title_joy
        LDX MDX
        LDY MDY
        JMP title_apply
title_joy:
        LDA TITLEPORT
        AND #3
        TAX
        LDY TITLEJOYDY,X
        LDA TITLEPORT
        LSR A
        LSR A
        AND #3
        TAX
        LDA TITLEJOYDX,X
        TAX
title_apply:
        JSR CAPPLY
        LDX #4
        LDA CURY
title_findrow:
        CMP TITLELIMIT-1,X
        BCS title_foundrow
        DEX
        BNE title_findrow
title_foundrow:
        CPX DIFF
        BEQ title_movedone
        TXA
        PHA
        LDX DIFF
        LDA #$19
        JSR title_optionink
        PLA
        TAX
        STX DIFF
        LDA #$17
title_optionink:
        LDY TITLEOPTIONLO,X
        STY CDST
        LDY TITLEOPTIONHI,X
        STY CDST+1
        LDY #39
title_inkrow:
        STA (CDST),Y
        DEY
        BPL title_inkrow
title_movedone:
        RTS

TITLEMID:
title_sprites:
        LDA #$30        ; the cockpit crosshair
        STA SPRPTR
        LDA CURX
        CLC
        ADC #$2D
        STA $D000
        LDA #0
        ROL A
        LDX SHOTXH
        BEQ title_spritex
        ORA #2
title_spritex:
        STA $D010
        LDA CURY
        STA $D001
        LDA #$0D
        STA $D027
        LDA $D01B
        AND #$FC
        STA $D01B
        LDA $D01D
        AND #$FC
        STA $D01D
        LDA $D017
        AND #$FC
        STA $D017
        LDA $D01C
        AND #$FE
        STA $D01C
        LDA SHOTSHP
        CLC
        ADC #$8C
        STA SPRPTR+1
        LDA SHOTX
        STA $D002
        LDA SHOTY
        STA $D003
        LDA SHOTVIS
        ASL A
        ORA #1
        STA VICENA
        RTS

title_blankrow:
        LDX #39
        LDA #$60
title_blank:
        STA LRROW,X
        DEX
        BPL title_blank
        INX
        LDA #1
        RTS

title_fillview:
        LDX #0
title_fill:
        STA TITLEMAT+40,X
        STA TITLEMAT+344,X
        INX
        BNE title_fill
        LDX #47
title_fillgap:
        STA TITLEMAT+296,X
        DEX
        BPL title_fillgap
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

; The attract IRQ shifted two 33-cell bands once per frame ($1A5F).
; Preserve Y, which holds the function key sampled for this frame.
title_colors:
        LDX #0
title_bandleft:
        LDA $4613,X
        STA $4612,X
        INX
        CPX #33
        BNE title_bandleft
        LDX #32
title_bandright:
        LDA $44FA,X
        STA $44FB,X
        DEX
        BPL title_bandright
        LDA TITLEAGE
        AND #7
        TAX
        LDA TITLEBAND,X
        STA $44FB
        STA $4632
        INC TITLEAGE
        LDA TITLEAGE
        CMP #7
        BCC title_colorend
        SEC
        SBC #7
        AND #7
        BNE title_colorend
        JSR title_nextink
        LDX #31
title_logocolor:
        STA TITLELOGOMAT,X
        STA TITLELOGOMAT+40,X
        STA TITLELOGOMAT+80,X
        STA TITLELOGOMAT+120,X
        DEX
        BPL title_logocolor
        LDA TITLEAGE
        AND #8
        BEQ title_purple
        LDA #$72
        BNE title_creditink
title_purple:
        LDA #$74
title_creditink:
        LDX #31
title_pubink:
        STA $44A4,X
        DEX
        BPL title_pubink
        LDX #22
title_lastink:
        STA $4689,X
        DEX
        BPL title_lastink
        EOR #6
        LDX #11
title_firstink:
        STA $4667,X
        DEX
        BPL title_firstink
title_colorend:
        RTS

title_nextink:
        LDX TITLEINK
        DEC TITLEINK
        BPL title_inkready
        LDA #4
        STA TITLEINK
title_inkready:
        LDA TITLEPALETTE,X
        RTS

; The welcome ribbon ($9BE5, $9CD3, $9D4A): from the confirm on, the bottom row
; scrolls 2 pixels a frame (fine X 7, 5, 3, 1), a cell every fourth frame; every
; third cell step its ink flips between black and white with a voice 2 pulse (42
; times, 504 frames), then it turns light green. The text is $97D9 (BRIEFWELCOME).
RIBINIT:
        LDX #39
rib_blank:
        LDA #$60
        STA LRROW,X
        LDA #0
        STA TITLECOLOR,X
        DEX
        BPL rib_blank
        STX RIBON       ; (X = $FF: running; the rest is the package image's: fine 0, toggle 0, ...)
        RTS

RIBTICK:
        LDA RIBON
        BEQ rib_done
        LDA RIBWAIT
        BEQ rib_move
        DEC RIBWAIT
rib_done:
        RTS
rib_move:
        LDA TITLEFINE
        SEC
        SBC #2
        BPL rib_fine
        LDA #7
rib_fine:
        STA TITLEFINE
        STA INTROFINE
        CMP #7
        BNE rib_done
        DEC RIBDIVIDE
        BNE rib_shift
        LDA #3
        STA RIBDIVIDE
        LDA RIBTOGGLE
        EOR #1
        STA RIBTOGGLE
        JSR rib_ink
        LDA #0
        STA $D40B
        STA $D407
        STA $D40D
        STA $D409
        LDA #3
        STA $D40A
        LDA #2
        STA $D40C
        LDA #$3F
        STA $D408
        LDA #$41
        STA $D40B
        DEC RIBLEFT
        BNE rib_shift
        LDA #0          ; the last: light green, no more scrolling
        STA RIBON
        LDA #13
rib_ink:
        LDX #39
rib_inkrow:
        STA TITLECOLOR,X
        DEX
        BPL rib_inkrow
        RTS
rib_shift:
        LDX #0
rib_copy:
        LDA LRROW+1,X
        STA LRROW,X
        INX
        CPX #39
        BNE rib_copy
        LDY RIBINDEX
        LDA BRIEFWELCOME,Y
        CMP #$FF
        BNE rib_char
        LDA #$60
        BNE rib_put
rib_char:
        INC RIBINDEX
rib_put:
        STA LRROW+39
        RTS

; Draw from the live cockpit character set. Each descriptor gives a VIC
; bitmap address and a terminated run of glyphs. Bit 7 selects the wordmark
; scale. Ink uses bitmap pair 2 (the low matrix nibble), leaving pair 3 for stars.
title_print:
        LDA TITLELINES+1,X
        BEQ title_printdone
        STA CDST+1
        LDA TITLELINES,X
        STA CDST
        INX
        INX
title_char:
        LDA TITLELINES,X
        INX
        CMP #$FF
        BEQ title_print
        STX TITLEINDEX
        PHA
        AND #$7F
        LDX #8
        STX CSRC+1
        ASL A
        ROL CSRC+1
        ASL A
        ROL CSRC+1
        ASL A
        ROL CSRC+1
        STA CSRC
        PLA
        BMI title_bigchar
        LDY #7
title_smallrow:
        LDA (CSRC),Y
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA TITLENIBBLE,X
        STA (CDST),Y
        LDA (CSRC),Y
        AND #15
        TAX
        TYA
        ORA #8
        TAY
        LDA TITLENIBBLE,X
        STA (CDST),Y
        TYA
        AND #7
        TAY
        DEY
        BPL title_smallrow
        LDA #16
title_charnext:
        CLC
        ADC CDST
        STA CDST
        BCC title_charindex
        INC CDST+1
title_charindex:
        LDX TITLEINDEX
        JMP title_char
title_printdone:
        RTS

TITLETAIL:
title_bigchar:
        LDA CDST
        PHA
        LDA CDST+1
        PHA
        LDY #0
        STY TITLEGLYPHY
title_bigrow:
        LDA (CSRC),Y
        STA TITLEBITS
        TYA
        AND #1
        ASL A
        ASL A
        TAY
title_bigpair:
        LDA #0
        ASL TITLEBITS
        ROL A
        ASL TITLEBITS
        ROL A
        TAX
        LDA TITLEPAIR,X
        STA (CDST),Y
        INY
        STA (CDST),Y
        INY
        STA (CDST),Y
        INY
        STA (CDST),Y
        TYA
        CLC
        ADC #5
        TAY
        CPY #32
        BCC title_bigpair
        INC TITLEGLYPHY
        LDY TITLEGLYPHY
        CPY #8
        BEQ title_bigdone
        TYA
        AND #1
        BNE title_bigrow
        LDA CDST
        CLC
        ADC #<320
        STA CDST
        LDA CDST+1
        ADC #>320
        STA CDST+1
        JMP title_bigrow
title_bigdone:
        PLA
        STA CDST+1
        PLA
        STA CDST
        LDA #32
        BNE title_charnext

; Advance a few of the cockpit stars. Only background pairs can be set and
; only star pairs can be cleared, so crossing the lettering leaves it intact.
title_stars:
        LDX #7
title_starloop:
        JSR title_staraddr
        LDA (PTR),Y
        AND MASK3,X
        CMP MASK3,X
        BNE title_starmove
        LDA (PTR),Y
        AND CLEARM,X
        STA (PTR),Y
title_starmove:
        LDX SAVEX
        JSR MOVESTAR
        JSR title_staraddr
        LDA (PTR),Y
        AND MASK3,X
        BNE title_starstep
        LDA (PTR),Y
        ORA MASK3,X
        STA (PTR),Y
title_starstep:
        LDX SAVEX
        DEX
        BPL title_starloop
        RTS
title_staraddr:
        STX SAVEX
        LDA STARX,X
        STA POSX
        LDA STARY,X
        STA POSY
        JMP PIXADDR

TITLEARM: .BYTE 0
TITLEFINE:.BYTE 0
TITLEPOS: .BYTE 0
TITLEMENU:.BYTE 0
TITLEPORT:.BYTE 0
TITLEAGE: .BYTE 0
TITLEINK: .BYTE 4
TITLEWAIT:.BYTE 0
RIBON:   .BYTE 0
RIBWAIT: .BYTE 1       ; skip the first frame after RIBINIT, then start the scroll
RIBDIVIDE:.BYTE 3
RIBLEFT: .BYTE 42
RIBTOGGLE:.BYTE 0
RIBINDEX:.BYTE 0
TITLEINDEX:.BYTE 0
TITLEBITS:.BYTE 0
TITLEGLYPHY:.BYTE 0
TITLEOPTIONLO: .BYTE <$44F0,<$4540,<$4590,<$45E0,<$4630
TITLEOPTIONHI: .BYTE >$44F0,>$4540,>$4590,>$45E0,>$4630
TITLELIMIT: .BYTE $66,$76,$86,$96
TITLEJOYDX: .BYTE 0,$FD,3,0
TITLEJOYDY: .BYTE 0,$FE,2,0
TITLEBAND: .BYTE $72,$79,$72,$79,$7A,$79,$7A,$79
TITLEPALETTE: .BYTE $78,$7A,$74,$79,$72
TITLEPAIR: .BYTE $00,$0A,$A0,$AA
TITLENIBBLE: .BYTE $00,$02,$08,$0A,$20,$22,$28,$2A,$80,$82,$88,$8A,$A0,$A2,$A8,$AA
TITLEART:
TITLELINES:
; TITLELETTERDATA
TITLETEXT:
; TITLECOPYDATA
TITLETEXTEND:
TITLESETUP:
        LDY #TITLEPUNCTSIZE-1
title_fontcopy:
        LDA TITLEPUNCT,Y
        STA TITLEPUNCTFONT,Y
        DEY
        BPL title_fontcopy
        RTS

TITLEFONTRESTORE:
        LDA #0
        LDY #TITLEPUNCTSIZE-1
title_fontblank:
        STA TITLEPUNCTFONT,Y
        DEY
        BPL title_fontblank
        RTS

; TITLEBRIEFWELCOME
TITLEPUNCT:
; TITLEPUNCTDATA
TITLEPUNCTEND:
TITLEEXTRA:
; TITLEMUSIC
; TITLEINTRO
TITLEEND:
