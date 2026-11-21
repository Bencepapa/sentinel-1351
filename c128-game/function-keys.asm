; CIA1 legacy keyboard column (also used by the C128 function keys).
; Compare the entire sample as on C64. Shift uses a different column.
FKEYF1 = $EF
FKEYF3 = $DF
FKEYF7 = $F7

FKEYREAD:
        LDA #$FE
        STA CIA1PA
        LDY CIA1PB
        LDA #$BF        ; restore the port-2 pot select
        STA CIA1PA
        TYA
        RTS

FKEYFRAME:
        JSR FKEYREAD
        LDY PAUSED
        BNE fkey_resume
        CMP FKEYLAST
        STA FKEYLAST
        BEQ fkey_done
        CMP #FKEYF1
        BEQ fkey_pause
        CMP #FKEYF7
        BNE fkey_done
        LDA ENDMODE
        BEQ fkey_restart
        CMP #2
        BNE fkey_done
        LDA ENDPHASE    ; victory wait: F7 bypasses the fire lockout
        CMP #3
        BCC fkey_done
fkey_restart:
        JMP FKEYRESTART
fkey_done:
        RTS
fkey_pause:
        INC PAUSED
        LDA HUDTIME+2
        STA FKEYCOLON
        LDA #$6E
        STA HUDTIME+2
        LDA #0
        STA $D418
        RTS
fkey_resume:
        STA FKEYLAST
        LDA #$FF
        STA CIA1PA
        LDX CIA1PA
        LDA #$BF
        STA CIA1PA
        TXA
        AND #$1F
        CMP #$1F
        BEQ fkey_done
        DEC PAUSED
        LDA FKEYCOLON
        STA HUDTIME+2
        LDA #$0F        ; the port's master volume
        STA $D418
        RTS

; Continue drawing the raster splits and the current sprites. Each skip
; replaces a JSR's return with a jump to the next shared display section.
FKEYVIEW:
        LDA PAUSED
        BNE fkey_viewskip
        JMP FIREPH
fkey_viewskip:
        PLA
        PLA
        JMP fkey_guns
FKEYGUNS:
        LDA PAUSED
        BNE fkey_gunskip
        JMP SWEEPSND
fkey_gunskip:
        PLA
        PLA
        JMP fkey_strip
FKEYSWEEP:
        LDA PAUSED
        BNE fkey_done
        LDA HYPON
        CMP #2
        BEQ fkey_warpburst
        CMP #3
        BEQ fkey_warpburst
        JMP SWEEPSND
fkey_warpburst:
        JSR SWEEPSND
        JMP ENGBURST    ; after the strip split, with the warp pitch already set
FKEYINPUT:
        LDA PAUSED
        BNE fkey_inputskip
        JMP INPUTV
fkey_inputskip:
        PLA
        PLA
fkey_wraphigh:
        BIT $D011
        BPL fkey_wraphigh
fkey_wraplow:
        BIT $D011
        BMI fkey_wraplow
        JSR FKEYTUNNEL
        JMP CLOCKFRAME

; The tunnel's raster IRQ only draws the existing bands. Replay its current
; compare list without advancing the tunnel phase, mines, or wave colours.
FKEYTUNNEL:
        LDA MAPSHOWN
        ORA WIPE
        ORA HYPON
        BNE fkey_tunneldone
        LDA OVOWNER
        CMP #$80
        BNE fkey_tunneldone
        LDA vv2+1
        CMP #<MNVB
        BNE fkey_tunneldone
        LDA vv2+2
        CMP #>MNVB
        BNE fkey_tunneldone
        LDA #0
        STA MTINDEX
        LDA MTLINES
        STA $D012
        LDA #1
        STA $D019
        STA $D01A
fkey_tunneldone:
        RTS
FKEYTUNNELEND:

; F3/F4: the report's remaining system checks end and the energy is full at once.
; (The original only ends the checks: its energy refill, +9 a frame, still has to
; finish, so with a drained ship F3 looked dead. A tap while the text is typed
; counts too: the original polls only after the text.)
FKEYREPAIR:
        LDA FKEYLAST
        CMP #FKEYF3
        BNE fkey_nokey
        STA FKEYGO
fkey_nokey:
        LDA MSSTATE
        CMP #10
        BNE fkey_repair
        LDA FKEYGO
        BEQ fkey_repair
        LDA #0
        STA FKEYGO
        STA MRROW       ; the report's remaining inspection noise
        LDA #8
        STA MRINDEX
        LDY #3
        LDA #$79
        JSR g_mrcfull   ; energy 9999 and the recharge done
fkey_repair:
        JMP MRREPAIR

; The key frame's JSR supplies the one return ENDRETURN discards.
FKEYRESTART:
        JSR ENDQUIET
        JSR ENDHIDE
        LDX #$17
        LDA #0
        STA FKEYGO
fkey_clrsid:
        STA $D400,X
        DEX
        BPL fkey_clrsid
        LDA #$0F
        STA $D418
        JMP OVENDRESET

PAUSED:  .BYTE 0
FKEYLAST:.BYTE $FF
FKEYCOLON:.BYTE $6E
FKEYGO:  .BYTE 0
