"""Build a single-file PRG of Sentinel from a (patched) multi-file D64.

usage: python onefile.py [in.d64] [out.prg]

The original game is loaded by a chain of loaders (SENTINEL -> SN0 -> SN1,
SN2, SN3). This script rebuilds the memory image the loaders leave behind,
LZ-packs it, and wraps it in a self-unpacking PRG that starts with RUN.

Unpacking (all with IRQs off and $01=$34, i.e. RAM everywhere):
  1. the startup code copies the depacker to $D800 and moves the packed data
     up so that it ends at $CFFF
  2. the depacker unpacks $E000-$FFFF, $D100-$D3FF, $D500-$D7FF, zero page and
     stack (to temp pages $DA00/$DB00), $0200-$07FF, and finally $0800-$CFFF
     in place: the output grows up toward the not yet read input and ends
     exactly where the input ends (checked by simulation at build time; if
     needed the last bytes are stored raw)
  3. zero page/stack are copied into place, $01=$37, JMP $245A (game entry)
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'tools'))
sys.path.insert(0, HERE)
from asm import asm
from build import file_sectors, read_file

IN_D64 = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'Sentinel-1351.d64')
OUT_PRG = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(IN_D64)[0] + '.prg'

ENTRY = 0x245A
DEPACK = 0xD800          # RAM under color RAM, unused by the game
ZPTMP, STKTMP = 0xDA00, 0xDB00

# ---------------- memory image ----------------
def image(d64):
    d = open(d64, 'rb').read()
    f = {n: read_file(d, file_sectors(d, n)) for n in ('SN0', 'SN1', 'SN2', 'SN3')}
    m = bytearray(65536)
    sn0 = f['SN0'][2:]
    m[0x0000:0x0800] = sn0[0x100:0x900]                      # $C100-$C8FF
    for src, dst in zip(range(0xCA, 0xD0), (0xD1, 0xD2, 0xD3, 0xD5, 0xD6, 0xD7)):
        o = (src - 0xC0) * 256
        m[dst * 256:dst * 256 + 256] = sn0[o:o + 256]
    for n in ('SN1', 'SN2', 'SN3'):
        b = f[n][0] | f[n][1] << 8
        m[b:b + len(f[n]) - 2] = f[n][2:]
    return m

# ---------------- LZ packer ----------------
# region: start lo/hi, end lo/hi, then tokens until the end address is reached
# token $00-$7F: n+1 literals follow
# token $80-$FF: match, length (t&$7F)+3, then 16-bit backward distance
MAXM = 130

def pack(data):
    out = bytearray(); lit = bytearray()
    heads = {}
    def flush():
        nonlocal lit
        while lit:
            chunk = lit[:128]; lit = lit[128:]
            out.append(len(chunk) - 1); out.extend(chunk)
    def insert(p):
        if p + 3 <= n:
            heads.setdefault(bytes(data[p:p + 3]), []).append(p)
    i = 0; n = len(data)
    while i < n:
        best_len, best_pos = 0, 0
        if i + 3 <= n:
            for p in reversed(heads.get(bytes(data[i:i + 3]), [])[-64:]):
                l = 3
                while l < MAXM and i + l < n and data[p + l] == data[i + l]:
                    l += 1
                if l > best_len:
                    best_len, best_pos = l, p
                    if l == MAXM: break
        if best_len >= 4:
            flush()
            d = i - best_pos
            out += bytes([0x80 | (best_len - 3), d & 255, d >> 8])
            for k in range(best_len): insert(i + k)
            i += best_len
        else:
            lit.append(data[i]); insert(i); i += 1
    flush()
    return out

def region(start, end, data):
    return bytes([start & 255, start >> 8, end & 255, end >> 8]) + pack(data)

def max_overrun(tokens, gap):
    """In-place decode with input `gap` bytes ahead of output: largest overrun."""
    s, d, i, worst = gap, 0, 0, -1 << 30
    while i < len(tokens):
        t = tokens[i]; i += 1; s += 1
        if t < 0x80:
            for _ in range(t + 1):
                i += 1; s += 1; d += 1
                worst = max(worst, d - s)
        else:
            i += 2; s += 2; d += (t & 0x7F) + 3
            worst = max(worst, d - s)
    return worst

# ---------------- 6502 code ----------------
DEPACKER = """
SRC = $FB
DST = $FD
MP  = $F9
TMP = $F7
END = $F5
CNT = $F4
        * = $D800
        LDY #0
        LDA #7
        STA CNT
region: JSR GETB
        STA DST
        JSR GETB
        STA DST+1
        JSR GETB
        STA END
        JSR GETB
        STA END+1
tok:    JSR GETB
        CMP #$80
        BCS match
        TAX
        INX
lit:    JSR GETB
        STA (DST),Y
        INC DST
        BNE lit1
        INC DST+1
lit1:   DEX
        BNE lit
        BEQ next
match:  AND #$7F
        CLC
        ADC #3
        TAX
        JSR GETB
        STA TMP
        JSR GETB
        STA TMP+1
        LDA DST
        SEC
        SBC TMP
        STA MP
        LDA DST+1
        SBC TMP+1
        STA MP+1
mc:     LDA (MP),Y
        STA (DST),Y
        INC MP
        BNE mc1
        INC MP+1
mc1:    INC DST
        BNE mc2
        INC DST+1
mc2:    DEX
        BNE mc
next:   LDA DST
        CMP END
        BNE tok
        LDA DST+1
        CMP END+1
        BNE tok
        DEC CNT
        BNE region
; all unpacked: zero page and stack into place, then start the game
        LDX #2
dz:     LDA $DA00,X
        STA $00,X
        INX
        BNE dz
dsk:    LDA $DB00,X
        STA $0100,X
        INX
        BNE dsk
        LDX #6
dst:    LDA STUB,X
        STA $01F8,X
        DEX
        BPL dst
        JMP $01F8
GETB:   LDA (SRC),Y
        INC SRC
        BNE gb1
        INC SRC+1
gb1:    RTS
STUB:   LDA #$37
        STA $01
        JMP $245A
"""

def startup(blob_from, blob_pages, src_start):
    top = 0xD000 - 256
    return f"""
        * = $0801
        .BYTE $0B,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00
        SEI
        LDA #$34
        STA $01
        LDX #0
cpd:    LDA DPK,X
        STA $D800,X
        INX
        BNE cpd
        LDA #<{blob_from + (blob_pages - 1) * 256}
        STA $FB
        LDA #>{blob_from + (blob_pages - 1) * 256}
        STA $FC
        LDA #<{top}
        STA $FD
        LDA #>{top}
        STA $FE
        LDX #{blob_pages}
pg:     LDY #$FF
by:     LDA ($FB),Y
        STA ($FD),Y
        DEY
        BNE by
        LDA ($FB),Y
        STA ($FD),Y
        DEC $FC
        DEC $FE
        DEX
        BNE pg
        LDA #<{src_start}
        STA $FB
        LDA #>{src_start}
        STA $FC
        JMP $D800
DPK:
"""

def asm_bytes(src):
    chunks, sym = asm(src)
    (base, code), = chunks.items()
    return base, bytes(code), sym

def main():
    m = image(IN_D64)
    _, depacker, _ = asm_bytes(DEPACKER)
    assert len(depacker) <= 256

    # regions that unpack into free space first ...
    head = bytearray()
    head += region(0xE000, 0x0000, m[0xE000:0x10000])         # end wraps to $0000
    head += region(0xD100, 0xD400, m[0xD100:0xD400])
    head += region(0xD500, 0xD800, m[0xD500:0xD800])
    head += region(ZPTMP, ZPTMP + 256, m[0x0000:0x0100])
    head += region(STKTMP, STKTMP + 256, m[0x0100:0x0200])
    head += region(0x0200, 0x0800, m[0x0200:0x0800])
    # ... then $0800-$CFFF in place. The input must stay ahead of the output;
    # if it does not, store the last `raw` bytes uncompressed at their place.
    r1 = m[0x0800:0xD000]
    tokens = pack(r1)
    over = max_overrun(tokens, len(r1) - len(tokens))
    raw = 0
    while over > 0:
        raw = ((raw + over + 63) // 64) * 64
        tokens = pack(r1[:len(r1) - raw])
        over = max_overrun(tokens, len(r1) - raw - len(tokens))
    end = 0xD000 - raw
    blob = head + bytes([0x00, 0x08, end & 255, end >> 8]) + tokens + r1[len(r1) - raw:]
    blob_start = 0xD000 - len(blob)
    print(f'packed {len(blob)} bytes (raw tail {raw})')

    # PRG: startup + depacker (256) + padding + blob, blob moved up to end at $CFFF
    pages = (len(blob) + 255) // 256
    pad = pages * 256 - len(blob)
    _, st, sym = asm_bytes(startup(0, pages, blob_start))
    blob_from = sym['DPK'] + 256
    _, st, sym = asm_bytes(startup(blob_from, pages, blob_start))
    if blob_from + pages * 256 > 0xD000:
        sys.exit(f'PRG too big')
    body = st + depacker.ljust(256, b'\x00') + bytes(pad) + blob
    open(OUT_PRG, 'wb').write(bytes([0x01, 0x08]) + body)
    print(f'wrote {os.path.abspath(OUT_PRG)} ($0801-${0x0801 + len(body) - 1:04X}, '
          f'{(len(body) + 2 + 253) // 254} blocks)')

if __name__ == '__main__':
    main()
