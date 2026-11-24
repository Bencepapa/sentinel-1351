; Out of energy (issue #28; briefs/out-of-energy.md): what the original does at 0000.
;
; The code is spread over what was free and already in the PRG, nothing resident moved:
;  - zero page ($2D-$C1: free, common to both banks): this file, staged in the padding
;    of the ending payload and copied there by B1INIT (bank1.asm);
;  - the copy stub's tail (bank1.asm): OEIN, the input;
;  - the zero padding of game.asm (energy-pads.asm, build.py puts it in).
; Hooks (same-size patches, build.py / game.asm / ending.asm): TICKHK -> OEWORLD (every frame, at the
; end of the vertical blank: the energy),
; HINPUT's JSR INPUT -> OEIN, STARS's entry -> OESTARS, the digits' wrap in ENERGY10
; (en3 = $F8E0) -> OESET, HENERGY no longer stops at 0000, ARRSTEP's ENTERNOTICE -> OEENT.
; OEFLAG $2D (build.py defines it first: zero page): 0, or out of energy ($F865) and then also the
; clock of the stars' slow-down and the warp-in: 1 at the start, a step every other frame, stops at
; 255. ENDRESET2 clears it (OECLRM), as the original's init at $8E56.
        * = $2D
        .BYTE 0
OEFRAME:LDA CLOCKDIV    ; every other frame (the clock's frame counter: not while it stands still)
        LSR A
        BCC oe_r
        LDA OEFLAG
        BNE oe_st
        LDA HYPON       ; a jump has its own energy (HENERGY): only the flash
        BNE oe_fl
        LDA MSSTATE     ; (not in a base's sequence before its tunnel, MSSTATE 1-15: docking: $BA = 1
        ORA ENDMODE     ; there, the energy counts up; nor in an ending, ENDMODE 1-2: the original's
        BNE oe_r        ; $F886 runs when $BA | $88 = 0, and its flash)
        LDA #55         ; -1 every 110 frames
        JSR HENERGY
oe_fl:  LDA HUDE        ; $FA5B: below 2000 the four digits' colours flash every 15 frames, 7
        CMP #$72        ; and 8; at 2000 and more they are white again
        LDA #1
        BCS oe_f2
        LDA CLOCKDIV    ; bit 4 -> carry
        ASL A
        ASL A
        ASL A
        ASL A
        LDA #7
        ADC #0
oe_f2:  CMP $D83E       ; (only when it changes)
        BEQ oe_r
        LDX #3
oe_f1:  STA $D83E,X
        DEX
        BPL oe_f1
oe_r:   RTS
oe_st:  STA WTCNT       ; stranded: the world's clock stops ($F927 never calls $BE29): its countdown is
                        ; OEFLAG - 1 after its DEC, never 0 (but once at the start)
        INC OEFLAG      ; the clock: a step every other frame (the stars slow down over 510
        BNE oe_fl       ; frames, then the warp-in is tried: $F96B sets $FB for $1AF2)
        DEC OEFLAG
        JSR OEARR       ; (in the pads; every other frame until it starts)
        JMP oe_fl; The digits wrapped past 0000 (ENERGY10's en3 = $F8E0): once, the message, the siren, and the
; tracking computer is out ($89E6 never runs again).
OESET:  STY HUDE+3      ; (Y = $70 from en3; HENERGY lets only the first wrap through)
        LDA #$81
        STA MSGCOL
        LDA #$10
        STA MSGRATE
        LDA #<OETXT
        LDX #>OETXT
        LDY #$FF
        JSR MSGSTAT
        LDA #1          ; (the first colour at once, not after a flip's time)
        STA OEFLAG
        STA MSGCD
        STA SNDDIR      ; ($0912) the rattle: 3 sweeps up from $0Bxx
        LDA #$0B
        STA SNDHI0
        LDA #$40
        LDX #$03
        LDY #$1E
        JMP SNDGO
OETXT:  .BYTE $40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$4F,$55,$54,$40,$4F,$46,$40,$45,$4E,$45,$52,$47,$59,$FF
OEZPEND:
