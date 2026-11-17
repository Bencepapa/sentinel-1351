; Game endings. Original $8869 (death), $F5B9 (victory) and $F440 (the rating).
; Installed before the high image is unpacked; $0200-$0C5F is saved in VDC RAM.
; VDC RAM (build.py): the saved workspace, the reset snapshot (ENDRANGES), then
; the payload staged at ENDSTAGE: the victory text, the death reports and the
; packed matrix/HUD/cockpit-art/bottom-sprite masters.
        * = $0200
ENDSETUP:
        LDA #<ENDSTAGE  ; the payload, before GINIT2 unpacks the high image over it
        STA CSRC
        LDA #>ENDSTAGE
        STA CSRC+1
        LDA #>ENDVPAY
        LDX #<ENDVPAY
        JSR ELVADR
        LDX #ENDPAYPAGES
        JSR ELSAVE
        JSR GINIT2
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
; Run-length stream from the current VDC address: 0, address = a new destination
; (high byte 0: the end); 1-$7F = that many literal bytes; $81-$FF = the next byte
; ($80 less) times.
ENDUNPACK:
eu_token:JSR ELREAD
        TAX
        BEQ eu_dest
        BPL eu_literal
        JSR ELREAD
eu_run: JSR eu_put
        DEX
        CPX #$80
        BNE eu_run
        BEQ eu_token
eu_literal:JSR ELREAD
        JSR eu_put
        DEX
        BNE eu_literal
        BEQ eu_token
eu_dest:JSR ELREAD
        STA CDST
        JSR ELREAD
        STA CDST+1
        BNE eu_token
        RTS
eu_put: LDY #0
        STA (CDST),Y
        INC CDST
        BNE eu_putdone
        INC CDST+1
eu_putdone:RTS
ENDVIEW:
        LDA ENDMODE
        BEQ end_check
        CMP #2
        BNE end_flashjump
        JMP ENDWINFRAME
end_flashjump:JMP ENDFLASH
end_check:
        LDA SHIPLOST
        ORA M_DEAD+4
        BEQ end_checkwin
        LDA #1
        STA ENDMODE
        LDA #255
        STA ENDTIME
        JSR ENDALARM
ENDSTOP:                ; no input, fire, map key or jump; base hooks and enemy fire off
        LDA #<g_mt9
        STA iv1+1
        LDA #>g_mt9
        STA iv1+2
        LDA #0
        STA FIREFLAG
        STA SHOTARM
        JMP ENDQUIET
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
        JMP ENDWINSTART
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
; The death's full-screen star field ($88D7).
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
        LDA #>ENDVHEAD  ; the four reports, from VDC RAM into the hidden text screen
        LDX #<ENDVHEAD
        JSR ELVADR
        JSR ENDUNPACK
        LDA #<ENDDEATHTEXT
        LDX #>ENDDEATHTEXT
        LDY #8
        JSR ENDPRINTAT
        LDA #<ENDLOSTTEXT
        LDX #>ENDLOSTTEXT
        LDY #12
        JSR ENDPRINTAT
        LDA #$5E
        STA ENDDELAY
        LDA #1
        STA ENDDELAY+1
        LDA #<ENDDEATHAUTO
        STA ENDTIME
        LDA #>ENDDEATHAUTO
        STA ENDTIME+1
        LDA #<ENDDEATHKEY
        STA ENDKEYWAIT
        LDA #>ENDDEATHKEY
        STA ENDKEYWAIT+1
        JSR ENDSHOW
        JMP ENDLOOP
ENDREPORT:
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
        JSR ENDRANKSET
        LDA #15
        STA ENDROW
        JSR ENDPRINT
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
; $F3CE: the rating; ENDTEXTP the rank's 13 characters, ENDCLASSDIGIT the class.
ENDRANKSET:
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
        BEQ end_rankdone
        CLC
        LDA ENDTEXTP
        ADC #14
        STA ENDTEXTP
        BCC end_rankptrnext
        INC ENDTEXTP+1
end_rankptrnext:
        DEX
        JMP end_rankptr
end_rankdone:
        LDA ENDCLASS
        EOR #7
        CLC
        ADC #$71
        STA ENDCLASSDIGIT
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
        JSR ENDTICK
        BEQ ENDRESET
        JMP ENDLOOP
; The original's wait ($F60D-$F625 for victory): Z set to restart, after the
; timeout or, once the button lockout is over, with fire.
ENDTICK:
        LDA ENDTIME
        BNE end_timelo
        DEC ENDTIME+1
end_timelo:
        DEC ENDTIME
        LDA ENDTIME
        ORA ENDTIME+1
        BEQ end_tickdone
        LDA ENDKEYWAIT
        ORA ENDKEYWAIT+1
        BEQ end_readbutton
        LDA ENDKEYWAIT
        BNE end_keylo
        DEC ENDKEYWAIT+1
end_keylo:
        DEC ENDKEYWAIT
        LDA #1
        RTS
end_readbutton:
        LDA #$FF
        STA $DC00
        LDA $DC00
        AND #$10
end_tickdone:RTS
ENDRESET:
        JSR ENDHIDE
        LDA #$0A
        LDX #$60
        JSR ELVADR
        LDA #1
        STA ENDCOPYMODE
        JSR ENDCOPY
        LDA #>ENDVMASTER ; matrix, HUD text, cockpit art and bottom sprite slots
        LDX #<ENDVMASTER
        JSR ELVADR
        JSR ENDUNPACK
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
ENDPRINTAT:
        STA ENDTEXTP
        STX ENDTEXTP+1
        STY ENDROW
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
        JSR ENDCHAR
        INC ENDINDEX
        JMP end_character
end_printdone:RTS
; A = character: its 16 x 8 pixels (value 2) at CDST, which moves on by 16.
ENDCHAR:
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
        LDA CDST        ; the right half: CDST + 8 (CDST is a multiple of 16)
        ORA #8
        STA end_right+1
        LDA CDST+1
        STA end_right+2
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
end_right:STA $FFFF,Y
        DEY
        BPL end_glyph
        CLC
        LDA CDST
        ADC #16
        STA CDST
        BCC end_charptr
        INC CDST+1
end_charptr:RTS
; Victory ($F5B9-$F634). The HUD, cockpit, crosshair and stars stay; the view is
; wiped clear, the energy refills ($F6A7), the original's text block is drawn
; hidden and revealed ($F635), its numbers ($D505) and the rank ($F3CE) with it;
; then fire after the original's lockout, or its timeout, restarts. All of it
; runs in the frame's 3D-view time, bounded by the raster.
ENDWINSTART:
        LDA #2
        STA ENDMODE
        JSR ENDSTOP
        LDA #0
        STA ENDPHASE
        STA TRUN
        STA MAPSPR      ; (the map's planet sprite goes with the map)
        LDA #$FF        ; no steering
        STA JOY
        LDA #<ENDMODE   ; stars: pixel 1, only on empty pixels, as over the map
        STA gplmode+1
        STA germode+1
        LDA #>ENDMODE
        STA gplmode+2
        STA germode+2
        JMP MAPCLOSE    ; the view wipes back a row a frame: the map or the stars go
ENDWINFRAME:
        LDX ENDPHASE
        BNE ew_text
        JSR ENDREFILL   ; 0: the energy refills
        BCC ew_done
        LDA WIPE        ; (the 15-frame wipe ends long before)
        BNE ew_done
        INC ENDPHASE
        LDA #0
        STA ENDJOB
        STA ENDCHARN
        LDA #ENDREVEAL  ; frames to the reveal ($F600-$F696)
        STA ENDTIME
        JMP ENDRATINGINPUT ; the statistics, before any number is shown
ew_done:RTS
ew_text:
        DEX
        BNE ew_rank
        DEC ENDTIME     ; 1: a number or the rank into the text a frame; rows 4-14 hidden
        LDX ENDJOB
        CPX #8
        BCS ew_print
        INC ENDJOB
        JSR ENDJOBX
ew_print:
        LDA #220
        JSR ENDSTREAM
        BCC ew_done
        LDA ENDTIME
        BPL ew_done
        LDX #130        ; revealed: rows 4-16, the letters purple ($F696)
        LDA #$14
ew_reveal:
        STA $449F,X
        STA $4521,X
        STA $45A3,X
        STA $4625,X
        DEX
        BNE ew_reveal
        INC ENDPHASE
        RTS
ew_rank:
        DEX
        BNE ew_wait
        LDA #240        ; 2: the rank's row, visible
        JSR ENDSTREAM
        BCC ew_done
        INC ENDPHASE
        LDA #<ENDWINAUTO
        STA ENDTIME
        LDA #>ENDWINAUTO
        STA ENDTIME+1
        LDA #<ENDWINKEY
        STA ENDKEYWAIT
        LDA #>ENDWINKEY
        STA ENDKEYWAIT+1
        RTS
ew_wait:
        JSR ENDTICK     ; 3: the wait
        BNE ew_done
        LDA #0
        STA $D015
        JMP ENDRESET
; 154 energy units a frame (the original's $F6A7 adds one a pass). C set: full.
ENDREFILL:
        LDX #3
        CLC
ef_digit:
        LDA HUDE,X
        ADC ENDADD,X
        CMP #$7A
        BCC ef_store
        SBC #10
ef_store:
        STA HUDE,X
        DEX
        BPL ef_digit
        BCC ef_done
        LDA #$79        ; past 9999: full
        LDX #3
ef_full:STA HUDE,X
        DEX
        BPL ef_full
ef_done:RTS
; The text's characters ENDCHARN to A-1, from VDC RAM. A text row's 20
; characters are a bitmap row, from row 4. C set: all printed.
ENDSTREAM:
        STA ENDCHAREND
        LDA #>ENDVTEXT
        LDX ENDCHARN
        JSR ELVADR
es_next:LDA ENDCHARN
        CMP ENDCHAREND
        BCS es_done
        LDA $D012       ; (a character takes up to 13 lines; the guns' split is at 194)
        CMP #ENDLASTLINE
        BCS es_late
        LDA ENDCHARN
        LSR A
        LSR A
        LSR A
        LSR A
        CLC
        ADC #$65
        STA CDST+1
        LDA ENDCHARN
        ASL A
        ASL A
        ASL A
        ASL A
        STA CDST
        INC ENDCHARN
        JSR ELREAD
        CMP #32
        BNE es_glyph
        LDA #0          ; a space: no glyph to read
        LDY #15
es_space:STA (CDST),Y
        DEY
        BPL es_space
        BMI es_next
es_glyph:JSR ENDCHAR
        JMP es_next
es_late:CLC
es_done:RTS
; X = 0-5: the number of bitmap row 8 + X into the text ($D505), 6: the rank
; names from VDC RAM, 7: the rank.
ENDJOBX:
        CPX #6
        BCC ENDNUMBER
        BNE ej_rankrow
        LDA #>ENDVRANKS
        LDX #<ENDVRANKS
        JSR ELVADR
        JMP ENDUNPACK
ej_rankrow:
        JSR ENDRANKSET
        LDA #>ENDVRANK
        LDX #<ENDVRANK
        JSR ELVADR
        LDA ENDTEXTP
        STA CSRC
        LDA ENDTEXTP+1
        STA CSRC+1
        LDY #0
ej_rank:LDA (CSRC),Y    ; the rank's 13 characters ($F2D6), then CLASS and the digit
        JSR ELWRITE
        INY
        CPY #13
        BNE ej_rank
        LDY #0
ej_class:LDA ENDCLASSTEXT,Y
        JSR ELWRITE
        INY
        CPY #7
        BNE ej_class
        RTS
ENDNUMBER:
        STX ENDK
        LDA ENDNUMROW,X ; characters 14-19 of the row
        TAX
        LDA #>ENDVTEXT
        JSR ELVADR
        LDX ENDK
        LDY ENDNUMSRC,X
        LDA ENDHITS,Y
        STA ENDV
        LDA ENDHITS+1,Y
        STA ENDV+1
        LDA #32
        CPX #0
        BNE en_mark
        LDY ENDRENER+2  ; $EA00 or more: the original's mark and 60000
        BNE en_over
        LDY ENDRENER+1
        CPY #$EA
        BCS en_over
        LDY ENDV        ; $D1F0 is entered with carry clear here ($D50D):
        BNE en_less     ; it shows one unit less
        DEC ENDV+1
en_less:DEC ENDV
        BCC en_mark
en_over:LDA #$60
        STA ENDV
        LDA #$EA
        STA ENDV+1
        LDA #$6D
en_mark:JSR ELWRITE
        CPX #5
        BNE en_digits
        LDA #0          ; BASE STATIONS: friendly bases left in the inner ring ($D61C)
        STA ENDV
        STA ENDV+1
        LDY #3
en_base:LDX M_INNER,Y
        LDA M_STATE,X
        BPL en_none
        INC ENDV
en_none:DEY
        BPL en_base
en_digits:
        JSR ENDDEC
        LDX ENDK
        LDA ENDFROM,X
        STA ENDFROMV
        LDA ENDFORCE,X
        STA ENDFORCEV
        LDA #0
        STA ENDSHOWN
        LDY #0
en_digit:
        LDA #32         ; a column the original does not print: a space
        CPY ENDFROMV
        BCC en_put
        LDA ENDDIG,Y    ; leading zeros left out, up to the column always printed
        ORA ENDSHOWN
        BNE en_show
        CPY ENDFORCEV
        LDA #32
        BCC en_put
en_show:INC ENDSHOWN
        LDA ENDDIG,Y
        ORA #$70
en_put: JSR ELWRITE
        INY
        CPY #5
        BNE en_digit
        RTS
; ENDV: five decimal digits ($D1F0).
ENDDEC:
        LDX #0
ed_power:
        LDY #$FF
        SEC
ed_sub: INY
        LDA ENDV
        SBC ENDPOWLO,X
        STA ENDV
        LDA ENDV+1
        SBC ENDPOWHI,X
        STA ENDV+1
        BCS ed_sub
        LDA ENDV
        ADC ENDPOWLO,X
        STA ENDV
        LDA ENDV+1
        ADC ENDPOWHI,X
        STA ENDV+1
        TYA
        STA ENDDIG,X
        INX
        CPX #4
        BNE ed_power
        LDA ENDV
        STA ENDDIG+4
        RTS
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
ENDPHASE:.BYTE 0
ENDJOB:.BYTE 0
ENDCHARN:.BYTE 0
ENDCHAREND:.BYTE 0
ENDK:   .BYTE 0
ENDV:   .BYTE 0,0
ENDSHOWN:.BYTE 0
ENDFROMV:.BYTE 0
ENDFORCEV:.BYTE 0
ENDDIG: .BYTE 0,0,0,0,0
ENDCOLORS:.BYTE 2,8,10,4,9
ENDWEIGHTLO:.BYTE $E8,100,10,1
ENDWEIGHTHI:.BYTE 3,0,0,0
ENDADD: .BYTE 0,1,5,4
ENDPOWLO:.BYTE $10,$E8,100,10
ENDPOWHI:.BYTE $27,$03,0,0
; Per number row 8-13: VDC offset of characters 14-19, value (offset from ENDHITS),
; the first column printed and the column printed even when zero.
ENDNUMROW:.BYTE 94,114,134,154,174,194
ENDNUMSRC:.BYTE 4,0,2,7,9,0
ENDFROM:.BYTE 0,2,2,3,1,4
ENDFORCE:.BYTE 3,4,4,4,3,4
ENDCLASSTEXT:.BYTE 67,76,65,83,83,32
ENDCLASSDIGIT:.BYTE $71,0
ENDEXPAND:.BYTE 0,2,8,10,32,34,40,42,128,130,136,138,160,162,168,170
ENDDEATHTEXT:
; ENDDEATHTEXTDATA
ENDLOSTTEXT:
; ENDLOSTTEXTDATA
; ENDHEADERDATA
; ENDRATINGDATA
ENDRANGES:
; ENDRANGEDATA
        .BYTE 0,0
ENDINGEND:
ENDDEATHAUTO = 10144
ENDDEATHKEY = 444
ENDLASTLINE = 178
ENDREVEAL = 23
ENDWINAUTO = 18983
ENDWINKEY = 527
