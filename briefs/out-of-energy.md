# Out of energy (issue #28): the C64 original and the C128 port

Survey only; no game code changed. Method: the original (`c64game`) in the JS machine with `m.dma = true`, energy poked low in
normal flight, in the dogfight loop, in a hyperspace jump (poked at the start and in the middle), and the user's two quick-saves
(`sentinel-c64game-frame8219/8241.state.json`, read only; both are at sector 17, the base's tunnel, energy 0003). PCs were counted
with a wrapped `cpu.step`. Scratch scripts: `.zen/e4.js`, `e9-e12.js`, `e20-e23.js`, `fx.js` (not part of the work).

## Findings: the original

### Energy value and its decrements
* Energy has no variable: the four HUD digits `$543E-$5441` (screen codes `$70`-`$79` = 0-9, thousands first).
* `$F886` ENERGYTICK, from the frame IRQ (`$0C1F`, only while `$BA|$88` = 0, so also with the map open and in base tunnels, not in
  hyperspace): `-1` every 110 calls (`$F864` reloaded `$6E`), measured about one unit per 110 frames (`F886` runs once a frame).
  While docked (`$F86B`) it counts up instead (`$F9D6`, +1 a call).
* `$F8A1` (-1 ones digit, borrowing up), `$F8B2` (-10, tens): a phasor shot (`$151D`), thrust (`$FEA7`), the deflector (15 per call),
  hyperspace (`$B498`, `$B62C`, `$B721`, about a unit a frame).
* A decrement that finds 0000 wraps through all four digits to `$F8E0` ENERGYOUT. So the digits sit at 0000 until the next
  decrement (up to 110 frames, or the next shot / thrust) and only then does the message appear.

### Low-energy flash
* `$FA5B`, called from `$F886` every frame (also with the flag set, forever): while the thousands digit `$543E` < `$72` (energy
  below 2000; measured: toggles at 1999, not at 2999 / 5000) a counter `$FA59` (`$0F` frames) toggles colour RAM `$D83E-$D841`
  (the four digits) between `$07` and `$08` (`$FA5A` EOR `$0F`). The shield digit has the same thing at `$FA86` (`$5432` = 0 shows
  the shield flash, `$D832/$D833`). (The user says flashing starts "about 1000"; the code says 2000.)

### ENERGYOUT `$F8E0` (once, when the flag is set)
1. digits := 0000;
2. prints the message with `$9C5C` (inline-parameter text printer: A=`$81`, X=`$10`, Y=`$FF`, text pointer `$F847`): 13 spaces,
   `OUT OF ENERGY`, 2 spaces, `$FF` (screen codes, e.g. `$4F $55 $54` = OUT), into the single standing message row (the 1-char
   strip under the cockpit view, text row at raster 233-242, the row the other notices use), plus `$0912` (a tone);
3. `$F865` := 1 (the out-of-energy flag; cleared only by the sector/new-game init at `$8E56`, so it is permanent for the sector, and the
   game, since nothing can jump any more);
4. `$F868/$F869` := 1, `$F866/$F867` := `$90` (the slowdown counters), `$966F/$9670/$33B5` := `$28`, speed `$F209` := `$41` (slowest).

### What the flag changes
* **Main loop** (`$2CE8` flight, `$8A34-$8B34` dogfight, base loop `$8CF8`): every 128 passes it calls `$F927`. With `$F865` = 0 that
  returns at once. With the flag it never returns (only game over leaves it, via `$99F3` -> `$8869`):
  * **Phase 1, slow-down** (`$F93B-$F968`), about 380-420 frames (8 s): 144 rounds; each round does `$F868` delay steps
    (`ROL $F86A` x6) before every star step (`$16B3`, `$9DAA`, `$F0B4`: crosshair/explosion work and the star move); the delay grows by
    one each round (`$F869`), so the star rate falls from about 27 to 14 steps a frame and then stops: "the ship slows and stops".
    Digits forced to 0000 each round.
  * **Phase 2, stranded** (`$F978`, forever): per pass `$99F3` game-over check; every pass `$F0B4` is NOT called (stars frozen); every
    2nd pass `$C947` (enemy fire / warp-in countdown `$C92E`), `$16B3` + `$9DAA` (crosshair-related explosions); every 16th pass
    the fighter streams `$2F6D/$2FB9/$3005`, `$33B6` (drift towards the middle) and `$1AF2`. Enemies keep firing
    (`$84D7` hit about once every 5 s measured) so the game ends by shields (or planet).
  * Not called in the loop, so dead: thrust `$FEA7`, the input poll `$FB43` (C= map, proton key, `$FDEC`), phasor launch `$1467`
    (`$D1`), tracking, the steering `$39C1`, `$BAD4/$EE01`, the world's tick `$BE29` (map countdown / squadrons moving), the
    sector-clear and other `$2D..` work.
* **IRQ** (keeps running): `$0BB6` with the flag skips the "idle" test and runs the enemy sprite update `$2E36` every 4th frame;
  `$0D0D`: flag set and `$88` not 0 -> no `$B38F`; `$133A`: no hit-effect rush `$094E/$095D/$C3A8`; `$F886` no longer decrements
  but still flashes. The crosshair (sprite 0) still follows the mouse/joystick (measured, x 171 -> 2/5/205), the clock `$FAD7`
  (TIME 00:49 -> 00:58) and the scanner/radar keep running.
* **Measured in phase 2 (dogfight, energy 1 -> 0)**, same inputs as an unflagged control run: fire (mouse left, 25 frames): shots `$F43B`
  stays 1 (control 1 -> 3); proton (space, both buttons): protons stay 8; map (C= key, right button): `$B8` stays 0 (control
  opens the map); crosshair moves; enemy positions keep changing and the SID shows enemy fire.
* **Energy never returns** except a friendly base's refill (`$F86B`), which cannot be reached any more (no map). No game over is
  triggered by the energy itself.

### Hyperspace
`$B4BD` (acceleration loop), `$B6B1` and `$B716` (jump steps and the deceleration) test `$F865`: with the flag set the "38 passes per
step" counter `$B3DB` is not used, so the step counter `$B3DA` (normally 40-60 steps x 38 passes) is decremented every pass. Energy
runs out in the jump (0001 poked mid-jump, `$B3DA` = 32): the speed jumps `$03` -> `$41`, the steps drop 31 -> 0 in about 10 frames,
the deceleration runs (about 55 frames), and the ship arrives (frame 334 after the poke at 259, i.e. about 75 frames) at the right
destination sector; energy at the start of the jump: the jump finishes in about 100 frames instead of about 800. `$F8A1` in the
jump keeps wrapping (`$F8E0` again every 10 units: the message and `$F209` := `$41` repeat). After the arrival the normal flight loop
reaches `$F927` and the ship is stranded as above. This is what the user saw ("slowed, stopped, no map/fire, crosshair moves,
fighters warp in, no idea where the jump ended").

### The user's saved states (base tunnel, sector 17)
Energy 0003 in both; the digits reach 0000 at about frame 400, the flag at frame 407 (8241) / 429 (8219), `$F927` (called from the
base loop) starts phase 1 within about 170 frames, phase 1 ends about 380 frames later, then phase 2 (fighters `$2F6D` move, `$C947`,
about 3 hits at the ship until shields 11 -> 8). The tunnel scroll (stars/bands) slows and stops exactly as the user describes.

## Port diff (c128-game + c128-gui/cockpit)

| | Original | Port now |
|---|---|---|
| Passive tick | -1 per 110 frames in flight, map, bases (`$F886`) | none (energy 9999 constant over 3000 frames of flight) |
| Shots / deflector / thrust | `$F8B2` -10 | shots: `ENERGY10` (`cockpit.asm` 1157) -10; deflector via `HENERGY`; thrust: none |
| Hyperspace | `$F8A1` ~1 a frame | `HENERGY` (`game.asm` 2533), 1 per 10 frames |
| At 0000 | `$F8E0`: flag, message, stranded | `ENERGY10` `en3` and `HENERGY` `g_he2` just stay at 0000 |
| Low-energy flash | `$FA5B` below 2000 | none found |
| Message | OUT OF ENERGY in the message row | none (`NOTICEREQUEST` ids 1-5, 8-15 damage, `$11+` end texts exist) |
| Fire, proton, map, thrust, steering, world tick | dead in the stranded state | always on |
| Stars, jump steps | slow-down then frozen; jump races to the end | unchanged |
| Warp-ins, enemy fire, clock | run | run |
`ENDENERGY` (`game.asm` 6022, patched into `ENERGY10`'s first line by `build.py`) and `ENDONE` already hook the same spots for the
ending's energy tally: keep them.

## Plan and byte estimate

1. **Flag + tick** (about 35 bytes): `ENEMPTY` byte (+ `ENFLC` flash counter, `ENTICK` 1 byte). Once a frame outside hyperspace
   and while `ENEMPTY` = 0: `LDA #110 / JSR HENERGY` (the existing one-unit-per-A-frames routine; map open and bases count too).
   Hook: `TICKHK` (the world's clock, already once a frame) or `MISSIONFRAME`; about 12 bytes.
2. **Trigger** (about 20 bytes): at `HENERGY` `g_he2` (0000 reached by a decrement: `BEQ g_he9` -> `JMP ENEMPTYSET`) and at `ENERGY10`
   `en3` (same-size patch in `build.py`: `JMP ENEMPTYSET` + NOPs for the `LDY #$70 / STY x4` block, `ENEMPTYSET` re-zeroes the
   digits). `ENEMPTYSET`: if flag set RTS; set flag; `NOTICEREQUEST` with a new id; set speed variable to the slowest
   (the port's thrust speed, if any).
3. **Message** (about 46 bytes): new id 6 in `mission_print` (`CMP #6 / BNE / JMP ENMSG` before `mission_damage`, ids 6 and 7 would
   otherwise fall into the system-damage path), `ENMSG` = `MSGCOL`/`MSGRATE` + `LDA/LDX/LDY` + `JMP MSGSTAT` (like
   `mission_clear`), text 13 spaces + `OUT OF ENERGY` + 2 spaces + `$FF` (29 bytes).
4. **Gates** (about 6 bytes each, `LDA ENEMPTY / BNE skip`): phasor launch (`LAUNCHD`/`FIREPH`), proton (`g_tp9` area / torpedo
   request), map request (`GMAPTOG`/`MAPOPEN`, includes C= and right button), thrust, steering (`VBWORK` steering part), the world
   tick (`TICKHK` map clock). About 36 bytes. Crosshair, enemy fire, fighter movement, warp-ins, clock, radar are left running.
5. **Slow-down and freeze** (about 30 bytes): stars (`FGVB`/`VIEWVB`, the star step) run at a rate that falls over about 400 frames
   (e.g. step only when `frame AND mask = 0`, the mask growing 0,1,3,7 every ~100 frames; counter `ENSLOW`), then stop. Deceleration
   in the original is a rate, not a speed change: keep it a rate.
6. **Hyperspace** (about 8 bytes): in the jump's step timer (`HYPSTART` area, 13.5 frames per step) a flag test that takes a step
   every frame; at the arrival nothing else (the port's `HARRIVE` keeps the destination). Set the speed to slow like `$F209` := `$41`.
7. **Flash** (about 40 bytes + 3 data): below 2000 (`HUDE` < `$72`) toggle the four digits' colour every 15 frames
   (`$07`/`$08`; colour RAM for `HUDE`, check how the port paints the HUD), keep it also when the flag is set.
Total about 190-210 bytes. The resident core has 33 free bytes (README lists `$0BCA-$0C5F` 150 free; check the current build output
before choosing): keep only the gate tests (`LDA ENEMPTY / BNE`, about 36 bytes plus the 6 byte trigger hooks) resident or in the
hook slots (`VBWORK`, `TICKHK`, the `sprcj`-style self-modified JSRs, "zero cost when idle") and put `ENEMPTYSET`, the message,
the tick and the flash in bank 1 (44 KB free) through the existing trampoline/overlay manager (a package like MINES, not TITLE), or
into the `$0BCA-$0C5F` / `$05CD-$0C5F` free range if the build shows it. The flag byte must be in the reset snapshot area so that a
game-over reset clears it (original: only the init at `$8E56` clears it).
No code in the glue (`$5300`), cockpit chunks or map may move; `fixed-symbols.json` must still match.

### Test ideas (`js/test`, with `m.dma = true`)
* Port: energy 0001/0000 + tick -> flag set, message row shows OUT OF ENERGY (same text as the original), HUD 0000.
* With the flag: fire / proton / C= / right button / thrust do nothing (shots, protons, `MAPOPEN` unchanged), crosshair and enemy
  fire still run; the star step count falls to 0 within about 400 frames; TIME keeps running; `TICKHK` squadron move stopped.
* Jump with energy poked low mid-jump: arrival at the chosen sector within about 100 frames, then stranded.
* Flash: colour toggle every 15 frames below 2000, none at 2000+.
* Parity against the original with `fx.js`-style fixtures (hyperspace poke at `B3DA` 32; the user's two saves: flag frame, phase-1
  length about 400 frames, hit count) and a regression that a full refill (base docking) clears nothing it should not.

## Addendum: the "0999" in hyperspace (states frame5535 and frame5212)

States: both are in the jump to sector 19 (`$BA`=1, `$E5`=3, map `$B8`=1): 5535 has energy 0045 (`$B3DA` 44 steps left), 5212 has
1158 (70 steps left; no out-of-energy in the 1158 frames to the arrival, energy 0818 at the end).

* **0999 is the normal count, not a glitch.** 1000 - 1 = 0999 through `$F8A1`'s ones/tens/hundreds borrow (seen in 5212 as `1999 -> 0999`,
  then `0998`). The jump, and above all the deflector (fire held in hyperspace: `$270D`, `$F8B2` + 5 x `$F8A1`, 15 a call, about 10-15 a
  frame), drains 10-15 units a frame, so the display runs 0999 -> 0000 in about 70 frames and ends in the message; the screenshot caught it on
  the way. The jump alone costs about 0.3 unit a frame (5212: 1158 -> 0818 in 1158 frames).
* **HUD values, 5535 (energy 0045), at frame ends:** ... 0045 0044 ... (the tens borrow shows 0049 / 0039 for a few cycles inside `$F8B2`)
  ... 0001 0000, then the flag. The wrap itself is `0000 -> $F8B2/$F8A1 borrow -> 0009 -> 0099 -> 0999 (written at $F8D4) -> $F8E0 ->
  0099 -> 0009 -> 0000` within about 20 cycles (0 of 60 frame ends showed 0999), then `$9C5C` prints the message. In the jump the drain does
  not stop at the flag: `$F8A1`/`$F8B2` run on, so `$F8E0` fires 5 times in the 5535 jump (the text is printed again each time, `$F209` := `$41`).
* **Exit path:** after `$F8E0` (frame 5) `$B6B1` (the jump step loop, 399 passes) skips the 38-pass delay: `$B3DA` runs 44 -> 1 in 49 frames,
  then `$B716` (the deceleration, 342 passes) takes about 46 frames and `$BA` = 0 at frame 100: out of hyperspace about 100 frames after the
  0000, in the destination sector, then `$F927` strands the ship. `$B4BD` is only the acceleration loop (not reached in these states).
  The second screenshot (ENERGY 0000, shields 00, targets 03) is the stranded state after the shields were shot away.
* **Plan changes:** the trigger must be once-only (the port's deflector costs 10 a frame in the jump and would reach 0000 repeatedly; the original
  prints again each wrap, the port once); no 0999 transient to copy; the jump shortcut is a step per frame once the flag is set.

## Progress (the port, 2026-11-21)

Implemented as planned. Files: `c128-game/energy.asm` (zero-page code), `energy-pads.asm` (code in game.asm's zero padding), `bank1.asm`
(`OEIN`, `OECLRM` in the copy stub's tail, B1INIT copies the zero-page code), `build.py` (hooks and staging), `game.asm`, `ending.asm`,
`mines.asm` (one-instruction hooks), `js/test/out-of-energy.js` (new; registered in `run.js`).

* **Memory (no resident byte moved, fixed symbols unchanged):** the resident core's 33 free bytes and the glue's 1 byte are untouched, as are
  the TITLE package (0 left), the low stream (ends `$DCD1` as before) and the tunnel stream. The code lives in what was free *and already in the
  PRG*: zero page `$2D-$C1` (149 bytes: data 3, code 146; the README's zero page is free and common to both banks), staged in the padding of the
  ending payload (the 8th page had 149 spare bytes; B1INIT copies them, +10 bytes in the init staging that the TITLE streams absorbed: its
  staging holes are now 676 / 63 bytes instead of 687 / 44), the copy stub's tail (`$0155-$0179`, 37 bytes of the 43 the stub's slot had), and two
  runs of zero padding in game.asm (`g_gi9`: 26 bytes, `g_mowipe`: 8 bytes). Zero padding inside the compressed low block costs PRG bytes
  (code compresses worse than zeros): the first try overflowed the low stream by 27 bytes, so only the uncompressed glue's pads are used.
  Free now: zero page `$02-$2A` and `$C2-$FA` (the memory test's fill list was changed accordingly), the stub page `$017A-$01BF` (70 bytes),
  the ending core's `$0C3F-$0C5F` 33 bytes, high 2, packed 8 and glue 1 as before. Left in the zero-padding: `g_mowipe`'s 2 bytes, 11 + 10
  bytes at `g_mcwipe` / `FHROW`, 16 + 13 + 11 bytes in the low block (cost PRG if used).
* **Behaviour:** passive -1 per 110 frames (`HENERGY` with A=110, once a frame from `TICKHK` -> `OEWORLD`, not in a jump, with the map open and
  in bases too); flash 7/8 every 15 frames below 2000 (`$D83E-$D841`); the digits' wrap in `ENERGY10` (`en3`, the original's `$F8E0`) runs
  `OESET`: flag `OEFLAG` ($2D), the message `OUT OF ENERGY` through `MSGSTAT` (colours `$81`, rate `$10`, 255 flips as `$9C5C`'s call) and
  `SNDRUSH` (the original's `$0912` rattle was 22 bytes more: a 48 frame rising sweep instead), digits 0000; once. `HENERGY` no longer stops at
  0000 (`CMP #$FF` never equal), so the deflector or a shot at 0000 reaches `ENERGY10`'s wrap, in a jump too. Gates after `INPUT` (`OEIN`, in
  `HINPUT` and the mine sequence's input hook): JOY := `$FF`, FIREFLAG, TREQ := 0, CPREV := 1 (no C= / right-button edge), so no steering, phasor,
  proton or map; the crosshair has moved already. Stars (`STARS` entry patched to `OESTARS`): every frame, then every other frame, every 4th,
  then none, by `OET / 64` (255 frames; the original's slow-down lasts about 400, its rate falls from 27 to 14 steps a frame). The world's clock
  stops (`WTCNT` held at `$FF`); enemies, fire, warp-ins, the crosshair, radar and the TIME clock run. In a jump with the flag: `HTIME` := 1 and
  `HACC` := `$FF` every frame, so the acceleration ends and a step takes a frame; the deceleration (120 frames) runs as before. The flag, `OET`
  and the flash counter are cleared by `OECLRM`, called from `ENDRESET2` in place of its first store, i.e. by every game-over, victory and F7
  restart.
* **Deviations from the original** (measured: the jump test arrives 182 frames after the energy runs out, the original about 75-100 because
  its deceleration loop is shorter; the star slow-down 255 frames, not 400; no `HSPD` reset in the jump; one message, not one per wrap; rising
  sweep instead of the rattle). Each is bytes: the zero page is full (149 of 149).
* **Tests** (`js/test/out-of-energy.js`, 13 checks): the tick (flight and map open), the flash, the trigger and the message once, every gate (phasor,
  proton, map with C= and the right button, steering) against a control, the crosshair, OVRUN and late splits, the stars' stages, the world's
  clock, the jump (energy runs out at frame 7 of the jump, arrival at the chosen sector, flag and message on arrival), and the reset (die out of
  energy, F7/button restart: flag 0, energy 9999, the phasor fires again).

### Final status: `node js/test/run.js` ends with "all checks passed"

What the four failures were, measured, not guessed:
1. **Fight late writes, overlay frame-for-frame:** phase, not per-frame cost. The init got 2968 cycles longer (the copy of the zero-page code and
   the longer stub), which moves where the game starts in the frame; the world's seed and the SID noise (`$D41B`, the fights' random numbers) then
   differ and these chaotic fights run differently (with every hook of this feature switched off, in the JS machine, the fight test still
   failed). `B1INIT` now has a delay loop (`LDY #4 / LDX #200`, constants only) that puts the init at a phase where the fights, the overlay test and
   the repair test pass. A delay that makes the init a whole frame longer (exact phase equality: `LDY #46 / LDX #159`) passes the fight test too but
   makes the harness's fixed frame counts fail (the mines test), so it is not used. Four small delays were tried in parallel full runs: only 4000 cycles
   passed. The init stays in the same frame (18) as before. The stub's staging slot shrank from 128 to 122 bytes (its real size, asserted) to pay for the loop.
2. **Repair beam 108/97:** the per-frame energy code (`OEFRAME`, about 60 cycles in `TICKHK`) took the beam's free time (without it 104/97). In
   MSSTATE 1-15 (a base's sequence before its tunnel, incl. docking) the energy neither ticks (the original's `$BA` = 1 there, energy counts
   up) nor flashes, and returns at once (the scenario with energy 0000 also no longer ends up out of energy before the report).
3. **Victory, energy 9999:** the tick ran after the refill; it is now off while `ENDMODE` is not 0 (an ending: the original does not tick there either:
   its IRQ routine needs `$BA | $88` = 0 and the ending/death loops are not flight).

**The warp-in** (the user's note): in the original the F927 loop forces it: `$F96B-$F976` set `$BA` = 0, `$FC` = 0 and `$FB` = 1, and the loop
calls `$1AF2` every 16th pass, which sees `$FB` and runs `$FF1B` (WAVEINIT: the three fighters' places) and the points' rush; measured in the user's
states 8219/8241 (the base's tunnel): `WAVEINIT` once, about 540 frames after `$F8E0`, alive flags 000 -> 111. It is not the normal squadron logic
(none was due: the sector's own group was already gone) but a forced trigger, also in the tunnel. Port: `OESET` sets `ARRFX` := 1 (the port's
arrival: points rush in, `ARREND` puts three fighters in place, at least 3 ships in the sector) when `MSSTATE` is 0, i.e. at once when the energy runs out,
not after the slow-down (the zero page has no bytes left for a timer). Not done: in a base's sequence (`MSSTATE` <> 0, the tunnel of the user's
states) no warp-in is started, because the port's arrival draws in the 3D view and the tunnel's raster code owns the screen there. Test: `out of
energy: the warp-in is forced` (empty sector, three fighters alive, rush frames seen) and `no warp-in is started in the middle of a base's sequence`.

**Deviations still open** (each costs bytes, the zero page is full: 149 of 149): the star slow-down is 255 frames (about 400 in the original); the
jump arrives about 180 frames after the energy runs out (75-100 in the original: its deceleration loop is shorter); the warp-in starts with the
message (the original: about 380 frames later, after the slow-down); the tone is `SNDRUSH`; the message blink rate is whatever `MSGRATE` held; no tunnel warp-in.
