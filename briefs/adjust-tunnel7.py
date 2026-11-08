from pathlib import Path
p=Path('c128-game/tunnel.asm');s=p.read_text().replace('        JSR MTPAINT\n        INC MTPHASE','        INC MTPHASE\n        JSR MTPAINT');p.write_text(s)
p=Path('js/test/run.js');s=p.read_text().replace('let src=0xD100,end=A[src]','let src=0xD060,end=A[src]');p.write_text(s)
