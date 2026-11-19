# Task: survey the C64 original's title screen and start sequence (read-only investigation)

Goal: the C128 port has no title screen yet. We will port it as an overlay package (see
`briefs/memory-overlay-plan.md`: title / intro packages loaded from bank 1 into the shared slot, shown once at start
and again after a game reset; the scrolling text will lose the advertisement and get a few lines about the port).
Document exactly how the ORIGINAL works so it can be re-implemented with the same look, sound and timing.
Trace it in the JS C64 machine (js/src/machine.js, `.zen/lib.js` helpers, SentinelDisasm, hooks, `js/c64-symbols.txt`,
the unpatched original Sentinel.d64 payload and the 1351 patch `Sentinel-1351_v10.prg` as `c64game`). Note from an
earlier survey: with `m.dma = true` from frame 0 the original stops at a grey screen with no music; turn DMA on only
after about frame 250 (or leave it off for tracing, then check the raster timing separately).

Write the findings below "## Findings" in this file, with addresses, sizes and a table per part. Cover:

1. **Boot to title:** the loader/depacker stages, when the title appears (frame numbers), the screen mode (the
   cockpit with bitmap lettering in the view), which memory holds what (bitmap, screen, colour RAM, sprites,
   charset), how the title lettering is drawn (bitmap data, address and size, colours), what runs in the IRQ.
2. **Music:** the 3-voice SID tune (around `$1C6x-$2074`, called from `$0C5D`?): data format, player routine
   (address, size, per-frame call, tempo), the register writes (record the SID write log of the whole tune with
   frame numbers: voices, waveforms, ADSR, filter), length, whether it loops or plays once, what stops it
   (fire, F-keys, restore), the sound effects heard on the title (sirens, beeps). Deliver the tune as an extractable
   asset: raw data bytes + player or a frame-by-frame register dump, and its size (packed and unpacked).
3. **Scrolling text:** where the 520-byte text lives, its encoding, the scroller routine (row, speed, fine scroll,
   colour effect), the full text content (dump it as plain text so we can rewrite it), wrap/loop behaviour.
4. **Difficulty selector** (`$8609`, loop `$864A`, store `$87C6`, confirm `$867F`; labels printed by `$27CD`/`$871E`):
   screen layout, texts, colours, how input works (joystick/1351/keys), the five levels' names, what each level sets
   (`DIFFLEVEL $E0`, table `DIFFICULTY $8422`: squadrons by difficulty; shields, protons, systems via `SHIPINIT $8451`,
   mothership events from difficulty 2 and higher, etc.): a table level -> all effects; how F5 / fire / F7 reach it.
5. **Start sequence:** the "welcome scroll", the Starfleet briefing: the raster effect that opens the top bar
   (the HUD strip) and the text typed word by word / letter by letter (text at `$97D9`, 306 bytes; routine
   addresses, timing in frames, the raster line values and which registers are used for the opening animation,
   sound, the colours), what happens after it (automatic map opening, `$998E` prompt: Fire/Space advances to the
   sector map), the first sector/world generation (`$20F1` etc.) and the HUD initialisation order.
6. **Attract mode / flags:** the `$88` attract flag (pause is bypassed in attract mode), whether the title runs a
   demo, timers, what returns to the title after game over / F7 / RESTORE (GAMEENTRY `$245A`) and what it resets.
7. **Assets and sizes:** a list of every graphic/data/code block used only by the title/intro (address range, size
   raw and after lz_pack-style compression, what it is), so we can budget overlay packages; which parts the C128 port
   already has (cockpit bitmap lettering? charset? sprites?) and what is new.
8. **Anything missing:** things the user might have forgotten that belong to the title/start flow (credits, copyright
   text, hi-score, key help, language/colour cycling, sound test, the 1351 patch's mouse detect prompt, game ports
   handling) — list whatever the original does that we did not name here.
9. **Porting proposal:** for the C128 (VIC-IIe 40-column screen, shared slot S1 of 3481 bytes in the overlay plan,
   bank 1 for data, copy stub at `$0100`): the package split (title, intro, music), estimated sizes, what to reuse
   from the original as raw data vs rewrite, the raster-critical parts (the bar-opening effect), and the order of work
   in small steps each fitting one agent task. Include how the itch/JS page and tests can verify it (SID write log
   compare, frame timing, screenshots).

Do not change code. Branch feature/game-end. No commit/push. End with a short summary of the main findings and
open questions.

## Findings

### Method and scope

The comparison uses the checked-in `Sentinel.d64` and `Sentinel-1351_v10.prg` (`c64game` in `js/programs.js`). The disk is the unpatched **repository copy**. Its title already carries a crack credit, so it cannot establish the retail title's exact credits. I followed both loaders with `SentinelDisasm`, checked the disk chain with `mouse/tools/d64.py`, and traced the reconstructed disk image and the patched PRG independently in `js/src/machine.js` with `.zen/lib.js` and address hooks. The disk trace starts at `$245A` after the loader copies. I also executed the two disk loaders with instant KERNAL LOAD hooks to verify the sequence. Neither disk trace includes physical IEC load time.

Frame numbers are zero-based from `m.start()`, and a write in frame F is visible in that frame or the next completed render depending on its raster position. The patched reference enables `m.dma` at frame 250, and the direct disk reference enables it at frame 74. All baseline traces execute the native 6510 code. The input scenarios below state when the controls were pressed. PAL figures use the JS machine's 312-line, 63-cycle model.

### 1. Boot, title picture and interrupts

| Stage | Address / size | Observed |
|---|---|---|
| Disk boot | `SENTINEL`, `$0100–$01FF`, 256 payload bytes | `LOAD"SENTINEL",8,1` overwrites a stack return to autostart. `$0100` sets a red border and blanks the display, then loads `SN0` and jumps to `$C000`. |
| Disk second stage | `SN0`, `$C000–$CFFF`, 4,096 bytes | Loads `SN1` (47,104 bytes at `$0800–$BFFF`) and `SN2` (8,192 at `$E000–$FFFF`). Copies eight pages `$C100–$C8FF` to `$0000–$07FF`, and six pages `$CA00–$CFFF` to RAM under I/O at `$D100–$D3FF` and `$D500–$D7FF`. Loads `SN3` (4,096 at `$C000–$CFFF`), using a stacked return to `$245A`. |
| Patched one-file boot | 38,223-byte PRG including header, BASIC at `$0801`, SYS 2061 at `$080D` | Startup masks IRQs, banks all RAM with `$01=$34`, copies a one-page depacker image from `$084E` to `$D800`, and relocates the packed pages upwards to end at `$CFFF`. Inverse order is only for the upward copy. The decoder advances forward. |
| Patched depack | `$D800`, frame 31 | Seven LZ regions in order are `$E000–$FFFF`, `$D100–$D3FF`, `$D500–$D7FF`, ZP staged at `$DA00`, stack staged at `$DB00`, `$0200–$07FF`, and `$0800–$CFFF` in place. Four-byte little-endian start/end headers, end exclusive. Literal length is token + 1 for `$00–$7F`, otherwise match length is (token & 127) + 3 followed by a 16-bit backward distance. The stub at `$01F8` restores `$01=$37` and jumps to `$245A` in frame 175. |
| Common game entry | `$245A–$25EB` | Sets stack and banking, blanks in grey, clears the SID and performs a long initialization loop at `$2491` calling `$F9C3` 16,384 times. Resets game state via `$F6C1`, sets up graphics and creates the initial world and HUD. |
| Build and reveal | `$25B8 → $18AA → $19E8`, then `$25DE → $0A68` | Patched: credit drawing starts frame **238**. The last credit is drawn and the IRQ installed in **245**, first full active title raster in **246** and first music notes in **248**. Direct disk payload: **63, 69, 70, 72** respectively. Disk with instant KERNAL LOADs reached `$245A` at frame 1 line 245 and played its first notes at frame 74. |

Cold DMA enabled from frame 0 reproduced the grey failure. This shifts `$245A` to frame 185, line 282. The `LDA $D011` / mask / `STA $D011` at `$2475–$247E` feeds the *live* raster bit 8 back into the *compare* high bit, so the initial `$D012=$D9` targets line 473 and the split chain never starts. The itch C64 profile already uses `hooks.fixC64Original()` for this sequence and the related `$8D9A` case. A faithful timing test should state whether that browser fix is active.

| Display piece | C64 memory and draw path |
|---|---|
| VIC bank and view | CIA2 selects bank `$4000–$7FFF`. The view uses multicolor bitmap (`$D011=$3B`, `$D016=$18`, `$D018=$18`), bitmap `$6000–$7F3F` (8,000 visible bytes), matrix `$4400–$47E7` (1,000), color RAM `$D800–$DBE7` (1,000 nibbles). In bitmap mode pixel values 1 and 2 select the upper and lower matrix nibbles respectively, while 0 uses `$D021` and 3 uses color RAM. [Commodore Programmer's Reference Guide, graphics chapter](https://www.commodore.ca/manuals/c64_programmers_reference/c64-programmers_reference_guide-03-programming_graphics.pdf) |
| Text strips | `$D018=$50` selects screen `$5400–$57E7`, charset `$4000–$43FF` (128 × 8 bytes used). HUD occupies rows 0–2 and the scroll text is row **23**, `$5798–$57BF`. The bottom has cockpit rivet/scale graphics. |
| Sprites and shared art | Sprite pointers `$47F8–$47FF` are multiplexed and the text matrix's `$57F8–$57FF` are cleared. Shape ranges are `$4800–$53FF` and `$5800–$5FFF` (80 × 64). The title uses the cockpit guns, with pointers `$7E/$7F` in the lower bitmap split, plus the shared barrel/scale machinery. The main crosshair is hidden in attract. The radar and both gun bases are part of the saved cockpit bitmap, centered amid animated stars. |
| Small bitmap credits | `$19E8–$1A5E` calls `$27CD → $0816` with the character codes at `$1861–$1899`. The printer reads 8-byte glyphs at `$4000 + code*8`, expands each to two 8-byte multicolor cells wide and writes the pixels directly. Tile rows 4, 6, 13, 15, 16 contain the two publisher/crack fields, PRESENTS, CREATED BY, BRYAN and BRANDENBURG. |
| Large logo | `$1A15–$1A30 → $087E` draws the eight character codes at `$1878–$187F` at tile row 8, columns 4–35, with each source 8×8 glyph scaled to 32×32 physical pixels. The 1,024 bytes written are four 256-byte spans at `$6A20/$6B60/$6CA0/$6DE0`, stride 320. The complete credit-and-logo printer writes 1,808 distinct bytes including the blank portions of its glyph rectangles. |
| Color animation | Ink is multicolor pixel value 2. `$196B–$19E7` recolors rectangles through `$BA54` when `$89 & $7F == $6F`. The logo matrix cycles `$72,$78,$7A,$74,$79` (red, orange, light red, purple, brown) from `$189B–$189F`. Other credit lines alternate via XOR `$06` at `$189A`. Frame interval depends on main-loop work, about 7–9 frames early in the patched DMA trace. `$1A5F–$1A98` moves two 33-cell matrix bands in opposite directions at `$44FB–$451B` and `$4612–$4632`, injecting from `$18A1–$18A8`. This animates color under the bitmap. |

`$0A68` installs the hardware RAM vectors `$0AD9` (IRQ) and `$0AB9` (NMI). `$0A80` disables both CIA interrupt masks, enables the VIC raster IRQ, initializes music/HUD and enables interrupts. The IRQ uses five arrays at `$0A42/$0A47/$0A4C/$0A51/$0A56`, with dispatch addresses at `$0A5C/$0A61`, then acknowledges via `$0D1C`. The table gives the nominal IRQ lines after the initial `$D9` bootstrap.

| Compare line | Handler | Work in the title |
|---|---|---|
| `$38` (56) | `$0CCB` | Text HUD mode (`$1B/$08/$50` for `$D011/$D016/$D018`), colors and border. Attract hides the crosshair. |
| `$4A` (74) | `$0B25` | Bitmap mode, black view, copy sprite shadows, step the frame counter, scan keys/port 2, update the cockpit text scroller and the two matrix bands. The patch samples the SID pots here. `$88` skips the pause logic and much of active-flight IRQ work. |
| `$C2` (194) | `$0C47` | Lower-view sprites, then music call at `$0C5D` and shared effects tick. The music call itself was generally at raster 198–199. |
| `$E3` (227) | `$0C66` | Disable sprites for the transition. |
| `$E9` (233) | `$0C6E` | Switch to text with fine X scroll, update shared cockpit/sprite state, schedule `$38` next frame. |

VIC writes happen after the compare. With DMA enabled, for example, the `$4A` bitmap handoff can write `$D011` around line 74 cycle 60 and `$D018` around line 75 cycle 56. Use the full ordered VIC log to compare split timing.

### 2. SID tune and effects

| Component | Finding |
|---|---|
| Player addresses | Init `$1C70–$1CF1` (130 bytes), tick `$1CF2–$1EB3` (450 bytes), stop `$1EB4–$1EC6` (19 bytes). Mutable player state `$1EC7–$1EDF`, including note pointers, durations, gates and tempo. ZP `$7B–$7D` is the finish flag and temporary stream pointer. |
| Format and tempo | Three independent streams of **pitch, duration** byte pairs. Pitch bit 7 marks a rest. Otherwise the low nibble indexes the low/high frequency tables at `$1EE8/$1EF4` (12 bytes each), then the combined word is shifted right by 7 minus the pitch's high nibble. A zero duration ends playback for all voices. `$1F00=$02` gives one tick per two frames after the third-call startup. Durations count these ticks. Every tick writes six frequency bytes, and a new event writes pulse gate off, then the new gate state. |
| Voice 1 | `$1F01–$1F9E`, 158 bytes, 78 events including 26 rests. `$D400/$D401` frequency, `$D404` gate. |
| Voice 2 | `$1F9F–$1FFE`, 96 bytes, 47 events including 28 rests. `$D407/$D408` frequency, `$D40B` gate. |
| Voice 3 | `$1FFF–$2074`, 118 bytes, 58 events including 25 rests. `$D40E/$D40F` frequency, `$D412` gate. |
| Timbre and filter | All voices are pulse (`$40` gate off, `$41` on). Pulse widths `$B00,$B00,$A00` with ADSR bytes `$59/$AA` for all three. Init clears SID registers `$D400–$D418`, sets `$D418=$0F`, and leaves the filter unselected (`$D415–$D417=0`). |
| End | Each stream totals 2,120 ticks, 4,240 PAL frames of note durations (~84.8 s at 50 frames/s). In the patched reference, init is frame 245, first tick 248, last regular tick 4486, and stop 4488. In the disk payload these are 69, 72, 4310, and 4312. Stop sets `$7B=$FF` and clears `$D400–$D418`. `$0C5D` stops being called while the title keeps running. |
| Input and restart | Fire, F5 or F7 entering the selector calls `$18B4`, clears the three SID controls and clears `$88`. F1 and F3 leave the title music running. RESTORE reaches `$245A`, clears SID and reinitializes the tune as part of the next title. |
| Other sounds | The startup has an eight-write voice-2 pulse setup at `$31EC–$320B` (patched frame 229, direct disk frame 54), while the screen is blank, prior to music init. The unattended active title trace contains no additional siren, beeps, or gameplay sound writes. Menu confirmation does invoke the shared firing/audio path, followed by the distinct welcome and briefing sounds below. |

**Asset locator and trace checksum.** The complete contiguous music player/data image is `$1C70–$2074`, 1,029 bytes raw and 857 packed by `c128-game/build.py`'s `lz_pack`. In the original disk's `SN1` PRG it is file offset `$1472` for `$0405` bytes, including the two-byte PRG load header in the offset calculation. The patched block is identical apart from runtime player state when read after playback. Use the *initial* disk image for byte comparisons or reset the player with init before invoking the tick routine.

I captured the complete ordered SID write sequence in both builds. Restrict the log to writer PCs `$1C70–$1EC0`, including init and the final register clear. Normalize frame to the first included write, keeping order within each frame, then encode each event as `frameDeltaLE16, registerOffsetU8, valueU8` where `frameDelta` is relative to init, register offset is relative to `$D400`, and both builds produce **13,150 writes / 52,600 bytes**, SHA-256 `10743917c6a3c36ed2cdc30eaff062948e3dedb1f3d89cbc3bb9ba27769f0cbd`. This direct event encoding packs to 52,762 bytes, making the player and source streams a much smaller reference. The count comprises 39 init writes, 12,720 frequency writes (six per tick), 366 gate writes (two for each of 183 events), and 25 final clears. The local source block and trace checksum are the asset references in this report.

### 3. Title text scroller

| Item | Finding |
|---|---|
| Data | `$C133–$C344` is 530 bytes including the terminator. The visible text area `$C133–$C31F` is 493 bytes. The following 36 `$40` blanks at `$C320–$C343` precede `$FF`. Other routines reuse that blank tail. On `SN3`, use file offsets `$0135–$0346` inclusive, with the PRG header. `TITLETEXT $1861` is the static title credit block. `SCROLLER $C133` in the symbols is the stream address. |
| Character codes | Direct indices in the custom charset. Letters and digits coincide with uppercase ASCII. `$40` is the text space, `$7A` is the visible dot/separator, and `$FF` ends the stream. The row starts full of the `$60` blank tile. |
| Feeder and raster | `$C345–$C34F` resets the source operand at `$C35E/$C35F`. `$C350–$C375` shifts 39 bytes left in `$5798–$57BF`, inserts one byte at the right and rewinds on `$FF` in that same call. `$13F5–$140F` runs once per top-view IRQ and steps the `$0A4A` table operand through 7 down to 0 for the `$E9` split's `$D016`. CSEL stays clear in this split (38 visible columns). One pixel/frame, a character every eight frames, starting at patched frame 246. RAM `$DB98–$DBBF` is white (`$01`) in the idle title. The view animation changes the bitmap's matrix. |
| Wrap | 529 consumed characters × 8 = **4,232 frames** (~84.6 s) per wrap. Patched rewinds were at frames 4478 and 8710. Scrolling continues beyond the single play of the tune. |
| Text contents, in order | Game name and 1984 Synapse Software Corporation copyright, F5 for the difficulty menu, F7 to start, a catalog of other Synapse games, a teaser for the Dimension X follow-up on Jaraloba, and the publisher sign-off. The 1351 version prepends Burwor's credit plus mouse controls (left shoots, right opens map, both launch a torpedo), and shortens the catalog. The original stream and its decoding are identified above for local inspection. |

### 4. Difficulty selector

| Item | Finding |
|---|---|
| Entry | F5 is scanned into `$FDE3` at `$FDEE` and checked at `$85FE`, only while attract is set. F7 (`$FDE4`) and raw port-2 Fire at `$DC00 & $10` are polled by the slower main-loop pass at `$2DC0–$2DFC`. Each reaches `$8609`. Patched F7 pressed in frames 300–306 entered at 306 and reached the ready loop at 316. Patched F5 pressed at 300 entered at 302. |
| Transition and layout | `$18B4` clears title sound and flags, erases the view and scroll row, then restores the lower cockpit. `$8712–$8767` prints the five labels from `$1915–$1938` via `$27CD`. Tile rows 6/8/10/12/14, centered at columns 11/12/13/11/9, with stars, HUD, radar and a crosshair. Default top row and highlight use matrix `$17` (yellow ink). Other rows use `$19` (brown ink), and `$8779/$8784` recolor the active and previous rows. The cursor starts at `$120A=$5E`. |
| Selection | Original `$864A` waits for a port-2 direction (any of bits 0–3 active) before allowing the crosshair to move off the initial row. `$878F` then samples it every 200 menu-loop passes, typically about 6–7 observed frames. `$87C6` stores `$E0`. Y boundaries are `$66,$76,$86,$96`, so row 0 is Y < `$66`, row 4 starts at Y = `$96`. Vertical movement selects the levels. Horizontal movement alone can release the initial hold. In the patched JS raw-port trace bit 0 increased crosshair Y and bit 1 decreased it, so check direction conventions in the frontend. |
| 1351 and keys | v10 changes `$864A` to load `$96` and can therefore see mouse-synthesized directions. The patched crosshair hook updates position from pot deltas and the left mouse button is Fire. Confirm at `$867F` is `$97` only. F7 or Space by themselves in the selector do not confirm or exit it. A continuous Fire press can reach the confirmation check once the menu is ready. Keyboard arrows on the web use the frontend joystick mapping. One v10 1351 trace entered with left click at frame 300, moved through all five levels via pot deltas and confirmed level 4 at frame 477. |

The system HP list runs from `$39` to `$40` in this order. Phasors, long-range scanner, short-range scanner, Stellar Grid, tracking computer, hyperspace coordinator, long-range scan sequencer, and communications. The shield table is at `$844A`. HP tables start at `$8427` in five-byte columns. Boot loads 8 protons at `$25D5`, including on restart. `$8451` reads `$8450` to update the proton display. I confirmed all five rows with the patched menu using joystick direction and Fire.

| `$E0` | Menu spelling | Squadron placement calls | Shields / protons | Starting system HP | Corner-base warp/spawn mask | Max rating class |
|---|---|---:|---|---|---|---:|
| 0 | SKIRMISH | 10 | 40 / 8 | 255, 255, 4, 6, 3, 4, 2, 255 | off | 3 |
| 1 | ASSAULT | 15 | 30 / 8 | 10, 10, 3, 4, 3, 4, 2, 255 | off | 4 |
| 2 | BATTLE | 24 | 25 / 8 | 5, 6, 2, 4, 3, 4, 2, 255 | `$7F` | 5 |
| 3 | INVASION | 31 | 25 / 8 | 5, 4, 2, 4, 3, 4, 2, 255 | `$7F` | 6 |
| 4 | ARMAGEDDON | 44 | 25 / 8 | 5, 4, 2, 4, 3, 4, 2, 255 | `$3F` | 7 |

The bitmap calls level 1 **ASSAULT**, which the manual lists as **Attack**. Corner bases and friendly bases exist at every difficulty. The mask governs subsequent events at `$9F9A`. Masked sector tick `$30` attempts adjacent reinforcements and `$15` may move corner bases in or out. The original can generate one fewer surviving squadron than placements because it clears the starting sector **after** the placements. For example a patched level-4 trace made 44 placements and kept 43 groups. Several in-game rules also read the same difficulty index.

| Difficulty-sensitive mechanic | Levels 0 / 1 / 2 / 3 / 4 and source |
|---|---|
| Enemy-proton delay parameter | 10 / 8 / 7 / 7 / 6 at `$284B`, read at `$28E4`. |
| Fighter placement and approach | Coordinate mask `$3F/$3F/$3F/$4F/$4F` and origin addend `$66/$66/$66/$55/$55` in `$3D4C/$3D52`. Easier levels also flatten designated approach coordinates via `$B5BA/$C69B`. |
| Automatic dogfight tracking | Step reload 8 / 7 / 7 / 6 / 6 from `$89CB`. Drift reload `2 * DIFF + type offset` (type offsets 4, 3, 3 at `$89DA`, with the carry from ASL clear for levels 0–4). |
| Enemy fire | Delay reload `$FF/$B0/$70/$40/$10` and substep divisor 3 / 3 / 3 / 2 / 2 at `$C913/$C918`, used at `$C947`. Level 4 selects a different speed scaling at `$C95C/$C9FC`. |
| Mines | Step delay 3 / 3 / 2 / 2 / 1 at `$CC27`, random mask `$0F` at every level (`$CC1C`). |
| Rating | Cap table `$F5B3`, victory bonus `(level+1)*256` (`$F456`), Jaraloba loss penalty `64<<level` (`$F51D`), extra low-level defeat display condition at `$F3DA` for levels 0–2. |

### 5. Confirm, welcome, briefing, and first map

The frame example below is the patched PRG with DMA from 250, Fire held in frames 300–307 for entry and 400–408 for confirmation, then released for the complete intro. Numbers in parentheses are relative to the first accepted confirmation at frame 400. The countdown milestones after `$96AA` are governed by the IRQ. The preceding main-loop fade varies slightly with input and raster timing.

| Phase | Routine and observed timing |
|---|---|
| Confirm | `$867F–$869A` accepts `$97` at **400**. Clears the menu flags, waits for the shared phasor handshake `$D1`, invokes `$1467`, rebuilds the world at `$20F1`, then initializes systems/shields and refreshes proton/shield digits with `$8451` (**402**). |
| Welcome ribbon begins | `$86AE → $9BE5` starts the message at **402**. This use of the symbol `PRINTBIG` targets the **bottom text ribbon** at `$5798`. Configuration `X=3` and `Y=$2A` gives 42 ribbon color/beep updates. The shared `$13D5 → $9CD3/$9D20` steps fine X by 2 pixels/frame and shifts a cell every four frames. `$DB98` alternates colors 0 and 1, then settles on 13. Beeps use voice 2 pulse via `$9D4A`, frequency `$3F00`, pulse width `$300`, AD/SR `$02/$00`. Updates were **413–905**, every 12 frames. |
| Retain selected level | `$86B8–$870F` writes SID master `$1F`, erases the four other menu labels and fades the view background through `$BABB`, then erases the retained label. In the reference, `$96AA` starts at **555** (+155) while the ribbon is still active. |
| Open the upper strip | `$96AA` prepares six rows of `$5400` text and color RAM below the three HUD rows, positions the white side glyphs `$61/$62`, initializes `$9909=$50` and the two-frame typing divisor. `$972B` waits for the ribbon job `$9BE3` to finish. First `$9768` step **905**, last **952**. One increment of `$0A5A` per frame over 48 frames extends the **text raster window**. The actual compare programmed for that frame trails the state update. |
| Opening registers and colors | The top compare stays at `$38`. The bitmap resume compare advances `$4A → $7A` (74 to 122 decimal, +48 scanlines). During the extended strip, `$D011/$D016/$D018=$1B/$08/$50`. At its bottom the normal raster handler restores `$3B/$18/$18`. `$D020/$D021` and the extra writes at `$0CCB` establish the border and grey text field, which carries white briefing characters, white side rules and the existing HUD colors. Each step retriggers the voice-1 triangle tick at `$97B9` with frequency `$8200`, AD/SR `$03/$00` and control `$11`. |
| Type the briefing | `$990C` points the writer at `$9821` and destination `$5478`. `$992B → $995B` writes **one character every two frames**, including spaces and embedded border glyphs, after the bar has opened. The first byte is at **952**, the last at **1412**, and the terminator at **1414** (+1014). The glyph writer clicks on all codes except `$40` (174 clicks in this trace). Voice 1 triangle, `$6200`, AD/SR `$02/$00` at `$9973–$998D`. Briefing text reports widespread enemy detection and the four friendly stations, then ends with END OF TRANSMISSION. |
| Wait, close, map | `$9952 → $9715` loads a 240-frame hold. The bottom briefing row flashes colors 1/15 every 40 frames after typing. `$9795` then lowers the split one line per frame in **1654–1701**, clears the extra text and arms `$BB/$B8=$0A`. `$FB43` starts map handling automatically and `$FB70` requests the grid wipe. The first `$B26D` map sound in this trace is **1708** (+1308). Map drawing then continues over subsequent frames. |
| Early Fire/Space | `$998E` is polling code, with no separate printed prompt string. `$96A7` initially delays its input poll (12 calls), then `$99A1` aborts the ribbon/text/bar, clears fire and sprite state, restores `$0A5A=$4A`, sets `$B8=1,$B9=0` and arms the map. This can skip the welcome and briefing once polling is active. Verified on the direct disk trace with Fire 125–132, Fire 225–232 and Space 820–827. The first grid sound was at **827** while the briefing was still typing. |

`$97D9–$9908` is 304 bytes of strings including both terminators. The requested 306-byte span through `$990A` also includes two delay variables. The welcome ribbon uses `$97D9–$9820` (72 bytes, `$FF` terminated), and the briefing uses `$9821–$9908` (232 bytes, `$FF` terminated). The latter has exactly 231 glyph codes. It is laid out as pre-padded rows, with `$61/$62` side characters, `$40` spaces and `$7A` punctuation. In `SN1` these start at PRG offsets `$8FDB` and `$9023`. The same bytes occur in both local builds.

| Shared world/HUD order | Addresses and values |
|---|---|
| Cold title | `$2594 → $20F1` once before the title with `$E0=0`. Then copy the 120-byte HUD template `$CE89–$CF00` to `$5400`, color the rows/dividers (`$265A/$269A`), seed the text footer and title scroll, prepare sprites/fighter movement, load 8 protons and `$8451`, install IRQ, and set energy to 9999 at `$F86C`. `$25ED` stamps the white corners and sides. The title HUD shows SHIELDS 40, PROTONS 08, ENERGY 9999, SECTOR 05.03, TIME 00:00, TARGETS 00. |
| New world after confirm | `$8694 → $20F1` again using the final `$E0`. Clears STATE and COUNT (`$033C–$0377` and `$0378–$03B3`) plus 120 scratch bytes at `$BDB1`. Writes player and selected map cell X=4/Y=2 (`$92/$93`, mirrors `$DF/$DE` and `$20E2/$20E1`). Seeds blue bases at cells 12/17/42/47 (`$FF`, count 0), orange at 0/9/50/59 (`$80`, count 1). `$225D` places randomly typed 1–3 groups of 3–9 ships only in empty cells, from `$BA85` (seed byte, raster and SID oscillator output). Clears index 24 (the player sector) last. |
| Play handoff | After `$18B4` clears attract, the world clock and energy resume subject to the menu/game flags. The intro can therefore show an already-running time/energy HUD. `$84B5` updates TARGETS from the current sector. `$FB43/$FB70` clear/prime the map view and start `$B094` grid draw. `$21C8/$216D` handle selection and marker drawing. At the map, Fire or Space confirms the cursor sector. The current sector closes the map. Another sector takes the jump path. |

### 6. Attract and reset paths

| Item | Finding |
|---|---|
| Attract state | `$18AA` sets `$88=1` and `$13D4=1`. It runs the starfield, lower cockpit animation, title color work, the scrolling text and the one-shot tune. The no-input trace stays in the title and continues scrolling after the tune through frame 4800 on the disk and frame 9000 on the patched build. The code guards normal pause, crosshair, energy, map and approach paths with `$88`. No autonomous battle or timed scene rotation was observed. |
| Pause and timers | `$0B69` skips F1 pause when `$88` is set. Outside attract F1 sets pause `$9F`, mutes `$D418`, and joystick activity resumes. `$F845/$F846` are IRQ-alive watchdog state. Main/menu checks at `$2D98/$8672` reset only if the counter reaches zero **and** the IRQ has failed to latch `$F845`. This is distinct from tune length, scroll wrap and gameplay timing. |
| F7 and game over | Title F7 enters the menu, while active play checks `$FDE4` in `$99F3` and branches to `$245A` through `$9A00` (also a main-loop path through `$2DE9`). After the map was open, F7 restarted the direct disk trace at 618 and the patched trace at 790. `$99F3` tests shields lost `$8300` and planet lost `$F431`, then branches to `$8869` for the report sequence. Ending and victory paths return to the same game entry after their own end/report waits. Prior DMA comparisons cover these transitions. [Overlay plan](memory-overlay-plan.md#93-step-4-the-ending-package), [game-end tests](../js/test/game-end.js) |
| RESTORE | In the running game RAM NMI points at `$0AB9`. The handler masks IRQ, selects `$01=$36`, restores the two bitmap pages `$6000/$6100` from `$0600/$0700`, and jumps to `$245A`. Tested via `cpu.nmi()` on the patched menu at frame 850, where the same frame reached `$245A` and the title IRQ was active again at 920. This is a CPU NMI test. Physical RESTORE key delivery and KERNAL-visible edge cases need a hardware/VICE check. |
| Reset effects | `$F6C1–$F844` clears `$E0` to 0, pause/input and fight flags, map/sector scratch flags, ending/rating counters, shield/planet-loss flags, and the watchdog. `$245A` reinitializes the raster, bitmap and ship state, creates a new world, resets the scroll pointer via `$C345`, and reinitializes the tune. The initial world is regenerated after the next difficulty selection. |

### 7. Asset inventory and measured sizes

Sizes below are measured by feeding the indicated bytes to the current C128 `lz_pack`, with each row compressed independently and **no** headers, alignment, relocation or copy cost. Joined totals are separately compressed. Runtime byte counts include writable state where listed. Shared routines are dependencies and are listed separately so they can be budgeted once.

| Title/intro-specific block | C64 range (inclusive) | Raw / packed bytes |
|---|---|---:|
| Static title glyph codes including the eight logo characters | `$1861–$1899` | 57 / 58 |
| Title palettes, stripe index/pattern and scratch | `$189A–$18A9` | 16 / 17 |
| Set attract and enter title | `$18AA–$18B3` | 10 / 11 |
| Leave title for menu | `$18B4–$1914` | 97 / 94 |
| Five difficulty labels | `$1915–$1938` | 36 / 37 |
| Title recolor, lettering draw and matrix-band update | `$196B–$1A98` | 302 / 276 |
| Glyph routines and bitmap string wrapper, reusable by the menu | `$0816–$08E4`, `$27CD–$280B` | 270 / 259 |
| Title scroller stream | `$C133–$C344` | 530 / 452 |
| Title scroller pointer/reset and character feeder | `$C345–$C375` | 49 / 50 |
| Five-split table including shared entries, plus title-side smooth-scroll code | `$0A42–$0A66`, `$13F5–$140F` | 64 / 65 |
| Selector and F5 entry | `$85FE–$87F8` | 507 / 484 |
| **TITLE + selector subtotal** | Above rows concatenated in table order | **1,938 / 1,772** |
| Music code / mutable state / note tables and event streams | `$1C70–$2074` as one block | **1,029 / 857** |
| Intro controller, prompt, strings and state | `$96A4–$99F2` | **847 / 800** |
| Intro controller with strings excluded | `$96A4–$97D8`, `$9909–$99F2` | 543 / 512 |
| Welcome and briefing strings only | `$97D9–$9908` | 304 / 288 |
| All title glyph write values as gathered from printer destinations | 7 rectangles, footprint from `$6520` to `$74F7` with gaps | 1,808 / 409 before coordinates. Derivable from the font and layout |
| Shared bottom ribbon setup/step/voice-2 beep | `$9BDC–$9C5B`, `$9CD3–$9D6C` | 282 / 275 |
| Shared world initialization and group placement | `$20F1–$215B`, `$225D–$22B9` | 200 / 201 |
| Shared difficulty/ship initialization and HUD digits | `$8422–$84B4` | 147 / 137 |
| Shared HUD template | `$CE89–$CF00` | 120 / 108 |
| Shared live font / lower cockpit bitmap / 2 screen matrices | `$4000–$43FF` / `$7680–$7CBF` / `$4400–$47E7` + `$5400–$57E7` | 1,024 / 564, then 1,600 / 254, then 2,000 / 212 at the sampled title frame |

The C128 build already contains the matching `$4000–$43FF` charset (byte-for-byte against the disk and the running title), a captured cockpit bitmap with radar cleanup, gun/crosshair/planet sprites remapped to its VIC slots, shared screen and color masters and plotters. The port maintains bitmap matrix `$4400`, text screen `$4800`, and the writable view `$63C0–$767F`. It has shared difficulty values and movement tables, `SHIPINIT`, world/sector init, cockpit/ending text code and automatic map drawing primitives. The title lettering is generated in the C64 view and has no pre-rendered standalone logo in the C128 pack. Remaining work is the title and selector presentation, scroller, title audio, intro sequencing, line-by-line bar opening, and routing boot/reset into those overlays.

### 8. Extra details and version differences

| Item | Finding |
|---|---|
| Credits | Disk title uses the two fixed fields for **THE BAD BROTHERS**. v10 replaces them with **SYNAPSE SOFTWARE**. Both proceed through PRESENTS, SENTINEL, CREATED BY and BRYAN BRANDENBURG. The 1984 copyright and ads are in the scroll, separate from the fixed lettering. |
| Port 2 only | Stock game reads joystick port 2. v10 samples `$D419/$D41A` in `$02DB`, normally after holding CIA1 selection at `$BF`. POTX `$FF` falls back to joystick. Mouse buttons share fire/up wires, and right is handled separately in the patch. The 1351 has **automatic detection and scroller help**, with no native detection prompt observed. The itch frontend can show its own input-mode overlay. |
| F3 | The key is read into `$FDE2`, consumed by the docking path at `$9403`. It did not affect the title. |
| High scores and extras | The native game has an end rank/rating. No native title high-score table, language switch, user color toggle or sound-test screen was found in the entry/input paths or unattended title trace. The browser's persisted scores are a separate feature in `js/src/hiscore.js`. |

### 9. C128 overlay proposal

| Package | Bank-1 store / live placement | Budget and reuse |
|---|---|---|
| TITLE + selector | Use the reserved bank-1 TITLE region from the plan (`$8C00–$99FF`), loaded into S1 `$E960–$F6F8` with the existing `$0100–$0154` copy stub and overlay manager. | The surveyed blocks are 1,938 raw / 1,772 packed. Allow about 2.1–2.4 KB live after input/overlay glue. Use the existing cockpit font/art/sprites and draw into the protected view window, with new scroll copy and resident controller inputs. |
| MUSIC | Store its data with TITLE or after its reserved area if redirected by the build. Keep player/state and streams resident in S1 for the title's lifetime. | 1,029 raw / 857 packed for the reference. Original TITLE+music joined is 2,967 raw / 2,628 packed, 514 bytes under S1 raw. Target 3.1–3.4 KB before committing the layout. Every-frame bank switching for music is avoidable. Keep stock music as the local comparison source and use music data authorized for distribution. |
| INTRO | Planned bank-1 INTRO region `$9A00–$A7FF`, next owner of S1. | Original controller/text plus complete shared ribbon block totals 1,129 raw / 1,068 packed. Reserve about 1.2–1.5 KB until the port's existing text writer and beep can be measured. Keep the first map's initialization and dispatch resident. |

The 3,481-byte limit is the **expanded live slot**. New bank-1 bytes also need to reach the computer in the distributed PRG. The surveyed reference blocks together pack to **3,654 bytes** before headers. The current `sentinel-c128-game.prg` is 57,312 bytes, loads at `$1C01` and ends at `$FBDE`, leaving **801 contiguous bytes** before `$FF00`. The historical staging estimate in the plan predates this image. Measure actual compressed staging holes in the current build and use the proposed outer archive or a smaller package set if they cannot fit. The original screen matrices, cockpit bitmap and SID trace need no duplicate staging allocation.

| Implementation step | Verification |
|---|---|
| 1. Add owner IDs, loaders and a resident boot/end-reset transition. | Inspect bank-1 source ranges, S1 bounds and cancellation of live IRQ/overlay hooks before each owner transfer. Fill the remaining slot with a sentinel pattern in tests. Confirm title after cold boot and after death/victory without leaving a MINES/ENDING hook live. |
| 2. Build the static cockpit title and efficient sprite/palette/scroller updates. | Capture the HUD, logo, graphics and bottom-row positions in JS screenshots at corresponding phases. Test `$D016` sequence, 38-column clipping, character step, terminator wrap and restore-to-flight. Keep bitmap writes out of relocated sprite and art slots. |
| 3. Add the music tick and explicit release when leaving TITLE. | Capture all `m.sidLog` triples before the next frame resets the buffer, with frame numbers and PC writer provenance. Assert update cadence, control/ADSR/filter writes, end silence, and cancels for F5/F7/Fire. For an authorized matching source tune, compare the normalized event hash above. Keep raster cycle checks separate from register-value equivalence. |
| 4. Wire the selector into resident `DIFF`, world and ship initialization. | Test all five levels and both controllers, actual confirmation, repeated title entry, system tables, and deterministic map generation with a fixed seed. Exercise the held-Fire edge and confirm that F1 does not pause the title. |
| 5. Implement the intro as timed jobs and map handoff. | Move the next compare by one line per frame, with the graphics mode/matrix switch in the resident raster handler. Keep map/game counters and voice-3 noise RNG ownership defined across TITLE/INTRO. Compare screenshots at the 0/24/48-line positions and during typing. Check 2-frame glyph pacing, close, auto map, and early Fire/Space. Keep VIC-IIe at 1 MHz for visible splits. Schedule bulk copy in a blanked window or within the current overlay deadlines. Validate PAL timing in JS and in x128 or on hardware. |
| 6. Finish play/reset integration and itch parity. | Restore cockpit matrices and shared SID/input state before play. Verify automatic and skipped intro both lead to the same playable grid, and that first hyperspace can preload MINES before a base. Exercise the itch `game` profile through its real keyboard, pad and pointer mappings, cold load, sound unlock, skip, map and reset. The C64 profile's fast depack and two browser IRQ fixes should be explicit in reference comparisons. |

### Summary and open checks

The title is a cockpit-and-starfield scene with generated bitmap lettering, a continuous eight-frame-per-character scroller and a one-shot SID tune. Confirmation rebuilds the world at the selected difficulty. The intro opens 48 raster lines for the briefing, then closes them before handing off to the Stellar Grid. The measured code and data fit S1 one package at a time, and load-time staging needs more space.

- Confirm the retail publisher/title presentation from a retail disk if that distinction matters. The two supplied images establish the repository disk and v10 behavior.
- Confirm actual VIC-IIe write deadlines, SID sound across 6581/8580, NTSC timing, and physical 1351/RESTORE input in VICE or on hardware. JS verifies the register sequence and uses an approximate DMA model.
- Measure final rewritten package sizes against the currently loaded PRG staging ranges, and decide whether the C128 keeps an early intro skip, the original held-Fire behavior and the automatic map timeout as part of its user-facing flow.
