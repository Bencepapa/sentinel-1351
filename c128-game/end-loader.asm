; The init loader, then resident helpers of the ending and the reset. Bank 1 holds
; the reset snapshot, the ending's payload and the packages (bank1.asm: the copy
; stub in common RAM at $0100, B1INIT). No gameplay code changes banks or calls
; the KERNAL; the stub's transfers run with interrupts off. The game never
; returns to BASIC: nothing of BASIC's is saved or restored.
ENDCOREPAGES = 9
        * = $1C10
ENDINIT:
        INC FAST
        JSR B1INIT      ; (staged above the payload: the stub, PCRs, vectors, manager, package, payload)
        LDA #$E0
        STA CSRC+1
        LDA #2
        STA CDST+1
        LDY #0
        STY CSRC
        STY CDST
        LDX #ENDCOREPAGES ; resident core (the package went to bank 1)
el_copy:LDA (CSRC),Y
        STA (CDST),Y
        INY
        BNE el_copy
        INC CSRC+1
        INC CDST+1
        DEX
        BNE el_copy
        JMP ENDSETUP    ; (it calls GINIT2, then takes the reset snapshot)
; The bank-1 byte address of ELREAD / ELWRITE (both): A = high, X = low.
ELVADR: STX b1r+1
        STX b1w+1
        STA b1r+2
        STA b1w+2
        RTS
ELREG: STX $D600
el_ready:BIT $D600
        BPL el_ready
        STA $D601
        RTS
; (No EXIT: the game never returns to BASIC; RUN/STOP does nothing.)
ENDQUIET:
        JSR OVMNOFF
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
; (the reset) restore the movement streams MINES can borrow. S1 stays owned
; by ENDING until the resident title entry replaces it.
ENDSTREAMS:
        LDA #<B1STREAM
        STA CSRC
        LDA #>B1STREAM
        STA CSRC+1
        LDA #$00
        STA CDST
        LDA #$81
        STA CDST+1
        LDX #3
        JMP B1GET
; Init only. Decode to borrowed low RAM before GINIT2 installs the low block.
TITLESTORE:
        LDA #<TITLESTAGE
        STA CSRC
        LDA #>TITLESTAGE
        STA CSRC+1
        LDA #0
        STA CDST
        LDA #$10
        STA CDST+1
        JSR g_upb
        LDA #<TITLEARTSTAGE
        STA CSRC
        LDA #>TITLEARTSTAGE
        STA CSRC+1
        JSR g_upb       ; append the title art and copy to the decoded code
        LDX #0
        LDA #0
title_clrpath:
        STA TITLEARTSTAGE,X
        STA TITLEARTSTAGE+256,X
        INX
        BNE title_clrpath
        STA CSRC
        STA CDST
        LDA #$10
        STA CSRC+1
        LDA #>B1TITLE
        STA CDST+1
        LDX #TITLEPAGES
        JMP B1PUT
ENDLOADEREND:
