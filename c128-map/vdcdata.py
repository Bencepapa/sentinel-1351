"""Data for the VDC (second display) map view, shared by the builds."""

# Icon glyphs copied from the game's character set (codes $66-$6A).
GLYPHS = [
    [0x00, 0x18, 0x7E, 0xE7, 0xFF, 0x7E, 0x3C, 0x00],   # blue saucer
    [0x00, 0x3C, 0x7E, 0xE7, 0xFF, 0x7E, 0x3C, 0x00],   # orange saucer
    [0x00, 0x00, 0x08, 0x1C, 0x08, 0x00, 0x00, 0x00],   # 1 squadron
    [0x00, 0x20, 0x70, 0x20, 0x00, 0x04, 0x0E, 0x04],   # 2 squadrons
    [0x10, 0x38, 0x10, 0x02, 0x07, 0x42, 0xE0, 0x40],   # 3 squadrons
]


def double(nibble):
    """Each of the 4 bits becomes 2 pixels, so one icon half fills one 8-pixel character."""
    out = 0
    for bit in range(4):
        if nibble & (8 >> bit):
            out |= 3 << (6 - 2 * bit)
    return out


def chardata():
    """Characters $E0-$EC: vertical line, horizontal line, crossing, 5 icons x 2 halves."""
    chars = [
        [0x18] * 8,
        [0, 0, 0, 0xFF, 0xFF, 0, 0, 0],
        [0x18, 0x18, 0x18, 0xFF, 0xFF, 0x18, 0x18, 0x18],
    ]
    for g in GLYPHS:
        chars.append([double(b >> 4) for b in g])
        chars.append([double(b & 15) for b in g])
    data = bytearray()
    for c in chars:
        data += bytes(c) + bytes(8)
    assert len(data) == 208
    return bytes(data)


def rowtables():
    """Text row * 80, low and high bytes, for 25 rows."""
    return (bytes((r * 80) & 255 for r in range(25)),
            bytes((r * 80) >> 8 for r in range(25)))


# C64 colour -> VDC RGBI colour, indexed by the low nibble of the colour code
# used by the game's colour matrix.
VCOL = bytes([0, 15, 8, 7, 11, 4, 2, 13, 12, 12, 9, 1, 14, 5, 3, 14])


def screencodes(text, width=40):
    """VDC screen codes (letters 1-26, digits and punctuation as in ASCII), space padded."""
    out = bytearray()
    for ch in text.upper():
        if 'A' <= ch <= 'Z':
            out.append(ord(ch) - 64)
        else:
            out.append(ord(ch))
    out += bytes([32]) * (width - len(out))
    assert len(out) == width
    return bytes(out)


# The game's messages for the attack rings, in the order of LASTMSG 1-4 ($3E7E).
MESSAGES = [
    'MOTHERSHIP ENGAGED IN BATTLE',
    'MOTHERSHIP DESTROYED',
    'JARALOBA IS SURROUNDED',
    'JARALOBA CEASES TO EXIST',
]
TITLE = 'SENTINEL 1351 - SECTOR MAP'
KEYS1 = 'STICK OR MOUSE: CURSOR   FIRE: SELECT'
KEYS2 = 'R: NEW MAP  T: FAST TICKS  V: THIS SCREEN  SPACE: EXIT'


def textdata():
    """(address, bytes) pairs for the VDC texts: messages, title, key lines."""
    msgs = b''.join(screencodes(m) for m in MESSAGES)
    return [(0x4360, msgs), (0x3F00, screencodes(TITLE)),
            (0x3F28, screencodes(KEYS1)), (0x3F50, screencodes(KEYS2, 56))]


def planetchars(sprite_frames):
    """4 sprite frames (64 bytes, 21 rows of 3 bytes) -> 4 x 9 VDC characters (16 bytes each).

    The 24x21 sprite becomes a 3x3 block of characters, row by row; the missing
    three pixel rows at the bottom are blank."""
    out = bytearray()
    for f in range(4):
        sp = sprite_frames[f * 64:f * 64 + 63]
        for cy in range(3):
            for cx in range(3):
                for r in range(8):
                    row = cy * 8 + r
                    out.append(sp[row * 3 + cx] if row < 21 else 0)
                out += bytes(8)
    assert len(out) == 576
    return bytes(out)


# Ship systems (see SHIP-STATUS.md): names from $9245, messages from $8301-$83FC
# (the game writes "@" for a space).
SYSTEMS = [
    'PHASOR CANNONS',
    'LONG RANGE SCANNER',
    'SHORT RANGE SCANNER',
    'STELLAR GRID',
    'AUTOMATIC TRACKING COMPUTER',
    'HYPERSPACE COORDINATOR',
    'LONG RANGE SCAN SEQUENCER',
    'COMMUNICATIONS MODULE',
]
SYSMSGS = [
    'PHASORS DESTROYED CAPTAIN',
    'LONG RANGE SCANNER DESTROYED',
    'SHORT RANGE SCANNER DESTROYED',
    'STELLER GRID UPDATE DESTROYED',
    'AUTOMATIC TRACKING COMPUTER DESTROYED',
    'HYPERSPACE COORDINATOR DESTROYED',
    'LONG RANGE SCAN SEQUENCER DESTROYED',
    'COMMUNICATIONS MODULE DESTROYED',
]
KEYS3 = 'H: TAKE A HIT   B: REPAIR AT BASE'


def shipdata():
    """(address, bytes) pairs: system names (28 each), messages (40 each), labels, key line."""
    names = b''.join(screencodes(s, 28) for s in SYSTEMS)
    msgs = b''.join(screencodes(s, 40) for s in SYSMSGS)
    labels = (screencodes('SHIP SYSTEMS', 12) + screencodes('SHIELDS', 12) +
              screencodes('HITS TAKEN', 12) + screencodes('OK', 6) + screencodes('DOWN', 6) +
              screencodes('INTACT', 6) + screencodes('LOST', 6))
    return [(0x3E00, names), (0x3A80, msgs), (0x3BC0, labels), (0x3F88, screencodes(KEYS3))]
