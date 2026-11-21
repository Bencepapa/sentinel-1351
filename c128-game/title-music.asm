; The original title tune: three streams of (pitch, duration) pairs (stored as one
; pitch plane and one duration plane for the three voices, which pack better; each
; voice walks its own part of both, from the start index MUIDX), one tick every
; second frame ($1CF2). Pitch bit 7 is a rest (the voice keeps its frequency, its
; gate goes off); else the low nibble indexes the 12-note table and 7 - (the high
; nibble) shifts the word right. A zero duration ends the tune for all voices. The
; data is the disk's ($1ED6, $1EE8, $1EF4, $1F01-$2074): build.py extracts it,
; see the end of this block. The init and tick write the same SID registers in the
; same order as the original's.
MUSICINIT:
        LDX #$18        ; SID clear, $D418 down to $D400
        LDA #0
mu_clear:
        STA $D400,X
        DEX
        BPL mu_clear
        STA $D415
        TAX             ; (the player's state is the package image's: counts 0, MUDIV 2)
mu_setup:
        LDY MUSICSETUP,X
        LDA MUSICSETUP+13,X
        STA $D400,Y
        INX
        CPX #13
        BNE mu_setup
        RTS

MUSICTICK:
        LDA MUSTOP
        BEQ mu_run
        RTS
mu_run:
        DEC MUDIV
        BMI mu_go
        RTS
mu_go:
        LDA #1
        STA MUDIV
        LDX #2
mu_voice:
        LDA MUCNT,X
        BNE mu_next
        LDY MUIDX,X
        LDA MUSICD,Y
        BNE mu_event
        JMP MUSICEND
mu_event:
        STA MUCNT,X
        INC MUIDX,X
        LDA MUSICP,Y
        BMI mu_rest
        PHA
        AND #15
        TAY
        LDA MUSICLO,Y
        STA MUFL,X
        LDA MUSICHI,Y
        STA MUFH,X
        PLA
        LSR A
        LSR A
        LSR A
        LSR A
        EOR #$FF
        CLC
        ADC #8
        TAY
        BEQ mu_pitched
mu_shift:
        LSR MUFH,X
        ROR MUFL,X
        DEY
        BNE mu_shift
mu_pitched:
        LDA #$41
        BNE mu_gate
mu_rest:
        LDA #$40
mu_gate:
        STA MUGATE,X
mu_next:
        DEX
        BPL mu_voice
        LDX #0
mu_freq:
        LDY MUSICREG,X
        LDA MUFL,X
        STA $D400,Y
        LDA MUFH,X
        STA $D401,Y
        INX
        CPX #3
        BNE mu_freq
        LDX #0
mu_gates:
        LDA MUGATE,X
        BEQ mu_nogate
        LDY MUSICREG,X
        LDA #$40
        STA $D404,Y
        LDA MUGATE,X
        STA $D404,Y
        LDA #0
        STA MUGATE,X
mu_nogate:
        DEC MUCNT,X
        INX
        CPX #3
        BNE mu_gates
mu_done:
        RTS

; The tune ran out: the original clears $D418-$D400 and stays silent.
MUSICEND:
        LDA #$FF
        STA MUSTOP
        LDA #0
        LDX #$18
mu_silence:
        STA $D400,X
        DEX
        BPL mu_silence
        RTS

; Leaving the title early (F5, F7, Fire): the three controls off ($18B4); the main
; loop then stops calling MUSICTICK.
MUSICSTOP:
        LDA #0
        STA $D404
        STA $D40B
        STA $D412
        RTS

MUSTOP:  .BYTE 0
MUDIV:   .BYTE 2
MUCNT:   .BYTE 0,0,0
MUGATE:  .BYTE 0,0,0
MUSICREG: .BYTE 0,7,14
; MUSICDATA
