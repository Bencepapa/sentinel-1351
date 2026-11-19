# Task: C128 title screen, step 3 (music) and step 5 (Starfleet intro) + scroll-text charset

Read first: `briefs/title-survey.md` (sections 2 music, 5 intro/briefing, 9 proposal and the six steps), `briefs/title-fidelity.md`
(done), `briefs/memory-overlay-plan.md`, `PLAN-C128-COCKPIT.md` "Handing the work on", `c128-game/README.md`,
`Codex-handover.md`, `c128-game/title.asm`, `title-core.asm`, `title-text.txt`, `js/test/title.js`.
State: title page, colour cycling, scroller, selector with confirm animation are done and verified by the user
(the user also tested: the selector's fire/blink sounds work). Memory: TITLE package 1799 bytes in S1 (`$E960-$F6F8`),
105 bytes left below `$FF00` in the PRG staging, resident ~397 bytes (check the build output), bank 1 ~45 KB.

## Part A: music (survey step 3)
Port the original's one-shot 3-voice title tune (data ~1 KB at the original `$1C6x-$2074`, called from `$0C5D`).
Reproduce the SID register write stream (the survey recorded 13,150 SID writes; the reference trace and checksum are in
the survey): the same notes/waveforms/ADSR/filter at the same frames. Player state and tune data live with the TITLE
package (data may sit in bank 1 and be copied/streamed; avoid per-frame bank switching if possible; the tune must not
disturb the raster-critical title code: late splits and OVRUN stay 0). Stop (silence all voices, volume as the
original) when leaving TITLE: on F5/F7/Fire/selector, on game start, and at reset. Sound effects of the selector
(already working) must still play on top. Test: capture `m.sidLog` triples frame by frame and compare the normalised
event stream with the original's (hash + first differing frame report), the end silence, and the cancellation.
Note: use the original game's own tune data as the local comparison source; keep the music data in a separate,
clearly named file so it can be swapped later (the user may replace it).

## Part B: Starfleet intro (survey step 5)
After the difficulty is confirmed the original runs: the welcome scroll, then the Starfleet briefing: a raster effect
opens a 48-line bar at the top (the HUD strip expanding, "48-line HUD expansion", see survey section 5 and the
routines around `$998E`, text at `$97D9` 306 bytes), the message is typed letter by letter / word by word with
the original's glyph pacing (2 frames per glyph?) and beeps, then the bar closes and the sector map opens
automatically (early Fire/Space advances). Port it: the message text (use the original's), the raster opening
(one compare line moved by one line per frame; the graphics mode/matrix switch in the resident raster handler; keep
VIC-IIe at 1 MHz for visible splits), the sound/beeps, the colours, the hand-off to the first map (the first map's
initialisation must stay resident), then normal play. The intro runs after the selector confirmation and also
after every game reset+selection. Schedule bulk copies in blanked windows or within overlay deadlines
(`briefs/memory-overlay-plan.md` sections 8-10: the frame budget is small in some frames; here nothing else runs, so
it is easier). Tests: screenshots/pixel compares at the 0/24/48-line positions and during typing against the original at
the same frame offsets (a few frames of tolerance), the text drawn, close, auto map, early Fire/Space, 0 late splits and
OVRUN (m.dma = true), and the itch pages (`js/test/itch.js`) still start the C128 game and detect game over.

## Part C: scroll text charset
The user edits the scroller text in `c128-game/title-text.txt`. Document in that file (comment lines at the top, if the
build allows comment lines starting with `#`; otherwise in the README) which characters the scroller font supports and
make `build.py` fail with a clear message on an unsupported character (the user remembers only capital letters and
digits; punctuation such as `.` works; check `-`, `,`, `'`, `!`, `?`, `:`, `/`, `(`, `)` and add the missing ones if
the font data / lettering allows it within memory; otherwise list them as unsupported). Keep the text a single place
to edit.

## Rules
- No code moved in glue/cockpit/map; all bound checks in `build.py`; memory per `c128-game/README.md`. If the music or
  intro do not fit in the TITLE package + staging, report exact numbers and use bank 1 for data and the outer archive
  idea from the overlay plan (decide, measure, document).
- Work in order A, B, C with a full verification after each (build + the relevant tests; run the whole
  `node js/test/run.js` at the end of each part; it must end "all checks passed"). Rebuild `python c128-game/build.py`,
  `python js/build.py`, `python js/bundle.py`, `python js/itch.py`.
- Update README + PLAN Status + memory-overlay-plan. Do NOT commit or push.
- Final handover per part: what was built, memory left, VICE checks for the user, uncertainties. If you hit your usage
  limit, leave the tree in a state that builds, and write the status of each part into this file under `## Progress`.
