; Sentinel C128: the cockpit and the sector map as one program.
;
; This file is only the glue. c128-game/build.py joins three sources into one
; program: c128-gui/cockpit/cockpit.asm (unchanged but for a few marked patches),
; c128-map/map.asm (every label it defines gets the prefix M_, its code moves to
; right after the cockpit's code, its second-display data to $2900) and this file.
;
; Flow: the cockpit starts in the player's sector (4,2 on the map, SECTOR 05.03,
; empty as in the original). C= opens the map (the original's map key): the map
; program's grid draw-in, icons, cursor, ticks and second display run as they do
; standalone. Fire on another sector jumps there at once (hyperspace comes later);
; SPACE returns without a jump. Back in the cockpit, what the map holds for the
; sector decides what is there: a squadron (STATE 1-3) of COUNT ships is approached
; group by group with the long range scanner, each group becomes up to three
; fighters (all type 1 for now); TARGETS on the HUD shows the ships left, each
; kill lowers the map's COUNT, the last one empties the sector on the map.
; Motherships (STATE $80 / $FF) are not ported yet: those sectors are empty here.
;
; The map and the cockpit share the bitmap at $6000 (the original also redraws
; one over the other). Coming back, RESTORE puts the cockpit back from master
; copies at $5000-$5FDF (CPU RAM that the VIC-IIe cannot use, see build.py):
; the sprite shapes kept in bitmap rows 0-2 and 23-24, the cockpit art, the colour
; matrix; the 3D view is cleared and the colour RAM copied from COLORDATA.

MASTER  = $5000         ; master copies (build.py): rows 0-2, shot slots, art, matrix
MSPR    = $5000         ; bitmap $6000-$63BF (960)
MSHOT   = $53C0         ; bitmap $7CC0-$7F7F (704)
MART    = $5680         ; bitmap $7680-$7CBF (1600)
MMAT    = $5CC0         ; matrix $4478-$4797 (800)
HUDSEC  = $4865         ; the HUD's sector digits (row 2, column 21)
CSRC    = $FB           ; copy pointers (PTR of both programs)
CDST    = $FD

GAMEINIT:               ; once, from the cockpit's START
        LDA $D012       ; the world: the map program's start layout ($20F1)
        ORA #$01
        STA M_SEED
        JSR M_GENONCE
        JSR SHOWSEC
        JMP SECTORIN

; C= in the cockpit: the map.
TOMAP:  LDA #$01
        STA CPREV       ; (C= is still held on the way back)
        LDA #$00
        STA VICENA
        STA $D404
        STA $D40B
        STA MJUMPF
        LDA FAST
        AND #$FE
        STA FAST
        JSR M_MSETUP    ; the map program's set-up and draw-in start
        JMP M_frame     ; its frame loop; it comes back to TOCOCK

; From the map: SPACE (no jump) or fire on another sector (MJUMPF = 1).
TOCOCK: LDA #$00
        STA VICENA
        STA $D404
        STA $D40B
        LDA #$01
        STA SPREV       ; (SPACE may still be held: it would leave the program)
        JSR RESTORE
        LDA MJUMPF
        BEQ g_tc1
        LDA #$00
        STA MJUMPF
        JSR SECTORIN
g_tc1:    JSR SHOWSEC
        LDA #$0F
        STA $D418
        JMP frame

; Into the sector M_SELX / M_SELY: its squadron's ships (none for an empty or a
; mothership sector), then the cockpit's arrival (the approach, ARRIVE).
SECTORIN:
        JSR SECIDX
        LDA #$00
        LDY M_STATE,X
        BEQ g_sin1      ; empty
        BMI g_sin1      ; a mothership: not ported yet
        LDA M_COUNT,X
g_sin1: STA SQCOUNT
        JMP ARRIVE

; A kill ($3CD9): the map's COUNT follows; at 0 the squadron is gone ($3CDE).
SECKILL:STX SKX
        JSR SECIDX
        LDA M_COUNT,X
        BEQ g_sk9
        DEC M_COUNT,X
        BNE g_sk9
        LDA #$00
        STA M_STATE,X
g_sk9:  LDX SKX
        RTS

SECIDX: LDA M_SELY      ; X = row * 10 + column
        ASL A
        ASL A
        CLC
        ADC M_SELY
        ASL A
        CLC
        ADC M_SELX
        TAX
        RTS

SHOWSEC:LDX M_SELX      ; SECTOR cc.rr on the HUD: column and row from 1
        INX
        TXA
        ORA #$70
        STA HUDSEC+1
        LDX M_SELY
        INX
        TXA
        ORA #$70
        STA HUDSEC+4
        RTS

; The cockpit's picture back after the map.
RESTORE:LDX #$00        ; colour RAM, as START does
g_rs0:    LDA COLORDATA,X
        STA COLOR,X
        LDA COLORDATA+256,X
        STA COLOR+256,X
        LDA COLORDATA+512,X
        STA COLOR+512,X
        LDA COLORDATA+768,X
        STA COLOR+768,X
        INX
        BNE g_rs0
        LDA #$C0        ; the 3D view, bitmap rows 3-17 ($63C0-$767F): cleared
        STA CDST
        LDA #$63
        STA CDST+1
        LDX #19
        LDY #$00
        TYA
g_rs1:    STA (CDST),Y
        INY
        BNE g_rs1
        INC CDST+1
        DEX
        BNE g_rs1
        LDA #<MSPR      ; the master copies
        LDX #>MSPR
        LDY #$00
        JSR CPSRC
        LDA #$00
        LDX #$60
        JSR CPDST
        LDA #<960
        LDX #>960
        JSR COPYN
        LDA #<MSHOT
        LDX #>MSHOT
        JSR CPSRC
        LDA #$C0
        LDX #$7C
        JSR CPDST
        LDA #<704
        LDX #>704
        JSR COPYN
        LDA #<MART
        LDX #>MART
        JSR CPSRC
        LDA #$80
        LDX #$76
        JSR CPDST
        LDA #<1600
        LDX #>1600
        JSR COPYN
        LDA #<MMAT
        LDX #>MMAT
        JSR CPSRC
        LDA #$78
        LDX #$44
        JSR CPDST
        LDA #<800
        LDX #>800
        JMP COPYN

CPSRC:  STA CSRC
        STX CSRC+1
        RTS
CPDST:  STA CDST
        STX CDST+1
        RTS
COPYN:  STA CNTL        ; copy A/X bytes (low/high) from CSRC to CDST
        STX CNTH
        LDY #$00
g_cn1:    LDA CNTH
        BEQ g_cn3
g_cn2:    LDA (CSRC),Y    ; whole pages
        STA (CDST),Y
        INY
        BNE g_cn2
        INC CSRC+1
        INC CDST+1
        DEC CNTH
        JMP g_cn1
g_cn3:    LDX CNTL        ; the rest
        BEQ g_cn5
g_cn4:    LDA (CSRC),Y
        STA (CDST),Y
        INY
        DEX
        BNE g_cn4
g_cn5:    RTS

MJUMPF: .BYTE 0         ; the map chose another sector
CPREV:  .BYTE 0         ; C= / SPACE held (edges only)
SPREV:  .BYTE 0
SKX:    .BYTE 0
WSIZE:  .BYTE 0
CNTL:   .BYTE 0
CNTH:   .BYTE 0
