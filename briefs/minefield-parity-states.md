# Second round: check the minefield parity against the user's two save states

After `briefs/minefield-parity-fixes.md` (same rules; do NOT commit or push; builds on the
working tree). The user saved the same situation in both versions, loadable in the JS
machine (`m.loadState(m.stateFromText(...))`):

- `briefs/ref/c64-minefield.state.json`: the C64 original (v10 patch), the reference.
- `briefs/ref/c128-minefield.state.json`: the C128 game (a build from before the fixes; load it
  with the matching PRG only if it still loads, else recreate the situation by playing the
  scenario through the game's own routines).

Situation in both: approaching a **friendly** mothership; on the long range radar the base is a
little left of the centre; the **minefield has just begun**; the cursor/crosshair is at a random
place. Use them to compare, frame by frame with `m.dma = true` and the same input script
(left/right/up/down held, fire, SPACE / both buttons), the C64 against the current port:
the cursor's vertical and horizontal limits, the steering lock (when the side reading reaches 0),
steering after the mothership appears, the firing and torpedo refusals, the entry message line
and its flashing, the radar at a jump. Fix whatever still differs, and add the C64 state's
traces as a test (the state file must be loaded by the test, so keep it in `briefs/ref/`).

Tests and finish as in the previous brief ("all checks passed", late splits 0, OVRUN 0, docs).
Final message: what matched, what was fixed, what is uncertain.
