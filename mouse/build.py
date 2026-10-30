"""Build Sentinel-1351.d64: assemble sentinel_mouse.asm and patch the original disk.

usage: python build.py [input.d64] [output.d64]
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'tools'))
from asm import asm

SRC = os.path.join(HERE, 'sentinel_mouse.asm')
IN_D64 = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'Sentinel.d64')
OUT_D64 = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, '..', 'Sentinel-1351.d64')

# free/rewritten regions the code may occupy (inclusive end)
REGIONS = [(0x02A2, 0x02FF), (0xB2D8, 0xB399), (0x03B4, 0x03F5), (0x0100, 0x01D7)]

# ---------------- D64 helpers ----------------
SPT = [0] + [21] * 17 + [19] * 7 + [18] * 6 + [17] * 10
def ts_off(t, s):
    return (sum(SPT[1:t]) + s) * 256

def file_sectors(d, name):
    t, s = 18, 1
    while t:
        o = ts_off(t, s)
        for i in range(8):
            e = d[o + i * 32:o + i * 32 + 32]
            if e[2] & 7 == 2 and e[5:21].rstrip(b'\xa0').decode('latin1') == name:
                secs = []
                ft, fs = e[3], e[4]
                while ft:
                    secs.append(ts_off(ft, fs))
                    ft, fs = d[secs[-1]], d[secs[-1] + 1]
                return secs
        t, s = d[o], d[o + 1]
    raise KeyError(name)

def read_file(d, secs):
    out = bytearray()
    for o in secs:
        n = 254 if d[o] else d[o + 1] - 1
        out += d[o + 2:o + 2 + n]
    return out

def write_file(d, secs, data):
    p = 0
    for o in secs:
        n = 254 if d[o] else d[o + 1] - 1
        d[o + 2:o + 2 + n] = data[p:p + n]
        p += n
    assert p == len(data)

# ---------------- memory model ----------------
# where each runtime address lives on disk: (file, file load address, runtime base)
# SN0 ($C000) holds pages $0000-$07FF at $C100-$C8FF (copied by its loader)
def locate(addr):
    if addr < 0x0800:
        return 'SN0', addr + 0x0100
    if addr < 0xC000:
        return 'SN1', addr - 0x0800
    if addr >= 0xE000:
        return 'SN2', addr - 0xE000
    if addr < 0xD000:
        return 'SN3', addr - 0xC000
    raise ValueError(f'${addr:04X} not patchable')

def main():
    chunks, sym = asm(open(SRC).read())
    for base, code in chunks.items():
        end = base + len(code) - 1
        if not any(lo <= base and end <= hi for lo, hi in REGIONS):
            sys.exit(f'chunk ${base:04X}-${end:04X} overflows its region')
        print(f'chunk ${base:04X}-${end:04X} ({len(code)} bytes)')

    d = bytearray(open(IN_D64, 'rb').read())
    files = {n: file_sectors(d, n) for n in ('SN0', 'SN1', 'SN2', 'SN3')}
    data = {n: read_file(d, s) for n, s in files.items()}

    def poke(addr, bs, expect=None):
        f, off = locate(addr)
        off += 2  # skip load address
        if expect is not None and bytes(data[f][off:off + len(expect)]) != bytes(expect):
            sys.exit(f'unexpected bytes at ${addr:04X}: {data[f][off:off+len(expect)].hex()}')
        data[f][off:off + len(bs)] = bs

    # the old input routine region must be what we expect before overwriting
    poke(0xB2D8, b'', expect=bytes.fromhex('ced6b2d02ea9018dd6b2'))
    poke(0xB2D8, bytes([0xEA]) * (0xB39A - 0xB2D8))  # clear old routine
    for base, code in chunks.items():
        poke(base, code)

    # variables with initial values (original operand defaults)
    init = {'YMAX': 0xAD, 'YMIN': 0x58, 'YCEN': 0xAA, 'DDLY': 0x40,
            'MFLAG': 0x80, 'OPOTX': 0xFF, 'OPOTY': 0xFF, 'MDX': 0, 'MDY': 0,
            'PX': 60, 'PY': 48, 'PSY': 0, 'MFRM': 0}
    for k, v in init.items():
        poke(sym[k], bytes([v]))
    poke(sym['BND'], bytes([0x00, 0xFE]))  # crosshair X range
    # steering tables: CEN0 PMSK0 (YCEN) PMSK2 NMSK0 DS0 NMSK2 DS2
    poke(sym['CEN'], bytes([0x7F, 0xF7, 0xAA, 0xFE, 0xFB, 0xFF, 0xFD, 0xFF]))

    lo, hi = lambda a: a & 255, lambda a: a >> 8
    # hooks
    poke(0x0B43, bytes([0x20, lo(sym['POTRD']), hi(sym['POTRD']), 0xEA]),
         expect=bytes.fromhex('a5a02903'))
    poke(0x0D19, bytes([0x20, lo(sym['CURSOR']), hi(sym['CURSOR'])]), expect=bytes.fromhex('200cb3'))
    poke(0x0BB0, bytes([0x20, lo(sym['JOYIN']), hi(sym['JOYIN'])]), expect=bytes.fromhex('20d8b2'))
    # difficulty menu keeps the crosshair pinned until it sees a direction on $DC00;
    # let it see the mouse-synthesized directions in $96 instead
    poke(0x864A, bytes([0xA5, 0x96, 0xEA]), expect=bytes.fromhex('ad00dc'))
    # map pointer (enhancement): its shape, a + centred where the crosshair's
    # centre is (x 12, y 7), in sprite shape $4F ($53C0, unused, all zero)
    plus = bytearray(64)
    for r in range(4, 11):
        plus[r * 3 + 1] = 0x08
    plus[7 * 3 + 1] = 0x7F                 # x 9-15
    poke(0x53C0, bytes(plus), expect=bytes(64))
    # map pointer (enhancement): the map loop and the crosshair routine's Y
    poke(0xFBCE, bytes([0x20, lo(sym['MSEL']), hi(sym['MSEL'])]), expect=bytes.fromhex('20c821'))
    poke(0x129B, bytes([0x20, lo(sym['MPY']), hi(sym['MPY']), 0xEA, 0xEA, 0xEA]), expect=bytes.fromhex('a4b8f002a900'))
    poke(0x0D12, bytes([0x20, lo(sym['MPY0']), hi(sym['MPY0']), 0x4C, 0x1C, 0x0D, 0xEA]), expect=bytes.fromhex('a9008d01d0f003'))
    for a in (0xFE30, 0xFE68, 0xFEA0):  # keyboard scans end with LDA #$7F / STA $DC00
        poke(a, bytes([0xA9, 0xBF]), expect=bytes.fromhex('a97f'))
    # relocate the self-modified operands of the old routine
    moves = {0xB38C: 'YCEN', 0xB349: 'YMIN', 0xB340: 'YMAX', 0xB333: 'DDLY'}
    writers = [0x24B2, 0x24B7, 0x24BC, 0x860E, 0x863F, 0x869C, 0x870C,
               0x8C7E, 0x8C83, 0x8C88, 0x8E22, 0x8E27]
    for w in writers:
        f, off = locate(w)
        tgt = data[f][off + 3] | data[f][off + 4] << 8
        assert data[f][off + 2] == 0x8D and tgt in moves, hex(w)
        poke(w, bytes([0x8D, lo(sym[moves[tgt]]), hi(sym[moves[tgt]])]))

    # title: the crack's "THE BAD BROTHERS" back to the original publisher
    # (fixed fields of 7 and 8 characters, "PRESENTS" follows)
    poke(0x1861, b"SYNAPSE" + b"SOFTWARE", expect=b"THE BADBROTHERS")
    # scroller: credit and mouse help in front, room taken from the old
    # "also available from Synapse" advert. ('@' = space, 'z' = separator
    # glyph; the font has no usable ':' or ','.) The text runs $C133-$C31F;
    # the blanks from $C320 on must stay put: the game also uses them as an
    # empty string when it erases big text on the map screen.
    old = bytes(data['SN3'][2 + 0x133:2 + 0x320])
    assert bytes(data['SN3'][2 + 0x320:2 + 0x344]) == b'@' * 36
    credit = (b'1351@SUPPORT@BY@BURWORz@@'
              b'MOUSE@BUTTONS@@LEFT@SHOOT@@RIGHT@MAP@@BOTH@TORPEDOz@@')
    text = old
    for cut in (b'@@NEW@YORK@CITY@@OPERATION@ESCAPE', b'@@AND@COMING@SOON',
                b'@@SHAMUS@CASE@II', b'@@PHARAOHS@CURSE'):
        assert text.count(cut) == 1, cut
        text = text.replace(cut, b'')
    new = credit + text
    assert len(new) <= len(old), 'scroller has no room'
    poke(0xC133, new.ljust(len(old), b'@'), expect=old)

    for n, s in files.items():
        write_file(d, s, data[n])
    open(OUT_D64, 'wb').write(d)
    print('wrote', os.path.abspath(OUT_D64))

if __name__ == '__main__':
    main()
