;;PAD STARS
; The stars (STARS's entry): full speed, then every 2nd, 4th frame, then none ($F93B-$F96B); the
; stage is OEFLAG / 64 (0 when not out of energy), a star step when OEFLAG AND stage = 0.
OESTARS:LDA OEFLAG
        BEQ oe_s1
        ASL A
        ROL A
        ROL A
        AND #$03
        AND OEFLAG
        BNE oe_s9
oe_s1:  INC FRMC        ; (STARS's first instruction)
        JMP STARS2
oe_s9:  RTS
; ENDRESET2's STA ENDMODE: a new game is not out of energy.
OECLRM: STA ENDMODE
        STA OEFLAG
        RTS
;;PAD FRC
; Out of energy in a jump (HENERGY at 0000): leave at once, as the end of the jump's steps does
; (g_hv21: the deceleration, 120 frames); not in the deceleration itself.
OEFORCE:LDA HYPON
        CMP #3
        BCS oe_fx
        JMP g_hv21
oe_fx:  RTS
;;PAD CLK
; Every frame (TICKHK): the energy, then the world's clock.
OEWORLD:JSR OEFRAME
        JMP WORLD
;;PAD ARR
; $F96B sets $FB, $1AF2 warps three fighters in: the arrival of a squadron of at least 3
; ships (SQINCHK refuses while fighters, an approach or a base's tunnel are there).
OEARR:  JSR SECIDX
        LDA #3
        STA M_COUNT,X
        JMP SQINCHK
;;PAD SQ
; SECTORIN's LDY M_STATE,X: out of energy there are no ships in the arrival's sector (SQCOUNT 0: no
; approach, no scanner lock, no rush; the original's stranded loop never runs the approach), the warp-in
; (OEARR) brings the fighters. The flags are those of the LDY (Z: empty).
OEMS:   LDY OEFLAG
        BEQ oe_ms1
        LDY #0
        RTS
oe_ms1: LDY M_STATE,X
        RTS
;;PAD ENT
; The arrival's "ALERT ENTERING GORGANITOR SECTOR" is not in the original's warp-in: only the
; warning at its end, so that nothing replaces OUT OF ENERGY before it.
OEENT:  LDA OEFLAG
        BNE oe_en9
        JMP ENTERNOTICE
oe_en9: RTS
