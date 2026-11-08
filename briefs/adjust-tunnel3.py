from pathlib import Path
p=Path('c128-game/build.py');s=p.read_text().replace("read()[:768]", "read()[256:1024]");p.write_text(s)
p=Path('c128-game/mines.asm');s=p.read_text().replace('MNBACK = $8000','MNBACK = $8100').replace('MNBACKEND = $8300','MNBACKEND = $8400').replace('LDA #$80\n        STA mn_streamdst+2','LDA #$81\n        STA mn_streamdst+2').replace('mn_streamdst:STA $8000','mn_streamdst:STA $8100');p.write_text(s)
