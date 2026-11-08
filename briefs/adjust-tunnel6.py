from pathlib import Path
p=Path('c128-game/mines.asm');s=p.read_text();a=s.index('MNSTREAMINIT:');b=s.index('; Loaded as a fourth',a);s=s[:a]+'''MNSTREAMINIT:
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
'''+s[b:];s=s.replace('LDA #160\n        STA mp_pass+4','LDA #175\n        STA mp_pass+4');p.write_text(s)
p=Path('c128-game/build.py');s=p.read_text().replace("    stream = lz_pack(open(os.path.join(ROOT, 'c128-gui/ref/streams-e800.bin'), 'rb').read()[256:1024])", "    import itertools\n    stream = bytes(v for value, group in itertools.groupby(open(os.path.join(ROOT, 'c128-gui/ref/streams-e800.bin'), 'rb').read()[256:1024]) for v in (len(list(group)), value))");p.write_text(s)
p=Path('c128-game/tunnel.asm');s=p.read_text().replace('        LDX MTINDEX\n        LDA MTLINES,X','mt_do:  LDX MTINDEX\n        LDA MTLINES,X',1).replace('        SBC #1\n        STA $D012\n        LDA #1', '        SBC #1\n        CMP $D012\n        BCC mt_do\n        BEQ mt_do\n        STA $D012\n        LDA #1');p.write_text(s)
