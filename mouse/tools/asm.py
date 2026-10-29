# tiny 2-pass 6502 assembler: asm(src) -> dict addr->bytes, symbols
import re, sys
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dis6502 import ops, L
OPC={(m,a):op for op,(m,a) in ops.items()}
BR={'BPL','BMI','BVC','BVS','BCC','BCS','BNE','BEQ'}
def num(t,sym,p2):
    t=t.strip()
    m=re.fullmatch(r'([<>]?)(.+?)([+-]\d+)?',t)
    pre,base,off=m.group(1),m.group(2),m.group(3)
    if base.startswith('$'): v=int(base[1:],16)
    elif base.isdigit(): v=int(base)
    elif base in sym: v=sym[base]
    elif not p2: v=0xFFFF
    else: raise KeyError(base)
    if off: v+=int(off)
    if not p2: v&=0xFFFF        # pass 1: an unknown label is $FFFF; LABEL+n must not overflow
    if pre=='<': v&=255
    if pre=='>': v=(v>>8)&255
    return v
def isconst8(t,sym):
    t=t.strip()
    return re.fullmatch(r'\$[0-9A-Fa-f]{1,2}',t) is not None or (t in sym and sym[t]<256 and t in ZPSYM)
ZPSYM=set()
def asm(src):
    sym={}; out={}
    for p2 in (False,True):
        pc=0; chunks={}; cur=None
        for ln,line in enumerate(src.splitlines(),1):
            line=line.split(';')[0].rstrip()
            if not line.strip(): continue
            m=re.match(r'^(\w+)\s*=\s*(.+)$',line.strip())
            if m:
                v=num(m.group(2),sym,True); sym[m.group(1)]=v
                if re.fullmatch(r'\$[0-9A-Fa-f]{2}',m.group(2).strip()): ZPSYM.add(m.group(1))
                continue
            m=re.match(r'^\s*\*\s*=\s*(.+)$',line)
            if m: pc=num(m.group(1),sym,True); cur=pc; chunks[cur]=bytearray(); continue
            m=re.match(r'^(\w+):(.*)$',line.strip())
            if m:
                if not p2 and m.group(1) in sym: raise Exception(f'dup {m.group(1)}')
                sym[m.group(1)]=pc; line=m.group(2)
                if not line.strip(): continue
            parts=line.strip().split(None,1); mn=parts[0].upper(); arg=parts[1].strip() if len(parts)>1 else ''
            if mn=='.BYTE':
                b=bytes(num(x,sym,p2)&255 for x in arg.split(','))
            else:
                if mn in BR:
                    t=num(arg,sym,p2); d=t-(pc+2)
                    if p2 and not -128<=d<=127: raise Exception(f'line {ln}: branch out of range')
                    b=bytes([OPC[(mn,'rel')],d&255])
                elif arg=='': b=bytes([OPC[(mn,'imp')] if (mn,'imp') in OPC else OPC[(mn,'acc')]])
                elif arg.upper()=='A': b=bytes([OPC[(mn,'acc')]])
                elif arg.startswith('#'): b=bytes([OPC[(mn,'imm')],num(arg[1:],sym,p2)&255])
                elif arg.startswith('('):
                    if arg.upper().endswith(',X)'): b=bytes([OPC[(mn,'izx')],num(arg[1:-3],sym,p2)])
                    elif arg.upper().endswith('),Y'): b=bytes([OPC[(mn,'izy')],num(arg[1:-3],sym,p2)])
                    else: v=num(arg[1:-1],sym,p2); b=bytes([OPC[(mn,'ind')],v&255,v>>8])
                else:
                    idx=''
                    if arg.upper().endswith(',X'): idx='x'; arg=arg[:-2]
                    elif arg.upper().endswith(',Y'): idx='y'; arg=arg[:-2]
                    v=num(arg,sym,p2)
                    zm={'':'zp','x':'zpx','y':'zpy'}[idx]; am={'':'abs','x':'abx','y':'aby'}[idx]
                    if isconst8(arg,sym) and (mn,zm) in OPC: b=bytes([OPC[(mn,zm)],v])
                    else: b=bytes([OPC[(mn,am)],v&255,v>>8])
            chunks[cur]+=b; pc+=len(b)
    return chunks,sym
