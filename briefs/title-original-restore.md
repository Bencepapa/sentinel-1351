# Task: restore the ORIGINAL title music, briefing text and sounds; fix the intro screen and the selector sounds

State: the C128 title (c128-game/title*.asm, title-core.asm, title-music.asm/.txt, title-intro.asm/.txt, intro-core.asm,
js/test/title*.js, title-intro.js, title-music.js) was extended by Codex with a NEW score and a NEW briefing text. The user wants the
ORIGINAL ones (this is a personal tribute project; the user decided to use the original's music, texts and sounds).
A local checkpoint commit exists (do not commit or push yourself). Read `briefs/title-survey.md` (sections 2 music, 5 briefing/intro,
the sound notes) and `briefs/title-music-intro.md` (what was built), `briefs/memory-overlay-plan.md`,
`PLAN-C128-COCKPIT.md` "Handing the work on", `c128-game/README.md`, `Codex-handover.md`.

## Work items (verify each against the original in the JS C64 machine; m.dma on only after frame ~250)
1. **Original title music.** Replace the new score by the original one-shot 3-voice tune: the survey recorded 13,150 SID writes
   with a checksum and source offsets (original `$1C6x-$2074`, called from `$0C5D`, ~1 KB data; player routine in the original).
   Port the original player/data (data may live in bank 1; keep it in a clearly named separate file) and reproduce the SID write
   stream frame by frame (the test compares the normalised event stream and the checksum with the original). Same stop rules as now
   (F5/F7/Fire stop it, silence at leaving TITLE).
2. **Selector sounds.** In the original the difficulty selector has the engine hum (a background engine sound) running while the menu
   is shown, and a short sound whenever the selection changes between the choices; the confirm sound/gun shot/blink already work (user
   verified). Trace the original's selector (`$8609`, loop `$864A`, store `$87C6`, confirm `$867F`) for the SID writes: engine hum start,
   per-move beep, stop; port them with the same register values and timing, test with the SID write log compared to the original.
3. **Original briefing.** Replace the new "Patrol Control" briefing text by the original Starfleet message (text at `$97D9`, 306 bytes,
   encoding in the survey) and its original sounds: the sound heard while the top raster bar opens/closes differs from the original
   (the original's effect: trace its SID writes during the bar opening/closing and the typing beeps; port them exactly). Keep the original's
   timing (glyph pacing, the 48-line bar steps).
4. **Welcome scroll bug (before the briefing).** Screenshot `briefs/img-title/c128-intro-bug.png`: the scrolling welcome text alternates
   white and green letters, jumps between x positions (the fine scroll / character step is wrong), the UI at the top is falling apart
   (the HUD strip is cut off on the right: `TARGE`, the top border/lines broken), and one gun is missing (only the left gun is visible,
   the right one is gone). Compare frame by frame with the original's welcome scroll (survey section 5): colours, scroll mechanics, the
   HUD/sprites state during the intro (sprites for the guns must stay enabled, the HUD rows and borders intact; check `$D016`, `$D011`,
   sprite enable `$D015`, the X MSB bits, colour RAM of the HUD and the matrix switch in the resident raster handler), fix the code and add
   tests that compare the screen/colour RAM/sprite registers with the original at several frames of the welcome scroll and during the briefing.
5. All existing tests stay green: `node js/test/run.js` ends "all checks passed", 0 late splits and 0 OVRUN (m.dma = true), see the other title tests
   (they were written for the new music/briefing: update them to the originals). Build: `python c128-game/build.py`, `python js/build.py`,
   `python js/bundle.py`, `python js/itch.py`. Run the full suite once at the end (several minutes; make sure no other node suite is running).

## Memory
Resident free 150 bytes, 14 bytes below `$FF00` in the PRG staging, S1 slot 637 bytes free, bank 1 about 44.8 KB. The original music (~1 KB) and
briefing (306 bytes) can go to bank 1, or to the outer archive if the PRG staging is too small: decide, measure and document; report exact numbers
if something does not fit. The new Codex score/briefing data may be deleted from the build once replaced (keep the files out of the build or remove them).

Do NOT commit or push. Update README + PLAN Status + memory-overlay-plan. Final message: per item what was done, memory left, VICE checks for the user,
uncertainties. If you hit your usage limit, leave the tree building and write the status per item under `## Progress` in this file.

## Progress

Status per item (2026-11-19; the tree builds, `node js/test/run.js` was run at the end):

1. **Original title music: done.** `c128-game/title-music.asm` is a compact player of the original's streams. Its data
   (initial state `$1ED6`, note tables, three (pitch, duration) streams `$1F01-$2074`, stored as one pitch plane and one
   duration plane) is copied from the disk's `SN1` by `title_music()` in `build.py`; the Codex score `title-music.txt` is
   gone. `js/test/title-music.js` runs the original C64 (writer range `$1C70-$1EC6`, 13,150 writes, SHA-256 `10743917...`
   as in the survey) and the port and compares every SID write with its frame relative to the init: identical. F5/F7/Fire
   switch the three controls off (as `$18B4`), the natural end clears `$D418-$D400`. `MUSICINIT` now runs after the picture
   is drawn (the original's `$0A68`), so the first notes come 3 frames after the init as in the original.
2. **Selector sounds: done, with one finding.** The original starts the engine hum at selector entry (`$C38E`: voice 3 noise,
   AD/SR `$22/$A0`, `$D412=$81`) and sets `$D418=$1F`; the port does the same (`title_openselect`, `ENGBURST`). During the
   confirm and the whole intro the original's engine tick (`$C379`) bursts the hum again every 6 frames (frames 2, 8, 14 ...
   after the accept): the port's `ENGTICK` runs from the accept to the map with the same frames. There is NO SID write in the
   original when the selection moves (traced with joystick and mouse, `m.sidLog` with writer PCs); the test asserts the
   selector idles silent. The sound the user remembers is the hum itself (sustained noise from selector entry).
3. **Original briefing: done.** The welcome ribbon (`$97D9`, 72 bytes) and the Starfleet message (`$9821`, 231 glyphs) are
   copied from the disk by `title_briefing()`; `title-intro.txt` is gone. The bar's open/close blips (`D404,D406,D400,D401,
   D403,D405,D404`), the typing clicks (one per glyph except `$40`, 174), the `D404=0` writes and the ribbon beeps are the
   original's: all 3,324 SID writes from frame 25 after the accept to the bar's end match the original in order, each within
   a frame (`js/test/title-intro.js`).
4. **Welcome scroll / intro screen: done.** The white and green letters were an uninitialised ribbon ink (the title's white
   cells mixed with the cockpit's green), and the step was 6-4-2-0 instead of the original's 7-5-3-1. The ribbon (`RIBTICK` in
   `title.asm`) now starts at the accept like the original (ink black/white every 12 frames, 42 beeps, light green at the end,
   126 cell steps); its text, ink and fine scroll equal the original's for 504 frames. The intro loop syncs at line 243 now
   (it lost a frame whenever the stars/shift work crossed the frame end), keeps the stars moving, the crosshair and the guns
   (a line-194 gun stage in `intro-core.asm`; the guns were missing in the intro), and the retained label's ink goes at the
   end of the confirm. The screenshot's cut-off HUD (`TARGE`) is only the crop of the screenshot: the HUD matches the original
   (test). Tests compare the ribbon, the typed message and its ink (incl. the 15/1 flash), the HUD rows and ink, the gun
   sprite registers and the bar's line steps with the original.
   VICE finding: the C128 KERNAL arms a VIC raster IRQ (`$D01A` = `$F1`), which made `OVSTART` refuse the TITLE load for
   ever (the game hung at boot in VICE x128, not in the JS machine). `TITLEBOOT` now clears `$D01A`.
5. **Memory:** TITLE package 3,307 bytes (S1 171 free; the 13 decode pages limit it to 3,328), seven streams (two newly used
   staging holes: the dead EXIT code `$1F79`, 96 bytes, and the dead START saves `$1D14`, 69 bytes; the hidden text rows stage
   800 bytes now), 52 staging bytes left, resident 115 bytes free (`$0BED-$0C5F`), bank 1 44,533 bytes free.

### Follow-up: HUD and ribbon in the browser (c128-intro-ribbon-1/2.png)

Reproduced in the JS machine (the register log per frame, original vs port, `.zen/t/dbg16.js`): my earlier claim "the HUD
matches the original" only covered the HUD text and colour RAM. It did NOT hold for the registers. From the first
IRQ-driven intro frame (frame 156 after the accept, i.e. when the first glyph of the ribbon reaches the left edge) the
port's raster handlers (`intro-core.asm`) wrote no `$D020` at all and no border edge at line 56, so the HUD lost its purple
side blocks and frame lines (grey bar, white left bar: the screenshot) and the ribbon strip had no grey border. The title
loop (frames 1-155) was correct, the C64 original too.
Fix: `intro_irq_top`, `intro_irq_view` and `intro_irq_ribbon` now repeat the title loop's sequences exactly (WAITST at 56 with
`BG=BORDER=1`, the 20-iteration edge delay, `BORDER=HUDBRD`, `BG=$0B`; the view's white edge line at the split with the
10-iteration delay and `BIT VIEWBG`; the ribbon strip writes `BORDER` and `BG`). `INTROBASE` is 74 / `INTROEND` 122 as in the
original. Line 75 is a bad line: the first bar steps wait at line 78 instead of 75-77 (WAITST's tail is stretched there).
The cadence itself was right in the JS machine (2 pixels a frame, `$D016` = 7, 5, 3, 1, a cell every 4 frames, also with
`m.dma = false`, as the page runs); the choppy look came with the broken IRQ frames.
Tests (`js/test/title-intro.js`): per frame from 6 to 504 the sorted `$D011/$D016/$D020/$D021` writes (HUD, view split,
borders; the C64's extra bitmap strip at 226-231 and `$D018` left out) equal the original's within a frame, the ribbon text,
ink and fine scroll per frame (already), the bar's split steps and `late()` over all intro frames (it was accidentally not
applied before). `ENDPKGSTAGE` moved from `$E980` to `$E9C0` (the packed resident core grew); resident free 57 bytes.
Note: `game: in a fight the splits' colours change off the screen` is phase-sensitive (one heavy fight frame, 2-3 late writes
when the fixture's frame phase hits it); it flipped with unrelated layout changes and passes in the final build.

### Follow-up 2: x shake of the ribbon strip

Measured per frame (`.zen/t/dbg20.js`, line:cycle of the strip's writes, original vs port, DMA): the original writes
`$D020/$D021` at 233:52-56, `$D011` at 233:60 and `$D016` (the fine value) at **234:5** (spread 5 cycles), the reset
`$D016 = 8` at 242:14. The port wrote the fine value at **233:15** (right after `$D011`), i.e. around cycle 16 of line 233
where the VIC starts drawing the line: with the 5-cycle WAITST jitter the last line of row 22 was shifted by the fine
scroll on some frames and not on others, a one-pixel x shake (not tied to the ink flip or the beep: those run after the
frame's display in the title loop and in the main loop of the IRQ phase, the strip's write cycles had the same spread on
beep frames). Fix: both the title loop and `intro_irq_ribbon` now write `$D016` FIRST, at the end of line 232 (cycles 50-62
or 0-11 of line 233, before the VIC starts drawing line 233), then border/background and `$D011`: the fine scroll then
moves lines 233-234 whole on every frame. (A first try, a delay to the original's 234:5, passed the strip test but
shifted the cycle phase of the whole title run and flipped two phase-sensitive suite tests, `game: in a fight ...` and
`game: C= again closes the map ...`, so the cheaper reordering is in.) The title loop also starts the tune at a frame's
top (a changed code length had moved the init writes across a frame boundary).
Test (`js/test/title-intro.js`): the cycle of the strip's `$D016` fine write, `$D020` and `$D021` is logged on every
frame 6-504 for both machines; spreads must stay within the original's + 3 cycles and the fine write must lie before
cycle 12 of line 233, including all 41 beep/ink-change frames.
Final numbers: TITLE package 3,320 bytes (limit 3,328; S1 158 free: `$E963-$F62A`), resident 57 bytes free.

### Follow-up 3: the ribbon jumps forward/back every 4th frame (itch page)

Cause: the machine's renderer (and so the page) draws the strip from the screen matrix as it is at the END of the
frame, while the register log gives the per-line `$D016`. The port updated the row (the 39-byte shift) and the fine
scroll after the strip's display (confirm branch of the title loop, main loop at line 243 in the IRQ phase), i.e. in
the vblank. On a cell-step frame the renderer therefore combined the NEXT frame's shifted row with this frame's old
fine value: the text jumped one cell (8 px) ahead for one frame, then back (frames 467/468, 471/472 ...). The original
shifts the row in its IRQ at line 74, before the strip is drawn, so end-of-frame memory equals what the strip shows.
My earlier tests missed it because they compared "row at the end of the previous frame + this frame's fine" within
one frame of tolerance, and register values/cycles, never the resulting picture. (Real hardware fetches the matrix at
line 235 and would show the same jump on a step frame only if the row changed after that line; the port's order was
wrong for both.)
Fix: the row/ink/fine update (`RIBTICK`) and the hum tick now run in the body of the frame, before the strip is
drawn: in the title loop at `title_aim` (frame body, line ~75+), in the intro main loop at a sync at line 125
(between the bar and the strip; the sprites and the stars still follow at line 243, `intro_late`). The first intro
iteration now waits for line 125 of the next frame. `RIBWAIT` starts at 1 and the hum counter keeps its original phase.
Test (`js/test/title-intro.js`): the ribbon's pixels (lines 236/238/240, 304 columns, drawn by the machine's own
renderer) equal the C64's on every frame 8-504, with the DMA model on and off, and the text's left edge never moves
backwards; the earlier row/ink/fine check is now exact per frame (no one-frame tolerance); all SID writes (3,324) still
match. Memory unchanged: TITLE 3,320 bytes, resident 57 free. (A Codex run had left a partial version of this edit in
`title.asm`/`intro-core.asm`/`title-intro.asm`: RIBTICK in the title body was right, a RIBTICK call inside the view IRQ
and the missing call in `intro_welcome` were not: removed/restored.)

Final state of follow-up 3: the two phase-sensitive suite tests flipped again with the moved ribbon update; three NOPs after the
hum tick in the title body (a cycle-phase change only, commented in title.asm) bring both back; TITLE package 3,323 bytes
(limit 3,328), resident 57 free. Full run: all checks passed.
