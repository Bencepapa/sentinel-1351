import sys
ops={}
T="""00 BRK imp;01 ORA izx;05 ORA zp;06 ASL zp;08 PHP imp;09 ORA imm;0A ASL acc;0D ORA abs;0E ASL abs;10 BPL rel;11 ORA izy;15 ORA zpx;16 ASL zpx;18 CLC imp;19 ORA aby;1D ORA abx;1E ASL abx;20 JSR abs;21 AND izx;24 BIT zp;25 AND zp;26 ROL zp;28 PLP imp;29 AND imm;2A ROL acc;2C BIT abs;2D AND abs;2E ROL abs;30 BMI rel;31 AND izy;35 AND zpx;36 ROL zpx;38 SEC imp;39 AND aby;3D AND abx;3E ROL abx;40 RTI imp;41 EOR izx;45 EOR zp;46 LSR zp;48 PHA imp;49 EOR imm;4A LSR acc;4C JMP abs;4D EOR abs;4E LSR abs;50 BVC rel;51 EOR izy;55 EOR zpx;56 LSR zpx;58 CLI imp;59 EOR aby;5D EOR abx;5E LSR abx;60 RTS imp;61 ADC izx;65 ADC zp;66 ROR zp;68 PLA imp;69 ADC imm;6A ROR acc;6C JMP ind;6D ADC abs;6E ROR abs;70 BVS rel;71 ADC izy;75 ADC zpx;76 ROR zpx;78 SEI imp;79 ADC aby;7D ADC abx;7E ROR abx;81 STA izx;84 STY zp;85 STA zp;86 STX zp;88 DEY imp;8A TXA imp;8C STY abs;8D STA abs;8E STX abs;90 BCC rel;91 STA izy;94 STY zpx;95 STA zpx;96 STX zpy;98 TYA imp;99 STA aby;9A TXS imp;9D STA abx;A0 LDY imm;A1 LDA izx;A2 LDX imm;A4 LDY zp;A5 LDA zp;A6 LDX zp;A8 TAY imp;A9 LDA imm;AA TAX imp;AC LDY abs;AD LDA abs;AE LDX abs;B0 BCS rel;B1 LDA izy;B4 LDY zpx;B5 LDA zpx;B6 LDX zpy;B8 CLV imp;B9 LDA aby;BA TSX imp;BC LDY abx;BD LDA abx;BE LDX aby;C0 CPY imm;C1 CMP izx;C4 CPY zp;C5 CMP zp;C6 DEC zp;C8 INY imp;C9 CMP imm;CA DEX imp;CC CPY abs;CD CMP abs;CE DEC abs;D0 BNE rel;D1 CMP izy;D5 CMP zpx;D6 DEC zpx;D8 CLD imp;D9 CMP aby;DD CMP abx;DE DEC abx;E0 CPX imm;E1 SBC izx;E4 CPX zp;E5 SBC zp;E6 INC zp;E8 INX imp;E9 SBC imm;EA NOP imp;EC CPX abs;ED SBC abs;EE INC abs;F0 BEQ rel;F1 SBC izy;F5 SBC zpx;F6 INC zpx;F8 SED imp;F9 SBC aby;FD SBC abx;FE INC abx"""
for e in T.split(';'):
    h,m,a=e.split(); ops[int(h,16)]=(m,a)
L={'imp':1,'acc':1,'imm':2,'zp':2,'zpx':2,'zpy':2,'izx':2,'izy':2,'rel':2,'abs':3,'abx':3,'aby':3,'ind':3}
def fmt(m,a,b,pc):
    if a=='imp':return m
    if a=='acc':return m+' A'
    if a=='imm':return f'{m} #${b[1]:02X}'
    if a=='zp':return f'{m} ${b[1]:02X}'
    if a=='zpx':return f'{m} ${b[1]:02X},X'
    if a=='zpy':return f'{m} ${b[1]:02X},Y'
    if a=='izx':return f'{m} (${b[1]:02X},X)'
    if a=='izy':return f'{m} (${b[1]:02X}),Y'
    if a=='rel':return f'{m} ${(pc+2+(b[1]-256 if b[1]>127 else b[1]))&0xffff:04X}'
    w=b[1]|b[2]<<8
    return {'abs':f'{m} ${w:04X}','abx':f'{m} ${w:04X},X','aby':f'{m} ${w:04X},Y','ind':f'{m} (${w:04X})'}[a]
def load(fn):
    d=open(fn,'rb').read(); return d[0]|d[1]<<8, d[2:]
if __name__=='__main__':
    base,data=load(sys.argv[1])
    start=int(sys.argv[2],16) if len(sys.argv)>2 else base
    end=int(sys.argv[3],16) if len(sys.argv)>3 else base+len(data)
    pc=start
    while pc<end:
        i=pc-base; op=data[i]
        if op in ops:
            m,a=ops[op]; n=L[a]; b=data[i:i+n]
            if len(b)<n: break
            print(f'{pc:04X}  {" ".join(f"{x:02X}" for x in b):9} {fmt(m,a,b,pc)}')
        else:
            n=1; print(f'{pc:04X}  {op:02X}        .byte ${op:02X}')
        pc+=n
