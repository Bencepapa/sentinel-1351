# Survey and plan: bank 1 overlays for the C128 game

Status (2026-11-17, later): steps 0-1 (measurements, bank 1 in the JS machine) and
**steps 2-4 are done** (the bank-1 store, the overlay slot S1 with MINES, the ENDING
package): see section 9 for what was built, where it differs from this plan, the new
memory map and the free bytes. **Later the same day the exit to BASIC was removed**
(the user's decision: RUN/STOP does nothing, BASIC's memory is the game's): section 10
has what went and the current free-byte table; it supersedes the EXIT parts of 5.1,
5.2, 9.1 and 9.4. Sections 1-8 are the survey as written before. Read first: `PLAN-C128-COCKPIT.md` ("Status",
"Handing the work on"), `c128-game/README.md` ("How it is built", the memory map
and the 2026-11-11/15/17 sections), `briefs/memory-rearrangement.md`.

## 1. Key decisions (summary)

1. **Bank 1 becomes the store** (63 KB, today 0 bytes used). VDC RAM stops being
   the ending's store and is freed for the 80-column display (the map/system screen,
   the box cover).
2. **One transfer primitive in common RAM**: a 64-byte stub at `$0100-$013F` (stack
   page bottom; common to both banks, the game's stack never goes below `$01EA`)
   that copies bank 1 <-> bank 0 by toggling the MMU preconfiguration registers
   (`STA $FF02` / `LDA (CSRC),Y` / `STA $FF01` / `STA (CDST),Y`: 24 cycles a byte).
3. **Packages are stored raw in bank 1, linked at fixed addresses, copied, never
   relocated and never unpacked at run time.** A copy is resumable (N bytes a frame),
   an unpack is not; raw copies also keep every page crossing of raster code.
   Compression is used only at load time (the PRG window).
4. **One time-shared slot, S1 = `$E960-$F6F8` (3,481 bytes)**, today the init
   helpers plus the minefield/tunnel. Its owners never overlap in time:
   MINES (base sectors) / ENDING (after death or victory) / TITLE (before play) /
   INTRO (the first seconds of play). The raster tunnel stays at its present address
   (`MNSTART = $EA16`) and is loaded during the hyperspace jump into a base sector,
   long before its IRQ chain starts; the slot is never written while
   `$D01A` bit 0 is set or `$FFFE/$FFFF` points into it.
5. **The ending's resident workspace `$0200-$0C5F` is freed**: a ~360-byte ending
   core stays resident (the per-frame check, death flash, statistics), the other
   ~2,290 bytes become the ENDING package in S1. With the untouched `$19F9-$1BFF`
   (519 bytes) this gives **about 2.6 KB of new resident space** for gameplay
   features (sector cleared, damage warnings, issue fixes, the live VDC display).
6. **Load capacity**, not bank 1, is the real limit: the PRG window `$1C01-$FEFF`
   is 58,111 bytes and the PRG already uses 54,879. The title fits in the 3.4 KB that
   is still free at load time only if its data is small; the box cover, a longer tune
   and VDC assets need an **outer packer**: the whole current PRG packs to 38,029
   bytes with the game's own `lz_pack` format (31,492 with deflate), leaving about
   **19.5 KB** of packed bank-1 archive in the same single PRG.
7. **Reset returns to the title** through: ENDING restores the snapshot (from bank
   1) -> load TITLE into S1 (screen blanked, synchronous) -> title -> difficulty ->
   load INTRO -> intro -> automatic map -> play. First boot takes the same path after
   init.

## 2. The measured memory map (current build, working tree of 2026-11-17)

Build output (scratch build, identical PRG):
`memory left: high 2 bytes ($F6F7-$F6F8), packed 91 bytes, glue 1 byte; low stream
3189 bytes` and `ending memory: workspace 8, loader 3, VDC 256 bytes free of 16K
(snapshot $0A60-$3684, payload $3700 1895 bytes in 8 pages), 23 snapshot ranges`.
PRG `$1C01-$F25F`, entry `$1D00`.

### MMU and banks

- START: `SEI`, MMU CR `$0E` (bank 0 RAM, I/O, KERNAL ROM), then init `$3F`
  (all RAM, init only), gameplay `$3E` (bank 0, all RAM, I/O). EXIT restores the
  caller's CR. Nothing touches bank 1, `$D506` (RCR) or the preconfiguration
  registers `$D501-$D504`. **Bank 1 is entirely unused.**
- Common RAM: the KERNAL's default RCR (1 KB at the bottom, `$0000-$03FF`); zero
  page and stack are always bank 0. The game uses zero page only at `$FB-$FE`
  (`CSRC`/`CDST`/`PTR`/`MP`). Minimum stack pointer measured in flight and
  map open/close: `$EA` (JS entry); `$0100-$01BF` is never reached.
- The game's NMI/IRQ vectors at `$FFFA/$FFFE` (bank 0 RAM) point to `NMIRTI` in the
  `$C000` glue; only the tunnel installs a real IRQ (`MTIRQ`), through mines hooks.
- 2 MHz is used in the vertical border (lines 251-47) every frame and during init.
- JS machine (`js/src/machine.js`): one 64 KB RAM (no bank 1), MMU registers
  zeroed (not the KERNAL values), CR bits 6-7 ignored, VDC RAM 64 KB (a flat C128
  has 16 KB). **Bank 1 must be added to the JS machine before anything else.**

### Bank 0 by lifetime (condensed; the full table is in `c128-game/README.md`)

| Range | Bytes | Contents | Needed |
|---|---|---|---|
| `$0200-$0C57` | 2,648 | ending workspace (code+state), originals saved in VDC | ending; 360 bytes of it every frame |
| `$0C58-$0C5F` | 8 | free | - |
| `$0C60-$19F8` | 3,481 | relocated low block: MS*/MR* base sequences, positioning, enemy proton (M only); battle-message queue `GBT*`, end-event hooks, `MSCOUNT`, `MSARRIVE` (all modes). Frozen symbols. | mixed |
| `$19F9-$1A09` | 17 | `ENDCROSS` (issue #20), part of the low block (`LOWEND` = `$1A0A`; the boundary test writes `$B6` there) | victory |
| `$1A0A-$1BFF` | 502 | **untouched** (C128 BASIC's free ML area) | free |
| `$1C01-$1CFC` | 252 | BASIC stub, ending loader `ENDINIT`/`ENDRESTORE`/VDC I/O | init, EXIT |
| `$1D00-$52FF` | | cockpit chunk 1, masters, tables, font, screens, sprite slots, matrix master, helpers | resident |
| `$5300-$5DFE` | 2,815 | glue (frozen) | resident |
| `$5E00-$7FFF` | | streams, sprite slots, 3D-view bitmap, cockpit art | resident |
| `$8000-$84FF` | 1,280 | type-1 movement streams (mines borrow `$8100-$83FF`) | F/D |
| `$8500-$BFFC` | 15,101 | cockpit chunk 2, map, repair helper | resident |
| `$C000-$CFF9` | 4,090 | high glue, hyperspace | resident |
| `$D000-$DFFF` under I/O | | init staging; runtime `$D200-$DFA9` = original low-RAM backup (3,498) | EXIT |
| `$E000-$E95F` | 2,400 | proton/type/hyperspace code | resident |
| `$E960-$EA15` | 182 | `GINIT3` (init), `GLOWCOPY`, `GREXIT` (EXIT) | init/EXIT only |
| `$EA16-$F6F6` | 3,297 | minefield + tunnel (`MNSTART`..`MNEXTRAEND`, incl. 398 packed art, `MTIRQ`, `MNSTREAM`) | M only (+`MNREQUEST` in the torpedo path, `MNSTREAM*` at reset) |
| `$F6F7-$F6F8` | 2 | free | - |
| `$F6F9-$FEFF` | 2,055 | `TORPA` + `TSHOT` | F/D/M |

Truly free bank-0 bytes today (after issues #18-#21): 2 high, 1 glue, 0 workspace, 3 loader,
9 helper pad (`$52F7-$52FF`), 6 in the old ARRSTEP block (`$5B1B-$5B20`), 502 at `$1A0A-$1BFF`
(but the low archive's staging has only 1 byte left below `$DF00`, and its backup at most 86
more below `$E000`), about 150 scattered alignment bytes; under I/O `$D000-$D1FF` and
`$DFAA-$DFFF` after init (data only, MMU `$3F`).

### Load-time window (single PRG, KERNAL LOAD stops at `$FF00`)

58,111 bytes (`$1C01-$FEFF`); used 54,879 (`$1C01-$F25F`). Still unused at load:
`$F260-$FEFF` (3,232; must be consumed before `GINIT2` decodes the high image
there, as the ending staging is), 91 packed-image bytes before `$7680`, 114 bytes at
`$DF8E-$DFFF`.

Packing measurements of the PRG body (bytes): whole body `lz_pack` 38,029, deflate
31,492, LZMA 28,110. By region (`lz_pack` / deflate): cockpit chunk 1 + assets
8,960 -> 4,802 / 3,838; font/screens 4,096 -> 1,421 / 1,099; cockpit art + sprites
2,432 -> 693 / 592; type-1 streams 1,280 -> 216 / 132; cockpit chunk 2 9,376 ->
7,762 / 6,030; map 5,728 -> 4,794 / 3,684; `$C000` 4,096 -> 3,730 / 2,991; the
ending staging 4,704 -> 3,907 / 3,236; already packed streams barely change.

### VDC RAM (16 KB assumed; it is the ending's store today)

| VDC range | Bytes | Contents |
|---|---|---|
| `$0000-$0A5F` | 2,656 | original bank-0 `$0200-$0C5F` (for EXIT) |
| `$0A60-$3684` | 11,301 | reset snapshot (23 ranges, bridged gaps) |
| `$3685-$36FF` | 123 | alignment |
| `$3700-$3EFF` | 2,048 (1,895 used) | payload: victory text (240), death reports + rank names (RLE), display masters `$4400-$4BFF` and `$7680-$7FFF` (RLE) |
| `$3F00-$3FFF` | 256 | free |

The display is blanked at START (`ENDVDCBLANK`: registers 25/26/10) because these
bytes overlap the boot screen, attributes and font.

## 3. Modules by when they are needed

| Class | Modules (size) | Plan |
|---|---|---|
| Always resident | cockpit, map, glue, high glue, hyperspace, TORPA/TSHOT, battle messages, statistics hooks, `MNREQUEST` (20) | stays |
| Raster-critical | cockpit split schedule (polled), `MTIRQ`/`MTFRAME`/`MTPAINT` tunnel (in MINES), future intro panel split, future sprite multiplex (#5) | resident at a fixed address before use; never evicted while running |
| Per base sector (M) | MINES 3,297 at `$EA16`; MS*/MR*/ET* parts of the low block (~3 KB, frozen in place) | MINES -> S1 package; low block stays (frozen) |
| Once per game, end | ending package ~2,290 (+ 360 core) | ENDING -> S1 |
| Before play | title, menu, music, scroller (new, ~2-2.6 KB code) | TITLE -> S1, data in bank 1 |
| Early play | intro: welcome scroll, top-bar opening, typed Starfleet message (new, ~0.8-1.2 KB code) | INTRO -> S1 |
| Init / EXIT only | `GINIT3` (init), `GREXIT` 38, `ENDSETUP`/`ENDCOPY` save direction | init: before S1 is used; `GREXIT` -> resident |
| Store only (never executed) | EXIT backups (2,656 + 3,481 + 519), snapshot 11,301, payload 2,048, type-1 stream master 1,280, texts, music notes, VDC charsets, box cover | bank 1 |

## 4. Size estimates of the new features

From the original (`Sentinel-1351_v10`, traced in the JS machine without `m.dma`:
with `m.dma = true` from frame 0 the original stops at a grey screen at `$F16D`
with no music; set DMA only after frame 250). Coverage of code executed in the
title/menu/intro phases and never at boot or in 1,500 frames of play: 1,861 bytes.

- **Title screen** (cockpit, HUD, stars; "SYNAPSE SOFTWARE PRESENTS / SENTINEL /
  CREATED BY BRYAN BRANDENBURG" in bitmap letters with colour cycling; text at
  `$1861-$18A9`, code `$14CE-$1609`, `$1978-$19E7`). Port: 600-800 bytes code.
- **Scroller** in the bottom text row (`$C134-$C33F`, ~520 bytes of text, code
  `$2DCF-$2DFB`). Port: ~150 bytes code (the message row's `STRIPX` fine scroll
  exists), text in bank 1 read a byte at a time.
- **Music**: the original has title music: a 3-voice player, init `$1C6x-$1CF1`,
  play `$1CF2-$1EC6` (called from `$0C5D`), state/frequency tables `$1EC7-$1EFF`,
  notes `$1F00-$2074` (voice pointers `$1F01`, `$1F9F`, `$1FFF`; two bytes a note;
  plays once, then silences the SID). About 1,045 bytes in all, ~600 of them code.
  6 SID writes every 2 frames. A port of this player is ~550 bytes of S1 code; notes
  stay in bank 1 (any length). A new, longer tune: 1-3 KB of notes, bank 1 only.
- **Difficulty menu** (SKIRMISH ... ARMAGEDDON in the view, crosshair selection;
  `$8609-$8775`, `$878F-$8798`, `$18B4-$1914`, names `$1915-$193B`). Port: ~400
  bytes; choosing re-runs `SHIPINIT` and the map's start layout for `DIFF` (the
  layout patch "only once" must allow a rerun after the snapshot restore).
- **Intro** (after the menu, with the game clock running): "WELCOME ABOARD
  CAPTAIN, STANDBY FOR MESSAGE FROM STARFLEET COMMAND..." scrolls in the bottom row;
  then the upper HUD panel grows down over the view (about 3 rows, a raster split),
  the message is typed letter by letter ("GORGANITOR SQUADRONS DETECTED IN ALL
  SECTORS ... GOOD LUCK..."), "END OF TRANSMISSION." flashes, the panel closes and
  the automatic map opens (about 25 s in all). Text `$97D9-$990A` (306 bytes),
  code `$96AA-$972A`, `$9762-$9794`, `$990C-$9993`, `$9CFF-$9D1F`, panel/split
  `$3252-$3276`, `$3371-$33B2`, `$3596-$3626`. Port: 0.8-1.2 KB code (the split is
  the delicate part), text in bank 1.
- **(a) Sector cleared**: original `$3CDE-$3D1F`: clears the cell (`$033C,X`,
  `$BDB1,X`, `$BDED,X`), prints `$3C84` "SECTOR CLEARED CAPTAIN" through `$9C5C`
  (colour `$81`, `X=$0F`, `Y=$20`), then sets `$B8=1`, `$BB=$37`, `$C376=1`
  (check: the map opening). Also `$3CA4` "SQUADRON DESTROYED SIR". Port: 60-120
  bytes resident through the existing kill hook (`ENDKILL`/`SECKILL`) and the map
  opening used after base sequences.
- **(b) System damage**: the port's `SHIPHIT` sets `SYSLAST` where the original
  prints "... DESTROYED" (`$84F2`, texts `$8301-$83FC`, 250 bytes). Port: 150-250
  bytes resident (names from the resident repair table `$2F50` + suffix, or the
  original texts fetched from bank 1 into a 32-byte buffer), a warning sound ~30.
- **(c) Open issues**: #13 freeze the target sector during hyperspace (30-60 bytes,
  map tick), #12 stars frozen during the pre-jump erase (20-50), #11 stars lag while
  the map draws (timing, 0-100), #10 game speed (80-150 resident + ~100 in TITLE),
  #9 planet/mothership events in flight (300-600), #8 map messages (already on the
  message line; verify and close), #7 VDC second display (400-800 resident + 1 KB
  VDC data + free VDC RAM), #1 VDC visual fixes (50-150), #3 target rectangle
  (150-300), #4 3D radar (150-300), #5 sun/planet sprites (300-500 + 256-512 shapes,
  raster multiplex), #6 star field (100-400, CPU-bound). #2 (multiplayer), #14
  (browser audio) and #17 (C64 patch) need no C128 memory.
- **(e) VDC**: the map program's VDC code is still in the map chunk (disabled with
  `VDCON=0`); its 1 KB of VDC data was displaced from `$2900` by type-1 masters
  (keep it in bank 1). Letters: copy the character ROM into VDC RAM (no storage).
  Box cover on a 16 KB VDC: 640x176 bitmap + 80x22 attributes = 15,840 bytes, or
  640x200 monochrome = 16,000; packed 8-11 KB (estimate), in bank 1. Note: the box
  art is someone else's artwork; using it is the user's call.

Totals: new pre-game code ~3.5 KB (two S1 packages), new pre-game data 1-6 KB
(bank 1), new resident gameplay code ~1-2.5 KB, VDC assets 9-12 KB packed.

## 5. The architecture

### 5.1 Bank 1 layout (proposal; `build.py` generates and checks it)

| Bank 1 | Bytes | Contents |
|---|---|---|
| `$0000-$03FF` | - | common RAM (not separate) |
| `$0400-$0FFF` | 3,072 | unused (room for a 4 KB common area later) |
| `$1000-$29FF` | 6,656 | EXIT backup of bank-0 `$0200-$1BFF` (replaces VDC `$0000` and `$D200`) |
| `$2A00-$2A3F` | 64 | EXIT backup of the stub page `$0100-$013F` |
| `$2C00-$5BFF` | 12,288 | reset snapshot (11,301 today) |
| `$5C00-$63FF` | 2,048 | ending payload (as today) |
| `$6400-$68FF` | 1,280 | type-1 stream master (`$8000-$84FF`) for the reset |
| `$7000-$7CFF` | 3,328 | MINES package image (linked at `$EA16`) |
| `$7E00-$8BFF` | 3,584 | ENDING package (linked at `$E960`) |
| `$8C00-$99FF` | 3,584 | TITLE package |
| `$9A00-$A7FF` | 3,584 | INTRO package |
| `$A800-$AFFF` | 2,048 | music notes, scroll and message texts |
| `$B000-$B7FF` | 2,048 | VDC map characters, system-screen templates |
| `$B800-$EFFF` | 14,336 | box cover (packed), later packages |
| `$F000-$FEFF` | - | left alone: BASIC 7's string heap grows down from `$FF00` in bank 1 |
| `$FFFA-$FFFF` | 6 | NMI/RESET/IRQ vectors -> `$013F` (an `RTI` in common RAM) |

### 5.2 The common-RAM stub (`$0100-$013F`, installed by init, saved for EXIT)

```
; PCRA ($D501) = $3E (the game's bank 0), PCRB ($D502) = $7F (bank 1, all RAM)
; X = pages; CSRC = bank-1 source, CDST = bank-0 destination; Y = 0
B1COPY: STA $FF02        ; CR <- PCRB: bank 1 (the value written is ignored)
        LDA (CSRC),Y     ; zero page is common
        STA $FF01        ; CR <- PCRA: bank 0
        STA (CDST),Y
        INY
        BNE B1COPY       ; 24 cycles a byte
        INC CSRC+1
        INC CDST+1
        DEX
        BNE B1COPY
        RTS
B1PUT:  ...              ; the other direction (snapshot, backups)
B1GET:  STA $FF02 / LDA (B1P),Y / STA $FF01 / RTS   ; one byte, ~25 cycles
NMIB1:  RTI              ; $013F: both banks' NMI vectors during a transfer
```

Rules: the opcode fetches after `STA $FF02` come from bank 1, so the stub must be in
common RAM; init saves and sets `$D501/$D502` (EXIT restores them: BASIC 7 uses
them) and writes bank 1's `$FFFA-$FFFF`; transfers run with interrupts off (the
game's normal state) and never while the tunnel IRQ is enabled; an NMI (RESTORE)
inside the window lands on `NMIB1`. Speed: ~700 bytes a frame of full 1 MHz time,
~1,400 at 2 MHz (blanked screen or border only); a 3,328-byte package takes 80,000
cycles = 4.7 frames at 1 MHz, 2.4 at 2 MHz. The VDC byte path is about the same
(BIT/BPL/LDA $D601: 20-25 cycles), so moving the ending's store costs no time.

### 5.3 The slot and the overlay manager

- **S1 = `$E960-$F6F8`** (3,481). MINES keeps its link address `$EA16`
  (`build.py` already asserts `MNSTART == $EA16`) so the tunnel's page crossings do
  not change; ENDING, TITLE and INTRO are linked at `$E960`. Init-only `GINIT3`
  runs before S1 is first used; `GREXIT` (38 bytes) moves to resident low RAM.
- **Manager** (~200 bytes, resident in `$19F9-$1BFF`): `OVOWNER` (0 none, 1 MINES,
  2 ENDING, 3 TITLE, 4 INTRO), `OVWANT`, a resumable job pointer, the package table
  (bank-1 address, pages, the package's `unload` entry). `OVLOAD` (synchronous) and
  `OVSTEP` (background, at most N bytes per call, from the frame loop).
  Eviction: call the owner's `unload` (MINES: `MNOFF` + `MTOFF`), then refuse to
  write if `$D01A & 1` or the IRQ vector points into S1 (a test counts refusals).
- **Entry guards**: every reference from resident code into S1 goes through a
  resident trampoline that checks `OVOWNER`. Today's references to audit (from
  the build's patches): `g_tp6: JSR MNREQUEST` (all modes: move the 20 bytes to
  resident), `mp_pass: JSR MNPASS`, `JSR MNSTEER`, `MSPREAD: JMP MNREAD`,
  `JMP MNVIEW`, `JSR MNOFF` (first `MSPOSOFF` call site), `ENDQUIET`'s `JSR MNOFF`,
  `GINIT3`'s `JSR MTINIT`, `ENDSTREAMS`' `MNSTREAMINIT/MNSTREAMRESTORE` (replace by
  a raw copy of the stream master from bank 1). `build.py` scans every resident
  chunk for absolute operands into S1 and fails on any not in the trampoline list.
- **Budget** (measured with `m.dma`, CPU cycles spent in the frame loop's wait
  loops): flight in an empty sector min 8,039 / median 13,638 a frame; map opening
  min 9,477; map open min 8,358. A background quota of 128 bytes a frame (3,100
  cycles) in the border window after `TICKHK` (deadline check like `EXLIM`) loads
  a package in 27 frames. Measure hyperspace, fights and the M sequence before
  relying on them (step 0).

When each package is loaded:

| Package | Trigger | Budget |
|---|---|---|
| MINES | the jump's destination is a base sector (`HYPSTART`), background | acceleration 4.5 s + steps + deceleration 2.4 s (>400 frames); fallback: synchronous in `MSARRIVE` (~5 frames) |
| ENDING | `ENDSTOP` (after `MNOFF`/`MTOFF`), background during the 255 flash frames; victory: synchronous at `ENDWINSTART` (~3 frames, during the wipe) | ample |
| TITLE | after `ENDRESET`; at boot after init; synchronous, screen blanked (`$7B`), 2 MHz | 2.4 frames |
| INTRO | after the difficulty choice, synchronous or background | 1-2 frames |

### 5.4 Raster-critical code

- The tunnel never moves: same link address, same bytes as today, copied raw. It is
  loaded during the jump, i.e. before `MNVIEW` installs `MTIRQ`; MINES stays the
  owner until a later package is needed (death, title, intro), and eviction first
  runs `MTOFF`.
- The intro's panel split is polled inside the cockpit's frame loop (no IRQ),
  through a same-size slot like the repair report's `MRMODE`/`MRATTR`/`MRWAIT`; the
  INTRO package stays the owner while it runs, and any player action that needs S1
  (a jump into a base sector, death) ends the intro first.
- Tests: the DMA late-split and `OVRUN` counts stay 0 in every scenario, including
  with a background load running; the 256-phase tunnel comparison stays within
  2 lines; a check that MINES' bytes in S1 equal the build's image before `MNVIEW`.

### 5.5 Reset, title and first boot

```
death/victory -> ENDSTOP: load ENDING (background) -> ending screens
  -> fire/timeout -> ENDRESET (restores the snapshot from bank 1, blank $7B)
  -> OVLOAD TITLE (blanked, 2 MHz) -> title loop in the normal frame loop
     (HUD and cockpit as the original; input to the ship off; stars; music from
     the blank hook; scroller in the bottom row)
  -> difficulty: DIFF, SHIPINIT, the map's start layout for DIFF
  -> OVLOAD INTRO -> intro (game clock running) -> automatic map -> play
first boot: init (snapshot taken) -> OVLOAD TITLE -> as above
```

The snapshot must be taken by code that is not in S1 at that moment: at init the
ENDING package runs from S1 before TITLE is loaded, or the save direction of
`ENDCOPY` moves to the loader.

### 5.6 VDC RAM

After the store moves to bank 1 the game uses no VDC RAM. Plan for a 16 KB VDC
(the flat C128; detect 64 KB only as an extra):

- title: the box cover, 640x176 + attributes (15,840) decoded from bank 1 straight
  into VDC RAM (literals through `$D601`, matches with the VDC's own block copy);
- play: text mode, screen `$0000`, attributes `$0800`, characters `$2000-$3FFF`
  (character ROM copied in, the map's characters from bank 1); `$1000-$1FFF` free;
- the display stays blanked (`ENDVDCBLANK`) until it holds a complete picture.

### 5.7 Load capacity

Phase A (no outer packer): bank-1 contents that are already loaded today (ending
code, payload, MINES) move to bank 1 at init for free; new data has `$F260-$FEFF`
(3,232) plus ~200 bytes of margins, consumed before `GINIT2`. Enough for TITLE and
INTRO code with the original's 1 KB tune and texts, not for the box cover.

Phase B (outer packer, before the title if the title is to have more than the
original's data): the build keeps producing today's PRG as the *inner image*
(every existing check unchanged), then writes the distributed PRG: BASIC stub +
boot code + packed inner image + packed bank-1 archive, ending at or below `$FEFF`.
Boot: copy a ~200-byte decoder to `$0100` (common RAM); copy the packed archive into
bank 1 and decode it there with CR `$7F`; decode the inner image in place in bank 0
(CR `$3F` for the `$D000` staging), forward with the packed stream at the top and a
margin that `build.py` proves by simulating the decoder (the write pointer never
passes the read pointer); jump to `START`. Memory is then exactly today's load-time
image. Capacity: 58,111 - 38,029 - ~400 = **about 19.5 KB packed** (more with a
stronger format such as ZX0, at the cost of a new decoder). Boot time: ~60 KB at
~50 cycles a byte at 2 MHz, ~1.5 s.

### 5.8 Checks `build.py` needs

- each package fits S1 and is linked at its base (MINES at `$EA16`, others `$E960`);
- the bank-1 layout table: no overlap, inside `$0400-$EFFF`, packages page-aligned,
  snapshot/payload/backup sizes within their areas;
- the resident-reference audit into S1 (trampoline list only); packages may call
  resident code freely; only MINES writes `$FFFE/$FFFF`, and `MTOFF` restores it;
- the stub fits `$0100-$013F`; tests check the minimum stack pointer stays above
  `$0180`;
- all existing checks: frozen symbols below `$E000`, chunk bounds, sprite regions,
  PRG <= `$FEFF`, the outer image's in-place decode margin;
- VDC use of each mode <= `$3FFF` (the JS machine gets a 16 KB VDC option with
  address wrap, so an overflow fails the tests instead of passing on a 64 KB model).

## 6. Implementation order (one agent task each)

0. **Measurements, no game change.** (a) A VICE x128 monitor check of bank 1 and
   common RAM: RCR `$D506`, PCR defaults `$D501-$D504` (expected `$3F/$7F/$01/$41`,
   RCR `$04`), a byte written through `$FF02` in bank 1, VDC RAM size (16 vs 64 KB)
   of the user's VICE setup. (b) A JS coverage tool (wrap `cpu.step`, tag each
   frame F/D/M/H/E) over the existing game scenarios: which bytes of `$0200-$0C5F`,
   `$0C60-$19F8`, `$E960-$F6F8` run in each mode, and every resident reference into
   S1. (c) Spare cycles per frame and per window in hyperspace, fights and the M
   sequence (flight/map figures above). (d) `GUNPACK` cycles a byte. Output: a table
   in `c128-game/README.md`.
1. **JS machine bank 1**: `ram1`, CR bits 6-7 for CPU accesses, common RAM by RCR,
   KERNAL values for `$D501-$D506`, VIC always bank 0, `ram1` in save states (old
   states: fill it from the current PRG's archive in the replay helpers), a 16 KB VDC
   mode, the debugger able to show bank 1. Unit tests against step 0's VICE results.
2. **Bank-1 store** (no behaviour change): the stub, PCR/vector setup and EXIT
   restore; the EXIT backup (`$0200-$0C5F`, `$0C60-$19F8`) and the reset snapshot and
   payload move from VDC/`$D200` to bank 1 (`ELREAD`/`ELWRITE` become bank-1 calls at
   the same call sites). Tests: all existing, snapshot/EXIT byte equality, VDC RAM
   untouched after START. Risk: EXIT to BASIC (PCRs), VICE cold LOAD.
3. **Overlay manager + MINES as the first package** (behaviour identical): S1, the
   guards and trampolines, `MNREQUEST` resident, the stream master for the reset,
   background loading at `HYPSTART`, synchronous fallback. Tests: S1 filled with
   `$A5` outside M across all scenarios, every base/tunnel DMA test (0 late writes,
   0 `OVRUN`), refused eviction while `MTIRQ` runs, the 256-phase tunnel comparison.
4. **ENDING package**: split core (~360 resident) and package (~2,290 in S1);
   loads at `ENDSTOP`/`ENDWINSTART`; `GREXIT` resident. `game-end.js` results
   unchanged (timings within a frame). Result: ~2.3 KB free at `$0200-$0C5F` plus
   `$19F9-$1BFF` (after the manager, ~2.6 KB): report the new margins.
5. **(a) sector cleared + automatic map** and 6. **(b) damaged/destroyed messages
   and the warning sound**: resident, compared with the original (`$3CDE`, `$84F2`).
7. **Outer packer** (phase B) if the title is to carry more than ~3 KB of new data;
   otherwise stage TITLE/INTRO at `$F260-$FEFF`. Test: the decoded inner image equals
   the inner PRG byte for byte at the jump to `START`; boot time; VICE autostart.
8. **TITLE package**: title screen, the original's music player and tune (compare
   SID writes frame by frame with `$1CF2`), scroller, difficulty menu, the reset and
   boot flow of 5.5, `DIFF` and the map layout rerun, #10's speed option.
9. **INTRO package**: welcome scroll, panel split, typed message, END OF
   TRANSMISSION, automatic map; aborted by a jump or death. DMA split tests.
10. **VDC display** (#7, #1): characters from ROM + bank 1, the map/system screen
    updated a few cells a frame, unblanking; uses resident space from step 4.
11. **Box cover on the VDC** (title only): a converter (image -> 640x176 +
    attributes), packed in bank 1, the VDC decoder with block-copy matches, text
    mode rebuilt after the title.
12. **Issues** #13, #12, #11 (small fixes), then #3, #4, #9, #5, #6 by resident
    space and CPU budget.

## 7. Risks and open questions

- **Bank-1 semantics differ between VICE, real hardware and the JS model** (RCR,
  PCR defaults, zero page/stack mapping): step 0 must confirm before step 2.
- **Stale references into S1**: a call into a slot that holds another package
  runs garbage. Mitigation: the build's reference audit plus the `$A5` fill tests.
- **Old save states** (`briefs/ref/*.state.json`) have no bank 1: replay helpers
  must rebuild it, or the supplied-state tests break.
- **Time for background loads** in hyperspace and fights is not measured yet;
  the synchronous fallbacks keep correctness, at a cost of a few frames' hitch.
- **The title's difficulty** changes the world layout after the snapshot restore:
  the map's "start layout only once" patch must be revisited.
- **The intro split** is the one new raster-sensitive piece; it runs in an empty
  start sector, but a squadron can still enter: decide whether the intro pauses
  the world (the original does not).
- **The 16 KB VDC** leaves no room beside a full colour cover; the cover and the
  play display take turns, each rebuilt from bank 1.
- **EXIT to BASIC**: BASIC 7 keeps strings at the top of bank 1 (do not use
  `$F000-$FEFF` there) and needs its PCRs back.

Rejected alternatives: VDC RAM as the store (16 KB, all used, conflicts with the
display); relocating raster code on load (page crossings); unpacking on every load
(not resumable, ~45-50 cycles a byte); a second file from disk (the browser page and
VICE autostart take one PRG); MMU zero-page relocation tricks (emulator support);
running game code in bank 1 (the VIC and all state are in bank 0).

## 8. Measurements (step 0-1) (2026-11-17)

Probe tools: `briefs/ref/vice-probes/` (README.txt there). VICE x128 3.9 with a scratch config
(`-config <scratch.ini>`, nothing saved), `-80col -warp -autostartprgmode 1`, a PRG with `SYS 7424`; the
probe saves its result table with KERNAL SAVE to an attached d64 (monitor breakpoints proved unreliable).
Everything marked "VICE" below was observed there; "JS" means only the JS model (now checked against VICE in
`js/test/banks.js`). Real hardware was not available: what VICE emulates but nobody promised is listed under
"Uncertain" in 8.6.

### 8.1 MMU and bank 1 in VICE (the plan's stub works)

- **Registers at SYS time** (CR `$00`): `$D501-$D504` = `$3F $7F $01 $41`, `$D505` = `$37`, RCR `$D506` = `$04`,
  P0L `$00`, P0H reads `$F0`, P1L `$01`, P1H reads `$F0`, version `$D50B` = `$20`.
- `STA $FF01-$FF04` loads CR from `$D501-$D504`; the value stored is ignored (A = `$00` and `$FF` give the same).
  **A read of `$FF01-$FF04` loads CR as well** (and returns the register). Writes to `$D501-$D504` leave CR alone.
  `$FF00` and `$D500` are the same register; CR reads back as written in every configuration.
- **CR bit 6 selects the bank, bit 7 is ignored** (`$BF` acts as bank 0, `$FF` as bank 1). Colour RAM `$D800` is one
  RAM for both banks. With CR bit 0 set (`$7F`) `$D000-$DFFF` is bank-1 RAM.
- **RCR** (all 8 bits read back): bits 0-1 = 1/4/8/16 KB, bit 2 = common at the bottom, bit 3 = at the top
  (`$FC00/$F000/$E000/$C000`), bit 6 = the VIC's bank (8.3). **Zero page and stack are common for every RCR, also
  `$00`**: the pointers `$D507-$D50A` name physical pages, so **code at `$0100-$01xx` runs in both banks** (checked
  with RCR `$00` too). The grid of 21 RCR values x 25 addresses is in `js/test/banks.js`.
- **The copy primitive (5.2) works byte-exact in VICE**: B1PUT/B1GET with `$FF02`/`$FF01`, 3 pages bank 0 <-> bank 1
  (LCG pattern, different in every page) and bank-1 RAM under `$D000` (PCRB `$7F`, I/O off); bank 0 left untouched.
  Bytes (23 each): GET `A0 00 8D 02 FF B1 F2 8D 01 FF 91 F4 C8 D0 F3 E6 F3 E6 F5 CA D0 EC 60`, PUT
  `A0 00 B1 F2 8D 02 FF 91 F4 8D 01 FF C8 D0 F3 E6 F3 E6 F5 CA D0 EC 60` (src `$F2/$F3`, dst `$F4/$F5`, X pages).
- **Speed** (CIA1 timer, 1 MHz, VIC display off): 6,159 cycles net for a page = **24.05 a byte**; 3 pages 18,475.
  With the display on (bad lines) 3 pages take 19,563 (+5.9%). In **2 MHz mode** (`$D030` bit 0) a page takes 3,207
  (12.5 raster cycles a byte: x1.92, not x2; VICE draws no extra screen DMA there).
- A trap met on the way: under `SYS` from BASIC `$4000-$7FFF` is BASIC ROM (CR `$00`), so probe code must sit
  below `$4000` or switch CR to `$3E` first.

### 8.2 VDC RAM size in VICE

- Default x128: **16 KB**: R28 = `$2F` at program start. Writes 11/22/33/44/55 at `$0000/$4000/$8000/$C000/$FFFF`
  read back `22 22 44 44 55`: VICE's 16 KB mode ignores only address bit 14 (not a pure wrap at `$3FFF`), so a
  program that overflows into `$8000-$BFFF` would *not* be caught by VICE. The address register is 16 bits
  (`$4000` after a write at `$3FFF`); fill/copy through R30 wrap the same way.
- `-VDC64KB` (command line, or `[C128] VDC64KB=1`) **changed nothing observable**: R28 still `$2F`, same
  aliasing. Setting R28 bit 4 (`$3F`) makes all 64 KB distinct in either setting.
- **The game's code path never reads or writes R28**: it only uses VDC `$0000-$3EFF` (the ending's store, payload
  `$3700` 8 pages), so the VDC size does not show anywhere in it. JS: `new C128('c128')` is now a 16 KB VDC
  (addresses wrap at `$3FFF`: stricter than VICE), `{ vdcKb: 64 }` or `m.setVdcKb(64)` gives the old flat 64 KB.
  All existing tests pass with the 16 KB default.

### 8.3 Can the VIC show bank 1 while the CPU runs in bank 0? Yes (VICE)

Set RCR bit 6 (`$D506` = `$44`); the CPU's CR stays `$3E`. Checked through sprite-background collisions (`$D01F`)
with different data in the two banks, VIC blocks 1 and 2 (`$DD00` `%10`, `%01`; block 3 cannot hold a bitmap at
`$E000`: the CPU cannot write `$FF00-$FF04`):

| VIC data | read from bank 1 with RCR bit 6 |
|---|---|
| hires bitmap, multicolor bitmap | yes |
| screen matrix (text mode, and the bitmap's colours), character generator | yes |
| sprite pointers, sprite data | yes |
| colour RAM `$D800` | one RAM, not banked: the CPU still copies the 1,000 colour nibbles (I/O visible) |
| **character ROM image** at `+$1000` of the block | there with RCR bit 6 = 0 (also at `$5000`, `$9000`), **absent in bank 1** |

- So a ~10 KB image (bitmap 8,000 + matrix 1,000) can stay in bank 1 and be shown without copying; only the colour
  RAM needs a 1,000-byte copy (about 25,000 cycles, 1.3 frames at 1 MHz). Put the bitmap at `+$2000` of a block
  (`$6000-$7F3F` in block 1, `$A000-$BF3F` in block 2; not at `+$0000`: the missing ROM image is a VICE
  observation, not a promise), the matrix at a 1 KB boundary in the same 16 KB block, and set `$DD00` for the
  block. This takes one 16 KB block of bank 1 away from the plan's 5.1 layout while the cover is shown.
- **Not tested**: the VIC's view of the *common* area (`$0000-$03FF`: a matrix at `$0000`) in bank 1; real
  hardware; CR bit 7 / banks 2-3 (a 256 KB machine).

### 8.4 Spare cycles per frame (JS machine, `m.dma = true`; `briefs/ref/vice-probes/measure.js`)

Spare = processor cycles spent in the frame loop's polling loops (`frame`, `WAITLN`'s `wl1`, `WAITST`'s `wst1`, `w251`,
`vbw`), at 1 MHz unless said. A copy loop costs 24 cycles a byte: 1,000 spare cycles = 41 bytes.

| Scenario | Frames | min | median | mean |
|---|---|---|---|---|
| flight, empty sector (mouse moving / still) | 400 / 300 | 9,080 / 9,201 | 11,276 / 11,507 | 12,385 / 13,315 |
| map opening (until the icons are drawn) | 251 | 8,376 | 13,209 | 13,008 |
| map open | 300 | 8,212 | 13,638 | 13,288 |
| hyperspace jump, whole | 842 | 3,352 | 10,008 | 9,986 |
| ... acceleration (HYPON 1) | 218 | 10,276 | 12,296 | 12,230 |
| ... the steps (HYPON 2) | 432 | **3,352** | 7,829 | 7,805 |
| ... deceleration (HYPON 3) / arrival (4) | 120 / 42 | 7,054 / 9,607 | 11,551 / 15,525 | 11,751 / 14,836 |
| fight after the jump (moving + firing) | 900 | **2,192** | 7,865 | 7,805 |
| ... 3 / 2 / 0 fighters alive | 329 / 282 / 289 | 2,192 / 2,556 / 4,336 | 7,065 / 7,693 / 8,713 | 7,133 / 7,532 / 8,837 |
| enemy base ($80): scanner, rings, minefield | 614 | 3,986 | 9,124 | 9,495 |
| ... minefield with the tunnel IRQ on (first 15 / next 321 frames) | 15 / 321 | 3,986 / 4,847 | 6,385 / 8,799 | 6,052 / 8,768 |
| friendly base ($FF): approach, mines, docking, repair | 1,139 | **2,992** | 9,839 | 11,285 |
| ... docking (MSSTATE 7) / repair (8-10) | 100 / 365 | 5,732 / 2,992 | 7,334 / ~16,800 | 7,393 / ~15,000 |

- **The worst frames leave 2,000-3,000 cycles (80-125 bytes)**: fights with 3 fighters, repair, a hyperspace step.
  Medians are 7,000-9,000 (290-375 bytes a frame). The plan's quota of 128 bytes a frame (3,100 cycles) is above
  the worst frames: use a deadline check (like `EXLIM`), not a fixed count.
- The spare time comes in pieces. For an empty flight frame, by wait loop (cycles a frame): `wl1` until line 194 (the 3D
  view) 4,861, until line 230 1,618, until 78 120; `wst1` until line 55 3,078, 73 765, 241 332; `vbw` (the border
  after `TICKHK`, 2 MHz) 3,116 on average but a **median of only 16**, 8 at minimum: in flight and fights the
  frame's border work fills the 2 MHz window; only the map and the end of hyperspace leave 1,000-5,000 there.
- A copy must not run into a `WAITST` split: those are timed to the cycle.

### 8.5 What the JS machine models (how far its timing can be trusted)

- **CPU** (`cpu6502.js`): all documented opcodes with the data sheet's cycle counts incl. page-cross and branch
  penalties; instruction granularity (no bus cycles, no dummy reads/writes, no I-flag latency); undocumented
  opcodes jam. An IRQ is taken when an instruction has ended (7 cycles); the raster compare is latched when the
  line number changes, so the IRQ comes at the first instruction boundary after the line starts (jitter up to one
  instruction: no cycle-exact stable-raster work). No NMI source.
- **VIC** (`video.js`): 312 x 63 cycles (PAL); register writes are logged with (line, cycle) and the picture is
  drawn line by line. **DMA stealing only with `m.dma = true`**: 43 cycles on a bad line (lines 48-247, DEN set),
  `3 + 2n` for `n` sprites on a line, added in one lump when the line has passed (not at the real cycles, no BA
  write exemption). Without it (the default, and the page) the CPU is about 6% too fast on a full screen. 2 MHz
  (`$D030` bit 0): half a raster cycle per processor cycle, no refresh-cycle penalty, I/O at full speed.
- **CIA**: register files only: no timers (a read of `$DC04/$DC05` returns the processor cycle count), no TOD, no
  interrupts, ICR reads 0; CIA2 gives the VIC bank, CIA1 the keyboard/joystick/mouse lines. **SID**: write log and a
  voice-3 noise/pot model. **VDC**: no timing, always ready.
- **Checked against VICE** with the 3-page copy stub at 1 MHz: VIC off 18,489 (JS) vs 18,492 (VICE); display on with
  DMA 19,564 vs 19,563; 1 page 6,388-6,732 depending on the raster phase vs 6,348-6,734; **2 MHz: 3,087 vs 3,207 a
  page (JS 4% fast)**. So spare-cycle numbers with `m.dma = true` are good to a few percent at 1 MHz; the 2 MHz
  border window is optimistic by about 4% (and VICE draws no VIC DMA there, JS charges it when DEN is set). The
  frame-loop figures of 8.4 themselves were not compared with VICE.

### 8.6 Step 1: bank 1 in the JS machine (`js/src/machine.js`)

- `ram1` (second 64 KB bank); MMU registers with the VICE defaults; `$D500-$D50B` with the meanings above;
  `$FF01-$FF04` loading CR on read and write; CR bit 6 as the CPU bank (bit 7 ignored); RCR common RAM (1/4/8/16 KB,
  bottom/top); page-0/1 pointers (zero page and stack are physical pages, bank 0 by default); bank-1 RAM under I/O
  with CR bit 0; the VIC's bank from RCR bit 6 (`vicRam()`, no character ROM image in bank 1, as VICE); the 16 KB
  VDC option (`{ vdcKb: 64 }`); debugger `m0`/`m1`/`>1`; `peekBank`/`pokeBank`. While bank 0 and the default
  pointers are selected the access path is the old flat `ram[a]`.
- States: `ram1` is saved only when it is not empty, so fixtures keep their size; states without the new `banks`
  field load with bank 1 empty and the default MMU registers (the old ones were zeros that nothing read).
- `js/test/banks.js` (35 checks, run by `node js/test/run.js`): register defaults, load semantics, bank bits 6/7,
  I/O, the RCR grid against VICE, page pointers, **the B1GET/B1PUT stub byte for byte and its 24.05 cycles a byte**,
  the VIC's bank, VDC 16/64 KB, save/load incl. an old state and the supplied C128 minefield state, bank 1 empty
  and RCR untouched after 300 frames of the game, the debugger.
- **Uncertain / not verified in VICE**: the meaning of `$D505` (stored only); P0H/P1H bits other than the bank bit
  (relocation is modelled from the pointers; VICE was not asked to relocate); that a real C128 equals VICE for the
  RCR grid, the `$FF01` read side effect and the missing character ROM image in VIC bank 1; the VIC reading the
  common area.

## 9. Steps 2-4 done (2026-11-17)

Built in three verified increments; after each, `python c128-game/build.py`,
`python js/build.py`, `python js/bundle.py` and the full `node js/test/run.js` ended
with "all checks passed" (step 2: 103 boots keep the free-memory pattern, step 3:
107, step 4: see the README). Not committed.

### 9.1 Step 2: bank 1 is the store

- `c128-game/bank1.asm`: the stub at `$0100-$0154` (85 bytes, not 64: `B1GET`/`B1PUT`
  23 bytes each, with `B1GETY`/`B1PUTY` entries for tails; `ELREAD`/`ELWRITE` 19/18
  bytes, the same contract as the old VDC routines: a byte at a moving address, X/Y/C
  kept, and `ELREAD` sets N/Z from the byte, as `LDA $D601` did: `ENDUNPACK` tests them;
  `NMIB1` at `$0154`). The lowest stack pointer stays `$EA` (`banks.js`).
- `B1INIT` (staged after the payload, init only, before `GINIT2`): `$0100-$0154`,
  PCRs, bank 1's vectors into a temp page (`$FE00`), then into bank 1 `$2A00`; PCRA
  `$3E`, PCRB `$7F`; bank 1's `$FFFA-$FFFF` = `NMIB1`; `$0200-$1BFF` (26 pages) into
  bank 1 `$1000`; the payload. `ENDRESTORE` (EXIT): `$0200-$1BFF`, the vectors, the PCRs,
  then the stack page's bottom (from a copy at `$6000`, game RAM), then `SAVFAST`.
- The snapshot keeps exactly the descriptors it had in VDC RAM (the gap-bridging
  budget is still the 16K VDC's formula), so a reset restores the same bytes.
- Cost: bank-1 byte reads are 32 cycles against the VDC's 22; the ending's timings did
  not change (the per-frame text jobs have raster limits).

### 9.2 Step 3: the overlay manager, MINES

- `c128-game/overlay.asm` at `$1A10` (after the low block, in BASIC's free ML area;
  installed by `B1INIT`, restored by EXIT with `$0200-$1BFF`). Package table: MINES
  (bank 1 `$7000`, run `$EA16`), ENDING (bank 1 `$7E00`, run `$E970`).
- **Differences from 5.3**: (1) no guard on the base sequence's own calls (`MSVIEW`'s
  `JMP MNVIEW`, `mp_pass`'s `MNPASS`, `MNSTEER`, `MSPREAD`'s `MNREAD`): a trampoline
  there cost ~20 cycles a pass and changed the measured steering rate (59 -> 53 calls in
  60 frames). The check is at the base's arrival instead (`OVBASEIN` replaces MSECTOR's
  `JSR MSPOSON`), and `build.py`'s audit allows exactly these four. (2) `MNOFF`, called at
  every sector's arrival, does not load MINES: with MINES out of S1 `OVMNOFF` does what
  MNOFF does besides restoring MINES' own hooks (which are restored already: MINES only
  leaves S1 after `ENDQUIET`'s MNOFF). (3) No background load at `HYPSTART`: only an
  ending empties S1 and the reset reloads MINES (screen blanked), so a base arrival
  never finds S1 empty in play; `OVBASEIN`'s synchronous load (~4.5 frames) is the
  fallback (tested). The hyperspace background load is needed once TITLE/INTRO share
  S1 (steps 8/9). (4) `MNREQUEST` stays in MINES (its bytes unchanged); a resident copy
  `MNREQ` serves the torpedo path. (5) The stream master for the reset is a raw copy of
  `$8100-$83FF` in bank 1 `$6400` (taken at init), not MINES' packed stream.
- MINES' image goes to bank 1 at init (`OVINIT`, with the snapshot), so a reload is the
  state a reset restored before. The snapshot leaves `$E960-$F6F8` out (clipped after
  the same gap bridging).

### 9.3 Step 4: the ENDING package

- Core `$0200-$0556` (855 bytes): `ENDSETUP`, `ENDVIEW` (the per-frame check, the win
  poll), `ENDSTOP`, `ENDFLASH`, `ENDWINSTART`, the victory's phase 0 (`ENDWINFRAME`,
  `ENDREFILL`), `ENDONE`, `ENDPROTONUSED`, `ENDALARM`, `ENDRATTLE`, `ENDRESET2` (MINES
  and the streams back, the fresh game), `ENDCOPY` with `ENDRANGES` (22 descriptors),
  the trampolines, and the variables used in play, the flash and across endings
  (`ENDPAL`, `ENDPULSE`, `ENDFREQ` keep their values from one ending to the next).
  `ENDCOPY` is resident so that init needs no package swap (a first version loaded
  ENDING into S1 at init for the snapshot: init then took 59 frames instead of 53 and
  tests that start 56-60 frames after boot found no world yet). It now copies whole
  pages with `B1PUT`/`B1GET` (24 cycles a byte instead of ~45): play begins at frame
  48 (53 before); the reset's restore is faster too (screen blanked).
- Package `$E970-$F0ED` (1,918 bytes): `ENDUNPACK`, the scene, the report, the rank,
  `ENDLOOP`, `ENDTICK`, the reset's first part, the letters, the victory's
  text/rank/wait, the numbers, the rating (`$F440`), its inputs.
- Loading: `ENDSTOP` starts it (after `ENDQUIET`); `ENDFLASH` and the victory's phase 0
  (and `ENDWINSTART`'s own frame) call `OVSTEP`; pieces begin in lines 78-175
  (`OVLIM` 176) and end by line 190. Death: in S1 after 17 of the 255 flash frames.
  Victory: after 13 frames, and phase 1 waits for it (needed when the 15-frame wipe
  ends: two frames of margin; no frame lost in any test).
- Staging: core at `$E000` (ENDINIT copies 4 pages), package `$E400`, payload `$EE00`,
  `B1INIT` `$F600`, stub image, the manager's 496-byte area; the PRG ends at `$F932`.
- Timings (DMA frames, unchanged against the build before step 2): death report/rating
  613/616 (original 612), victory energy/text/rank 29/54/57 (original 28/53/56), resets
  711/10410/584/19039 (C64 715/10410/584/19040).

### 9.4 The memory map now

Bank 0 (changed rows; the rest as in 2):

| Range | Bytes | Contents |
|---|---|---|
| `$0100-$0154` | 85 | the copy stub (common RAM) |
| `$0200-$0556` | 855 | ending core |
| `$0557-$0C5F` | **1,801** | **free**, every mode |
| `$1A0A-$1A0F` | 6 | free |
| `$1A10-$1BF7` | 488 | overlay manager, MNREQ, trampolines |
| `$1BF8-$1BFF` | 8 | free |
| `$D200-$DFFF` | | free RAM beneath I/O after init (the backup left) |
| `$E960-$F6F8` | 3,481 | S1: GINIT3 at init; MINES `$EA16-$F6F6` in play; ENDING `$E970-$F0ED` from a death/victory to the reset; `$F6F7-$F6F8` free |

Bank 1:

| Bank 1 | Bytes | Contents |
|---|---|---|
| `$1000-$29FF` | 6,656 | bank-0 `$0200-$1BFF` as at SYS |
| `$2A00-$2A69` | 106 | `$0100-$0154`, PCRs, bank 1's vectors as at SYS |
| `$2C00-$4C93` | 8,340 | reset snapshot (22 ranges, S1 left out) |
| `$4D00-$54FF` | 2,048 | payload (1,895 used) |
| `$6400-$66FF` | 768 | `$8100-$83FF` (the streams the mines borrow) |
| `$7000-$7CE0` | 3,297 | MINES |
| `$7E00-$85FF` | 2,048 | ENDING (1,918 used) |
| `$FFFA-$FFFF` | 6 | `NMIB1` |

Free in bank 1: `$0400-$0FFF`, `$2B00-$2BFF`, `$5500-$63FF`, `$6700-$6FFF`,
`$7D00-$7DFF`, `$8600-$EFFF` (about 34 KB; `$F000-$FEFF` left to BASIC 7).

Free resident bank 0: **1,801 + 6 + 8 + 2 bytes** plus loader 14, glue 1, helper pad 9,
packed 168 (load time). The plan's ~2.6 KB counted all of `$1A0A-$1BFF` (the manager
took 488 of it) and a 360-byte core (it is 855: the snapshot copy and descriptors, the
victory's first phase, the trampolines).

### 9.5 Uncertain, and what to check in VICE x128

- Real hardware/VICE vs the JS model: the stub (checked in VICE in step 0), PCRA `$3E`
  with I/O; that the KERNAL's bank-1 `$FFxx` copy is not needed while the game runs
  (bank 1's vectors are restored at EXIT); an NMI (RESTORE) during a transfer.
- The victory's phase 1 waits for the package; with a slow view slot (a very full map
  when the win fires) the text could come a frame or two later than before.
- Check in VICE: cold LOAD and start; a minefield and its tunnel; death in the minefield
  (flash, scene, report, restart, then another base: mines and tunnel again); a
  victory (text, rank, restart). (The RUN/STOP-to-BASIC check is gone: the exit hung in
  VICE and was removed, section 10.)

## 10. No return to BASIC (2026-11-17)

The user's decision, after RUN/STOP's exit to BASIC hung in VICE: the game does not
return to BASIC, and BASIC's memory (zero page, `$0200-$1BFF`, bank 1 with BASIC 7's
variables and strings, the KERNAL/BASIC vectors) is the game's.

- **RUN/STOP does nothing.** The frame loop's check (`LDA CIA1PB / BMI nostop`) keeps
  its bytes and its branch, so a frame without RUN/STOP takes exactly the same cycles;
  with RUN/STOP held three NOPs replace the old `JMP EXIT` and the SPACE check follows
  as usual. The only restart is the game-over reset (`ENDRESET`, unchanged). A soft
  reset on RUN/STOP was not chosen: it would have to stop whatever runs at that moment
  (tunnel IRQ, a package load, hyperspace, a base sequence) the way `ENDQUIET`/`ENDSTOP`
  do at a death, a new path with its own risks; resetting the machine leaves the game.
- **Removed**: `ENDRESTORE` (loader); `B1INIT`'s copy of `$0200-$1BFF` into bank 1
  (`B1LOW` `$1000-$29FF`), its save of the stub page, the PCRs and bank 1's vectors
  (`B1STACK` `$2A00`, the `B1TEMP` page at `$FE00`); the cockpit's `EXIT` routine and
  START's saves of the caller's state (both turned into free space of the same size by
  `build.py` patches: no cockpit address moves, `EXIT`/`SPRCROSS`/`cpc` are where they
  were); `ENDVDCBLANK`'s save of `PTR` (5 bytes, left as free space so that
  `ARROWS`/`ARPIX` keep their addresses); the build's reservation of bank 1's
  `$F000-$FEFF` (BASIC 7 strings). `B1INIT` still installs the stub, sets PCRA `$3E`/PCRB
  `$7F` and bank 1's vectors (`NMIB1`), and loads the manager, the ENDING package and
  the payload. The bank-1 layout of the store is unchanged (snapshot `$2C00`, payload
  `$4D00`, streams `$6400`, MINES `$7000`, ENDING `$7E00`), and so are the snapshot's 22
  descriptors (the gap-bridging budget still uses the old 16 K VDC formula, which
  reserved `$0A60` bytes for the EXIT copy: the reset restores exactly the bytes it did).
- Moved: only `ENDQUIET` and `ENDSTREAMS` (in the loader page, `$1CB3`/`$1CD1` ->
  `$1C54`/`$1C72`; two `JSR`s in the ending core follow). Every other symbol keeps its
  address; the PRG differs only in the loader page, the two cockpit holes, the 5-byte
  helper hole, those two core operands and the init staging (`B1INIT`, which is 84 bytes
  shorter: the PRG ends at `$F8DE`).

Free memory now (bytes; "before" is the build just before this change):

| Area | Free now | Before | Where |
|---|---|---|---|
| Zero page | **248** | 0 (BASIC's/KERNAL's) | `$02-$2A`, `$2D-$FA`, `$FF` (the game uses `$FB-$FE`; the relocated rating, original `$F440`, uses `$2B/$2C` as its temp, as the original does) |
| Stack page (common RAM) | **107** | (not advertised) | `$0155-$01BF`, below the stack (lowest SP measured `$EA`) |
| `$0200-$0C5F` (core `$0200-$0556`) | 1,801 | 1,801 | `$0557-$0C5F`, every mode |
| BASIC's free ML area | 14 | 14 | `$1A0A-$1A0F` (6), `$1BF8-$1BFF` (8) |
| Loader page | **109** | 14 | `$1C93-$1CFF` (`ENDRESTORE` was here); `$1C00-$1C3A` (BASIC stub, `ENDINIT`) is dead after init |
| Resident cockpit holes | **165** | 0 | `$1D14-$1D58` (69, START's saves), `$1F79-$1FD8` (96, the old EXIT) |
| Helper pad | **8** | 3 | `$52C0-$52C4` (5, `ENDVDCBLANK`'s PTR save), `$52FD-$52FF` (3) |
| Old ARRSTEP block | 6 | 6 | `$5B1B-$5B20` |
| Glue | 1 | 1 | `$5DFF` |
| High (after MINES) | 2 | 2 | `$F6F7-$F6F8`, every mode |
| Packed margin (load time) | 168 | 168 | before `$7680` |
| S1 / ENDING package | 1,563 of S1 while ENDING is in; 130 of its 8 bank-1 pages | same | ENDING `$E970-$F0ED` (1,918); S1 `$E960-$E96F`, `$F0EE-$F6F8` |
| Load window (staging) | **1,569** | 1,485 | PRG now ends `$F8DE` (was `$F932`): `B1INIT` 111 bytes (was 195) |
| Bank 1 | **47,861** | 36,864 | `$0400-$2BFF` (10,240), `$5500-$63FF` (3,840), `$6700-$6FFF` (2,304), `$7D00-$7DFF` (256), `$8600-$FEFF` (30,976), `$FF05-$FFF9` (245) |
| VDC RAM | 16 K | 16 K | unused (display blanked) |

Dead but left in place: `SAVMMU`-`SAV1D` (`$28A3-$28B0`, 14 bytes; 12 of them are in the
reset snapshot, so they could hold reset-initialised variables).

Tests: the EXIT tests are gone (`run.js` "normal EXIT restores...", "EXIT restores the
stack page...", `game-end.js` "RUN/STOP restores every borrowed ending-workspace byte").
New: init writes no copy of BASIC's RAM, stack page, vectors or PCRs into bank 1 and
leaves BASIC 7's bank-1 areas alone; RUN/STOP held for 100 frames in flight and over
the map does nothing (the old EXIT and START holes are never executed, MMU stays `$3E`,
the map still opens); RUN/STOP held from a death and from a victory to the reset gives
the reset on the same frame as without it, then a fresh game. Every game boot now also
fills the new free areas (loader tail, both cockpit holes, the 5 helper bytes, zero page
`$02-$2A`/`$2D-$FA`/`$FF`, the stack page `$0155-$01BF`) with `$A5` and checks them
across all scenarios (a loaded save state re-arms the fill). The first run of that check
found the rating's `$2B/$2C`: the relocated `$F440` keeps the original's zero-page temp
(so before this change an ending also wrote BASIC's `$2B/$2C`). Validation: `python c128-game/build.py`, `python js/build.py`, `python js/bundle.py`, full `node js/test/run.js` ends with "all checks passed"; ending timings unchanged (death report/rating 613/615, victory 29/54/57, resets 711/10410/584/19039 DMA frames), 0 late splits / 0 OVRUN in every DMA scenario. No commit or push.

VICE x128: RUN/STOP in flight, over the map, in a base sequence, during the death flash
and on the victory screen should do nothing; the death and victory endings and their
restarts as before.

## 11. Title overlay and flight profile menu

The title survey's steps 1, 2 and 4 are implemented. Cold boot and the shared
game-over reset load TITLE into S1. The owner is `$20`. The resident entry
checks the overlay manager's swap guard and runs the title via a trampoline.
The title polls the raster with IRQs disabled, shares the cockpit's HUD and
gun sprites, and scrolls a 38-column strip by one pixel per frame. It feeds a
new character every eight frames and wraps at the terminator. The wordmark
uses the repository's emulator font. The scroll copy includes the original
game's attribution and an editable port credits placeholder. [Scroll text](../c128-game/title-text.txt)

F5, F7 and fire open the selector. Joystick up/down or 1351 vertical movement
chooses a flight profile and a fresh fire press confirms it. The resident
handoff evicts TITLE, sets the ship via `SHIPINIT` and generates the selected
world through the existing dock, mothership and squadron tables. The first
jump preloads MINES in bounded chunks during the view so a base can use
the package immediately on arrival. A direct base entry still has a synchronous
fallback. The reset restores the streams before changing the S1 owner.

### Load and runtime space

The 1,413-byte TITLE package loads at `$E963-$EEE7`. A single compressed
stream would overfill the PRG load window. `TITLESTORE` decodes two streams
into low RAM at `$1000` before the permanent low block is installed. It then
copies the package to its six reserved pages at bank 1 `$8600-$8BFF` and
clears the two phasor path pages used for staging. The build checks the
reserved ranges, staged stream sizes, end of PRG and resident S1 operands.

| Area | Layout and free bytes |
|---|---|
| Resident tail | `$0AD3-$0C5F`, **397 bytes** |
| Overlay manager | `$1A10-$1BFE` used, **1 byte** at `$1BFF` |
| Loader tail | `$1CCA-$1CFF`, **54 bytes** after `TITLESTORE` |
| S1 while TITLE runs | **2,068 bytes** outside its loaded image |
| Bank 1 | **46,325 bytes** free, including the range from `$8C00` |
| Title code staging | 745 bytes at `$FBE2-$FECA`, **53 bytes** left below `$FF00` |
| Title art and copy staging | 383 bytes at `$3400-$357E`, **129 bytes** left in these init-only pages |

The headless tests use DMA for the title splits, scroller cycle, selector choices,
first-jump load and death/victory transitions. The packaged itch program uses
the same entry through the title and reuses the existing ending statistics hooks.
In VICE x128, check cold boot and scroll, select and confirm with each port-2
device, then restart from an ending and select a different profile.
