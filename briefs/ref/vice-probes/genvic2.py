"""VIC-IIe bank 1 probe through sprite-background collisions (no screenshot needed).
For every test the two RAM banks hold different data; with RCR ($D506) bit 6 = 0 / 1 the VIC reads
bank 0 / bank 1 and $D01F (sprite-background collision) tells which data it saw.
Results are saved with KERNAL SAVE to the disk image like the MMU probe."""
import os, sys, json
sys.path.insert(0, r'C:\dev\c64\sentinel\mouse\tools')
from asm import asm

HERE = os.path.dirname(os.path.abspath(__file__))
BLK = int(os.environ.get('BLK', '0'))
BASE = BLK * 0x4000
CIA2 = {0: 0x03, 1: 0x02, 2: 0x01, 3: 0x00}[BLK]
SCR = BASE + 0x0400
SPD = BASE + 0x0800          # sprite data blocks: $20 = +$0800 (solid), $22 = +$0880 (empty), $21=+$0840
BMP = BASE + 0x2000
CHR = BASE + 0x2000
RES = 0x5000
L = []
a = L.append
layout = []


def fill_call(addr, count, val, bank):
    a(f'        LDA #<{addr}')
    a('        STA $FA')
    a(f'        LDA #>{addr}')
    a('        STA $FB')
    a(f'        LDA #<{count}')
    a('        STA $FC')
    a(f'        LDA #>{count}')
    a('        STA $FD')
    a(f'        LDA #{val}')
    a(f'        JSR {"FILL1" if bank else "FILL0"}')


def fill(bank, addr, count, val):
    fill_call(addr, count, val, bank)


def vicmode(d011, d016, d018):
    a(f'        LDA #${d011:02X}')
    a('        STA $D011')
    a(f'        LDA #${d016:02X}')
    a('        STA $D016')
    a(f'        LDA #${d018:02X}')
    a('        STA $D018')


def measure(name):
    """for RCR=$04 then $44: wait, clear, wait, read $D01F, record"""
    for rcr in (0x04, 0x44):
        a(f'        LDA #${rcr:02X}')
        a('        STA $D506')
        a('        JSR WAIT2')
        a('        LDA $D01F')
        a('        JSR WAIT2')
        a('        LDA $D01F')
        a('        JSR REC')
        layout.append(f'{name}: $D01F with RCR=${rcr:02X}')
    a('        LDA #$04')
    a('        STA $D506')


a('        * = $1C01')
a('        .byte $0C,$1C,$0A,$00,$9E,$37,$34,$32,$34,$00,$00,$00')
a('        * = $1D00')
a('        SEI')
a('        LDA #$3E')
a('        STA $FF00')
a('        LDA #<RES')
a('        STA $F6')
a('        LDA #>RES')
a('        STA $F7')
a('        LDX #0')
a('inst:   LDA STUBD,X')
a('        STA $0100,X')
a('        INX')
a('        CPX #$10')
a('        BNE inst')
a('        LDA #$00')
a('        STA $D020')
a('        STA $D021')
a(f'        LDA #${CIA2:02X}')
a('        STA $DD00')
# sprite 0: x=60 (screen), y=120, enabled, normal
a('        LDA #60')
a('        STA $D000')
a('        LDA #120')
a('        STA $D001')
a('        LDA #0')
a('        STA $D010')
a('        STA $D017')
a('        STA $D01C')
a('        STA $D01D')
a('        LDA #1')
a('        STA $D015')
a('        LDA #1')
a('        STA $D027')
# --- T1 bitmap: bank0 solid, bank1 empty; sprite solid in both
for b in (0, 1):
    fill(b, SPD, 64, 0xFF)                         # $20 solid
    fill(b, SPD + 0x80, 64, 0x00)                  # $22 empty
    fill(b, SCR + 0x3F8, 8, 0x20)                  # pointers solid
fill(0, BMP, 0x2000, 0xFF)
fill(1, BMP, 0x2000, 0x00)
vicmode(0x3B, 0xC8, 0x18)
measure('T1 hires bitmap (bank0 solid / bank1 empty)')
# --- T1b the same with multicolor bitmap ($D016 bit 4): pattern '01' = background (no collision); use $55 in bank 1
fill(0, BMP, 0x2000, 0xFF)
fill(1, BMP, 0x2000, 0x55)
vicmode(0x3B, 0xD8, 0x18)
measure('T1b multicolor bitmap (bank0 $FF=11 pairs foreground / bank1 $55=01 pairs background)')
# --- T2 screen matrix: text mode, charset identical (code 1 solid, code 0 empty), screens differ
for b in (0, 1):
    fill(b, CHR, 16, 0x00)                         # code 0 empty (8 bytes) + code 1 ...
    fill(b, CHR + 8, 8, 0xFF)                      # code 1 solid
fill(0, SCR, 0x3F8, 0x00)
fill(1, SCR, 0x3F8, 0x01)
vicmode(0x1B, 0xC8, 0x18)
measure('T2 screen matrix (bank0 code 0 empty / bank1 code 1 solid)')
# --- T3 chargen: screens identical (code 1), charset differs
fill(0, SCR, 0x3F8, 0x01)
fill(1, SCR, 0x3F8, 0x01)
fill(0, CHR + 8, 8, 0xFF)
fill(1, CHR + 8, 8, 0x00)
measure('T3 character generator (bank0 solid / bank1 empty)')
# --- T4 sprite pointer: bitmap solid both banks, pointers differ (bank0 -> solid data, bank1 -> empty data)
fill(0, BMP, 0x2000, 0xFF)
fill(1, BMP, 0x2000, 0xFF)
fill(0, SCR + 0x3F8, 8, 0x20)
fill(1, SCR + 0x3F8, 8, 0x22)
vicmode(0x3B, 0xC8, 0x18)
measure('T4 sprite pointer (bank0 -> solid data / bank1 -> empty data)')
# --- T5 sprite data: pointers identical ($20), data differs
fill(0, SCR + 0x3F8, 8, 0x20)
fill(1, SCR + 0x3F8, 8, 0x20)
fill(0, SPD, 64, 0xFF)
fill(1, SPD, 64, 0x00)
measure('T5 sprite data (bank0 solid / bank1 empty)')
# --- T7 character ROM image: chargen at +$1000 (D018=$14), RAM there empty in both banks, screen code 1 ('A')
fill(0, SCR, 0x3F8, 0x01)
fill(1, SCR, 0x3F8, 0x01)
fill(0, BASE + 0x1008, 8, 0x00)
fill(1, BASE + 0x1008, 8, 0x00)
vicmode(0x1B, 0xC8, 0x14)
measure('T7 character ROM image at +$1000 (RAM empty in both banks; 1 = ROM glyph seen)')
# --- T6 colour RAM from the CPU: bank 0 vs bank 1 view of $D800
a('        LDA #$07')
a('        STA $D800')
a('        LDA #$00')
a('        STA $FA')
a('        LDA #$D8')
a('        STA $FB')
a('        JSR CR1RD')
a('        JSR REC')
layout.append('T6 colour RAM $D800 read in bank 1 view (cfg $7E) after writing 07 in bank 0 view')
a('        LDA #$09')
a('        JSR CR1WR')
a('        LDA $D800')
a('        JSR REC')
layout.append('T6 colour RAM $D800 read in bank 0 view after writing 09 in the bank 1 view (cfg $7E)')
a('        JMP DONE')
# ---- subroutines (low RAM) ---------------------------------------------------------------------
a('WAIT2:  LDX #3')
a('w2o:    LDA $D012')
a('w2a:    CMP $D012')
a('        BEQ w2a')
a('        LDA $D011')
a('        BPL w2o')              # wait for raster line >= 256 then again: ~ frame
a('w2b:    LDA $D011')
a('        BMI w2b')
a('        DEX')
a('        BNE w2o')
a('        RTS')
a('REC:    LDY #0')
a('        STA ($F6),Y')
a('        INC $F6')
a('        BNE rec_r')
a('        INC $F7')
a('rec_r:  RTS')
for nm, bank in (('FILL0', 0), ('FILL1', 1)):
    a(f'{nm}:  STA $FE')
    a(f'{nm.lower()}l:  LDA $FE')
    if bank:
        a('        JSR W1')
    else:
        a('        LDY #0')
        a('        STA ($FA),Y')
    a('        INC $FA')
    a(f'        BNE {nm.lower()}n')
    a('        INC $FB')
    a(f'{nm.lower()}n:  LDA $FC')
    a(f'        BNE {nm.lower()}d')
    a('        DEC $FD')
    a(f'{nm.lower()}d:  DEC $FC')
    a('        LDA $FC')
    a('        ORA $FD')
    a(f'        BNE {nm.lower()}l')
    a('        RTS')
a('DONE:   SEI')
a('        LDA #$00')
a('        STA $FF00')
a('        LDA #0')
a('        LDX #0')
a('        JSR $FF68')
a('        LDA #1')
a('        LDX #8')
a('        LDY #1')
a('        JSR $FFBA')
a('        LDA #3')
a('        LDX #<NAME')
a('        LDY #>NAME')
a('        JSR $FFBD')
a('        LDA #<RES')
a('        STA $FB')
a('        LDA #>RES')
a('        STA $FC')
a('        LDA #$FB')
a('        LDX #<RESEND')
a('        LDY #>RESEND')
a('        JSR $FFD8')
a('FIN:    JMP FIN')
a('NAME:   .byte $52,$45,$53')
STUB = """
        * = $0100
W1:     LDY #0
        LDX #$7F
        STX $FF00
        STA ($FA),Y
        LDX #$3E
        STX $FF00
        RTS
CR1RD:  LDY #0
        LDX #$7E
        STX $FF00
        LDA ($FA),Y
        LDX #$3E
        STX $FF00
        RTS
CR1WR:  LDY #0
        LDX #$7E
        STX $FF00
        STA ($FA),Y
        LDX #$3E
        STX $FF00
        RTS
"""
sc, ss = asm(STUB)
sd = bytearray(0x30)
for k, v in sc.items():
    sd[k - 0x100:k - 0x100 + len(v)] = v
a('STUBD:  .byte ' + ','.join('$%02X' % x for x in sd[:0x18]))
a('        .byte ' + ','.join('$%02X' % x for x in sd[0x18:]))
hdr = ''.join(f'{k} = ${ss[k]:04X}\n' for k in ('W1', 'CR1RD', 'CR1WR')) + f'RESEND = ${RES + 0x1000:04X}\nRES = ${RES:04X}\n'
src = hdr + '\n'.join(L) + '\n'
src = src.replace('CPX #$10', 'CPX #$30')
chunks, sym = asm(src)
body = bytearray()
base = 0x1C01
for ad in sorted(chunks):
    off = ad - base
    if len(body) < off:
        body.extend(bytes(off - len(body)))
    body[off:off + len(chunks[ad])] = chunks[ad]
open(os.path.join(HERE, 'probe.prg'), 'wb').write(bytes([base & 255, base >> 8]) + bytes(body))
json.dump(layout, open(os.path.join(HERE, 'vlayout.json'), 'w'))
print('probe.prg', len(body), 'BLK', BLK, 'end', hex(base + len(body)))
