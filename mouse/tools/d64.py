import sys, os
def off(t,s):
    spt=[0]+[21]*17+[19]*7+[18]*6+[17]*10
    return (sum(spt[1:t])+s)*256
def chain(d,t,s):
    out=b''; seen=set()
    while t and (t,s) not in seen:
        seen.add((t,s)); o=off(t,s); b=d[o:o+256]
        if b[0]==0: out+=b[2:b[1]+1]; break
        out+=b[2:]; t,s=b[0],b[1]
    return out
d=open(sys.argv[1],'rb').read()
outdir=sys.argv[2] if len(sys.argv)>2 else None
o=off(18,0); print('disk:',d[o+0x90:o+0xa0].decode('latin1').encode('ascii','replace').decode())
t,s=18,1
types=['DEL','SEQ','PRG','USR','REL']
while t:
    o=off(t,s); b=d[o:o+256]
    for i in range(8):
        e=b[i*32:i*32+32]
        if e[2]&7==0 and e[2]==0: continue
        name=e[5:21].rstrip(b'\xa0').decode('latin1')
        data=chain(d,e[3],e[4])
        la=data[0]|data[1]<<8 if len(data)>1 else 0
        print(f"{name.encode('ascii','replace').decode()!r:20} {types[e[2]&7]} blocks={e[30]|e[31]<<8} ts={e[3]},{e[4]} len={len(data)} load=${la:04x}")
        if outdir:
            os.makedirs(outdir,exist_ok=True)
            safe=''.join(c if c.isalnum() else '_' for c in name)
            open(os.path.join(outdir,safe+'.prg'),'wb').write(data)
    t,s=b[0],b[1]
