"""Generate the VICE x128 MMU / bank 1 / VDC probe PRG (see briefs/memory-overlay-plan.md, Measurements). Run: python gen.py (STOP=<mark> stops early); bash run3.sh <tag>; python dec.py res_<tag>.bin"""
import os, sys, json
sys.path.insert(0, r'C:\dev\c64\sentinel\mouse\tools')
from asm import asm

HERE = os.path.dirname(os.path.abspath(__file__))
RES = 0x5000
CODE = 0x6000

# ---- common-RAM stubs, assembled at their run address $0100 -------------------
STUB = """
        * = $0100
; WR: cfg=$F8 data=$F9 addr=($FA)  -> writes in that configuration, back to home $FC
WR:     LDY #0
        LDA $F9
        LDX $F8
        STX $FF00
        STA ($FA),Y
        LDX $FC
        STX $FF00
        RTS
; RD: same, A = byte
        * = $0110
RD:     LDY #0
        LDX $F8
        STX $FF00
        LDA ($FA),Y
        LDX $FC
        STX $FF00
        RTS
; LCRk: A written to $FF0k (the value is ignored), returns A = CR as read at $FF00, then
; PCRA reloads home
        * = {LCR1AT}
LCR1:   {V1}
        RTS
        * = $012C
LCR2:   STA $FF02
        LDA $FF00
        STA $FF01
        RTS
        * = $0138
LCR3:   STA $FF03
        LDA $FF00
        STA $FF01
        RTS
        * = $0144
LCR4:   STA $FF04
        LDA $FF00
        STA $FF01
        RTS
; the plan's copy primitive. GET: bank 1 -> bank 0. X pages, ($F2) source, ($F4) dest.
; PCRA ($D501) = home bank 0 config, PCRB ($D502) = bank 1 config
        * = $0150
B1GET:  LDY #0
g_lp:   STA $FF02
        LDA ($F2),Y
        STA $FF01
        STA ($F4),Y
        INY
        BNE g_lp
        INC $F3
        INC $F5
        DEX
        BNE g_lp
        RTS
; PUT: bank 0 -> bank 1
        * = $0170
B1PUT:  LDY #0
p_lp:   LDA ($F2),Y
        STA $FF02
        STA ($F4),Y
        STA $FF01
        INY
        BNE p_lp
        INC $F3
        INC $F5
        DEX
        BNE p_lp
        RTS
; empty reference for timing
        * = $0190
NOP1:   RTS
; read $FF0k: X = value read, A = CR afterwards (the read itself reloads CR); then home again
        * = $0192
LRD1:   LDX $FF01
        LDA $FF00
        LDY $FF01
        RTS
LRD2:   LDX $FF02
        LDA $FF00
        LDY $FF01
        RTS
LRD3:   LDX $FF03
        LDA $FF00
        LDY $FF01
        RTS
LRD4:   LDX $FF04
        LDA $FF00
        LDY $FF01
        RTS
"""
NL = chr(10) + '        '
V1 = {"1": "LDA $FF00", "2": "STA $FF01", "3": "STA $FF01" + NL + "LDA $FF00",
      "0": "STA $FF01" + NL + "LDA $FF00" + NL + "STA $FF01",
      "5": "STA $FF01" + NL + "LDA $FF00" + NL + "TAX" + NL + "LDA #0" + NL + "STA $FF01" + NL + "TXA",
      "8": "STA $FF01" + NL + "LDA $FF00" + NL + "STA $FF01" + NL + "TSX" + NL + "STX $5200" + NL + "LDA $01F5" + NL + "STA $5201" + NL + "LDA $01F6" + NL + "STA $5202" + NL + "LDA $01F7" + NL + "STA $5203" + NL + "LDA $01F8" + NL + "STA $5204",
      "7": "STA $FF01" + NL + "STA $FF01",
      "9": "LDA $FF00" + NL + "STA $FF01",
      "A": "STA $FF01" + NL + "NOP" + NL + "NOP" + NL + "STA $FF01",
      "6": "STA $FF01" + NL + "LDA $FF00" + NL + "TAX" + NL + "LDY $FF01" + NL + "TXA"}[os.environ.get("V", "0")]
stub_chunks, stub_sym = asm(STUB.replace("{V1}", V1).replace("{LCR1AT}", os.environ.get("LCR1AT", "$0120")))

lines = []
done_lines = []


def DL(x):
    done_lines.append(x)


layout = []        # (name, count) in the order of REC calls


def L(s):
    lines.append(s)


def rec(name, n=1):
    layout.append((name, n))
    L(f';MARK Z{len(layout)}')


def lda_rec(addr, name):
    L(f'        LDA {addr}')
    L('        JSR REC')
    rec(name)


def setup(cfg, addr, data=None):
    L(f'        LDA #{cfg}')
    L('        STA $F8')
    if data is not None:
        L(f'        LDA #{data}')
        L('        STA $F9')
    L(f'        LDA #<{addr}')
    L('        STA $FA')
    L(f'        LDA #>{addr}')
    L('        STA $FB')


def wr(cfg, addr, data):
    setup(cfg, addr, data)
    L('        JSR WR')


def rd(cfg, addr, name):
    setup(cfg, addr)
    L('        JSR RD')
    L('        JSR REC')
    rec(name)


L(f'WR = ${stub_sym["WR"]:04X}')
for k in ('RD', 'LCR1', 'LCR2', 'LCR3', 'LCR4', 'B1GET', 'B1PUT', 'NOP1', 'LRD1', 'LRD2', 'LRD3', 'LRD4'):
    L(f'{k} = ${stub_sym[k]:04X}')
L(f'RES = ${RES:04X}')
L(f'RESEND = ${RES+0x1000:04X}')
L('OPTR = $F6')
L('SRC = $F2')
L('DST = $F4')
L('        * = $1C01')
L('        .byte $1A,$1C,$0A,$00,$99,$22,$48,$49,$22,$3A,$9E,$37,$34,$32,$34,$3A,$99,$22,$42,$41,$43,$4B,$22,$00,$00,$00')   # 10 PRINT"HI":SYS7424:PRINT"BACK"
L('        * = $1D00')
L('ENTRY:  SEI')
L('        LDA #<RES')
L('        STA OPTR')
L('        LDA #>RES')
L('        STA OPTR+1')
L('        LDA #$3E')
L('        STA $FC')
# ---- A: entry state --------------------------------------------------------------
L('        TSX')
L('        TXA')
L('        JSR REC')
rec('entry SP')
lda_rec('$FF00', 'entry CR ($FF00)')
for k in range(12):
    lda_rec(f'$D5{k:02X}', f'entry $D5{k:02X}')
# remember the baseline preconfiguration registers and RCR
for k in range(1, 5):
    L(f'        LDA $D50{k}')
    L(f'        STA $E{k}')
L('        LDA $D506')
L('        STA $E5')
L('        LDA #$3E')
L('        STA $FF00')
L('        JMP START')
L('REC:    LDY #0')
L('        STA (OPTR),Y')
L('        INC OPTR')
L('        BNE rec_r')
L('        INC OPTR+1')
L('rec_r:  RTS')
DL('VDCR:   BIT $D600')
DL('        BPL VDCR')
DL('        RTS')
DL('DONE:   SEI')
DL('        LDA #$00')
DL('        STA $FF00')
DL('        LDA #0')
DL('        LDX #0')
DL('        JSR $FF68')
DL('        LDA #1')
DL('        LDX #8')
DL('        LDY #1')
DL('        JSR $FFBA')
DL('        LDA #3')
DL('        LDX #<NAME')
DL('        LDY #>NAME')
DL('        JSR $FFBD')
DL('        LDA #<RES')
DL('        STA $FB')
DL('        LDA #>RES')
DL('        STA $FC')
DL('        LDA #$FB')
DL('        LDX #<RESEND')
DL('        LDY #>RESEND')
DL('        JSR $FFD8')
DL('FIN:    JMP FIN')
DL('NAME:   .byte $52,$45,$53')
lines.extend(done_lines)
L(f'        * = ${CODE:04X}')
L('START:  SEI')
# home: all RAM, bank 0, I/O
L('        LDA #$3E')
L('        STA $FF00')
lda_rec('$FF00', 'at CR=$3E read $FF00')
lda_rec('$D500', 'at CR=$3E read $D500')
L(';MARK A')
# ---- B: write / readback ------------------------------------------------------------
for k, v in enumerate((0xA1, 0xB2, 0xC3, 0xD4), 1):
    L(f'        LDA #${v:02X}')
    L(f'        STA $D50{k}')
for k in range(1, 5):
    lda_rec(f'$D50{k}', f'after writing A1/B2/C3/D4: $D50{k}')
for k in range(1, 5):
    L(f'        LDA $E{k}')
    L(f'        STA $D50{k}')
L(';MARK B1')
L('        JSR NOP1')
L('        LDA #$77')
L('        JSR REC')
rec('after JSR NOP1 (stub RTS at $0170)')
L(';MARK M0')
L('PCRSET:')
# PCRA = $3E home, PCRB = $7F bank 1
L('        LDA #$3E')
L('        STA $D501')
L('        LDA #$7F')
L('        STA $D502')
# $FF0k with A=$00 / A=$FF: CR as read afterwards
for k in (1, 2, 3, 4):
    L('        LDA #$00')
    L(f'        JSR LCR{k}')
    L('        JSR REC')
    rec(f'LCR{k} (A=$00): CR read at $FF00 after STA $FF0{k}')
    L(f';MARK L{k}a')
    L('        LDA #' + os.environ.get('AVAL', '$FF'))
    L(f'        JSR LCR{k}')
    L('        JSR REC')
    rec(f'LCR{k} (A=$FF): CR read at $FF00 after STA $FF0{k}')
    L(f';MARK L{k}')
L(';MARK B2')
lda_rec('$FF00', 'CR after the LCR tests (home)')
for k in (1, 2, 3, 4):
    L(f'        JSR LRD{k}')
    L('        JSR REC')
    rec(f'read $FF0{k}: CR afterwards')
    L('        TXA')
    L('        JSR REC')
    rec(f'read $FF0{k}: the value read')
L(';MARK B3')
lda_rec('$FF00', 'CR after the LRD tests (home)')
# the CR write itself: $FF00 and $D500 with bank bits via the stub; read back through $FF00
# (set CR to a value, read $FF00 in that state)
for cfg in ('$3E', '$7E', '$BE', '$FE', '$3F', '$7F', '$01', '$00', '$0E', '$10', '$20', '$C1'):
    L(f'        LDA #{cfg}')
    L('        STA $F8')
    L('        LDA #<$FF00')
    L('        STA $FA')
    L('        LDA #>$FF00')
    L('        STA $FB')
    L('        JSR RD')
    L('        JSR REC')
    rec(f'CR written {cfg}, read back at $FF00')
L(';MARK B')
# ---- C: banks ------------------------------------------------------------------------
wr('$3F', '$4000', '$10')
wr('$7F', '$4000', '$11')
rd('$3F', '$4000', 'bank0 $4000 (wrote 10)')
rd('$7F', '$4000', 'bank1 $4000 (wrote 11)')
wr('$BF', '$4000', '$12')
for cfg in ('$3F', '$7F', '$BF', '$FF'):
    rd(cfg, '$4000', f'after write in cfg $BF: read cfg {cfg}')
wr('$FF', '$4000', '$13')
for cfg in ('$3F', '$7F', '$BF', '$FF'):
    rd(cfg, '$4000', f'after write in cfg $FF: read cfg {cfg}')
# restore known: bank 0 = 10, bank1 = 11
wr('$3F', '$4000', '$10')
wr('$7F', '$4000', '$11')
# I/O visibility in bank 1: $7E, $D000 etc. (VIC register $D020 reads in both banks with I/O on)
rd('$7E', '$D500', 'cfg $7E read $D500 (I/O on, bank 1)')
rd('$7F', '$D500', 'cfg $7F read $D500 (RAM bank 1, was written?)')
L(';MARK C')
# ---- C: RCR grid ----------------------------------------------------------------------
RCRS = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D,
        0x0E, 0x0F, 0x44, 0x84, 0xC4, 0xF0, 0xFF]
PROBES = [0x0010, 0x01D0, 0x0200, 0x03FF, 0x0400, 0x0BFF, 0x0C00, 0x0FFF, 0x1000, 0x1BFF,
          0x1C00, 0x1FFF, 0x2000, 0x3FFF, 0x4000, 0xBFFF, 0xC000, 0xDFFF, 0xE000, 0xEFFF,
          0xF000, 0xFBFF, 0xFC00, 0xFEFF, 0xFFF0]
L('        LDA #0')
L('        STA $E6')           # rcr index
L('rcrlp:  LDX $E6')
L('        LDA RCRTAB,X')
L('        STA $D506')
L('        LDA $D506')
L('        JSR REC')
L('        LDA #0')
L('        STA $E7')
L('prlp:   LDX $E7')
L('        LDA PRLO,X')
L('        STA $FA')
L('        LDA PRHI,X')
L('        STA $FB')
L('        LDA #$3F')
L('        STA $F8')
L('        LDA #$A0')
L('        STA $F9')
L('        JSR WR')
L('        LDA #$7F')
L('        STA $F8')
L('        LDA #$A1')
L('        STA $F9')
L('        JSR WR')
L('        LDA #$3F')
L('        STA $F8')
L('        JSR RD')
L('        JSR REC')
L('        INC $E7')
L(f'        LDA $E7')
L(f'        CMP #{len(PROBES)}')
L('        BNE prlp')
L('        INC $E6')
L('        LDA $E6')
L(f'        CMP #{len(RCRS)}')
L('        BNE rcrlp')
rec('RCR grid: per RCR value: readback of $D506 then read of bank 0 after (bank0=A0, bank1=A1): A1 = common', len(RCRS) * (1 + len(PROBES)))
L('        LDA $E5')
L('        STA $D506')
L('        LDA $D506')
L('        JSR REC')
rec('RCR restored to baseline, read')
L(';MARK R')
# ---- D: the copy routine ------------------------------------------------------------------
# pattern at $5800-$5AFF (3 pages): LCG + page
L('        LDX #3')               # pages
L('        LDA #$00')
L('        STA $E8')
L('        LDA #$58')
L('        STA $E9')
L('        LDA #$07')
L('        STA $EA')              # running value
L('pat0:   LDY #0')
L('pat1:   LDA $EA')
L('        STA ($E8),Y')
L('        ASL A')
L('        ASL A')
L('        CLC')
L('        ADC $EA')
L('        ADC #3')
L('        STA $EA')
L('        INY')
L('        BNE pat1')
L('        INC $E9')
L('        INC $EA')              # page-dependent
L('        DEX')
L('        BNE pat0')
wr('$3F', '$4000', '$10')
# PUT 3 pages $5800 -> bank 1 $4000
L('        LDA #$00')
L('        STA SRC')
L('        STA DST')
L('        LDA #$58')
L('        STA SRC+1')
L('        LDA #$40')
L('        STA DST+1')
L('        LDX #3')
L('        JSR B1PUT')
# GET 3 pages bank 1 $4000 -> bank 0 $5C00
L('        LDA #$00')
L('        STA SRC')
L('        STA DST')
L('        LDA #$40')
L('        STA SRC+1')
L('        LDA #$5C')
L('        STA DST+1')
L('        LDX #3')
L('        JSR B1GET')
rd('$3F', '$4000', 'bank0 $4000 after the PUT (must still be 10)')
rd('$7F', '$4000', 'bank1 $4000 after the PUT (first pattern byte = 07)')
lda_rec('$FF00', 'CR after the copies (home)')
# a second GET: bank 1 $D000 (RAM in bank 1 with cfg $7F) -> bank 0 $5F00, after a PUT to $D000
L('        LDA #$00')
L('        STA SRC')
L('        STA DST')
L('        LDA #$58')
L('        STA SRC+1')
L('        LDA #$D0')
L('        STA DST+1')
L('        LDX #1')
L('        JSR B1PUT')
L('        LDA #$00')
L('        STA SRC')
L('        STA DST')
L('        LDA #$D0')
L('        STA SRC+1')
L('        LDA #$5F')
L('        STA DST+1')
L('        LDX #1')
L('        JSR B1GET')
L(';MARK D')
# ---- D2: timing with CIA1 timer A (screen blanked) ------------------------------------------
L('        LDA $D011')
L('        STA $EB')
L('        AND #$EF' if not os.environ.get('DEN') else '        ORA #$10')
L('        STA $D011')            # DEN off: no bad lines (DEN=1 env: display on)
L('        LDA $DC0E')
L('        STA $EC')
for fast in (0, 1):
    for nm, call in (('empty JSR/RTS', 'NOP1'), ('B1GET 1 page', 'B1GET'), ('B1PUT 1 page', 'B1PUT'),
                     ('B1GET 3 pages', 'B1GET3')):
        L(f'        LDA #{fast}')
        L('        STA $D030')
        if call == 'B1GET3':
            L('        LDX #3')
            call = 'B1GET'
        else:
            L('        LDX #1')
        L('        LDA #$00')
        L('        STA SRC')
        L('        STA DST')
        L('        LDA #$40')
        L('        STA SRC+1')
        L('        LDA #$5C')
        L('        STA DST+1')
        L('        LDA #$FF')
        L('        STA $DC04')
        L('        STA $DC05')
        L('        LDA #$10')
        L('        STA $DC0E')    # stop, force load
        L('        LDA #$11')
        L('        STA $DC0E')    # start
        L(f'        JSR {call}')
        L('        LDA #$00')
        L('        STA $DC0E')    # stop
        L('        LDA $DC04')
        L('        JSR REC')
        L('        LDA $DC05')
        L('        JSR REC')
        rec(f'timer left after {nm}, 2MHz={fast} (lo, hi; start $FFFF)', 2)
L('        LDA #0')
L('        STA $D030')
L('        LDA $EB')
L('        STA $D011')
L(';MARK T')
# ---- E: VDC --------------------------------------------------------------------------------


def vreg(reg, val_ml):
    L(f'        LDX #{reg}')
    L('        STX $D600')
    L('        JSR VDCR')
    L(f'        LDA {val_ml}')
    L('        STA $D601')


def vset(addr):
    vreg(18, f'#>{addr}')
    vreg(19, f'#<{addr}')


def vwrite(val):
    L('        LDX #31')
    L('        STX $D600')
    L('        JSR VDCR')
    L(f'        LDA #{val}')
    L('        STA $D601')


def vread_rec(name):
    L('        LDX #31')
    L('        STX $D600')
    L('        JSR VDCR')
    L('        LDA $D601')
    L('        JSR REC')
    rec(name)


def vregread(reg, name):
    L(f'        LDX #{reg}')
    L('        STX $D600')
    L('        JSR VDCR')
    L('        LDA $D601')
    L('        JSR REC')
    rec(name)


vregread(28, 'VDC R28 (bit 4 = 64K DRAM)')
L(';MARK V1')
vregread(0, 'VDC R0')
vregread(25, 'VDC R25')
vregread(34, 'VDC R34')
vregread(36, 'VDC R36')
L('        LDA $D600')
L('        JSR REC')
rec('VDC status $D600')
L(';MARK V2')
for a, v in ((0x0000, '$11'), (0x4000, '$22'), (0x8000, '$33'), (0xC000, '$44'), (0xFFFF, '$55')):
    vset(f'${a:04X}')
    vwrite(v)
    L(f';MARK W{a:04X}')
for a in (0x0000, 0x4000, 0x8000, 0xC000, 0xFFFF):
    vset(f'${a:04X}')
    L(f';MARK S{a:04X}')
    vread_rec(f'VDC RAM ${a:04X} (writes 11,22,33,44,55 at 0000,4000,8000,C000,FFFF)')
    L(f';MARK Q{a:04X}')
L(';MARK V3')
# address register after a write at $3FFF
vset('$3FFF')
vwrite('$66')
vregread(18, 'VDC R18 after write at $3FFF')
vregread(19, 'VDC R19 after write at $3FFF')
vset('$3FFF')
vread_rec('VDC RAM $3FFF')
vset('$7FFF')
vwrite('$67')
vregread(18, 'VDC R18 after write at $7FFF')
vset('$0000')
vread_rec('VDC RAM $0000 (after $3FFF=66, $7FFF=67 writes)')
vset('$3FFF')
vread_rec('VDC RAM $3FFF again')
vset('$7FFF')
vread_rec('VDC RAM $7FFF again')
# a fill of 4 bytes through R30 from $3FFE (R24 bit 7 clear = fill)
vreg(24, '#$00')
vset('$3FFE')
vwrite('$5A')
vreg(30, '#$03')               # 3 more bytes: $3FFF, $4000, $4001
vset('$3FFD')
vread_rec('VDC $3FFD')
vread_rec('VDC $3FFE')
vread_rec('VDC $3FFF')
vread_rec('VDC $4000')
vset('$0000')
vread_rec('VDC $0000 after fill wrap')
vread_rec('VDC $0001 after fill wrap')

# ---- data -----------------------------------------------------------------------------------
# second suite: R28 bit 4 set (what the KERNAL does for 64K DRAM)
vreg(28, '#$3F')
vregread(28, 'VDC R28 after writing $3F')
for a, v in ((0x0000, '$A1'), (0x4000, '$A2'), (0x8000, '$A3'), (0xC000, '$A4'), (0xFFFF, '$A5')):
    vset(f'${a:04X}')
    vwrite(v)
for a in (0x0000, 0x4000, 0x8000, 0xC000, 0xFFFF):
    vset(f'${a:04X}')
    vread_rec(f'R28=$3F: VDC RAM ${a:04X} (writes A1..A5 at 0000,4000,8000,C000,FFFF)')
vreg(28, '#$2F')
L('        JMP DONE')
L('RCRTAB: .byte ' + ','.join(f'${v:02X}' for v in RCRS))
L('PRLO:   .byte ' + ','.join(f'${a & 255:02X}' for a in PROBES))
L('PRHI:   .byte ' + ','.join(f'${a >> 8:02X}' for a in PROBES))

# The stubs are installed by the BASIC-side loader: a code block copied to $0100 at START.
# Put the installer before the first use: insert after SEI.
stubdata = bytearray(0xE0)
for a, b in stub_chunks.items():
    stubdata[a - 0x100:a - 0x100 + len(b)] = b
inst = ['        LDX #0', 'inst:   LDA STUBD,X', '        STA $0100,X', '        INX', '        CPX #$E0', '        BNE inst']
i = lines.index('START:  SEI')
lines[i + 1:i + 1] = inst
L('STUBD:  .byte ' + ','.join(f'${v:02X}' for v in stubdata[:0x40]))
L('        .byte ' + ','.join(f'${v:02X}' for v in stubdata[0x40:0x80]))
L('        .byte ' + ','.join(f'${v:02X}' for v in stubdata[0x80:]))

src = '\n'.join(lines) + '\n'
stop = os.environ.get('STOP')
if stop:
    src = src.replace(';MARK ' + stop + '\n', '        JMP DONE\n')
chunks, sym = asm(src)
open(os.path.join(HERE, 'probe.asm'), 'w').write(src)
body = bytearray()
base = 0x1C01
for a in sorted(chunks):
    off = a - base
    if len(body) < off:
        body.extend(bytes(off - len(body)))
    body[off:off + len(chunks[a])] = chunks[a]
prg = bytes([base & 255, base >> 8]) + bytes(body)
open(os.path.join(HERE, 'probe.prg'), 'wb').write(prg)
json.dump({'sym': sym, 'layout': layout, 'done': sym['DONE'], 'RES': RES, 'RCRS': RCRS, 'PROBES': PROBES},
          open(os.path.join(HERE, 'layout.json'), 'w'))
print('prg', len(prg), 'DONE', hex(sym['DONE']), 'end', hex(base + len(body)))
