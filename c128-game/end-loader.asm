; Init/exit only. The disabled 16K VDC holds the borrowed workspace and
; a reset snapshot. No gameplay code changes banks or calls the KERNAL.
        * = $1C10
ENDINIT:
        INC FAST
        LDA #0
        TAX
        JSR ELVADR
        LDA #2
        STA CSRC+1
        LDA #0
        STA CSRC
        LDX #10
        JSR ELSAVE
        LDY #$5F
el_tail:LDA $0C00,Y
        JSR ELWRITE
        DEY
        BPL el_tail
        LDA #$E0
        STA CSRC+1
        LDA #2
        STA CDST+1
        LDY #0
        STY CSRC
        STY CDST
        LDX #10
el_copy:LDA (CSRC),Y
        STA (CDST),Y
        INY
        BNE el_copy
        INC CSRC+1
        INC CDST+1
        DEX
        BNE el_copy
        LDY #$5F
el_copytail:LDA $EA00,Y
        STA $0C00,Y
        DEY
        BPL el_copytail
        JSR GINIT2
        JMP ENDSETUP
ELVADR: PHA
        TXA
        LDX #19
        JSR ELREG
        PLA
        LDX #18
        JSR ELREG
        LDX #31
        STX $D600
        RTS
ELREG: STX $D600
el_ready:BIT $D600
        BPL el_ready
        STA $D601
        RTS
ELWRITE:
el_wr:  BIT $D600
        BPL el_wr
        STA $D601
        RTS
ELREAD:
el_rd:  BIT $D600
        BPL el_rd
        LDA $D601
        RTS
ELSAVE: LDY #0
el_save:LDA (CSRC),Y
        JSR ELWRITE
        INY
        BNE el_save
        INC CSRC+1
        DEX
        BNE el_save
        RTS
ENDRESTORE:
        LDA #0
        TAX
        JSR ELVADR
        STA CSRC
        LDA #2
        STA CSRC+1
        LDX #10
        LDY #0
el_rest:JSR ELREAD
        STA (CSRC),Y
        INY
        BNE el_rest
        INC CSRC+1
        DEX
        BNE el_rest
        LDY #$5F
el_resttail:JSR ELREAD
        STA $0C00,Y
        DEY
        BPL el_resttail
        JMP GREXIT
ENDQUIET:
        JSR MNOFF
        JSR MSOFF
        LDA #0
        STA HYPON
        STA APPR
        LDX #2
el_noenemy:STA ALIVE,X
        DEX
        BPL el_noenemy
        LDA #1
        STA HPEND       ; refuse map/SPACE until the independent ending loop takes over
        JMP EFRESET
ENDSTREAMS:
        JSR MNSTREAMINIT
el_stream:JSR MNSTREAMRESTORE
        LDA mn_streamdst+2
        CMP #$84
        BNE el_stream
        RTS
ENDLOADEREND:
