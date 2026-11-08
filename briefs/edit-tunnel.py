from pathlib import Path
p=Path('c128-game/mines.asm');s=p.read_text();a=s.index('MNBACK:\n');s=s[:a]+'''MNBACK = $8000
MNBACKEND = $8300
; Reload consumed backup bytes from the packed type-1 movement master.
MNSTREAMINIT:
        LDA #<MNSTREAM
        STA mn_streamget+1
        LDA #>MNSTREAM
        STA mn_streamget+2
        LDA #0
        STA MNLEFT
        STA mn_streamdst+1
        LDA #$80
        STA mn_streamdst+2
        RTS
MNSTREAMBYTE:
        LDA MNLEFT
        BNE mn_streamrun
        JSR MNSTREAMGET
        STA MNMODE
        AND #$7F
        TAX
        INX
        STX MNLEFT
        LDA MNMODE
        BPL mn_streamrun
        INC MNLEFT
        INC MNLEFT
        JSR MNSTREAMGET
        STA mn_streamsub+1
        JSR MNSTREAMGET
        STA mn_streamsubhi+1
        SEC
        LDA mn_streamdst+1
mn_streamsub:SBC #0
        STA mn_streamcopy+1
        LDA mn_streamdst+2
mn_streamsubhi:SBC #0
        STA mn_streamcopy+2
mn_streamrun:
        DEC MNLEFT
        LDA MNMODE
        BPL MNSTREAMGET
mn_streamcopy:LDA $FFFF
        INC mn_streamcopy+1
        BNE mn_streamret
        INC mn_streamcopy+2
mn_streamret:RTS
MNSTREAMGET:
mn_streamget:LDA MNSTREAM
        INC mn_streamget+1
        BNE mn_streamret
        INC mn_streamget+2
        RTS
MNSTREAMRESTORE:
        LDA #64
        STA MNSTREAMN
mn_streamloop:
        JSR MNSTREAMBYTE
mn_streamdst:STA $8000
        INC mn_streamdst+1
        BNE mn_streamnext
        INC mn_streamdst+2
mn_streamnext:
        DEC MNSTREAMN
        BNE mn_streamloop
        RTS
MNSTREAMN: .BYTE 0
; Loaded as a fourth init stream, before low RAM's backup covers its staging.
MNEXTRA:
; TUNNELDATA
MNSTREAM:
; MNSTREAMDATA
MNEXTRAEND:
'''
s=s.replace('mn_restorego:\n        LDA MNLOAD','mn_restorego:\n        LDA MNLOAD')
s=s.replace('        LDA #<MNBACK\n        STA mn_rs+1','        JSR MNSTREAMINIT\n        LDA #<MNBACK\n        STA mn_rs+1')
s=s.replace('mn_rdok:DEC MNLOAD','mn_rdok:JSR MNSTREAMRESTORE\n        DEC MNLOAD')
p.write_text(s)
from pathlib import Path
p=Path('c128-game/mines.asm');s=p.read_text().replace('MNFRAME:\n        JSR SPRCROSS','MNFRAME:\n        JSR MTFRAME\n        JSR SPRCROSS');p.write_text(s)
p=Path('c128-game/build.py');s=p.read_text();s=s.replace("    glue = glue.replace('GINIT3END:', mine_source", "    tunnel = read('c128-game', 'tunnel.asm')\n    saved = json.load(open(os.path.join(ROOT, 'briefs/ref/c64-minefield.state.json')))\n    import base64\n    original = base64.b64decode(saved['state']['arrays']['ram'])\n    tunnel = tunnel.replace('; MTTABLEDATA', '.BYTE ' + ','.join(str(v) for v in original[0xF3F:0xF7F]))\n    mine_source = mine_source.replace('; TUNNELDATA', tunnel)\n    stream = lz_pack(open(os.path.join(ROOT, 'c128-gui/ref/streams-e800.bin'), 'rb').read()[:768])\n    mine_source = mine_source.replace('; MNSTREAMDATA', '.BYTE ' + ','.join(str(v) for v in stream))\n    glue = glue.replace('GINIT3END:', mine_source")
s=s.replace("    glue = glue.replace('GINIT3END:', mine_source + '\\nGINIT3END:')", "    glue = glue.replace('GINIT3END:', mine_source + '\\nGINIT3END:')\n    glue = glue.replace('        JSR g_upb\\n        LDX #141', '        JSR MTINIT\\n        LDX #141')")
# placeholder init helper inserted before extension
s=s.replace("    mine_source = mine_source.replace('; TUNNELDATA', tunnel)", "    mine_source = mine_source.replace('; TUNNELDATA', tunnel)\n    mine_source = mine_source.replace('MNEXTRA:', '''MTINIT:\n        JSR g_upb\n        LDA #<MTSTAGE\n        STA CSRC\n        LDA #>MTSTAGE\n        STA CSRC+1\n        LDA #<MNEXTRA\n        STA CDST\n        LDA #>MNEXTRA\n        STA CDST+1\n        JMP g_upb\nMTSTAGE = $DD80\nMNEXTRA:''')")
s=s.replace("    at('TORPA',", "    extra = bytes(image[symbols['MNEXTRA']-HIGH2:symbols['MNEXTRAEND']-HIGH2])\n    at('MNEXTRA', bytes(len(extra)))\n    at('TORPA',")
s=s.replace("    p(0xD100, low_stream)", "    p(0xD100, low_stream)\n    assert 0xD100 + len(low_stream) <= symbols['MTSTAGE']\n    extra_stream = bytes((symbols['MNEXTRAEND'] & 255, symbols['MNEXTRAEND'] >> 8)) + lz_pack(extra)\n    assert symbols['MTSTAGE'] + len(extra_stream) <= 0xDF00, 'tunnel stream overlaps runtime tables'\n    p(symbols['MTSTAGE'], extra_stream)")
p.write_text(s)
