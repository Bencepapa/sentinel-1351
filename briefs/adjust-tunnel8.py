from pathlib import Path
p=Path('c128-game/tunnel.asm');s=p.read_text().replace('        LDA MTLINES,X\nmt_wait:CMP $D012\n        BCS mt_wait\n','');p.write_text(s)
