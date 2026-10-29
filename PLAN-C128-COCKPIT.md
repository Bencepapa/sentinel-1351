# C128 port plan: the cockpit becomes the game

Branch `c128-port`. The native C128 cockpit (`c128-gui/cockpit/cockpit.asm`)
grows feature by feature until it plays like the original. Each feature is
ported from the C64 code and checked against it.

## How the work goes now

The `.asm` files stay the source; the browser runs the PRG that `build.py`
assembles, unchanged. So "updating the JS version" and "updating the PRG" are the
same step: edit `cockpit.asm`, run `python js/build.py` (or commit, and the
pre-commit hook does it), reload the page.

For each feature:

1. **Find it in the original** with the JS workbench on the C64 game: write
   watches (`w ADDR`) on what changes on screen, breakpoints on the routine,
   `d LABEL` to read it. Add the labels to `js/c64-symbols.txt`.
2. **Record what the original does** by calling its routines directly in the
   headless C64 machine with chosen inputs (no need to play to the right moment):
   the phasor test in `js/test/run.js` is the pattern.
3. **Port it** to `cockpit.asm`, routine for routine, keeping the original's
   addresses in comments.
4. **Compare** the port and the original in the same test, frame by frame, and
   check the timing (the cockpit's raster schedule leaves the vertical blank for
   input and stars, and lines 78-194 free while the 3D view is drawn).
5. **Look at it** in the page, and in VICE / on real hardware when timing matters
   (the JS machine does not steal cycles for bad lines and sprites yet).

## Done

### Phasor shot (this branch)

Original `$1424` (per frame, in the IRQ), `$1467` (launch, from the main loop),
`$1526` (one of 48 sub-ticks per frame), line routine `$3580`, sound `$15C7` /
`$15E0`, energy `$F8B2`.

- Holding fire arms a shot; the next pass launches it from a gun: the left gun
  when the crosshair is right of the middle, the right gun otherwise (they cross).
  The aim point moves 2 pixels every other shot (`$1417`).
- The path is a line from the gun to the crosshair (x stored halved, bit 7 = sprite
  x bit 8). The shot (sprite 1, multicolor, shapes `$70` down to `$67`) walks along
  it: a step every few sub-ticks, the gap growing by one each step (it slows as it
  recedes), a smaller shape every third step, 1 or 3 points per step from a
  fraction scaled by the path length.
- Pressing fire sets a flag (`$D0`, written only on a press by the input code
  `$02CB-$02D6`, cleared at the end of the shot `$158E`), so one press fires a whole
  shot and holding fire fires the next one as soon as the first is gone. (A first
  version of the port and its test cleared the flag on release, which froze the
  shot in mid-air; found by the user.)
- Yellow at launch, cyan after: the original's colour lookup reads a byte of its
  own code (`LDX $1520` / `LDA $1520,X` = `$1527` = `$13`).
- The gun that fired is red while the shot flies (`$1241`); a shot costs 10
  energy on the HUD; shots are counted (`$F43B`, used in the rating).
- The last 10 points of the path are the hit test window (`$3370`, `$1616`); the
  test itself (`$B7BA`) compares the shot with the enemy sprites. Not ported yet:
  there are no enemies.

Port differences: the path is made 24 points per frame instead of all at once
(the original's main loop can spend a whole frame on it, the cockpit's polled
loop cannot); the phasor work runs between lines 78 and 194. The test compares
five shots frame by frame with the original (path, shape, position, colour,
position on the path): identical.

## Next, in a suggested order

### 1. Enemies in the view and the hit test (start of the dogfight)

The squadrons: twin-pod fighters (shapes `$20-$30`, several rotations), lens
ships (`$31-$38`, multicolor), mines / drones (`$71-$7C`); enemy fire `$66-$70`
is the same shrinking sequence as the player's shot. Known entry points:

- hit test `$B7BA`: reads `$D01E` (sprite-sprite collisions) and the shot's
  position against the enemy sprites' shadow positions `$EB+`, for sprites 2-5,
  during the hit window; on a hit, `$CBFB` / `$CC01` tables, explosion shapes
  `$60-$63`;
- the ship being hit: `$84D7` is called from `$2953`, `$CA7B`, `$CD3B`, `$CF90`
  (enemy fire reaching the player, a ram, ...); `SHIP-STATUS.md` has the damage
  rules, already ported for the map program's ship panel;
- the squadron marker in the bitmap (`$3166`, a small H) is already in
  `c128-flight`.

To find first: the enemy movement and AI (who writes the sprite shadow
positions `$EB+`), how a squadron's size (`COUNT`) becomes sprites, what ends the
fight.

### 2. Scanners and the tracking computer

- long range scanner (system 1, `$3A`, read at `$30EC`), short range scanner
  (system 2, `$3B`, read at `$30D8`, `$9A5A`), scan sequencer (system 6, `$3F`,
  `$3813`): the rectangle under the view (the "radar" with the circle) shows
  them;
- automatic tracking computer (system 4, `$3D`, read at `$89EB`, `$8A5A`): the
  animated crosshair `$49-$4B` (already in the cockpit as the T key) and
  presumably steering toward a target (`$5C` non-zero while tracking).

Each is disabled when its system counter reaches 0, which ties into the ship
status panel.

### 3. Hyperspace

From the map, fire picks a sector; `$B700` counts the jump (`$B3DA` up to
`$3A`, `$B3DB` every 6), the star field changes, `$B764` returns to the cockpit
and recentres the crosshair, `$FCB8` sets the new sector `$92` / `$93` (off by up
to a column when the hyperspace coordinator, system 5, is destroyed), `$FBFB`
checks what is in the sector (`$FC77` for a mothership). The C128 map program
already has the map and the cursor; this joins the map and the cockpit into one
program, so it is also where the memory layout of the combined program gets
decided.

### 4. Mothership sequences

Entering a mothership sector (`$FC77`), the blue motherships as bases (repair,
"ENTERING BASE SECTOR" `$3FB9`, the status list `$932D`), the orange ones as
targets; the attack rings and the planet are already in the map program.

## Open questions

- Memory: the cockpit, the map and the fight together will not fit the current
  layout (code `$1D00-$2CFF`). Bank 1 RAM, or splitting code by screen, has to be
  decided before hyperspace joins the programs.
- The original runs the shot in its IRQ; the cockpit polls the raster. A raster
  IRQ (noted in `PLAN-C128-MAP-GUI.md`) would make adding the fight easier.
