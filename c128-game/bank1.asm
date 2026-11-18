; Bank 1, the store (briefs/memory-overlay-plan.md, 5.1/5.2).
;
; The copy stub lives in common RAM at the bottom of the stack page (zero page
; and the stack page are common to both banks for every RCR; the game's stack
; never goes below $01EA). STA $FF02 loads the CR from PCRB ($7F: bank 1, all
; RAM), STA $FF01 from PCRA ($3E: the game's bank 0); the value stored is
; ignored, A keeps the byte. The opcodes after STA $FF02 are fetched in bank 1:
; every bank switch is inside the stub. Interrupts are off (the game's state):
; no transfer runs while the tunnel's raster IRQ is enabled. An NMI (RESTORE)
; during a transfer finds bank 1's vectors pointing at NMIB1, an RTI.
;
; The game never returns to BASIC (2026-11-17: RUN/STOP does nothing), so none of
; BASIC's state is kept: no copy of $0200-$1BFF or of the stub's page; the PCRs
; and bank 1's vectors are set, not saved; BASIC 7's string area at the top of
; bank 1 is not reserved.
;
; Bank 1 ($0000-$03FF is common RAM, not separate):
;   ENDB1SNAP $2C00      the reset snapshot, then the ending's payload (build.py)
;   B1STREAM $6400-$66FF the movement streams $8100-$83FF (the reset)
;   B1MINES $7000-$7CFF  the MINES package (overlay.asm)
;   B1ENDING $7E00-$85FF the ENDING package (ending.asm)
;   $FFFA-$FFFF          the NMI/RESET/IRQ vectors: NMIB1
;   free: $0400-$2BFF, the payload's end-$63FF, $6700-$6FFF, $7D00-$7DFF,
;   $8600-$FEFF, $FF05-$FFF9 ($FF00-$FF04 are the MMU's in every bank)
B1STREAM = $6400        ; $8100-$83FF, the type-1 movement streams the mines borrow
B1MINES = $7000         ; the MINES package (S1 at $EA16), as decoded at init
B1ENDING = $7E00        ; the ENDING package (S1 at ENDPKG), ENDPKGPAGES pages from its staging
ENDPKGPAGES = 8         ; (build.py checks the package fits)
B1SH   = $FC           ; CSRC+1 and CDST+1 in zero page
B1DH    = $FE

        * = $0100
; X pages from bank 1 (CSRC) to bank 0 (CDST); B1GETY: Y = the first index
; (a tail: the pointers moved back by Y, X = 1). 24 cycles a byte.
B1GET:  LDY #0
B1GETY:
b1g:    STA $FF02
        LDA (CSRC),Y
        STA $FF01
        STA (CDST),Y
        INY
        BNE b1g
        INC B1SH
        INC B1DH
        DEX
        BNE b1g
        RTS
; X pages from bank 0 (CSRC) to bank 1 (CDST); B1PUTY as B1GETY.
B1PUT:  LDY #0
B1PUTY:
b1p:    LDA (CSRC),Y
        STA $FF02
        STA (CDST),Y
        STA $FF01
        INY
        BNE b1p
        INC B1SH
        INC B1DH
        DEX
        BNE b1p
        RTS
; One byte at the bank-1 address set by ELVADR, which moves on (as the VDC's
; address register did). X, Y and C are kept; N and Z follow the byte read (as
; LDA $D601 did: ENDUNPACK tests them).
ELREAD: STA $FF02
b1r:    LDA $FFFF
        STA $FF01
        INC b1r+1
        BNE b1rd
        INC b1r+2
b1rd:   ORA #0
        RTS
ELWRITE:STA $FF02
b1w:    STA $FFFF
        STA $FF01
        INC b1w+1
        BNE b1wd
        INC b1w+2
b1wd:   RTS
NMIB1:  RTI
B1STUBEND:

; Init (ENDINIT, before GINIT2 decodes the high image over this staging): the
; stub, the preconfigurations and bank 1's vectors (set, not saved: there is no
; return to BASIC), the overlay manager, the ENDING package and the payload.
        * = B1INITAT
B1INIT:
        LDX #B1STUBLEN-1
bi_stub:LDA ENDSTUBIMG,X
        STA $0100,X
        DEX
        BPL bi_stub
        LDA #$3E        ; PCRA: the game's bank 0 (RAM, I/O); PCRB: bank 1, all RAM
        STA $D501
        LDA #$7F
        STA $D502
        LDA #$FF
        LDX #$FA
        JSR ELVADR
        LDX #3
bi_vwrite:LDA #<NMIB1
        JSR ELWRITE
        LDA #>NMIB1
        JSR ELWRITE
        DEX
        BNE bi_vwrite
        LDX #0          ; the overlay manager into BASIC's free ML area
bi_ovl: LDA OVLIMG,X
        STA OVBASE,X
        INX
        BNE bi_ovl
        LDX #OVAREALEN-256
bi_ovl2:LDA OVLIMG+255,X
        STA OVBASE+255,X
        DEX
        BNE bi_ovl2
        LDA #<ENDPKGSTAGE ; the ENDING package (whole pages: reading on past its end is harmless)
        LDX #>ENDPKGSTAGE
        LDY #>B1ENDING
        STA CSRC
        STX CSRC+1
        LDA #<B1ENDING
        STA CDST
        STY CDST+1
        LDX #ENDPKGPAGES
        JSR B1PUT
        LDA #<ENDSTAGE  ; the payload (the victory text, the reports, the display masters)
        LDX #>ENDSTAGE
        LDY #>ENDBPAY
        STA CSRC
        STX CSRC+1
        LDA #0
        STA CDST
        STY CDST+1
        LDX #ENDPAYPAGES
        JMP B1PUT
ENDSTUBIMG:
B1INITEND:
OVLIMG = ENDSTUBIMG+128 ; (build.py stages the stub, then the manager's area)
OVAREALEN = 496         ; OVBASE-$1BFF (build.py checks)
