; The cold entry has START's JSR GAMEINIT on the stack. ENDRETURN discards
; the interrupted play frame before taking the reset entry below.
TITLERESET:
        JSR TITLEBOOT
        JMP frame

TITLEBOOT:
        JSR ENDHIDE
        JSR CLOCKINIT
        LDA #0
        JSR SHOWTG
        LDA #$79
        LDX #3
title_energy:
        STA HUDE,X
        DEX
        BPL title_energy
        LDA #<NMIRTI
        STA $FFFA
        LDA #>NMIRTI
        STA $FFFB
title_load:
        LDX #OVTITLE
        JSR OVLOAD
        BCS title_load  ; never execute a package if the slot is still busy
TITLETRAMP:
        JSR TITLERUN
TITLETRAMPEND:
        LDX #0          ; MINES loads when a base sector needs it
        JSR OVLOAD
        JSR FKEYREAD
        STA FKEYLAST
        JSR SHIPINIT
        JMP g_gi9       ; generate the selected world and start its clock

; Spend spare view time during the first jump to load MINES before a base
; arrival. The destination can change while the ship is in hyperspace.
OVMINEJUMP:
        JSR HYPVB
        BIT OVOWNER
        BMI ov_md_done
        LDA HYPON
        BEQ ov_md_done
        LDA OVJOB
        CMP #OVMINES
        BEQ ov_md_step
        LDX #OVMINES
        JSR OVSTART
        BCS ov_md_done
ov_md_step:
        LDA #145
        STA OVLIM
        JSR OVSTEP
        LDA #176
        STA OVLIM
ov_md_done:
        RTS
