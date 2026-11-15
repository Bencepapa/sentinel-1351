# Task: the end of the game (death, JARALOBA lost, winning, ratings)

Read first: `PLAN-C128-COCKPIT.md` sections "Status" and "Handing the work on" (all its
rules: no code moved in glue/cockpit/map, new code in the `$E000` chunk through the
existing slots or other free space, bound checks in `build.py` kept, tests count late
splits and OVRUN = 0, `m.dma = true` for timing; free memory is tiny: 2 resident,
91 packed, 1 glue bytes, so a memory rearrangement or packing may come first), then
`c128-game/README.md`.

## Goal (Status item 1)

The port shows the messages but never ends the game. Port the original's endings:

1. Player death (shields / systems) and "JARALOBA CEASES TO EXIST" (`$DD`, `$3E7D`,
   `$F431`): big flashing and sound effects, then the UI disappears, only the star
   field stays, large flashing letters say what happened and the player's rank.
2. Winning (all enemy motherships destroyed): a similar sequence, with its own text
   and rank.
3. After a while, or on a button press, the game resets itself (back to its start).

## How

1. Trace the original in the JS C64 machine (`m.dma = true`, `SentinelDisasm`, `m.vicLog`
   for the colour flashing, the SID registers for the sounds): the trigger conditions,
   the flash colours and timing, the sounds, the UI removal, the texts, the rank
   calculation (`$F43B` counts shots and is used in the rating; find the other inputs),
   the wait and the reset condition.
2. Port it with the same timing, colours, sounds and texts, reusing the cockpit's
   message and star code where the original does.
3. Add tests in `js/test/run.js` ("game:" group) comparing the port with the original
   (conditions, rank, frames/timings, text), keep all existing tests green.

## Constraints

- Work on branch `feature/game-end` (already created). Update `c128-game/README.md`
  and the Status in `PLAN-C128-COCKPIT.md`.
- Do NOT commit or push. Finish with a short handover (what changed, what is
  verified, memory left, anything uncertain) as your last message.
- Build: `python c128-game/build.py`, `python js/build.py`, `python js/bundle.py`;
  test: `node js/test/run.js` (several minutes; must end "all checks passed").

## Reference state

`briefs/ref/low-shield.state.json` (C64 original, load with
`m.loadState(m.stateFromText(...))`): the player has 3 shields and dies within seconds,
flying through a minefield while the mothership fires a proton torpedo at them. Use it
to trace the original's death sequence (flashing, sounds, UI removal, texts, rank, reset).

## Earlier analysis (opencode, not finished, unverified)

`.zen/` (untracked) holds trace scripts and outputs of the original's ending:
`lib.js`, `go25.js` (death timeline), `go26.js` (post-rank PC sampling), `go28.js`/`go29.js`
(colour PCs + SID), `ending2-6.txt`, `messages.txt`, `gameover.dis`. Original routines found:
`SHIELDSLOST $8300`, `PLANETLOST $F431`, `GAMEOVERCHK $99F3`, `GAMEOVER $8869`,
`GAMEENTRY $245A`, `SHIELDSDOWN $85D9`, `GFXCLEAR $BA72`. No port code was written.
Treat it as a starting point and verify it yourself.
