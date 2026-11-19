; The score advances once per visible title frame. All three voices share
; the event duration. Each event has three little-endian SID frequencies,
; with frequency zero for a rest.
MUSICINIT:
        JSR MUSICSTOP
        LDA #$0F
        STA $D418
        LDA #$26
        STA $D405
        STA $D40C
        STA $D413
        LDA #$A4
        STA $D406
        STA $D40D
        STA $D414
        LDA #0
        STA MUSICINDEX
        LDA #1
        STA MUSICWAIT
        RTS

MUSICTICK:
        LDA MUSICWAIT
        BEQ music_done
        DEC MUSICWAIT
        BNE music_done
        LDY MUSICINDEX
        LDA MUSICSCORE,Y
        BEQ MUSICSTOP
        STA MUSICWAIT
        INY
        LDX #0
music_note:
        LDA #$10
        STA $D404,X
        LDA MUSICSCORE,Y
        STA $D400,X
        INY
        ORA MUSICSCORE,Y
        PHA
        LDA MUSICSCORE,Y
        STA $D401,X
        INY
        PLA
        BEQ music_next
        LDA #$11
        STA $D404,X
music_next:
        TXA
        CLC
        ADC #7
        TAX
        CPX #21
        BNE music_note
        STY MUSICINDEX
music_done:
        RTS

MUSICSTOP:
        LDA #0
        STA MUSICWAIT
        LDX #$18
music_silence:
        STA $D400,X
        DEX
        BPL music_silence
        RTS

MUSICWAIT:  .BYTE 0
MUSICINDEX: .BYTE 0
MUSICSCORE:
; MUSICSCOREDATA
