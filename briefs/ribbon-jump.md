# Task: the C128 title's welcome ribbon text jumps forward/back every 4th frame

Context: `briefs/title-original-restore.md` (Progress section: what the previous agent did: original music, briefing, HUD fix, the `$D016`
write moved to the end of line 232), `c128-game/title.asm` (`RIBTICK`, the title loop), `intro-core.asm` (`intro_irq_ribbon`),
`js/test/title-intro.js`, `.zen/t/dbg16.js dbg19.js dbg20.js` (register/cycle compare scripts with the original), `briefs/title-survey.md`
section 5 (welcome ribbon: 2 px per frame, `$D016` = 7, 5, 3, 1, a cell every 4 frames).

Bug (user, itch page, screenshots `briefs/img-title/ribbon-f464.png`, `ribbon-f467.png`, `ribbon-f468.png`; the debugger shows the frame counter
and PC `title_wrap` / `$E9D0`): the ribbon text in the bottom strip ("WELCOME ABOARD CAPTAIN, STANDBY FOR MESSAGE FROM STARFLEET COMMAND...") runs
AHEAD at frame 467 (more text visible to the right), jumps BACK at frame 468, then advances smoothly about 1-2 px per frame; the next forward/back
jump is at frames 471-472: a 4-frame period = the character-cell step. So the shake is not the `$D016` write cycle but the relation between the
screen-matrix (character) shift and the `$D016` fine-scroll wrap at the cell step (on the step frame the characters shift one cell while the fine
scroll has not wrapped, or the other way round), or the strip uses the `$D016` of a different frame than the matrix content.

Do:
1. For both machines (the original C64 in the JS machine: `.zen/lib.js` `boot('c64game')`, reach the welcome ribbon; and the port) compute for every
   frame 6-520 the effective horizontal position (in pixels) of the ribbon text as the VIC shows it at the strip's lines: matrix text offset in
   cells * 8 + the fine-scroll value in effect for that strip at that frame (which `$D016` write applies to the strip's lines in that frame, and which
   matrix content is on screen when the strip is drawn). Assert in `js/test/title-intro.js` that the port's sequence equals the original's
   and is monotonic (never moves backwards, never jumps by a cell), in particular around frames 464-475 after the accept, without regard to
   m.dma on/off (the page runs without DMA: test both).
2. Find the cause (matrix shift timing vs `$D016` wrap; or the strip reading the wrong frame's value), fix it in `title.asm` / `intro-core.asm`
   without breaking the existing register/cycle tests; memory is tight (57 bytes resident free, 14 below `$FF00`, TITLE package 3,320 of 3,328, S1 158 free).
3. Rebuild: `python c128-game/build.py`, `python js/build.py`, `python js/bundle.py`, `python js/itch.py`; run the full `node js/test/run.js` ONCE at the end
   ("all checks passed"; two game tests are phase-sensitive: `game: in a fight the splits' colours...` and `game: C= again closes the map...`; if they flip
   because of your change, solve it without relaxing them).
4. Do NOT commit or push. Update the Progress section of `briefs/title-original-restore.md`. Final handover: cause, fix, tests, bytes, VICE/itch checks.
