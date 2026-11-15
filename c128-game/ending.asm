; Game endings. Original $8869, $F5B9 and $F440.
; Installed before the high image is unpacked; $0200-$0C5F is saved in VDC RAM.
        * = $0200
ENDSETUP:
        LDA #$0A
        LDX #$60
        JSR ELVADR
        JSR ENDCOPY
        DEC FAST
        RTS
; A descriptor is source address and byte count; the VDC address auto-increments.
ENDCOPY:
        LDA #<ENDRANGES
        STA end_desc+1
        LDA #>ENDRANGES
        STA end_desc+2
end_next:
        JSR ENDGET
        STA CSRC
        JSR ENDGET
        STA CSRC+1
        BEQ end_copydone
        JSR ENDGET
        STA ENDCLEFT
        JSR ENDGET
        STA ENDCLEFT+1
        LDY #0
        LDX ENDCLEFT+1
        BEQ end_tailstart
end_bytes:
        LDA ENDCOPYMODE
        BNE end_copyread
        LDA (CSRC),Y
        JSR ELWRITE
        JMP end_copynext
end_copyread:
        JSR ELREAD
        STA (CSRC),Y
end_copynext:
        INY
        BNE end_bytes
        INC CSRC+1
        DEX
        BNE end_bytes
end_tailstart:
        LDX ENDCLEFT
        BEQ end_nextjump
end_tailbytes:
        LDA ENDCOPYMODE
        BNE end_tailread
        LDA (CSRC),Y
        JSR ELWRITE
        JMP end_tailnext
end_tailread:
        JSR ELREAD
        STA (CSRC),Y
end_tailnext:
        INY
        DEX
        BNE end_tailbytes
end_nextjump:
        JMP end_next
end_copydone:RTS
ENDGET:
end_desc:LDA ENDRANGES
        INC end_desc+1
        BNE end_getdone
        INC end_desc+2
end_getdone:CMP #0
        RTS
ENDVIEW:
        LDA ENDMODE
        BEQ end_check
        JMP ENDFLASH
end_check:
        LDA SHIPLOST
        ORA M_DEAD+4
        BEQ end_checkwin
        LDA #1
        STA ENDMODE
        LDA #255
        STA ENDTIME
        LDA #<g_mt9
        STA iv1+1
        LDA #>g_mt9
        STA iv1+2
        LDA #0
        STA FIREFLAG
        STA SHOTARM
        JSR ENDALARM
        JSR ENDQUIET
        RTS
end_checkwin:
        LDA MSSTATE
        ORA HYPON
        ORA WIPE
        ORA APPR
        BNE end_viewdone
        DEC ENDWIN
        BPL end_viewdone
        LDA #7          ; the original polls every 64 loops: a cockpit frame is a loop,
        LDX MAPSHOWN    ; the map's loops run about 14 a frame, so it polls 2x faster there
        BEQ end_pollrate
        LDA #3
end_pollrate:STA ENDWIN
        LDY #59
end_sector:
        LDA M_STATE,Y
        BEQ end_empty
        CMP #$FF
        BNE end_viewdone
end_empty:
        DEY
        BPL end_sector
        LDA M_FLG
        ORA M_FLG+1
        ORA M_FLG+2
        ORA M_FLG+3
        BNE end_viewdone
        DEC ENDQUAL
        BNE end_viewdone
        LDA #2
        STA ENDMODE
        JMP ENDSCENE
end_viewdone:JMP VIEWWORK
ENDFLASH:
        JSR RANDOM
        AND #3
        TAX
        LDA ENDCOLORS,X
        STA FLASHC
        LDA ENDTIME
        CMP #150
        BCS end_flashnext
        LDA FLASHC
        STA HUDBRD
end_flashnext:
        JSR ENDRATTLE
        DEC ENDTIME
        BEQ ENDSCENE
        RTS
ENDSCENE:
        SEI
        LDA #0
        STA $D01A
        STA $D015
        STA $D404
        STA $D40B
        STA FAST
        STA TRUN
        INC MAPSHOWN    ; protected pixel-1 star plotter; ENDLOOP never draws the map
        LDA #$FF
        STA JOYG
        JSR ENDHIDE
        NOP
        NOP
        LDA #$18
        STA $D016
        STA $D018
        LDA #0
        STA $D020
        STA $D021
        LDX #0
end_matrix:
        LDA #$1A
        STA $4400,X
        STA $4500,X
        STA $4600,X
        STA $4700,X
        INX
        BNE end_matrix
        LDA #$60
        STA CDST+1
        LDA #0
        STA CDST
        TAY
        LDX #32
end_clear:
        STA (CDST),Y
        INY
        BNE end_clear
        INC CDST+1
        DEX
        BNE end_clear
        LDX #0
        LDA ENDMODE
        CMP #2
        BNE end_titles
        LDX #2
end_titles:
        LDA ENDTEXTLO,X
        STA ENDTEXTP
        LDA ENDTEXTHI,X
        STA ENDTEXTP+1
        LDA #8
        LDX ENDMODE
        CPX #2
        BNE end_firstrow
        LDA #5
end_firstrow:
        STA ENDROW
        JSR ENDPRINT
        LDX #1
        LDA ENDMODE
        CMP #2
        BNE end_second
        LDX #3
end_second:
        LDA ENDTEXTLO,X
        STA ENDTEXTP
        LDA ENDTEXTHI,X
        STA ENDTEXTP+1
        LDA #12
        LDX ENDMODE
        CPX #2
        BNE end_secondrow
        LDA #7
end_secondrow:
        STA ENDROW
        JSR ENDPRINT
        LDA #$5E
        STA ENDDELAY
        LDA #1
        STA ENDDELAY+1
        LDA ENDMODE
        CMP #2
        BNE end_startwait
        JSR ENDREPORT
end_startwait:
        LDA ENDMODE
        SEC
        SBC #1
        TAX
        LDA ENDAUTOLO,X
        STA ENDTIME
        LDA ENDAUTOHI,X
        STA ENDTIME+1
        LDA ENDKEYLO,X
        STA ENDKEYWAIT
        LDA ENDKEYHI,X
        STA ENDKEYWAIT+1
        JSR ENDSHOW
        JMP ENDLOOP
ENDREPORT:
        LDA ENDMODE
        CMP #2
        BEQ end_reportdone
        JSR RANDOM
        AND #3
        TAX
        LDA ENDHEADERLO,X
        STA ENDTEXTP
        LDA ENDHEADERHI,X
        STA ENDTEXTP+1
        LDA #4
        STA ENDROW
end_headerline:
        JSR ENDPRINT
        CLC
        LDA ENDTEXTP
        ADC #21
        STA ENDTEXTP
        BCC end_headerrow
        INC ENDTEXTP+1
end_headerrow:
        INC ENDROW
        INC ENDROW
        LDA ENDROW
        CMP #14
        BNE end_headerline
end_reportdone:
        JSR ENDRATINGINPUT
        JSR ENDRATING
        STA ENDCLASS
        STX ENDRANK
        LDA DIFF
        CMP #3
        BCS end_rankok
        LDA ENDMODE
        CMP #2
        BEQ end_rankok
        TXA
        AND #3
        STA ENDRANK
end_rankok:
        LDX ENDRANK
        LDA #<ENDRANKTEXT
        STA ENDTEXTP
        LDA #>ENDRANKTEXT
        STA ENDTEXTP+1
end_rankptr:
        CPX #0
        BEQ end_rankprint
        CLC
        LDA ENDTEXTP
        ADC #14
        STA ENDTEXTP
        BCC end_rankptrnext
        INC ENDTEXTP+1
end_rankptrnext:
        DEX
        JMP end_rankptr
end_rankprint:
        LDA #15
        STA ENDROW
        JSR ENDPRINT
        LDA ENDCLASS
        EOR #7
        CLC
        ADC #$71
        STA ENDCLASSDIGIT
        LDA #<ENDCLASSTEXT
        STA ENDTEXTP
        LDA #>ENDCLASSTEXT
        STA ENDTEXTP+1
        LDA #208
        STA ENDCOL
        JSR ENDPRINT
        LDA #0
        STA ENDCOL
        STA ENDDELAY
        STA ENDDELAY+1
        RTS
ENDLOOP:
end_wrap:BIT $D011
        BPL end_wrap
end_wraplow:BIT $D011
        BMI end_wraplow
        JSR STARS
        DEC ENDPALCOUNT
        BNE end_letterdone
        LDA #6
        STA ENDPALCOUNT
        DEC ENDPAL
        BPL end_paletteindex
        LDA #4
        STA ENDPAL
end_paletteindex:
        LDX ENDPAL
        LDA ENDCOLORS,X
        ORA #$70
        LDX #0
end_letterflash:
        STA $4400,X
        STA $4500,X
        STA $4600,X
        STA $4700,X
        INX
        BNE end_letterflash
end_letterdone:
        LDA ENDDELAY
        ORA ENDDELAY+1
        BEQ end_reportwaited
        LDA ENDDELAY
        BNE end_delaylo
        DEC ENDDELAY+1
end_delaylo:
        DEC ENDDELAY
        LDA ENDDELAY
        ORA ENDDELAY+1
        BNE end_reportwaited
        JSR ENDREPORT
end_reportwaited:
        LDA ENDTIME
        BNE end_timelo
        DEC ENDTIME+1
end_timelo:
        DEC ENDTIME
        LDA ENDTIME
        ORA ENDTIME+1
        BEQ ENDRESET
end_waitinput:
        LDA ENDKEYWAIT
        ORA ENDKEYWAIT+1
        BEQ end_readbutton
        LDA ENDKEYWAIT
        BNE end_keylo
        DEC ENDKEYWAIT+1
end_keylo:
        DEC ENDKEYWAIT
        JMP end_loopnext
end_readbutton:
        LDA #$FF
        STA $DC00
        LDA $DC00
        AND #$10
        BEQ ENDRESET
end_loopnext:
        JMP ENDLOOP
ENDRESET:
        JSR ENDHIDE
        LDA #$0A
        LDX #$60
        JSR ELVADR
        LDA #1
        STA ENDCOPYMODE
        JSR ENDCOPY
        LDX #0
end_colorback:
        LDA COLORDATA,X
        STA $D800,X
        LDA COLORDATA+256,X
        STA $D900,X
        LDA COLORDATA+512,X
        STA $DA00,X
        LDA COLORDATA+768,X
        STA $DB00,X
        INX
        BNE end_colorback
        JSR ENDSTREAMS
        JSR MRGLYPHBACK
        JSR g_gi2
        LDA #1          ; g_gi2 put type 1 back in the fighter slots: the shape cache, the
        STA SHLT        ; type and the sprites' looks (a type 2/3 fight leaves them set to
        STA SQTYPE      ; its own) must say so, or the fighters never render
        STA ETYPE
        LDA #0
        STA SHLK
        LDA #$2C        ; shpj back to its BIT
        STA shpj
        JSR GTYPE
        JSR SHIPINIT
        JSR EFRESET
        JSR g_gi9
        LDA #0
        STA ENDMODE
        STA ENDWIN
        STA ENDENER
        STA ENDENER+1
        STA ENDENER+2
        STA ENDPROTON
        STA ENDPROTON+1
        STA ENDBORROW
        LDA #60
        STA ENDQUAL
        JMP ENDRETURN
; A text line uses the original 16-pixel-wide bitmap alphabet ($0816).
ENDPRINT:
        LDA #0
        STA ENDINDEX
        LDA #$60
        STA CDST+1
        LDA ENDCOL
        STA CDST
        LDX ENDROW
end_rowaddr:
        CLC
        LDA CDST
        ADC #$40
        STA CDST
        LDA CDST+1
        ADC #1
        STA CDST+1
        DEX
        BNE end_rowaddr
end_character:
        LDY ENDINDEX
        LDA ENDTEXTP
        STA CSRC
        LDA ENDTEXTP+1
        STA CSRC+1
        LDA (CSRC),Y
        BEQ end_printdone
        PHA
        ASL A
        ASL A
        ASL A
        STA CSRC
        PLA
        LSR A
        LSR A
        LSR A
        LSR A
        LSR A
        CLC
        ADC #$40
        STA CSRC+1
        LDY #7
end_glyph:
        LDA (CSRC),Y
        PHA
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA ENDEXPAND,X
        STA (CDST),Y
        PLA
        AND #15
        TAX
        LDA ENDEXPAND,X
        PHA
        TYA
        CLC
        ADC #8
        TAY
        PLA
        STA (CDST),Y
        TYA
        SEC
        SBC #8
        TAY
        DEY
        BPL end_glyph
        CLC
        LDA CDST
        ADC #16
        STA CDST
        BCC end_charptr
        INC CDST+1
end_charptr:
        INC ENDINDEX
        JMP end_character
end_printdone:RTS
ENDONE:
        LDY HUDE+3
        CPY #$70
        BNE end_onecount
        INC ENDBORROW
end_onecount:
        INC ENDENER
        BNE end_oneret
        INC ENDENER+1
        BNE end_oneret
        INC ENDENER+2
end_oneret:RTS
ENDPROTONUSED:
        INC ENDPROTON
        BNE end_protonret
        INC ENDPROTON+1
end_protonret:
        DEC $485B
        RTS
; $3350, then $274C. Voice 2 noise and the voice 1 pulse rattle.
ENDALARM:
        LDA #15
        STA $D418
        LDA #0
        STA $D40B
        STA $D40D
        STA $D407
        LDA #$6B
        STA $D40C
        LDA #6
        STA $D408
        LDA #$81
        STA $D40B
        LDA #0
        STA $D404
        STA $D402
        STA $D405
        LDA #8
        STA $D401
        STA $D403
        LDA #$F0
        STA $D406
        LDA #$41
        STA $D404
        RTS
ENDRATTLE:
        LDY #24
end_rattle:
        LDA ENDPULSE
        SBC #13
        STA ENDPULSE
        STA $D403
        LDA ENDFREQ
        SBC #$3A
        STA ENDFREQ
        STA $D400
        BCS end_rattlenext
        LDA ENDFREQ+1
        SBC #8
        STA ENDFREQ+1
        STA $D401
end_rattlenext:
        DEY
        BNE end_rattle
        RTS
ENDRATINGINPUT:
        LDA #0
        STA ENDVICTORY
        LDA ENDMODE
        CMP #2
        BNE end_statstart
        LDA #4
        STA ENDVICTORY
end_statstart:
        LDX #1
end_statcopy:
        LDA HITS,X
        STA ENDHITS,X
        LDA KILLS,X
        STA ENDKILLS,X
        LDA SHOTS,X
        STA ENDSHOTS,X
        LDA ENDPROTON,X
        STA ENDRPROTON,X
        DEX
        BPL end_statcopy
        INC ENDKILLS
        BNE end_energyinput
        INC ENDKILLS+1
end_energyinput:
        LDX #2
end_energycopy:
        LDA ENDENER,X
        STA ENDRENER,X
        DEX
        BPL end_energycopy
        LDA M_DEAD+4
        STA ENDPLANET
        LDA #$AE        ; $F9D6 counts the final full-meter overflow as well
        LDX #0
        LDY ENDMODE
        CPY #2
        BEQ end_energybias
        LDA #$1E
        LDX #$46
end_energybias:
        CLC
        ADC ENDRENER
        STA ENDRENER
        TXA
        ADC ENDRENER+1
        STA ENDRENER+1
        BCC end_energyremaining
        INC ENDRENER+2
end_energyremaining:
        CPY #2
        BEQ end_inputdone
        LDX #3
end_digit:
        LDA HUDE,X
        AND #15
        TAY
        BEQ end_nextdigit
end_adddigit:
        CLC
        LDA ENDRENER
        ADC ENDWEIGHTLO,X
        STA ENDRENER
        LDA ENDRENER+1
        ADC ENDWEIGHTHI,X
        STA ENDRENER+1
        BCC end_digitcarry
        INC ENDRENER+2
end_digitcarry:
        DEY
        BNE end_adddigit
end_nextdigit:
        DEX
        BPL end_digit
end_inputdone:
        RTS
ENDMODE:.BYTE 0
ENDWIN:.BYTE 0
ENDQUAL:.BYTE 60
ENDTIME:.BYTE 0,0
ENDRANK:.BYTE 0
ENDCLASS:.BYTE 0
ENDROW:.BYTE 0
ENDINDEX:.BYTE 0
ENDCOL:.BYTE 0
ENDTEXTP:.BYTE 0,0
ENDCLEFT = ENDTIME       ; copy scratch is dead before the ending timer starts
ENDCOPYMODE:.BYTE 0
ENDENER:.BYTE 0,0,0
ENDBORROW:.BYTE 0
ENDPROTON:.BYTE 0,0
ENDDELAY:.BYTE 0,0
ENDKEYWAIT:.BYTE 0,0
ENDPULSE:.BYTE 0
ENDFREQ:.BYTE 0,0
ENDPAL:.BYTE 4
ENDPALCOUNT:.BYTE 1
ENDPLANET:.BYTE 0
ENDHITS:.BYTE 0,0
ENDKILLS:.BYTE 0,0
ENDRENER:.BYTE 0,0,0
ENDRPROTON:.BYTE 0,0
ENDSHOTS:.BYTE 0,0
ENDSCORE:.BYTE 0,0,0
ENDCOLORS:.BYTE 2,8,10,4,9
ENDWEIGHTLO:.BYTE $E8,100,10,1
ENDWEIGHTHI:.BYTE 3,0,0,0
ENDAUTOLO:.BYTE $A0,$90
ENDAUTOHI:.BYTE $27,$58
ENDKEYLO:.BYTE $BC,$86
ENDKEYHI:.BYTE 1,2
ENDCLASSTEXT:.BYTE 67,76,65,83,83,32
ENDCLASSDIGIT:.BYTE $71,0
ENDEXPAND:.BYTE 0,2,8,10,32,34,40,42,128,130,136,138,160,162,168,170
ENDTEXTLO:.BYTE <ENDDEATHTEXT,<ENDLOSTTEXT,<ENDWINTEXT,<ENDSAFETEXT
ENDTEXTHI:.BYTE >ENDDEATHTEXT,>ENDLOSTTEXT,>ENDWINTEXT,>ENDSAFETEXT
ENDDEATHTEXT:
; ENDDEATHTEXTDATA
ENDLOSTTEXT:
; ENDLOSTTEXTDATA
ENDWINTEXT:
; ENDWINTEXTDATA
ENDSAFETEXT:
; ENDSAFETEXTDATA
ENDRANKTEXT:
; ENDRANKTEXTDATA
ENDHEADERLO:.BYTE <ENDHEADER0,<ENDHEADER1,<ENDHEADER2,<ENDHEADER3
ENDHEADERHI:.BYTE >ENDHEADER0,>ENDHEADER1,>ENDHEADER2,>ENDHEADER3
; ENDHEADERDATA
; ENDRATINGDATA
ENDRANGES:
; ENDRANGEDATA
        .BYTE 0,0
ENDINGEND:
