# Out of energy: user VICE findings, 2026-11-24

Build tested: 2026-11-22 21:49 (uncommitted work). States in Downloads: c128_out_of_energy_in_hiperspace, frame4058, frame5224 (map, low energy).

## Running out in hyperspace
1. No flash below 2000 during hyperspace.
2. A long, loud, strong tone at run-out (new).
3. At 0000 the counter flashes and OUT OF ENERGY appears in the right place, but black, not blinking.
4. Tone and black text last until the jump counter reaches the target. It worked earlier, so the latest (uncommitted) change probably broke it.
   Expected: leave hyperspace at once and decelerate; counter flashes below 2000; message appears and blinks at once (or after the deceleration); the ship stops fully within 200-400 frames. The hyperspace deflector must not work meanwhile (minor).
5. Any shield use while out of energy breaks the top and bottom HUD (minor, after the rest).
6. OK: after leaving hyperspace the ship slows, functions locked, steering and cursor work during deceleration, then 3 fighters warp in.

## Running out on the way to a base (friendly or enemy)
7. Now: arrival, message, minefield, mothership sequence, map; the game goes on with 0000 energy and another jump works.
   Expected: leave hyperspace at once. If it runs out in the raster tunnel: stop, mines vanish, the tunnel decelerates and stops (does not vanish), 3 fighters warp in, as on the C64. Needs raster time: second step, but required.
   Plan B: the tunnel always runs to the end with 0000. Friendly mothership: refills energy (player saved). Enemy mothership: either it stops at its largest size and fires a torpedo every few seconds until death, or after the sequence there is no map (no energy) and 3 fighters warp in. Preferred: fighters already in the tunnel.

## Retest of the hyperspace fix (user, same day)
Findings 1-4 work (flash in hyperspace, clean exit). Deceleration speed is fine as is: the star slow-down needs no change.
8. New: if an enemy is in the sector, the long range scanner locks on it and the ship jumps to it; only after that does it vanish and the 3 fighters come. State: Downloads/sentinel-game-frame3836.state.json. Original: no tracking when out of energy (check).
9. Tunnel state: Downloads/sentinel-game-frame10593.state.json (in the raster tunnel, 22 energy left; 3 shots run it out). OUT OF ENERGY shows, but the flight just continues.
Still open: failing test `game: in a fight the splits' colours change off the screen` (late $D020 writes; the B1INIT delay loop is gone), 5, 7.
