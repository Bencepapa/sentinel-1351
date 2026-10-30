# Sentinel (Synapse, 1984) – Commodore 1351 mouse support

This document describes how mouse support was added to *Sentinel* by Bryan
Brandenburg (Synapse Software). The game is a first-person space shooter: the
joystick moves a crosshair, and the ship turns toward it.

- Patched disk: `Sentinel-1351.d64` (built from the original `Sentinel.d64`)
- Source: `mouse/sentinel_mouse.asm`
- Build: `python mouse/build.py [in.d64] [out.d64]`

## Controls with a mouse

| Input | Action |
|---|---|
| Mouse in **control port 2** | Moves the crosshair directly |
| Crosshair away from center (in flight) | Acts like a held joystick: the ship keeps turning toward it. There is a ±12 pixel dead zone around the center. |
| Left button | Fire (same line as the joystick fire button) |
| Right button | Opens the map: acts as the C= key once it has been held alone for 5 frames |
| Both buttons | Launches a proton torpedo (acts as SPACE). The laser is held back meanwhile, and the map doesn't open until the right button is released. |
| Mouse left alone | After the game's own idle delay (64 frames, no motion, no fire), the crosshair glides back to center, as with the joystick |
| Mouse motion on the sector map | Moves a + pointer over the grid; the cursor box jumps to the sector under it, the left button selects it (enhancement, not in the original) |
| Mouse motion on other screens | Turned into joystick directions |
| Forward / back | Crosshair up / down (the joystick is inverted, like a flight stick) |

When no mouse is plugged in, the game behaves exactly as it did before, joystick included.

## 1. Taking the game apart

### Disk layout and loader

The original disk has five PRG files, and each one loads the next:

| File | Load address | Role |
|---|---|---|
| `SENTINEL` | `$0100` | Boot loader. It loads into the stack page and autostarts with `LOAD"SENTINEL",8,1` by overwriting the return address, then loads `SN0`. |
| `SN0` | `$C000` | Second-stage loader. It loads `SN1` and `SN2`, copies `$C100-$C8FF` → `$0000-$07FF` and `$CA00-$CFFF` → `$D100-$D7FF` (RAM under I/O), then loads `SN3` and returns to `$245A` through a stack trick. |
| `SN1` | `$0800-$BFFF` | Main game |
| `SN2` | `$E000-$FFFF` | More game code and data (RAM under the KERNAL) |
| `SN3` | `$C000-$CFFF` | More code and data, loaded over `SN0` |

Patching therefore means changing bytes inside `SN0`, `SN1` and `SN2` in place.
Zero page and pages 2 and 3 come from `SN0`'s payload at `$C100+`.

A small Python D64 reader/writer (`mouse/tools/d64.py`, and the D64 code in
`build.py`) extracts the files and writes them back into the same sectors.
A 6502 disassembler (`mouse/tools/dis6502.py`) rebuilds the full runtime
memory image from those files for analysis.

### Finding the input code

Searching for `$DC00`/`$DC01` accesses showed the following:

- **`$B2D8`**: the per-frame port read. It writes `$DC00=$FF`, reads port 2,
  and stores the raw bits in **`$96`** (the joystick byte used everywhere)
  and the fire flag in `$97`.
- **`$B30C`**: the crosshair update. It moves **`CURX=$B2D7`** by ±3 and
  **`CURY=$120A`** by ±2 per frame. After an idle delay it drifts the
  crosshair back toward the center one pixel per frame (`$B372`). Some of its
  limits are self-modified operands (`$B340` Y max, `$B349` Y min, `$B38C`
  Y center, `$B333` idle delay), and twelve places in the game write them.
- **`$FDEE/$FE36/$FE6E`**: the keyboard scan. One of the three runs each frame,
  and each ends by writing `$DC00=$7F`.
- **The raster IRQ** at `$0AD9` runs five splits per frame. The split at
  `$0B25` calls the keyboard scan (`$0B43`…), then the port read (`$0BB0`).
  A later split calls the crosshair update (`$0D19`) only while the cockpit
  view is shown (`$B8=0`) and the game isn't in attract mode (`$88=0`).
- **`$864A`**: the difficulty menu reads `$DC00` directly and keeps the
  crosshair pinned until it sees a joystick direction.

Running the game in VICE with its remote monitor (`-remotemonitor`) confirmed
that the crosshair position drives the menu selection, and that holding the
joystick direction makes the ship turn. Simulated input was injected by
patching or poking memory over the monitor connection.

## 2. Reading a 1351 on the C64

The 1351 in proportional mode reports its position through the SID POT
registers (`$D419` X, `$D41A` Y) as a 7-bit counter that wraps around. The
movement is the difference between two readings. The patch uses the same
algorithm as Commodore's own driver (`M1351.64.SRC`, from
[MyDeveloperThoughts/1351MouseInBASIC](https://github.com/MyDeveloperThoughts/1351MouseInBASIC)):
take the 7-bit difference, halve it, and ignore ±1 jitter.

The SID only sees one control port at a time. Which one is chosen by
`$DC00` bits 7/6 (`%10` = port 2), and the selection has to stay stable for
the SID's 512-cycle sampling period. Commodore's driver selects the port and
then busy-waits 4 ms inside the IRQ, which a game can't afford. The patch
avoids the wait:

- The three keyboard scans now end with `$DC00=$BF` instead of `$7F`. Port 2
  is selected, and the joystick lines on bits 0–4 stay high, so they can still
  be read.
- Port 2 therefore stays selected for almost the whole frame. The pots are
  read once per frame, just before the next keyboard scan, so the latched
  values are always settled.

The mouse is detected automatically: an empty port (or a joystick) leaves
the X pot at `$FF`.

On port 2, the right mouse button pulls the "up" line, so in mouse mode that
bit is masked out of the joystick byte and handled separately.

## 3. The patch

### Hooks

| Address | Original | New |
|---|---|---|
| `$0B43` | `LDA $A0 / AND #$03` | `JSR POTRD / NOP` (POTRD redoes the replaced code and keeps its flags) |
| `$0BB0` | `JSR $B2D8` | `JSR JOYIN` |
| `$0D19` | `JSR $B30C` | `JSR CURSOR` |
| `$FE30`, `$FE68`, `$FEA0` | `LDA #$7F` | `LDA #$BF` |
| `$864A` | `LDA $DC00` | `LDA $96 / NOP` (the menu sees mouse directions too) |
| 12 writers of `$B333/$B340/$B349/$B38C` | `STA` into old operands | `STA` into the new variables `DDLY/YMAX/YMIN/YCEN` |

### Routines

- **POTRD** (every frame): reads both pots and computes the signed movement
  `MDX`/`MDY` with MOVCHK. The Y pot is inverted so that `MDY` is positive
  for "back". It also sets the "mouse present" flag.
- **JOYIN** (every frame; replaces `$B2D8`): reads port 2.
  - With a joystick, it does exactly what the original did.
  - With a mouse, MBTN turns the buttons into keys and masks the right button out.
    The keyboard scan reports keys as flags (`$FDEC` = C= opens the map,
    `$FDE5` = SPACE launches a torpedo), and the game only checks whether a
    flag is set. So MBTN just sets the flag with the same value the scan
    would store. A small counter (`RCNT`) waits 5 frames before treating the
    right button as C=. Pressing both buttons sets it negative, so the map
    stays shut until the right button is released.
    - In the cockpit, it ANDs in the **steering mask** `DS`, which holds
      directions as long as the crosshair is off center.
    - On other screens, it ANDs in directions taken from this frame's motion
      (MSYN).
- **CURSOR** (replaces `$B30C`):
  - Joystick: the original ±3/±2 stepping and the idle drift. The drift is
    re-implemented as ±1 steps through the same clamp code.
  - Mouse (MCUR): the crosshair moves by `MDX/MDY`. When there is no motion
    and no fire, it runs the original idle countdown and drift instead, so
    the crosshair glides back to center by itself.
  - Both paths go through **CAPPLY → CLAMP → SIDE**. These clamp the
    crosshair to the X range `$00-$FE` and the Y range `YMIN-YMAX`, then
    recompute the steering mask from the crosshair's distance to the center
    (`$7F`, `YCEN`) with a ±12 pixel dead zone.

### Where the code lives

The game uses almost all of its 64 KB, so free space had to be proven,
not assumed.

| Region | Size | Contents | How it was confirmed |
|---|---|---|---|
| `$B2D8-$B399` | 194 | CURSOR, CAPPLY, MOVCHK, MSYN | The original input routines are replaced entirely, and their self-modified operands are relocated. |
| `$02A2-$02FF` | 94 | JOYIN, POTRD | Unused by the KERNAL, never referenced by the game, and still intact after filling it with a marker byte and playing. |
| `$03B4-$03F5` + `$03F6-$03FF` | 66 + 10 | CLAMP, SIDE + variables | Same tests (fill pattern, reference scan) |
| `$0334-$033B` | 8 | steering tables | Unused by the KERNAL, never referenced by the game |
| `$0100-$01BF` | 192 | MCUR, MBTN | Dead leftovers of the crack's loader, garbled by stack pushes and never called. The game's stack stays at about `$01F0`, and the code survived play in VICE. |
| zero page `$4B $6F $AB $ED` | 4 | flags/temporaries | Not used as an operand anywhere in the game code |

Pitfalls found along the way:

- **Pages 4/5 are not free**, even though they look like leftover screen text.
  The line-drawing routine at `$3580` stores up to 256 points there (and
  77 points in page 2).
- **`$0293-$02A1` is not free.** The KERNAL's serial-bus code, which the loader
  uses, polls the RS-232 flag at `$02A1`. Putting code there hung the disk load.
- **`$6000-$7FFF` is not free**, even though `$7CC0-$7FFF` is zero and
  survived one fill test. It is a graphics buffer: the routine at `$BA72`
  clears all 32 pages of it at certain points, which wiped code placed at
  `$7D00` and crashed the game. A VICE watchpoint on the code's address
  found the routine.
- The code had to be made smaller several times to fit (a shared clamp path,
  a bounds table, a shorter MOVCHK, a pre-inverted Y axis).

### Title and credits

The cracked release replaced the publisher on the title screen with
`THE BAD BROTHERS`. The title text at `$1861` is made of fixed fields of
7 + 8 + 8 characters. They now read `SYNAPSE`/`SOFTWARE`/`PRESENTS` again,
which fits the fields exactly; another crack's copy (` BROKEN`/`BY TONY `/`MARTINI `)
shows the same layout.

The bottom scroller is raw screen text from `$C133` up to a `$FF` byte
(`@` is a space and `z` the separator glyph; the font has no usable `:` or `,`).
`1351 SUPPORT BY BURWOR.  MOUSE BUTTONS  LEFT SHOOT  RIGHT MAP  BOTH TORPEDO.`
was added at its start. The room came from the old "also available from
Synapse" advert: `AND COMING SOON`, `NEW YORK CITY`, `OPERATION ESCAPE`,
`SHAMUS CASE II` and `PHARAOHS CURSE` were dropped.

The 36 blanks at the end (`$C320-$C343`) must not move. The game also
uses `$C320` as an empty string when it erases big text on the map screen.
In v6 and v7 the text was allowed to grow into those blanks, and leftover
text ("THE 20TH C") appeared on the map.

## 4. Building and testing

```bash
python mouse/build.py
"C:\dev\c64\vice\win\bin\x64sc.exe" -controlport2device 3 -autostart Sentinel-1351.d64
```

In VICE, `Alt+Q` grabs the mouse. `-controlport2device 1` gives you a joystick
instead, to test the fallback.

`build.py` checks that the original bytes are what it expects before patching
each hook, and fails if any code chunk outside its free region.

### Loading the files

The PRGs in `prg/` are not standalone programs. `SENTINEL` loads `SN0`, which
loads the rest from **device 8**. All five files must be on the same disk:
attach the D64, or copy the files to an SD2IEC folder or a real disk, then
run:

```
LOAD"SENTINEL",8,1
```

It starts by itself.

## 5. One-file PRG

`python mouse/onefile.py Sentinel-1351_v8.d64` turns the multi-file disk into
a single self-unpacking `Sentinel-1351_v8.prg` (151 blocks). Load it with
`LOAD"SENTINEL-1351_V8",8` and type `RUN`, or drop it on VICE or an SD2IEC.

How it works:

1. **Memory image.** The script rebuilds what the loader chain leaves in
   memory: `SN0`'s copies to `$0000-$07FF` and `$D100-$D7FF`, plus `SN1`,
   `SN2` and `SN3`. That's about 63 KB. A PRG can only load into
   `$0801-$CFFF`, because KERNAL LOAD would write anything at `$D000+` into
   the I/O chips. So the image has to be compressed.
2. **Compression.** A simple LZ77 format: `$00-$7F` means a run of n+1
   literal bytes, and `$80-$FF` means a match of length (t&$7F)+3 with a
   16-bit backward distance. Each region has a 4-byte start/end header.
   The image packs to about 37.7 KB.
3. **Start-up** (BASIC `SYS 2061`):
   - Disable interrupts (`SEI`) and switch to all-RAM (`$01=$34`).
   - Copy the 256-byte depacker to `$D800` (RAM under the colour RAM, which
     the game doesn't use).
   - Move the packed data up so that it ends at `$CFFF`.
4. **Depacker.** It unpacks the regions that don't overlap the packed data
   first:
   - `$E000-$FFFF`
   - `$D100-$D3FF` and `$D500-$D7FF`
   - zero page and stack, into temporary pages at `$DA00/$DB00`
   - `$0200-$07FF`

   Then it unpacks `$0800-$CFFF` **in place**: the output grows upward
   toward input that hasn't been read yet. The build simulates the in-place
   unpack to prove the output never overtakes the input. Where it would, it
   stores the last bytes raw (256 bytes are raw here).
5. **Hand-over.** Copy zero page (except `$00/$01`) and the stack page into
   place, write a 7-byte stub to `$01F8` (`LDA #$37 / STA $01 / JMP $245A`),
   and jump to it. The stub has to run outside `$D000-$DFFF`, because I/O
   appears there as soon as `$01` is set.

The build also checks itself: a Python model of the depacker unpacks the
finished PRG and compares the result with the memory image, which matched
byte for byte. The PRG was also run in VICE with a 1351 mouse and with a
joystick.
