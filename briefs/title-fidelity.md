# Task: make the C128 title screen and difficulty selector match the C64 original (GitHub issue #24)

The first version of the C128 title (steps 1, 2, 4 of `briefs/title-step1.md`) works but differs from the original.
User screenshots (copies in `briefs/img-title/`): `c64-title.png`, `c64-selector.png` (original, from the JS page)
and `c128-title.png`, `c128-selector.png` (port). Read `briefs/title-survey.md` (the surveyed original) and the
earlier handover of the title task (`c128-game/title.asm`, `title-core.asm`, `title-text.txt`, `js/test/title.js`,
`briefs/memory-overlay-plan.md`).

Differences to fix (compare in the JS C64 machine frame by frame; use screenshots/pixel dumps; memory is tight:
check the build output; the TITLE package lives in the shared slot S1 `$E960-$F6F8`, resident free bytes ~397):

1. **Title page.** The original shows, in this order and over the starfield with the cockpit: `SYNAPSE SOFTWARE`,
   `PRESENTS`, the big `SENTINEL`, `CREATED BY`, `BRYAN BRANDENBURG` (two lines), with 2-3 colours running along the
   letters: some rows left-to-right, other rows right-to-left (a colour-cycling effect on the bitmap lettering colour
   RAM / a per-row colour rotation; find the routine and its timing in the original and port it). The port shows
   only a single-colour SENTINEL and looks like a piece of the S is missing: find and fix the lettering bug
   (compare the generated bitmap with the original's, pixel by pixel). Also the credit text rows with their
   fade-in/out if the original has them (check frame by frame).
2. **Scroller.** Verify the scroller against the original: the bottom row text is cut at the 38-column window as in the
   original; the placeholder scroll text stays (the user rewrites it), keep `PORT CREDITS GO HERE` at the end.
3. **Difficulty selector.** The port shows `FLIGHT PROFILE` with new names CADET/PATROL/ESCORT/VANGUARD/FRONTLINE and
   `FIRE TO CONFIRM`. Port the original's screen: names `SKIRMISH`, `ASSAULT`, `BATTLE`, `INVASION`, `ARMAGEDDON`
   (use the original's texts, layout, colours and font), the visible cursor/crosshair that moves with joystick/
   mouse, and on confirm: the gun fires (shot sprite/sound as in the original), the other entries disappear and the
   chosen one blinks yellow-brown with the original sound for a few seconds, then the game starts (timings from the
   JS C64 machine; the survey sections 4 and 5 have the routine addresses `$8609`, `$864A`, `$87C6`, `$867F`).
   Keep F5/F7/Fire opening it, five levels with the original values (already verified).
4. Tests (js/test/title.js): compare the title lettering bitmap and the colour cycle against the original at several
   frames (pixel or colour-RAM compare, same frame numbers within a few frames), the selector screen text and
   colours, the confirm animation timing, all five levels' state after confirmation (existing checks stay).
   `node js/test/run.js` must end "all checks passed" with 0 late splits and 0 OVRUN; build with
   `python c128-game/build.py`, `python js/build.py`, `python js/bundle.py`, `python js/itch.py`.
5. Do NOT commit or push. Update README + PLAN Status + memory-overlay-plan (memory left). Final handover: what
   was fixed per point, memory left, VICE checks for the user, uncertainties (e.g. if a point does not fit in memory).
