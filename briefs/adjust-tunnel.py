from pathlib import Path
p=Path('c128-game/build.py');s=p.read_text().replace("    mine_source = mine_source.replace('; TUNNELDATA', tunnel)","    table = tunnel[tunnel.index('MTTABLE:'):]\n    tunnel = tunnel[:tunnel.index('MTTABLE:')]\n    mine_source = mine_source.replace('; TUNNELDATA', tunnel)\n    mine_source = mine_source.replace('MNEXTRA:', table + '\\nMNEXTRA:')")
p.write_text(s)
