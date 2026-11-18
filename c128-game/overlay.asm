; S1, the time-shared slot $E960-$F6F8 (briefs/memory-overlay-plan.md, 5.3).
; One package at a time is copied raw from bank 1 into it, linked at its run
; address, never relocated (MINES at $EA16 keeps the tunnel's page crossings).
; Packages: 1 MINES (the base sectors: minefield, tunnel, mine art; linked at
; $EA16), 2 ENDING (the death scene, the victory's text and wait, the reset's
; first part, the rating; linked at ENDPKG). OVOWNER says which one S1 holds:
; $80 MINES, $40 ENDING, 0 none (a load in progress: 0).
;
; Every reference from resident code into S1 goes through a trampoline below
; (build.py audits the operands of all resident instructions), except the base
; sequence's calls, which only run after the sector's arrival went through one.
; A trampoline whose package is not loaded counts OVMISS and loads it at once.
; S1 is never written while a raster IRQ is enabled ($D01A bit 0: the tunnel) or
; while MINES' frame hooks point into it (vv2, sprcj): OVSTART refuses
; (OVREFUSE) and leaves S1 alone. The owner's own shutdown (MNOFF for MINES)
; comes first, from its caller.
;
; Installed at init by B1INIT (staged image, OVLEN bytes) into C128 BASIC's free
; ML area after the low block (the game never returns to BASIC).
OVBASE  = $1A10
OVAREAEND = $1C00
S1BASE  = $E960
S1END   = $F6F9
OVCHUNK = 32            ; bytes a step copies between raster checks (~14 lines)
OVFIRST = 78            ; (OVSTEP: not before the view, not into the splits above it)

        * = OVBASE
OVOWNER:.BYTE $80       ; (init loads nothing: MINES is decoded into S1 there)
OVJOB:  .BYTE 0         ; the package being copied, 0 none
OVSRC:  .BYTE 0,0       ; its next bank-1 byte,
OVDST:  .BYTE 0,0       ; its next S1 byte,
OVLEFT: .BYTE 0,0       ; bytes left
OVK:    .BYTE 0
OVSYNC: .BYTE 0         ; $80: no raster deadline (OVLOAD)
OVLIM:  .BYTE 176       ; OVSTEP's deadline line (a piece then ends by line ~190: the guns at 194)
OVMISS: .BYTE 0         ; trampoline calls that found their package missing
OVREFUSE:.BYTE 0        ; refused loads (the slot was busy)
; Packages (0: none, an eviction): S1 flag, bank-1 address, run address, end.
OVFLAG: .BYTE 0,$80,$40
OVB1LO: .BYTE 0,<B1MINES,<B1ENDING
OVB1HI: .BYTE 0,>B1MINES,>B1ENDING
OVDLO:  .BYTE 0,<MNSTART,<ENDPKG
OVDHI:  .BYTE 0,>MNSTART,>ENDPKG
OVELO:  .BYTE 0,<MNEXTRAEND,<ENDINGEND
OVEHI:  .BYTE 0,>MNEXTRAEND,>ENDINGEND

; X = package: begin loading it into S1 (OVSTEP copies it). C set: refused.
OVSTART:
        LDA OVFLAG,X
        CMP OVOWNER
        BEQ ov_have
        TXA
        BEQ ov_check
        CPX OVJOB
        BEQ ov_have     ; (already under way)
ov_check:
        LDA $D01A       ; a raster IRQ armed: the tunnel may be running from S1
        LSR A
        BCS ov_busy
        LDA vv2+2       ; MINES' blank and sprite hooks ($EA16-$F6xx) still installed
        SEC
        SBC #$EA
        CMP #13
        BCC ov_busy
        LDA sprcj+2
        SEC
        SBC #$EA
        CMP #13
        BCC ov_busy
        LDA #<NMIRTI    ; no IRQ vector into S1 (the tunnel leaves MTIRQ there)
        STA $FFFE
        LDA #>NMIRTI
        STA $FFFF
        LDA #0
        STA OVOWNER
        STX OVJOB
        LDA OVB1LO,X
        STA OVSRC
        LDA OVB1HI,X
        STA OVSRC+1
        LDA OVDLO,X
        STA OVDST
        LDA OVDHI,X
        STA OVDST+1
        SEC
        LDA OVELO,X
        SBC OVDLO,X
        STA OVLEFT
        LDA OVEHI,X
        SBC OVDHI,X
        STA OVLEFT+1
ov_have:CLC
        RTS
ov_busy:INC OVREFUSE
        SEC
        RTS

; A piece of the load under way: OVCHUNK bytes at a time until the raster reaches
; OVLIM (no limit with OVSYNC). C set: nothing (left) to do, S1 has its owner.
OVSTEP: LDX OVJOB
        BNE os_more
        SEC
        RTS
os_more:BIT OVSYNC
        BMI os_go
        BIT $D011       ; a piece begins only in the 3D view's time: line OVFIRST to OVLIM
        BMI os_late
        LDA $D012
        CMP #OVFIRST
        BCC os_late
        CMP OVLIM
        BCS os_late
os_go:  LDA OVLEFT+1
        BNE os_full
        LDA OVLEFT
        BEQ os_done
        CMP #OVCHUNK
        BCC os_k
os_full:LDA #OVCHUNK
os_k:   STA OVK         ; k bytes: Y from 256-k, the pointers k-256 back
        EOR #$FF
        TAY
        INY
        CLC
        LDA OVSRC
        ADC OVK
        STA CSRC
        LDA OVSRC+1
        ADC #$FF
        STA CSRC+1
        CLC
        LDA OVDST
        ADC OVK
        STA CDST
        LDA OVDST+1
        ADC #$FF
        STA CDST+1
        LDX #1
        JSR B1GETY
        CLC
        LDA OVSRC
        ADC OVK
        STA OVSRC
        BCC os_s
        INC OVSRC+1
os_s:   CLC
        LDA OVDST
        ADC OVK
        STA OVDST
        BCC os_d
        INC OVDST+1
os_d:   SEC
        LDA OVLEFT
        SBC OVK
        STA OVLEFT
        BCS os_l
        DEC OVLEFT+1
os_l:   ORA OVLEFT+1
        BEQ os_done
        JMP os_more
os_late:CLC
        RTS
os_done:LDX OVJOB
        LDA OVFLAG,X
        STA OVOWNER
        LDA #0
        STA OVJOB
        SEC
        RTS

; X = package, loaded completely now (interrupts off, ~25 cycles a byte: MINES
; ~4.5 frames at 1 MHz). C set: refused.
OVLOAD: JSR OVSTART
        BCS ol_ret
        LDA #$80
        STA OVSYNC
ol_step:JSR OVSTEP
        BCC ol_step
        LDA #0
        STA OVSYNC
        CLC
ol_ret: RTS

; Init (ENDSETUP, after GINIT2, with the reset snapshot): MINES' image as
; decoded (its state as a reset restores it) and the type-1 movement streams the
; mines borrow ($8100-$83FF) into bank 1. (13 pages: reading past MINES' end is harmless.)
OVINIT: LDA #<MNSTART
        LDX #>MNSTART
        LDY #>B1MINES
        STA CSRC
        STX CSRC+1
        LDA #<B1MINES
        STA CDST
        STY CDST+1
        LDX #13
        JSR B1PUT
        LDA #$00
        STA CSRC
        STA CDST
        LDA #$81
        STA CSRC+1
        LDA #>B1STREAM
        STA CDST+1
        LDX #3
        JSR B1PUT
        LDA #$80
        STA OVOWNER
        RTS

; The torpedo request in every mode (MNREQUEST, which stays in MINES): resident.
; Mine/settling loops never sample SPACE. Refusal is silent and free.
MNREQ:  LDA MSSTATE
        BEQ mq_request
        LSR A
        CMP #1
        BNE mq_refuse
mq_request:
        LDA TREQ
        RTS
mq_refuse:
        LDA #0
        STA TREQ
        RTS

; The trampolines: the only resident instructions with operands in S1. A, X, Y
; are kept on a hit (BIT); N, V, Z are not.
; MNOFF (MSOFF at every sector's arrival, ENDQUIET): with MINES not in S1 its
; hooks are all back already (MINES leaves S1 only after MNOFF: ENDQUIET), so only
; the rest of what MNOFF does is done here: MTOFF's IRQ off and black borders, no
; shot, MSPOSOFF.
OVTRAMP:
OVMNOFF:BIT OVOWNER
        BPL om_off
        JMP MNOFF
OVTRAMPEND:
om_off: LDA #48
        STA PHBUD+1
        SEI
        LDA #0
        STA $D01A
        STA VIEWBG
        STA $D021
        STA $D020
        STA SHOTARM
        STA SHOTON
        STA SHOTVIS
        JMP MSPOSOFF
; A base sector's arrival (MSECTOR, for a mothership; same-size patch of its
; JSR MSPOSON): MINES must be in S1 for the whole sequence (its calls into MINES
; are direct). Normally it is (only an ending empties S1 and the reset reloads it):
; else OVMISS counts and it is loaded now.
OVBASEIN:
        BIT OVOWNER
        BMI ob_ok
        PHA
        TXA
        PHA
        TYA
        PHA
        INC OVMISS
        LDX #1
        JSR OVLOAD
        PLA
        TAY
        PLA
        TAX
        PLA
ob_ok:  JMP MSPOSON
; The ENDING package's trampolines (ending.asm, ENDTRAMP) call this first: a
; missing package (its background load not finished) is completed now (OVMISS).
OVENDING:
        BIT OVOWNER
        BVS oe_ok
        PHA
        TXA
        PHA
        TYA
        PHA
        INC OVMISS
        LDX #2
        JSR OVLOAD
        PLA
        TAY
        PLA
        TAX
        PLA
oe_ok:  RTS
OVEND:
