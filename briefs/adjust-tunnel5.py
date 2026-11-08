from pathlib import Path
p=Path('c128-game/mines.asm');s=p.read_text();a=s.index('MNSTREAMINIT:');head=s[:a];tail=s[a:].replace('MNLEFT','MNSTREAMLEFT').replace('MNMODE','MNSTREAMMODE');s=head+tail.replace('MNSTREAMN: .BYTE 0','MNSTREAMLEFT: .BYTE 0\nMNSTREAMMODE: .BYTE 0\nMNSTREAMN: .BYTE 0');p.write_text(s)
