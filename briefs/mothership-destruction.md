# Task: destroying a mothership, and the end of the base sequence (C128 port)

You are working in `C:\dev\c64\sentinel`: the native Commodore 128 port of
Synapse's *Sentinel* (C64, 1984). The mothership approach is already ported and
committed (`MSECTOR`, `MSVIEW`, `MSRING`, `MSSTEP`, `MSCINIT`, `MSVB` at the end
of `c128-game/game.asm`; read `briefs/mothership-approach.md` for the
constraints, which all still apply). First read `PLAN-C128-COCKPIT.md`, section
"Mothership sequences": its "Proton torpedo in a base sector" item holds the
findings this task is built on.

## What the original does (traced, verify as you go)

1. **The kill rule.** At the start of the player's proton blast (`$BB77`,
   `$BACE` cleared) the base is destroyed only when all three are non-zero:
   `$E1` (in a base sector; `$FD3B` sets it for both kinds), `$8ED1` (radius
   >= 12, the white centre shows) and the phase flag `$953E`. Then `$8C3E` is
   set and `$BAD1` ends the approach loop (`$9162`).
2. **A miss.** Otherwise the blast is only the screen's flash: `$BAD1` stays 0,
   **the approach keeps growing to its end**, and a friendly base still goes on
   to its beam/repair. The user confirmed this in VICE (two shots at a friendly
   base with its centre showing, both missed, the ship was repaired). The port
   currently ends the approach on any blast (`g_msv3`: `TPF >= 3`): wrong.
3. **The phase flag `$953E`.** `$953F` runs every 32 loop passes; every 25
   calls it toggles `$953E` (`$953D` counter). `$8ED2` / `$8EE9` start it
   random, with a random first period 1-64. For an **enemy** base it is also
   the colour of the view: phase 0 = a random matrix colour (`$1x`) on every
   call (flicker), phase 1 = white `$11`. A friendly base is always `$11` but has
   the same hidden phase. Convert the rate to frames by measuring the original
   with `m.dma = true` (the approach's loop passes are not frames: about 128
   passes per radius step, 6-9 frames).
4. **A kill.** `$8D64` skips the beam and repair; `$8F53` waits for the blast
   to end, shows **BASESTAR DESTROYED CAPTAIN** (text at `$8F31`, via
   `$9BE5`), `$9020` draws fast growing rings from radius 1 to `$2C`
   (`$3635`/`$364C` with the plot callback `$EEFB`, `$3674` +1 per step), then
   the game returns to the map (`$8D6F` onward). `$8E42` clears the base's map
   cell (`$033C`/`$0378` at the sector `$92`/`$93`) when `$8C3E` is set.
5. **The end of every base sequence goes to the map.** The user observed in
   VICE: after the sequence the map comes up by itself (a friendly base has
   repaired the ship; an enemy base got too close and fired its torpedo; or the
   base was destroyed). The base's sector is then the one sector the map will
   not jump straight back to; the player must go elsewhere first. Port the map
   coming up and that rule; the repair and the enemy torpedo themselves stay for
   later (the port may go to the map when the approach reaches its endpoint).

How to reproduce the original: boot `c64game` in Node like `js/test/run.js`
(`originalDuration` there), set `$E2` (1 enemy, 0 friendly), **`$E1 = 1`**,
`$BAD1 = $BACE = $8C3E = 0`, `$89 = 1`, push the return address `$8D58` and
jump to `$909D`; then the real exit path (`$8D59`, `$918E`, `$92E3`, `$8F53`,
`$8D6F`) runs. SPACE (`m.setKey(7, 4, ...)`) fires the proton. Forcing
`$953E` to 0 or 1 around the blast reproduces both outcomes.

## Also in scope (small)

6. **The map's battle messages.** In the joined game the map's `SURROUND`
   (`c128-map/map.asm`) sets `LASTMSG` (1 MOTHERSHIP ENGAGED IN BATTLE,
   2 MOTHERSHIP DESTROYED, 3 JARALOBA IS SURROUNDED, 4 JARALOBA CEASES TO EXIST),
   but only `VDCMSG` prints it, and the VDC is off. So a blue base surrounded on
   its four sides disappears silently and squadrons then walk into its cell
   (faithful, but the player sees no message). Show these on the cockpit's
   message line as the original does (find how and when the original prints them
   from `$3E7E`); the game-over of message 4 is not part of this task.

## Out of scope

The friendly beam and repair (`$918E`, `$932D`), the enemy base's torpedo
(`$CF01`/`$CF04`), the mines, and game end. Note anything you learn about them
in the plan.

## Constraints (see the approach brief for details)

- Memory is very tight: the `$E000` code ends at `$ECD8` (TSH2 at `$EDC0`), and
  the packed image at `$6200-$7665` has **26 bytes** left before the cockpit art
  at `$7680`. Expect to rearrange: e.g. generate data in code, move tables, find
  another free area; keep the build's bound checks and add new ones.
- Do not shift code in the glue (`$5300`) or cockpit chunks; reach new code
  through self-modifying JSR/JMP slots; zero cost in flight and fights when idle.
- Heavy drawing in pieces with raster checks (`TLATE`), as `MSSTEP` / `MSVB` do.

## Tests and deliverables

- `python c128-game/build.py`, `python js/build.py`, `python js/bundle.py`;
  `node js/test/run.js` must end with "all checks passed", with `m.dma = true`
  timing checks (no late split writes, no `OVRUN`).
- Add checks: a miss keeps the approach growing (both kinds); a hit with the
  phase on destroys the base (message, rings, cell cleared, map shown, no
  repair); the phase toggles at the original's rate and the enemy flickers in
  phase 0; the base's sector cannot be targeted straight back from the map;
  the battle messages appear on the cockpit.
- Notes in `PLAN-C128-COCKPIT.md` and a user-facing line in `c128-game/README.md`.
- Do **not** commit or push. When done, write `chatgpt_handover.md` in the
  repository root (overwrite the old one) for Claude's review: what changed,
  where, what differs from the original, memory left, test results, what the user
  should check in VICE x128.
