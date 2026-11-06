# Task: the enemy base's proton torpedo (item 2 of the Status list)

Read first: `PLAN-C128-COCKPIT.md` "Status" and "Handing the work on" (all its rules:
no code moved in the glue/cockpit/map, new code in the `$E000` chunk through the existing
slots, every bound check in `build.py` kept, memory is tight - 97 bytes high code, 41 packed,
1 glue: plan a rearrangement such as another packed stream unpacked into space free after
init, and note that anything loaded must stay inside the KERNAL LOAD range: the last
bug was a tail staged at `$FF05`), `c128-game/README.md`, the section "Mothership
sequences" of the plan (its "Still deferred" paragraph describes this torpedo), and
`briefs/mothership-repair.md` for the expected form of work.

## Goal

In an enemy mothership sector the base fires a proton torpedo at the ship, as the original:
`$916C` arms `$CF01` at ring radius `$19`; `$CF04` (every 16 loop passes) copies 31 frames
backwards from `$AF80` to `$A000` into `$5140` (shapes `$45` / `$46`, the same art as our
`TORPA`); expanded white sprites 5 / 6 at x `$8C` / `$A1`; `$CF8C` applies five hits
(`$84D7`, `SHIPHIT`). In the measured original it is active about 43 DMA frames. Find out
in the original (JS C64 machine, `m.dma = true`, call routines directly) what exactly
happens: sounds, flash, the conditions, whether it can be shot down or dodged, what the
deflector or steering do, and what follows (the map comes up by itself, `MSRETURN`, normal
endpoint, locked). Friendly bases never fire. Then port it faithfully, with the same
cost-when-idle rule (zero in flight and fights).

## Tests and finish

- Tests in `js/test/run.js` ("game:" group) comparing the port with the original (frames,
  sprite positions/shapes, hits, sounds), split timing (late writes 0, OVRUN 0), and all
  existing tests green: `python c128-game/build.py`, `python js/build.py`,
  `python js/bundle.py`, `node js/test/run.js` ("all checks passed").
- Also check that no sprite asset region is overwritten (the earlier VICE noise bug) and
  nothing needed at load time lies beyond what the C128 KERNAL LOAD writes.
- Update `c128-game/README.md` and the plan's Status. Do NOT commit or push.
- Final message: what the original does, what changed, what is verified, memory left,
  anything uncertain (the user tests in VICE x128).
