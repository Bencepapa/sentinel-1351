; Leaf mine steering and sprite placement make no nested PTR calls.
; HITBOX preserves PTR; hit-mask scratch ends before star plotting/input.
MNHB = $FC             ; PTR high: HITBOX preserves it, no nested PTR users
MNDISP = $FB           ; same leaf-only scratch as MNTMP2
MNTMP2 = $FB           ; PTR, leaf-only scratch (explicit zero-page encoding)
MNSTART:
; Original $CC31-$CE88 and $B988-$BA10, one instruction per source label.
; Dedicated shadows keep cockpit/phasor/fighter state independent.
mn_cc31: LDA #$01 ; $cc31
mn_cc33: STA mn_dcc1a ; $cc33
mn_cc36: STA mn_dcc26 ; $cc36
mn_cc39: STA mn_dcc2c ; $cc39
mn_cc3c: LDY MNKIND ; $cc3c
mn_cc3e: LDX #$05 ; $cc3e
mn_cc40: LDA mn_dcc2d,Y ; $cc40
mn_cc43: STA $D028,X ; $cc43
mn_cc46: LDA #$00 ; $cc46
mn_cc48: STA mn_dcc1b ; $cc48
mn_cc4b: STA mn_dcc12,X ; $cc4b
mn_cc4e: JSR M_RND ; $cc4e
mn_cc51: AND #$0F ; $cc51
mn_cc53: STA mn_dcc0c,X ; $cc53
mn_cc56: DEX ; $cc56
mn_cc57: BPL mn_cc40 ; $cc57
mn_cc59: LDA mn_dcc2f,Y ; $cc59
mn_cc5c: STA $D025 ; $cc5c
mn_cc5f: STA MNCOLOR ; $cc5f
mn_cc62: LDA #$FC ; $cc62
mn_cc64: STA $D01D ; $cc64
mn_cc67: LDA #$89 ; $cc67
mn_cc69: STA MNENA ; $cc69
mn_cc6b: LDA #$76 ; $cc6b
mn_cc6d: STA $D01C ; $cc6d
mn_cc70: RTS ; $cc70
mn_cc71: LDA MNPAUSE ; $cc71
mn_cc74: BNE mn_cc7b ; $cc74
mn_cc76: DEC mn_dcc2c ; $cc76
mn_cc79: BEQ mn_cc7c ; $cc79
mn_cc7b: RTS ; $cc7b
mn_cc7c: LDX DIFF ; $cc7c
mn_cc7e: LDA mn_dcc27,X ; $cc7e
mn_cc81: STA mn_dcc2c ; $cc81
mn_cc84: LDX #$01 ; $cc84
mn_cc86: LDY #$02 ; $cc86
mn_cc88: LDA #$04 ; $cc88
mn_cc8a: STA mn_dcc18 ; $cc8a
mn_cc8d: LDA #$FB ; $cc8d
mn_cc8f: STA mn_dcc19 ; $cc8f
mn_cc92: LDA mn_dcc12,X ; $cc92
mn_cc95: BEQ mn_cc9a ; $cc95
mn_cc97: JMP mn_ccff ; $cc97
mn_cc9a: DEC mn_dcc06,X ; $cc9a
mn_cc9d: BNE mn_cca4 ; $cc9d
mn_cc9f: DEC mn_dcc0c,X ; $cc9f
mn_cca2: BEQ mn_cca7 ; $cca2
mn_cca4: JMP mn_ce08 ; $cca4
mn_cca7: LDA #$01 ; $cca7
mn_cca9: STA mn_dcc0c,X ; $cca9
mn_ccac: STA mn_dcc12,X ; $ccac
mn_ccaf: TXA ; $ccaf
mn_ccb0: PHA ; $ccb0
mn_ccb1: LDX DIFF ; $ccb1
mn_ccb3: JSR M_RND ; $ccb3
mn_ccb6: AND mn_dcc1c,X ; $ccb6
mn_ccb9: LDX mn_dcc26 ; $ccb9
mn_ccbc: DEX ; $ccbc
mn_ccbd: BPL mn_ccc1 ; $ccbd
mn_ccbf: LDX #$04 ; $ccbf
mn_ccc1: STX mn_dcc26 ; $ccc1
mn_ccc4: CLC ; $ccc4
mn_ccc5: ADC mn_dcc21,X ; $ccc5
mn_ccc8: STA MNPOS,Y ; $ccc8
mn_cccb: PLA ; $cccb
mn_cccc: TAX ; $cccc
mn_cccd: LDA MNPOS,Y ; $cccd
mn_ccd0: JSR mn_ce3a ; $ccd0
mn_ccd3: LDA #$01 ; $ccd3
mn_ccd5: STA mn_dcc00,X ; $ccd5
mn_ccd8: LDA #$8C ; $ccd8
mn_ccda: STA MNPOS1,Y ; $ccda
mn_ccdd: LDA #$7C ; $ccdd
mn_ccdf: STA MNSHAPE,X ; $ccdf
mn_cce1: LDA #$0B ; $cce1
mn_cce3: STA mn_dcbe2,X ; $cce3
mn_cce6: STA mn_dcbe8,X ; $cce6
mn_cce9: LDA #$23 ; $cce9
mn_cceb: STA mn_dcbee,X ; $cceb
mn_ccee: STA mn_dcbf4,X ; $ccee
mn_ccf1: LDA MNENA ; $ccf1
mn_ccf3: ORA mn_dcc18 ; $ccf3
mn_ccf6: STA MNENA ; $ccf6
mn_ccf8: LDA MNMSB ; $ccf8
mn_ccfa: AND mn_dcc19 ; $ccfa
mn_ccfd: STA MNMSB ; $ccfd
mn_ccff: DEC MNCOLOR ; $ccff
mn_cd02: DEC mn_dcbee,X ; $cd02
mn_cd05: BEQ mn_cd0a ; $cd05
mn_cd07: JMP mn_ce08 ; $cd07
mn_cd0a: LDA mn_dcbf4,X ; $cd0a
mn_cd0d: SEC ; $cd0d
mn_cd0e: SBC #$01 ; $cd0e
mn_cd10: CMP #$06 ; $cd10
mn_cd12: BCS mn_cd16 ; $cd12
mn_cd14: LDA #$06 ; $cd14
mn_cd16: STA mn_dcbee,X ; $cd16
mn_cd19: STA mn_dcbf4,X ; $cd19
mn_cd1c: DEC mn_dcbe2,X ; $cd1c
mn_cd1f: BNE mn_cd9b ; $cd1f
mn_cd21: LDA mn_dcbe8,X ; $cd21
mn_cd24: STA mn_dcbe2,X ; $cd24
mn_cd27: DEC MNSHAPE,X ; $cd27
mn_cd29: DEC mn_dcbe8,X ; $cd29
mn_cd2c: BNE mn_cd9b ; $cd2c
mn_cd2e: LDA MNENA ; $cd2e
mn_cd30: AND mn_dcc18 ; $cd30
mn_cd33: BEQ mn_cd93 ; $cd33
mn_cd35: STA HITFL ; $cd35
mn_cd37: TXA ; $cd37
mn_cd38: PHA ; $cd38
mn_cd39: TYA ; $cd39
mn_cd3a: PHA ; $cd3a
mn_cd3b: JSR SHIPHIT ; $cd3b
mn_cd3e: PLA ; $cd3e
mn_cd3f: TAY ; $cd3f
mn_cd40: PLA ; $cd40
mn_cd41: TAX ; $cd41
mn_cd42: LDA EXPL2 ; $cd42
mn_cd45: BEQ mn_cd4a ; $cd45
mn_cd47: JMP mn_cdf7 ; $cd47
mn_cd4a: LDA mn_dcbfa,X ; $cd4a
mn_cd4d: ASL A ; $cd4d
mn_cd4e: STA EVX02 ; $cd4e
mn_cd51: LDA mn_dcc00,X ; $cd51
mn_cd54: ASL A ; $cd54
mn_cd55: STA EVY02 ; $cd55
mn_cd58: LDA #$01 ; $cd58
mn_cd5a: STA EXPL2 ; $cd5a
mn_cd5d: LDA #$00 ; $cd5d
mn_cd5f: STA EXPB2 ; $cd5f
mn_cd62: LDA MNMSB ; $cd62
mn_cd64: AND mn_dcc18 ; $cd64
mn_cd67: BEQ mn_cd70 ; $cd67
mn_cd69: SEC ; $cd69
mn_cd6a: LDA MNPOS,Y ; $cd6a
mn_cd6d: ROR A ; $cd6d
mn_cd6e: BNE mn_cd74 ; $cd6e
mn_cd70: LDA MNPOS,Y ; $cd70
mn_cd73: LSR A ; $cd73
mn_cd74: SEC ; $cd74
mn_cd75: SBC #$06 ; $cd75
mn_cd77: STA EXPX2 ; $cd77
mn_cd7a: CMP #$0A ; $cd7a
mn_cd7c: BCC mn_cd82 ; $cd7c
mn_cd7e: CMP #$91 ; $cd7e
mn_cd80: BCC mn_cd87 ; $cd80
mn_cd82: LDA #$00 ; $cd82
mn_cd84: STA EXPL2 ; $cd84
mn_cd87: LDA MNPOS1,Y ; $cd87
mn_cd8a: SEC ; $cd8a
mn_cd8b: SBC #$32 ; $cd8b
mn_cd8d: STA EXPY2 ; $cd8d
mn_cd90: JMP mn_cdf7 ; $cd90
mn_cd93: LDA #$00 ; $cd93
mn_cd95: STA mn_dcc12,X ; $cd95
mn_cd98: JMP mn_ce08 ; $cd98
mn_cd9b: LDA mn_dcbfa,X ; $cd9b
mn_cd9e: BMI mn_cdc4 ; $cd9e
mn_cda0: CLC ; $cda0
mn_cda1: ADC MNPOS,Y ; $cda1
mn_cda4: STA MNPOS,Y ; $cda4
mn_cda7: BCS mn_cdba ; $cda7
mn_cda9: LDA MNMSB ; $cda9
mn_cdab: AND mn_dcc18 ; $cdab
mn_cdae: BEQ mn_cdc1 ; $cdae
mn_cdb0: LDA MNPOS,Y ; $cdb0
mn_cdb3: CMP #$4F ; $cdb3
mn_cdb5: BCC mn_cdc1 ; $cdb5
mn_cdb7: JMP mn_cdf7 ; $cdb7
mn_cdba: LDA MNMSB ; $cdba
mn_cdbc: ORA mn_dcc18 ; $cdbc
mn_cdbf: STA MNMSB ; $cdbf
mn_cdc1: JMP mn_cde4 ; $cdc1
mn_cdc4: AND #$7F ; $cdc4
mn_cdc6: SEC ; $cdc6
mn_cdc7: STA MNTMP ; $cdc7
mn_cdc9: LDA MNPOS,Y ; $cdc9
mn_cdcc: SBC MNTMP ; $cdcc
mn_cdce: STA MNPOS,Y ; $cdce
mn_cdd1: BCS mn_cde4 ; $cdd1
mn_cdd3: LDA MNMSB ; $cdd3
mn_cdd5: AND mn_dcc18 ; $cdd5
mn_cdd8: BNE mn_cddd ; $cdd8
mn_cdda: JMP mn_cdf7 ; $cdda
mn_cddd: LDA MNMSB ; $cddd
mn_cddf: AND mn_dcc19 ; $cddf
mn_cde2: STA MNMSB ; $cde2
mn_cde4: LDA mn_dcc1b ; $cde4
mn_cde7: EOR #$01 ; $cde7
mn_cde9: STA mn_dcc1b ; $cde9
mn_cdec: BEQ mn_ce08 ; $cdec
mn_cdee: CLC ; $cdee
mn_cdef: ADC MNPOS1,Y ; $cdef
mn_cdf2: STA MNPOS1,Y ; $cdf2
mn_cdf5: BNE mn_ce08 ; $cdf5
mn_cdf7: LDA #$00 ; $cdf7
mn_cdf9: STA mn_dcc12,X ; $cdf9
mn_cdfc: LDA #$01 ; $cdfc
mn_cdfe: STA mn_dcc0c,X ; $cdfe
mn_ce01: LDA MNENA ; $ce01
mn_ce03: AND mn_dcc19 ; $ce03
mn_ce06: STA MNENA ; $ce06
mn_ce08: LDA MNPOS,Y ; $ce08
mn_ce0b: JSR mn_ce3a ; $ce0b
mn_ce0e: DEC mn_dcc1a ; $ce0e
mn_ce11: BNE mn_ce23 ; $ce11
mn_ce13: TXA ; $ce13
mn_ce14: PHA ; $ce14
mn_ce15: TYA ; $ce15
mn_ce16: PHA ; $ce16
mn_ce17: JSR mn_b988 ; $ce17
mn_ce1a: PLA ; $ce1a
mn_ce1b: TAY ; $ce1b
mn_ce1c: PLA ; $ce1c
mn_ce1d: TAX ; $ce1d
mn_ce1e: LDA #$50 ; $ce1e
mn_ce20: STA mn_dcc1a ; $ce20
mn_ce23: CLC ; $ce23
mn_ce24: ROL mn_dcc18 ; $ce24
mn_ce27: SEC ; $ce27
mn_ce28: ROL mn_dcc19 ; $ce28
mn_ce2b: INY ; $ce2b
mn_ce2c: INY ; $ce2c
mn_ce2d: INX ; $ce2d
mn_ce2e: CPX #$02 ; $ce2e
mn_ce30: BEQ mn_ce23 ; $ce30
mn_ce32: CPX #$06 ; $ce32
mn_ce34: BEQ mn_ce39 ; $ce34
mn_ce36: JMP mn_cc92 ; $ce36
mn_ce39: RTS ; $ce39
mn_ce3a: PHA ; $ce3a
mn_ce3b: LDA MNMSB ; $ce3b
mn_ce3d: AND mn_dcc18 ; $ce3d
mn_ce40: BNE mn_ce85 ; $ce40
mn_ce42: PLA ; $ce42
mn_ce43: CMP #$44 ; $ce43
mn_ce45: BCS mn_ce4d ; $ce45
mn_ce47: LDA #$84 ; $ce47
mn_ce49: STA mn_dcbfa,X ; $ce49
mn_ce4c: RTS ; $ce4c
mn_ce4d: CMP #$60 ; $ce4d
mn_ce4f: BCS mn_ce57 ; $ce4f
mn_ce51: LDA #$82 ; $ce51
mn_ce53: STA mn_dcbfa,X ; $ce53
mn_ce56: RTS ; $ce56
mn_ce57: CMP #$7C ; $ce57
mn_ce59: BCS mn_ce61 ; $ce59
mn_ce5b: LDA #$81 ; $ce5b
mn_ce5d: STA mn_dcbfa,X ; $ce5d
mn_ce60: RTS ; $ce60
mn_ce61: CMP #$98 ; $ce61
mn_ce63: BCS mn_ce6b ; $ce63
mn_ce65: LDA #$80 ; $ce65
mn_ce67: STA mn_dcbfa,X ; $ce67
mn_ce6a: RTS ; $ce6a
mn_ce6b: CMP #$B4 ; $ce6b
mn_ce6d: BCS mn_ce75 ; $ce6d
mn_ce6f: LDA #$01 ; $ce6f
mn_ce71: STA mn_dcbfa,X ; $ce71
mn_ce74: RTS ; $ce74
mn_ce75: CMP #$D0 ; $ce75
mn_ce77: BCS mn_ce7f ; $ce77
mn_ce79: LDA #$02 ; $ce79
mn_ce7b: STA mn_dcbfa,X ; $ce7b
mn_ce7e: RTS ; $ce7e
mn_ce7f: LDA #$03 ; $ce7f
mn_ce81: STA mn_dcbfa,X ; $ce81
mn_ce84: RTS ; $ce84
mn_ce85: PLA ; $ce85
mn_ce86: JMP mn_ce7f ; $ce86
mn_b988: LDX #$01 ; $b988
mn_b98a: LDY #$02 ; $b98a
mn_b98c: LDA #$04 ; $b98c
mn_b98e: STA MNMASK ; $b98e
mn_b990: LDA #$FB ; $b990
mn_b992: STA MNMASK1 ; $b992
mn_b994: LDA JOYG ; $b994
mn_b996: AND #$0F ; $b996
mn_b998: LSR A ; $b998
mn_b999: LSR A ; $b999
mn_b99a: STA MNTMP1 ; $b99a
mn_b99c: CMP #$0F ; $b99c
mn_b99e: BNE mn_b9a1 ; $b99e
mn_b9a0: RTS ; $b9a0
mn_b9a1: LDA MNTMP1 ; $b9a1
mn_b9a3: STA MNTMP ; $b9a3
mn_b9a5: LDA #$7C ; $b9a5
mn_b9a7: SEC ; $b9a7
mn_b9a8: SBC MNSHAPE,X ; $b9a8
mn_b9aa: ASL A ; $b9aa
mn_b9ab: STA MNTMP2 ; $b9ab
mn_b9ad: LSR MNTMP ; $b9ad
mn_b9af: BCS mn_b9cb ; $b9af
mn_b9b1: CLC ; $b9b1
mn_b9b2: LDA MNPOS,Y ; $b9b2
mn_b9b5: ADC MNTMP2 ; $b9b5
mn_b9b7: STA MNPOS,Y ; $b9b7
mn_b9ba: BCC mn_b9cb ; $b9ba
mn_b9bc: LDA MNMSB ; $b9bc
mn_b9be: AND MNMASK ; $b9be
mn_b9c0: BEQ mn_b9c5 ; $b9c0
mn_b9c2: JMP mn_b9ec ; $b9c2
mn_b9c5: LDA MNMSB ; $b9c5
mn_b9c7: ORA MNMASK ; $b9c7
mn_b9c9: STA MNMSB ; $b9c9
mn_b9cb: LSR MNTMP ; $b9cb
mn_b9cd: BCS mn_b9fc ; $b9cd
mn_b9cf: SEC ; $b9cf
mn_b9d0: LDA MNPOS,Y ; $b9d0
mn_b9d3: SBC MNTMP2 ; $b9d3
mn_b9d5: STA MNPOS,Y ; $b9d5
mn_b9d8: BCS mn_b9fc ; $b9d8
mn_b9da: LDA MNMSB ; $b9da
mn_b9dc: AND MNMASK ; $b9dc
mn_b9de: BNE mn_b9e3 ; $b9de
mn_b9e0: JMP mn_b9ec ; $b9e0
mn_b9e3: LDA MNMSB ; $b9e3
mn_b9e5: AND MNMASK1 ; $b9e5
mn_b9e7: STA MNMSB ; $b9e7
mn_b9e9: JMP mn_b9fc ; $b9e9
mn_b9ec: LDA MNENA ; $b9ec
mn_b9ee: AND MNMASK1 ; $b9ee
mn_b9f0: STA MNENA ; $b9f0
mn_b9f2: LDA #$00 ; $b9f2
mn_b9f4: STA mn_dcc12,X ; $b9f4
mn_b9f7: LDA #$01 ; $b9f7
mn_b9f9: STA mn_dcc06,X ; $b9f9
mn_b9fc: CLC ; $b9fc
mn_b9fd: ROL MNMASK ; $b9fd
mn_b9ff: SEC ; $b9ff
mn_ba00: ROL MNMASK1 ; $ba00
mn_ba02: INY ; $ba02
mn_ba03: INY ; $ba03
mn_ba04: INX ; $ba04
mn_ba05: CPX #$02 ; $ba05
mn_ba07: BEQ mn_b9fc ; $ba07
mn_ba09: CPX #$06 ; $ba09
mn_ba0b: BEQ mn_ba10 ; $ba0b
mn_ba0d: JMP mn_b9a1 ; $ba0d
mn_ba10: RTS ; $ba10

mn_dcbe2: .BYTE $30
mn_dcbe3: .BYTE $c8
mn_dcbe4: .BYTE $b1
mn_dcbe5: .BYTE $3d
mn_dcbe6: .BYTE $c9
mn_dcbe7: .BYTE $21
mn_dcbe8: .BYTE $f0
mn_dcbe9: .BYTE $04
mn_dcbea: .BYTE $c9
mn_dcbeb: .BYTE $0d
mn_dcbec: .BYTE $d0
mn_dcbed: .BYTE $19
mn_dcbee: .BYTE $ad
mn_dcbef: .BYTE $0b
mn_dcbf0: .BYTE $08
mn_dcbf1: .BYTE $10
mn_dcbf2: .BYTE $0f
mn_dcbf3: .BYTE $e0
mn_dcbf4: .BYTE $21
mn_dcbf5: .BYTE $b0
mn_dcbf6: .BYTE $07
mn_dcbf7: .BYTE $a9
mn_dcbf8: .BYTE $00
mn_dcbf9: .BYTE $8d
mn_dcbfa: .BYTE $0b
mn_dcbfb: .BYTE $08
mn_dcbfc: .BYTE $f0
mn_dcbfd: .BYTE $04
mn_dcbfe: .BYTE $a9
mn_dcbff: .BYTE $0a
mn_dcc00: .BYTE $10
mn_dcc01: .BYTE $02
mn_dcc02: .BYTE $a9
mn_dcc03: .BYTE $06
mn_dcc04: .BYTE $4c
mn_dcc05: .BYTE $4c
mn_dcc06: .BYTE $cb
mn_dcc07: .BYTE $c9
mn_dcc08: .BYTE $20
mn_dcc09: .BYTE $f0
mn_dcc0a: .BYTE $e3
mn_dcc0b: .BYTE $c9
mn_dcc0c: .BYTE $0d
mn_dcc0d: .BYTE $f0
mn_dcc0e: .BYTE $df
mn_dcc0f: .BYTE $c9
mn_dcc10: .BYTE $80
mn_dcc11: .BYTE $b0
mn_dcc12: .BYTE $db
mn_dcc13: .BYTE $4c
mn_dcc14: .BYTE $06
mn_dcc15: .BYTE $cd
mn_dcc16: .BYTE $a9
mn_dcc17: .BYTE $08
mn_dcc18: .BYTE $ae
mn_dcc19: .BYTE $10
mn_dcc1a: .BYTE $01
mn_dcc1b: .BYTE $00
mn_dcc1c: .BYTE $0f
mn_dcc1d: .BYTE $0f
mn_dcc1e: .BYTE $0f
mn_dcc1f: .BYTE $0f
mn_dcc20: .BYTE $0f
mn_dcc21: .BYTE $a0
mn_dcc22: .BYTE $50
mn_dcc23: .BYTE $f0
mn_dcc24: .BYTE $80
mn_dcc25: .BYTE $c0
mn_dcc26: .BYTE $a9
mn_dcc27: .BYTE $03
mn_dcc28: .BYTE $03
mn_dcc29: .BYTE $02
mn_dcc2a: .BYTE $02
mn_dcc2b: .BYTE $01
mn_dcc2c: .BYTE $00
mn_dcc2d: .BYTE $07
mn_dcc2e: .BYTE $04
mn_dcc2f: .BYTE $0a
mn_dcc30: .BYTE $00
MNKIND: .BYTE 0
MNENA: .BYTE 0
MNMSB: .BYTE 0
MNPAUSE: .BYTE 0
MNCOLOR: .BYTE 0
MNMASK: .BYTE 0
MNMASK1: .BYTE 0
MNTMP: .BYTE 0
MNTMP1: .BYTE 0
MNSHAPE: .BYTE 0,0,0,0,0,0
MNPOS: .BYTE 0
MNPOS1: .BYTE 0,0,0,0,0,0,0,0,0,0,0
; Integration is active only through the mothership's existing hooks.
; The copied delay/position tables deliberately include the original's initial
; instruction-looking bytes: these are shared with earlier C64 code, and are
; not newly invented mine delays. $CC31 initializes only the fields it owns.
; Work is bounded in the view and 2 MHz blank. Thirty calls/frame approaching,
; fifteen settling are ceilings, not cycle-exact emulation of a C64 main loop.
; Each shape loads/restores in 64-byte pieces. The last fourteen settling frames
; release the sprites before the rings can reuse them. Stale C64 mine sprites
; are therefore deliberately not retained across that handover.
; Six stars alternate each frame, with twice STARTK's fractional rate; new stars
; are born at y=105 ($F1E5). Births stay banded through the visible rings;
; sprite cleanup restores the normal star loop, sequence exit restores random Y.
MNVIEW:
        LDA MAPSHOWN
        ORA WIPE
        ORA HYPON
        BEQ mn_viewgo
        RTS
mn_viewgo:
        LDA MSROW
        BEQ mn_loadgo
        JMP mn_running
mn_loadgo:
        LDA $D012
        CMP #115
        BCC mn_loadtime
        RTS
mn_loadtime:
        LDA MNFIN
        BEQ mn_loadready
        LDA MNLOAD
        BEQ mn_loadclean
        JSR MNRESTORE
        RTS
mn_loadclean:
        LDA #0
        STA MNFIN
mn_loadready:
        LDA MNLOAD
        CMP #12
        BNE mn_loadresume
        JMP mn_loaded
mn_loadresume:
        LDA MNLOAD
        BNE mn_copy
        LDA #0
        STA MNFIN
        STA MNLEFT
        STA SHLT
        STA SHLK
        LDA #<MNBACK
        STA mn_back+1
        LDA #>MNBACK
        STA mn_back+2
        LDA #$00
        STA mn_bak+1
        LDA #$60
        STA mn_bak+2
        LDA #<MNART
        STA mn_get+1
        LDA #>MNART
        STA mn_get+2
        LDA #$00
        STA mn_dst+1
        LDA #$60
        STA mn_dst+2
mn_copy:
        LDX #0
mn_bak: LDA $6000,X
mn_back:STA MNBACK,X
mn_src: JSR MNBYTE
mn_dst: STA $6000,X
        INX
        CPX #64
        BCC mn_bak
mn_srcok:
        CLC
        LDA mn_dst+1
        ADC #64
        STA mn_dst+1
        BCC mn_dstok
        INC mn_dst+2
mn_dstok:
        CLC
        LDA mn_bak+1
        ADC #64
        STA mn_bak+1
        BCC mn_bakok
        INC mn_bak+2
mn_bakok:
        CLC
        LDA mn_back+1
        ADC #64
        STA mn_back+1
        BCC mn_backok
        INC mn_back+2
mn_backok:
        INC MNLOAD
        LDA MNLOAD
        CMP #12
        BCS mn_loaded
        RTS
mn_loaded:
        JSR MTRESET
        JSR MNENTER
        LDA #$00
        STA MNKIND
        STA MNPAUSE
        LDA MSKIND
        CMP #$80
        BNE mn_kindok
        INC MNKIND
mn_kindok:
        LDA #$E0
        STA STARTK+7
        LDA #$4C
        STA nosh
        LDA #<MNSTARLOOP
        STA nosh+1
        LDA #>MNSTARLOOP
        STA nosh+2
        LDA #180
        STA mp_next-5
        LDA #160
        STA mp_pass+4
        JSR mn_cc31
        LDA #<MNFRAME
        STA sprcj+1
        STA HTSPR+1
        LDA #>MNFRAME
        STA sprcj+2
        STA HTSPR+2
        LDA #<MNVB
        STA vv2+1
        STA g_vs2+1
        LDA #>MNVB
        STA vv2+2
        STA g_vs2+2
        LDA #$4C
        STA nsy
        LDA #<MNNEWY
        STA nsy+1
        LDA #>MNNEWY
        STA nsy+2
        JMP MSPOS
mn_running:
mn_position:
        JSR MSPOS       ; scanner/depth work retains priority and its original rate
        LDA MSSTATE
        CMP #16
        BEQ mn_viewticks
        JSR MNRINGS
        LDA #<MSVB
        STA vv2+1
        STA g_vs2+1
        LDA #>MSVB
        STA vv2+2
        STA g_vs2+2
        LDA #<SPRCROSS
        STA sprcj+1
        STA HTSPR+1
        LDA #>SPRCROSS
        STA sprcj+2
        STA HTSPR+2
mn_vret:RTS
mn_viewticks:
        JSR MNHIT
        LDA MNFIN
        BNE mn_vret
        LDA MSROW
        CMP #2
        BCC mn_spawns
        LDX #5
        LDA #$FF
mn_nospawn:
        STA mn_dcc06,X
        DEX
        BPL mn_nospawn
mn_spawns:
        LDA #30
        LDX MSROW
        CPX #2
        BCC mn_vcount
        LDA #15
mn_vcount:
        STA MNWORK
mn_work:
        LDA $D012
        CMP #150
        BCS mn_vret
        JSR mn_cc71
        DEC MNWORK
        BNE mn_work
        RTS
MNVB:
        JSR MTFRAME
        LDA #$4C
        STA shj
        LDA #<MNSTARSTEER
        STA shj+1
        LDA #>MNSTARSTEER
        STA shj+2
        LDA #6
        STA MNPRE
mn_pre:
        LDA #8
        JSR TLATE
        BCS mn_prestars
        LDA MNWORK
        BEQ mn_prestars
        JSR mn_cc71
        DEC MNWORK
        DEC MNPRE
        BNE mn_pre
mn_prestars:
        LDA APPR
        PHA
        LDA #0
        STA APPR
        JSR STARS
        PLA
        STA APPR
        LDA MAPSHOWN
        ORA WIPE
        ORA HYPON
        BNE mn_bret
mn_bwork:
        LDA MNWORK
        BEQ mn_bret
        BIT $D011
        BMI mn_btime
        LDA $D012
        CMP #8          ; leave radar/input and a whole worst-case mine pass
        BCC mn_btime
        RTS
mn_btime:
        JSR mn_cc71
        DEC MNWORK
        JMP mn_bwork
mn_bret:RTS
MNHIT:
        LDA HITWIN
        BNE mn_hstart
        RTS
mn_hstart:
        LDX #1
        LDY #2
        LDA #4
        STA MNHB
mn_hloop:
        STY MNHY
        LDA MNENA
        AND MNHB
        BEQ mn_hnext
        LDA MNPOS,Y
        STA ESH+6
        LDA MNPOS1,Y
        STA ESH+7
        LDY #6
        JSR HITBOX
        BEQ mn_hnext
        LDA EXPL
        BNE mn_hide
        LDY MNHY
        LDA mn_dcbfa,X
        STA EVX0
        LDA mn_dcc00,X
        STA EVY0
        LDA #1
        STA EXPL
        LDA #0
        STA EXPB
        STA HITWIN
        LDA MNPOS,Y
        SEC
        SBC #24
        LSR A
        STA EXPX
        CMP #10
        BCC mn_hnoburst
        CMP #145
        BCS mn_hnoburst
        LDA MNPOS1,Y
        SEC
        SBC #50
        STA EXPY
        CMP #10
        BCC mn_hnoburst
        CMP #190
        BCC mn_hide
mn_hnoburst:
        LDA #0
        STA EXPL
mn_hide:
        LDA MNHB
        EOR #$FF
        AND MNENA
        STA MNENA
        JMP HITSND+8    ; $3350: noise only, no new colour flash or score/energy
mn_hnext:
        LDY MNHY
        ASL MNHB
        INX
        INY
        INY
        CPX #2
        BNE mn_hskip
        ASL MNHB
        INX
        INY
        INY
mn_hskip:
        CPX #6
        BEQ mn_hret
        JMP mn_hloop
mn_hret:RTS
MNHY = MNTMP1
MNSTARLOOP:
        JSR STARTK
        LDA #6
        STA MNSTLEFT
        LDX MNSTAR
mn_stloop:
        JSR ERASESTAR
        JSR MOVESTAR
        JSR PLOTSTAR
        INX
        CPX #NSTARS
        BCC mn_stnext
        LDX #0
mn_stnext:
        STX MNSTAR
        DEC MNSTLEFT
        BNE mn_stloop
        RTS
MNSTAR: .BYTE 0
; The star counter is dead before the next mine pass or hit test.
MNSTLEFT = MNTMP
; The pre-star loop calls mine simulation: keep its counter out of mine scratch.
; CD belongs only to INPUT/CURSOR, which runs after this blank work.
MNPRE = CD
MNBYTE:
        LDA MNLEFT
        BNE mn_bytego
        JSR MNGET
        STA MNMODE
        AND #$7F
        STA MNLEFT
mn_bytego:
        DEC MNLEFT
        LDA MNMODE
        BMI mn_bytezero
MNGET:
mn_get: LDA MNART
        INC mn_get+1
        BNE mn_getret
        INC mn_get+2
mn_getret:RTS
mn_bytezero:
        LDA #0
        RTS
; Load-only decoder scratch is dead before mine simulation starts.
MNLEFT = MNTMP1
MNMODE = MNTMP
MNRESTORE:
        LDA MNFIN
        BNE mn_restorego
        INC MNFIN
        LDA #0
        STA MNENA
        STA MNWORK
        JSR MNSTREAMINIT
        LDA #<MNBACK
        STA mn_rs+1
        LDA #>MNBACK
        STA mn_rs+2
        LDA #$00
        STA mn_rd+1
        LDA #$60
        STA mn_rd+2
mn_restorego:
        LDA MNLOAD
        BEQ mn_rret
        LDX #63
mn_rs:  LDA MNBACK,X
mn_rd:  STA $6000,X
        DEX
        BPL mn_rs
        CLC
        LDA mn_rs+1
        ADC #64
        STA mn_rs+1
        BCC mn_rsok
        INC mn_rs+2
mn_rsok:
        CLC
        LDA mn_rd+1
        ADC #64
        STA mn_rd+1
        BCC mn_rdok
        INC mn_rd+2
mn_rdok:JSR MNSTREAMRESTORE
        DEC MNLOAD
mn_rret:RTS
MNNEWY:
        LDA #105        ; original $F1E1-$F1F2: $D4 nonzero, stars born at y=$69
        STA STARY,X
        LDA #0
        STA STARV,X
        RTS
MNFRAME:
        JSR SPRCROSS
        LDA MAPSHOWN
        ORA WIPE
        ORA HYPON
        BEQ mn_spritego
        RTS
mn_spritego:
        LDA MNENA
        AND #$74
        STA MNDISP
        LDA VICENA
        AND #$8B
        ORA MNDISP
        STA VICENA
        LDA MNMSB
        AND #$74
        STA MNDISP
        LDA $D010
        AND #$8B
        ORA MNDISP
        STA $D010
        LDA $D017
        AND #$8B        ; original mines are expanded horizontally only
        STA $D017
        LDA $D01D
        ORA #$74
        STA $D01D
        LDA #$76
        STA $D01C
        LDA MNCOLOR
        STA $D026
        LDX MNKIND
        LDA mn_dcc2f,X
        STA $D025
        LDA mn_dcc2d,X
        STA $D029
        STA $D02B
        STA $D02C
        STA $D02D
        LDX #1
        LDY #2
mn_place:
        LDA MNPOS,Y
        STA $D002,Y
        LDA MNPOS1,Y
        STA $D003,Y
        LDA MNSHAPE,X
        SEC
        SBC #$71
        CLC
        ADC #$80       ; $6000-$62FF: twelve temporary fighter slots
        STA SPRPTR+1,X
        INX
        INY
        INY
        CPX #2
        BNE mn_placeskip
        INX
        INY
        INY
mn_placeskip:
        CPX #6
        BNE mn_place
        RTS
MNOFF:
        JSR MTOFF
        JSR MNEXIT
        LDA #$AD
        STA shj
        LDA #<FRMC
        STA shj+1
        LDA #>FRMC
        STA shj+2
        LDA #$20
        STA nsy
        LDA #<RANDOM
        STA nsy+1
        LDA #>RANDOM
        STA nsy+2
MNRINGS:
        JSR MTOFF
        LDA #$70
        STA STARTK+7
        LDA #$20
        STA nosh
        LDA #<STARTK
        STA nosh+1
        LDA #>STARTK
        STA nosh+2
        LDA #194
        STA mp_next-5
        LDA #140
        STA mp_pass+4
        LDA #0
        STA MNLOAD
        STA MNENA
        STA SHOTARM
        STA SHOTON
        STA SHOTVIS
        JMP MSPOSOFF
 ; Original $8CB2 resets vertical high every pass; input has no pitch effect.
MNPASS:
        LDA #$88
        STA ENY+1
        LDA $D012
        RTS
MNSTEER:
        LDA JOY
        PHA
        ORA #3
        STA JOY
        JSR STEER
        PLA
        STA JOY
        RTS
MNSTARSTEER:
        LDA MSSTATE
        CMP #16
        BNE mn_stdone
        LDA FLATCH
        BNE mn_stdone
        LDA FRMC
        LSR A
        BCS mn_stdone
        LDA JOYG
        LSR A
        LSR A
        LSR A
        BCS mn_stright
        INC SHX
        INC SHX
mn_stright:
        LSR A
        BCS mn_stdone
        DEC SHX
        DEC SHX
mn_stdone:
        JMP nosh
 ; Keep message ownership of the scanner row until its last colour flip.
MNREAD:
        LDA MSGON
        BNE mn_readret
        JMP lr7
mn_readret:RTS
; The C64 installs these bounds at $8C7C and restores them at $8E20.
MNENTER:
        LDA #$87
        LDX #$A5
        LDY #$91
        JSR MNBOUNDS
        LDA #<MNINPUT
        LDX #>MNINPUT
        BNE MNHOOK
MNEXIT:
        TXA
        PHA
        LDA #$58
        LDX #$AD
        LDY #$81
        JSR MNBOUNDS
        LDA #<INPUT
        LDX #>INPUT
        JSR MNHOOK
        PLA
        TAX
        RTS
MNHOOK:
        STA g_hk2+6
        STX g_hk2+7
        RTS
MNBOUNDS:
        STA BND+2
        STX BNDH+2
        STY YCEN
        RTS
MNINPUT:
        JSR INPUT
        LDA MPRES
        BEQ mn_phasefire ; joystick up+fire is not the mouse button chord
        LDA JRAW        ; original JOYIN suppresses fire for both buttons
        AND #$11
        BEQ mn_nofire
mn_phasefire:
        LDA MSSTATE
        CMP #16
        BEQ mn_readret
        LDA #0
mn_nofire:
        STA FIREFLAG
        RTS
; Mine/settling loops never sample SPACE. Refusal is silent and free.
MNREQUEST:
        LDA MSSTATE
        BEQ mn_request
        LSR A
        CMP #1
        BNE mn_refuse
mn_request:
        LDA TREQ
        RTS
mn_refuse:
        LDA #0
        STA TREQ
        RTS
MNFIN: .BYTE 0
MNLOAD: .BYTE 0
; MSPOS finishes its five passes before MNVIEW sets this remaining budget.
MNWORK = MSRUN
MNART:
; MNARTDATA
MNARTEND:
MNBACK = $8100
MNBACKEND = $8400
; Reload consumed backup bytes from the packed type-1 movement master.
MNSTREAMINIT:
        LDA #<MNSTREAM
        STA mn_streamget+1
        LDA #>MNSTREAM
        STA mn_streamget+2
        LDA #0
        STA MNSTREAMLEFT
        STA mn_streamdst+1
        LDA #$81
        STA mn_streamdst+2
        RTS
MNSTREAMGET:
mn_streamget:LDA MNSTREAM
        INC mn_streamget+1
        BNE mn_streamret
        INC mn_streamget+2
mn_streamret:RTS
MNSTREAMRESTORE:
        LDX #0
mn_streamloop:
        LDA MNSTREAMLEFT
        BNE mn_streamrun
        JSR MNSTREAMGET
        STA MNSTREAMLEFT
        JSR MNSTREAMGET
        STA MNSTREAMVALUE
mn_streamrun:
        DEC MNSTREAMLEFT
        LDA MNSTREAMVALUE
mn_streamdst:STA $8100,X
        INX
        CPX #64
        BNE mn_streamloop
        CLC
        LDA mn_streamdst+1
        ADC #64
        STA mn_streamdst+1
        BCC mn_streamret
        INC mn_streamdst+2
        RTS
MNSTREAMLEFT: .BYTE 0
MNSTREAMVALUE: .BYTE 0
; Loaded as a fourth init stream, before low RAM's backup covers its staging.
MNEXTRA:
MTOFF:
        LDA #48
        STA PHBUD+1
        SEI
        LDA #0
        STA $D01A
        STA VIEWBG
        STA $D021
        STA $D020
        RTS
; TUNNELDATA
MNSTREAM:
; MNSTREAMDATA
MNEXTRAEND:
