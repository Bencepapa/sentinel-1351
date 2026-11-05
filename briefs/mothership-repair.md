# Task: the friendly mothership's beam and repair sequence (C128 port)

You are working in `C:\dev\c64\sentinel`: the native Commodore 128 port of
Synapse's *Sentinel* (C64, 1984). The mothership approach and destruction are
ported and reviewed (`MSECTOR` ... `MSRETURN`, `MSFINISH` at the end of
`c128-game/game.asm`). Read `briefs/mothership-approach.md` and
`briefs/mothership-destruction.md` first: their constraints, how to reproduce
the original in the JS emulator, and the test rules all still apply. Read
`PLAN-C128-COCKPIT.md`, section "Mothership sequences".

## Goal

When a **friendly** base's approach reaches its endpoint (radius `$28`) and the
base was not destroyed, the port now goes straight to the map. Port what the
original does in between:

1. **The tractor beam** (`$8D66` -> `$918E`): runs only for a friendly base
   with `$E2`, `$BACE`, `$BAD1` and `$8C3E` all zero. As the user describes it
   from VICE: with a sound effect, two beam-like light rays come in from the
   base to our ship. The code draws two paths/rings (`$3580` with the
   parameters set up at `$919C`...) - trace it fully: shapes, colours, speed,
   sound.
2. **The repair** (`$8D69` -> `$92E3` -> `$932D`, skipped for an enemy base):
   texts appear showing the shield and the energy being charged, then the
   subsystems being scanned and repaired. The sequence lasts until everything
   is repaired, the shields are full and the energy is full; it also gives a new
   proton torpedo. Then the game returns to the map (`$8F53`, `$8D6F`).
   Find every text, its position/colours/timing, the order of the steps, how
   the counters advance (rates in frames, measured with `m.dma = true`), what
   is written to the ship's state (systems, shield, energy, proton count) and
   any sounds.
3. Port both into the C128 game: after the friendly endpoint (and only when
   the base was not destroyed), run the beam, then the repair on the cockpit
   (the port's systems: `SYSHP` and the HUD's systems display, the shield
   `SHLD`, the energy, the proton count at `$485A`/`$485B` - check how the port
   keeps each and how the HUD shows it), then the existing return to the map
   with the base's re-entry lock (`MSRETURN`, normal endpoint path).
4. Note: the original also runs `$92E3` after a proton was fired at a friendly
   base that survived (see the plan); keep that behaviour if it falls out
   naturally.

## Constraints

- Memory: `$E000` code up to `STR2Y` (`$F400`, about 950 bytes left), packed
  image margin about 645 bytes, glue has 12 bytes. Keep and extend the build's
  bound checks. If texts are long, store them compactly.
- No shift of glue / cockpit / map code (compare symbol addresses outside
  `$E000` before and after; only same-size patches there). Self-modifying
  slots, zero idle cost in flight and fights. Heavy drawing in raster-checked
  pieces (`TLATE`, as `MSSTEP` / `MSVB`).
- Timing: zero late split writes (`$D020/$D021` at lines 50-76 / 230-245,
  cycles 16-55) and zero `OVRUN` in DMA tests, through the whole sequence.

## Tests and deliverables

- `python c128-map/build.py`, `python c128-game/build.py`, `python js/build.py`,
  `python js/bundle.py`; `node js/test/run.js` ends with "all checks passed".
- Add checks: the beam runs only for an undestroyed friendly base; the repair's
  texts appear in the original's order; systems, shield, energy end full and the
  proton count grows by one (check the original's limit); the sequence's length
  in frames is close to the original's (measured, with `m.dma = true`); then
  the map with the re-entry lock; no overrun or late split meanwhile; the enemy
  endpoint still goes straight to the map.
- Notes in `PLAN-C128-COCKPIT.md`, a user-facing line in `c128-game/README.md`.
- Do **not** commit or push. Do not revert other uncommitted changes in the
  working tree (the map pointer limits in `c128-map/map.asm`, the base message
  rate and the re-entry fix in `game.asm`, test changes). When done, write
  `chatgpt_handover.md` in the repository root (overwrite) for Claude's review:
  what changed, where, differences from the original, memory left, test
  results, what the user should check in VICE x128.
