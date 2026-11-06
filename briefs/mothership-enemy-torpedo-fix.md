# Fix: the enemy torpedo's animation is scrambled (VICE x128)

Follow-up to `briefs/mothership-enemy-torpedo.md` (same rules; read it, `chatgpt_handover.md`
and `PLAN-C128-COCKPIT.md` "Handing the work on"; do NOT commit/push; keep every bound check).

Symptom (screenshots `briefs/img-torpedo/2.png`, `3.png`): the torpedo's shape is broken: its
upper part is at the bottom and its lower part at the top, as if the shape's rows (or the
two sprites' / two halves' data) were swapped. The save state
`briefs/img-torpedo/before-torpedo.state.json` is taken just before the torpedo is launched
(it fires within 1-2 seconds): load it in Node (`m.loadState(m.stateFromText(...))`, see the
plan), run frames with `m.dma = true` and dump sprites 5/6 (pointers, shape bytes, x/y,
expand bits) every frame; compare with the player's own torpedo (`GTORP` / `TSTEP`, which is
drawn correctly) and with the original's shapes `$45`/`$46` (the shape data copied by
`$CF04`). Find why the rows/halves are swapped: the backwards decode order, the shape slot
layout (63 bytes per sprite: is the 31-frame stream's frame order or a row order reversed?),
the pointer/slot (`$5140`) or the sprite Y expansion. Fix it and add a test that fails
before the fix: sprite shape bytes of the enemy torpedo equal those of the original (and of
the player's torpedo frames) at each frame.

Then rebuild (`python c128-game/build.py`, `python js/build.py`, `python js/bundle.py`),
run `node js/test/run.js` ("all checks passed"), update docs if needed. Final message: root
cause, fix, what is verified, memory left.
