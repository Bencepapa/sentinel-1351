# Task: fixes to the game end (branch feature/game-end, uncommitted work in the tree)

Read first: `briefs/game-end.md`, `PLAN-C128-COCKPIT.md` "Handing the work on", `c128-game/README.md`.
Same rules as there (no commit/push, build + `node js/test/run.js` must end "all checks passed",
finish with a short handover).

VICE test of the build found (screenshots in `briefs/img-end/`):

1. **Garbled screen** (`1.png`): on one of the ending screens (the user reports "the second
   screen", i.e. the one after the first flashing/ending text; the death ending's texts in
   `3.png` "THE BATTLE IS OVER / JARALOBA IS LOST" and `4.png` rank text look right) a flickering
   pattern of coloured characters/blocks fills the screen. Find which screen/transition that is
   (run the ending in the JS machine with `m.dma = true`, dump screen/colour/charset memory and
   `$D018/$D011/$DD00` there), fix it, and add a test that fails before the fix.
2. **HUD sector shows `0..01`** (`2.png`) after hyperspace jumping into the top-right sector
   (and similar for other rightmost sectors; `5.png` shows `0..03` for a rightmost-column
   sector too). Check whether it is expected for the original's display (compare the original's
   sector read-out for those sectors in the JS C64 machine) or a regression of this branch
   (the ending work may have clobbered the sector text / digit data or the sector arithmetic;
   compare with `main`). Fix if it is wrong, with a test.

Verify the winning ending too (not yet user-tested) the same way.

## Clarification (user, `briefs/img-end/6.png`)

The garbled flickering pattern is the **80-column (VDC) screen** (left in the picture, the
40-column VIC screen is on the right). Before the ending work the VDC screen was blank; now it
shows flickering garbage characters/colours. So the VDC (RAM/attributes/charset/mode at `$D600`)
is being touched or left uninitialised by the new code, probably during the game (it was seen
while playing) or at an ending. Keep the VDC screen blank as before.

## Clarification 2 (user, briefs/img-end/7.png)
At start-up the 80-column VDC screen first shows, for about a second, a garbled screen (leftover C128 BASIC boot text mixed with random coloured blocks and a block of cyan garbage at the bottom), and only then switches to the flickering pattern. The VDC must be cleanly blank (screen, attributes, and charset RAM) from the very start of the load/boot, as in `main`.
