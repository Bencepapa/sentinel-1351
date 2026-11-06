# Task: the base on the long range scanner (preliminary positioning)

Read first: `PLAN-C128-COCKPIT.md` sections "Status" and "Handing the work on" (follow
all its rules: no code moved in the glue/cockpit/map, new code in the `$E000` chunk
through the existing slots, bound checks in `build.py` kept, tests count late splits
and OVRUN = 0, `m.dma = true` for timing), then `c128-game/README.md`.

## Goal (item 1 of the Status list)

Arriving in a mothership sector (enemy or friendly), the long range scanner shows the
base's position like a group of fighters (readings, blip, steering moves it, fire/closing
in as for a group), before the ring approach starts. This is the original's preliminary
positioning phase: `$8C3F` / `$8C44` -> `$8D1C` -> `$9054`, the `$0F7F` wait, then
`$8D56` calls `$909D` (the rings). The port now skips it and starts the rings right
after the closing wipe (`MSECTOR`, `MSVIEW` in `c128-game/game.asm`).

## How

1. Trace the original with the JS C64 machine (as `js/test/run.js` does, `m.dma = true`):
   what `$8C3F`..`$9054`..`$8D56` do, the conditions that end it (when the rings start),
   the scanner readings/blip it uses (`$3776`, `$3736`, `$38E8`, ported as `LRSCAN`,
   `APINIT`, `BLIPPOS`), the timing in frames.
2. Port it, reusing the cockpit's approach/scanner code where the original does.
3. Add tests in `js/test/run.js` ("game:" group) comparing the port with the original
   (readings, blip, frames to the ring start), and keep all existing tests green.

## Constraints

- Update `c128-game/README.md` and the Status in `PLAN-C128-COCKPIT.md`.
- Do NOT commit or push. Finish with a short handover (what changed, what is
  verified, memory left, anything uncertain) as your last message.
- Build: `python c128-game/build.py`, `python js/build.py`, `python js/bundle.py`;
  test: `node js/test/run.js` (several minutes; must end "all checks passed").
