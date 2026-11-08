from pathlib import Path
p=Path('c128-game/build.py');s=p.read_text().replace('MTSTAGE = $DD74','MTSTAGE = $DCD4')
s=s.replace("    glue = glue.replace('        JSR g_upb\\n        LDX #141'", "    glue = glue.replace('        LDA #$D1\\n        STA CSRC+1', '        LDA #$D0\\n        STA CSRC+1')\n    glue = glue.replace('        LDA #$00\\n        STA CSRC\\n        LDA #$D0\\n        STA CSRC+1\\n        LDA #<LOWSTART', '        LDA #$60\\n        STA CSRC\\n        LDA #$D0\\n        STA CSRC+1\\n        LDA #<LOWSTART')\n    glue = glue.replace('        JSR g_upb\\n        LDX #141'")
s=s.replace('p(0xD100, low_stream)','p(0xD060, low_stream)').replace("assert 0xD100 + len(low_stream) <= symbols['MTSTAGE']", "assert 0xD060 + len(low_stream) <= symbols['MTSTAGE']")
s=s.replace("    p(0xD000, second)","    assert 0xD000 + len(second) <= 0xD060\n    p(0xD000, second)")
p.write_text(s)
p=Path('c128-game/mines.asm');s=p.read_text().replace('        JSR MTFRAME\n        JSR SPRCROSS','        JSR SPRCROSS').replace('MNVB:\n','MNVB:\n        JSR MTFRAME\n').replace('mn_loaded:\n','mn_loaded:\n        JSR MTRESET\n');p.write_text(s)
p=Path('c128-game/tunnel.asm');s=p.read_text().replace('        INC MTPHASE','        JSR MTPAINT\n        INC MTPHASE')
s=s.replace('        LDX #3\nmt_reverse:', '        LDX #0\n        LDY #3\nmt_reverse:').replace('        STA MTLINES+4,X\n        DEX\n        BPL mt_reverse','        STA MTLINES+4,Y\n        INX\n        DEY\n        BPL mt_reverse')
s=s.replace('MTPHASE: .BYTE 0', '''MTRESET:
        LDA #0
        STA MTPHASE
        STA MTAGE
        RTS
MTPAINT:
        LDA MTAGE
        CMP #64
        BCS mt_ageok
        INC MTAGE
mt_ageok:
        LDA MTPHASE
        LSR A
        LSR A
        LSR A
        LSR A
        AND #3
        LDX MNKIND
        BEQ mt_kind
        ORA #4
mt_kind:TAX
        LDA MTAGE
        LSR A
        LSR A
        LSR A
        LSR A
        LDY MSROW
        CPY #3
        BNE mt_fade
        LDA MSCLOCK
        LSR A
        LSR A
        LSR A
        LSR A
mt_fade:STA MTLEVEL
        LDY #0
mt_paint:
        LDA #0
        CPY MTLEVEL
        BCS mt_black
        LDA MTPALETTE,X
mt_black:
        STA MTINK,Y
        INX
        TXA
        AND #3
        BNE mt_nowrap
        TXA
        SEC
        SBC #4
        TAX
mt_nowrap:
        INY
        CPY #4
        BNE mt_paint
        LDA MTINK
        STA VIEWBG
        LDA MTINK+1
        STA MTCOLORS
        STA MTCOLORS+6
        LDA MTINK+2
        STA MTCOLORS+1
        STA MTCOLORS+5
        LDA MTINK+3
        STA MTCOLORS+2
        STA MTCOLORS+4
        LDA MTINK
        STA MTCOLORS+7
        RTS
MTAGE: .BYTE 0
MTLEVEL: .BYTE 0
MTINK: .BYTE 0,0,0,0
MTPALETTE: .BYTE 9,6,11,4,7,13,10,3
MTPHASE: .BYTE 0''')
# fade enables inner first: threshold inversely indexed
s=s.replace('        CPY MTLEVEL\n        BCS mt_black','        TYA\n        CLC\n        ADC MTLEVEL\n        CMP #4\n        LDA #0\n        BCC mt_black')
p.write_text(s)
