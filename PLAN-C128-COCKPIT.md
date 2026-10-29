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

### Type-1 fighters, step (a) of the dogfight (this branch)

A type-1 wave starts with the cockpit (`NEWWAVE` / `WAVEINIT`, original
`$FF1B`): three twin-pod fighters fly their movement streams (`MOVEN`, original
`$2F6D` / `$2FB9` / `$3005`, one step per frame), drift back toward the middle
of the view every other frame (`EDRIFT`, `$33B6`) and become sprites 4-6 every
4th frame (`PLACE`, `$2E36` / `$2E86`), shaped by depth (`$20-$2F`), yellow,
light green and white. `js/test/run.js` starts the same wave in the original and
in the port and runs both for 2000 frames: positions, sprites shown, shapes, x
and y are identical in every frame.

Port notes: the fight code and the streams live at `$8000-$8FFF` (bank 0 RAM
under the BASIC ROM, visible with MMU `$0E`); the fighter and shot shapes sit in
bitmap rows 0-2 and 23-24 (`$6000-$63BF`, `$7CC0-$7FFF`), which are behind the
HUD and bottom text strips and never shown as bitmap, so the VIC can use them as
26 more sprite slots; the fight runs between the gun split (line 194) and line
230, because the star field already fills the vertical blank (up to 113 of 126
lines). In the original the carry going into the drift's comparisons comes from
unrelated code; the test sets it, so in play a drift step can differ by one unit.

### Steering, hits and explosions, steps (b) and (c) (this branch)

- **Steering** (`STEER`, original `$39C1`): translated instruction for
  instruction from the disassembly (every line keeps its address as a comment).
  The joystick byte (with the mouse patch's mask: the crosshair off centre steers)
  rotates every fighter around the ship. The test runs the original and the port
  with a scripted joystick for 2000 frames: identical. Steering takes up to 18
  lines a frame; it runs in the vertical blank at 2 MHz (see below).
- **Hit test** (`SHOTHIT` / `HITBOX`, `$3244` / `$324C` / `$3371`), once a frame:
  in the last 10 points of its path the shot hits a fighter shown within 12
  pixels across and 10 down. A fighter takes `ETYPE` shots (`EHITS`, `$C59A`); a
  hit that does not destroy it ends the shot. A kill: the fighter is gone, the
  shot disappears, TARGETS on the HUD counts down (`$3CC4`), kills are counted.
  The test fires at fighters in both programs (kills, a two-shot fighter, misses):
  identical.
- **Hit sound and flash** (`HITSND` `$3349`, `FLASH` `$1321`, `HITSND2` `$C3A8`):
  voice 2 noise, and the 3D view's background and border go light blue, blue,
  light blue, white, blue, black (6 frames each).
- **Explosion** (`EXPLODE` / `EXPTICK` / `PSTEP`, `$16B3`): 26 white points (the
  first 12 two pixels tall) fly apart from the fighter's place, drifting with its
  last step, in 20 steps that come faster; plotted only into empty pixels and
  erased only where still white. The test runs 3 explosions in both on the same
  bitmap: points and bitmap identical at every step. The original counts main
  loop passes between steps (about 8 a frame in a fight), the port counts 8 a
  frame; a step (up to 76 pixels) is spread over the free time of the 3D view
  and the fight slot, with a raster check per point.
- When all three are destroyed a new wave of three comes (the squadron and wave
  bookkeeping, `$3CD6-$3D4B`, belongs to the approach phase, not done yet).

Found in the original: a kill with the fighter's sprite above y 60 (or at 240
and below) jumps from `$3320` to `$3337` with a byte still on the stack, so the
interrupt's RTS goes astray (a crash, presumably rare in play); the port pulls
the byte. The explosion's points can reach bitmap rows 0-2, which in the port
hold sprite shapes, so the port does not plot there (hidden behind the HUD
anyway).

### Enemy fire and the ship being hit, step (d) (this branch)

- **Enemy fire** (`EFRAME` / `EFIRE`, `$C947`): the fighters take turns; when the
  delay runs out (by difficulty) the one whose turn it is fires if it is shown at
  x `$44-$FF`, y `$6C-$B3`. The shot is sprite 2, single colour, doubled, its
  colour cycling, shapes `$67` up to `$70`, moving away from the middle of the
  view; at `$70` it reaches the ship. The original calls `$C947` once per main
  loop pass (about 16 a frame); the port calls it 16 times a frame.
- **The ship hit** (`SHIPHIT`, `$84D7` / `$85D9`, the map program's model): a
  random working system loses a point, the shields one point (HUD), below 0 the
  ship is lost (`SHIPLOST`; the game-over sequence is not ported, the cockpit goes
  on). Difficulty `DIFF` (0-4, default 1) sets systems, shields and the fire rate.
  The destroyed-system messages are not shown yet (no message line in the
  cockpit).
- **Flash** (`$1321` with `$1303`): white, light red, orange, white, red, black.
- **The second explosion** (`EXPLODE2`, `$9DAA`): 12 points, all two pixels tall,
  where the shot reached the ship; generated from the first.
- The test runs enemy fire in the original and the port at difficulties 1 and 3
  for 3000 frames each (16 calls a frame): shots, positions, shapes, steps, the
  explosion's start and its points are identical. Quirks kept: the steps worked out
  from the fighter's stream at launch are dropped (`$CA13`); the step test reads
  zero page `$04` instead of `#$04` (`$CB6C`); the second explosion never checks
  its y at the start.

**2 MHz in the border.** The frame was full (star field 113 of 126 vertical blank
lines, the fight slot 194-230 nearly full). The cockpit now switches to 2 MHz
(`$D030` bit 0) from line 251 to line 47, where the VIC-IIe fetches nothing
(sprites off, no bad lines): the star field, steering, enemy fire and explosion
work run there at twice the speed. The JS machine's raster timing follows `$D030`
(it used to scale the whole frame). Steering now runs there whole, after the star
field (one step before the movers instead of after them). In 6000 frames of aimed
play no slot runs late and no frame overruns.

Not yet: the approach and the arrival of the wave, the tracking computer, types
2 and 3, the squadron count, the game-over sequence, system messages and what a
destroyed system disables.

## Next (from the user, 2026-10-29): one program, the approach, the scanners

### A. The map and the cockpit as one program

The user's idea: the map program's grid in the cockpit, squadrons only in the
sectors where the map has them, and for now an instant jump from sector to
sector (hyperspace later). How:

- **One `.prg`**: the map's code (`c128-map/map.asm`, `$1D00-$37FF` today) moves
  into bank 0 RAM beside the fight code (`$8C00+` / `$A000+`); the shared tables
  (`YLO`/`YHI`/`XLO`/`XHI`, `RANDOM`, `PIXADDR`) are kept once; labels that clash
  are renamed.
- **The bitmap is shared** (`$6000`), as in the original (the map clears it,
  `$BA72`, and draws the grid): going to the map saves nothing, coming back
  redraws the cockpit art from a copy. The copy (8 KB bitmap + 1 KB matrix + 1 KB
  colour) goes to RAM bank 1 (the C128's second 64 KB; the MMU's common RAM lets
  the copy routine reach both banks) or, if it fits, bank 0 `$A000-$BFFF`.
- **The VIC bank** stays bank 1; the map's planet sprites (`$4E40`, pointers
  `$39-$3C`) and the VDC character data (`$4000-$43FF` in the map program, the HUD
  font in the cockpit) are only copied to the VDC once, so they can live anywhere.
- **The world**: `STATE` / `COUNT` (the map's sector table) decide what a jump
  meets: type 1-3 and the number of ships; an empty sector has no fighters.
  `TARGETS` on the HUD = `COUNT`, as the original sets it on arrival (`$FCE9`). A
  kill lowers `COUNT` (`$3CD9`); the last one empties the sector (`$3CDE`).
- **Keys**: the right button / C= opens the map (as in the original), choosing a
  sector and fire jumps at once (hyperspace, step 3, replaces this later).

### B. The approach phase and the long range scanner (traced)

What happens on arrival in a squadron's sector (`$FCE1-$FD7A`, `$C6A9`):

- The squadron (`COUNT` ships) is split into **groups of up to 3**
  (`$C593-$C595`, `$3D58`), placed far away; `$E3` = 1 (approaching).
- The approach loop `$C6A9` steers (`$39C1`, every 4 passes), moves, and every
  32 passes checks each group's **distance** (`$2C43`): `|x - $88A0| + |y - $8890|
  + |z - $8690|`, 16 bits. Below `$0400` the group **arrives** (`$C749`): it becomes
  up to 3 fighters around its position (`$FF1B` + offset), the dogfight starts.
- **Fire selects the next group** (`$3801-$382A`, needs the long range scan
  sequencer `$3F`), with a sound (`$38D0`).
- **Closing in** (`$C848`): when the chosen group is in front (`$C847` = 1) and the
  long range scanner's side and up readings are both 0-3, the ship rushes forward:
  12 depth steps of -6 per call (`$C81E`), the speed `$F209` and its sound.
- When all fighters of a group are down, after a pause (`$C8D4`, 15 counts) `$E3`
  goes back to 1: the next group is approached.

**The long range scanner's numbers** (`$382D-$38CF`, text row 23, `$57A1-$57B5`):
three readings for the chosen group, X (side), Y (up) and Z: each from the high
byte of the coordinate minus 8 (`$389C`), a sign glyph (`$6B` / `$6D`), and the
size looked up in a table at `$ED00` (most likely an angle table: it turns an
offset into degrees), shown as two decimal digits. Side and up both 0-3 = the
group is straight ahead (that is what `$C848` waits for).

**The number under the crosshair** (`$3935`, a sprite with three digits): the
distance (`$2C43`) of the chosen group (approach) or of the first live fighter
(dogfight), high byte / 2, in decimal. **Its colour**: white (`$01`) when the
target is in front (depth at or beyond `$8690`), light green (`$0D`) when it is
behind. 000 when TARGETS is 0.

**Flying from sector to sector without a hyperspace jump**: in the code the
ship's sector (`$92` / `$93`) is written only at the start (`$2100`) and on
hyperspace arrival (`$FCD0-$FCDF`, with the coordinator's random column error).
Thrust (`$FEA7`, `$C81E`) only moves the objects in the sector closer. So far
nothing shows another way; to check in the game: a write watch on `$92` in the
page's debugger while doing it shows which code changes the sector.

## Next, in a suggested order

### 1. Enemies in the view and the hit test (start of the dogfight)

What the code says about the enemies (found with the JS workbench; labels in
`js/c64-symbols.txt`):

| Squadron type | Map colour | Enemy | Shapes | Shots to destroy |
|---|---|---|---|---|
| 1 | light blue (`$1E`) | twin-pod fighter (the small H) | `$20-$2F`, 16 sizes by distance (`$2E86`) | 1 |
| 2 | light green (`$1D`) | spiky ship, multicolor | `$3E-$44` by distance (`$2EBE`, table `$2EAE`) | 2 |
| 3 | purple (`$14`) | lens ship / saucer, multicolor | `$31-$38` by distance (`$2F18`, table `$2F08`) | 3 |

- The squadron type of the fight (`$A5`) picks the shape routine by patching a
  jump (`$2E7B`, targets at `$2E30` / `$2E33`, set at `$C80C` and `$FFAF`).
- Up to **3 enemies at once**, sprites 4-6; a squadron comes in waves
  (`$C593`). Each enemy has a position: x `$16/$17`, y `$1C/$1D`, depth z
  `$22/$23` (16 bit, X = 0, 2, 4); the depth picks the shape size.
- Each enemy's hit counter (`$C59A-$C59C`) starts at the type number
  (`$C7A6`); a hit lowers it (`$32A7`); at 0 the enemy is destroyed (`$32BE`),
  otherwise the shot stops there and the enemy's colour steps (`$2EC4`).
- Enemy fire is sprite 2, shapes `$66-$70` growing as it comes in; sprite 3 is
  the right gun; sprite 0 the crosshair, sprite 1 the player's shot.
- Seen in the start sector: three type-1 fighters at once, shields 40 to 24 in
  about two minutes.
- Others: **mines** around the motherships (`$71-$7C`, `$CCDF` / `$CD27`), and the
  enemy mothership's proton torpedo (see step 4); both belong to the mothership
  sequences.

#### How a fight runs (traced in the original, with the user's description)

**Phase 1, approach.** Entering a squadron's sector, the three position slots
(x `$16/$17`, y `$1C/$1D`, depth `$22/$23`, X = 0, 2, 4) hold up to three
**groups** of fighters, far away (values like `$06xx-$0Dxx`). The player turns
the ship (`$39C1`, rotation of every slot around the ship, all four directions,
about 700 bytes) to bring the selected group to 0 bearing and 0 pitch on the
long-range scanner; fire switches between groups (user). The ship then closes in
fast (user); the range shows under the crosshair. The loop is `$C6A9-$C746`:
every pass it checks whether a group is close enough (`$2C43`, `$2CDE`).

**Phase 2, the group arrives.** `$C749-$C7C0` turns the group into fighters:
its position becomes an offset (`$2B-$30`), `$FF1B` sets the three fighters'
start positions (x `$888C` / `$8850` / `$88AF`, y `$8880` / `$888C` / `$8864`,
depth `$8B14` / `$8B28` / `$8B00`, i.e. beyond the visible depths) and their
movement streams, the offset is added, and hit counters and alive flags get the
type. They then come in one by one, at most 3 on screen (user).

**Phase 3, the dogfight.** Per main-loop pass (the loop is not tied to the frame:
about 16 passes per frame in the JS machine, a little fewer on a real C64):

| What | Original | How often |
|---|---|---|
| fighters fly their movement streams | `$2F6D`, `$2FB9`, `$3005` (one each) | every 16 passes (about once a frame) |
| steering moves (rotates) them around the ship | `$39C1` | every 4 passes |
| attackers drift back toward the middle of the view (x `$8832-$890E`, y `$885E-$88AE`, depth `$8640-$87E0`, 4 units per call) | `$33B6` | every 32 passes |
| the ship's thrust: held key `$FDE6` speeds up (`$F209`), costs 10 energy per step, brings all slots closer (depth -6 per `$C81E`) | `$FEA7` | every 4 passes |
| automatic tracking computer: while system 4 (`$3D`) works and tracking is on, it steers the ship toward a target fighter; destroyed, it switches off (`$89EB`) and the fighters drift out of view (user) | `$89E6`, `$8B49`, `$8BED` | every 32 passes |
| fighters -> sprites 4-6 (shape by depth, hidden outside x `$8751-$894F`, y high byte `$88`, depth `$86xx-$87xx`) | `$2E36` x3, via the patched jump `$2E7B` | IRQ, every 4th frame |

**Movement streams** (type 1): three tables of signed steps (bit 7 = minus,
`$2BEF` / `$2C0B` / `$2C27` add them): x `$E800`, y `$EA00`, depth `$EB00`, 512
steps each, looping; the three fighters start at offsets `$00`, `$AA`, `$54`.
A fighter takes one step per call for type 1; types 2 and 3 step every 1 and 2
calls (`$2F8B`), so the bigger ships move more slowly. Types 2 and 3 use other
x / y tables (`$FF15`, `$FF18`).

**Port notes.** The cockpit is frame-locked, the original is not: one stream
step per frame matches the original's rate in the JS machine (0.99 per frame).
VIC bank 1 has exactly 16 sprite slots free (`$4C00-$4FFF`; `$5000-$5FFF` shows
the character ROM on the C128), so the shot and the fighters get one slot each,
refilled from shape tables kept elsewhere. Bank 0 RAM `$8000-$BFFF` is free with
the cockpit's MMU setting (`$0E`) for the new code and tables.

Suggested order inside this step: (a) the dogfight with one type-1 wave:
fighters on their streams, the drift, the sprites by depth; (b) steering
(`$39C1`); (c) the hit test and the explosion (`$60-$63`); (d) enemy fire and the
player being hit (`$84D7`); (e) the approach phase (groups, long-range scanner,
group selection, closing in, fighters arriving one by one) and the tracking
computer; (f) types 2 and 3; (g) waves and the squadron count. Open question from
the user: can the enemy mothership's torpedo be shot down?

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

How the user remembers them: the motherships are drawn as concentric strange
circles that grow as the ship closes in; the enemy (orange) mothership fires a
proton torpedo, a rotating triangular 3D object; the friendly (blue) mothership
reaches out with a tractor beam (two rays of light from the mothership to the
player) and repairs the ship. What the code shows so far:

- **The approach** is the loop at `$90F3`: every 128 frames the radius `$43`
  grows and the mothership is drawn by `$3635` / `$364C` (a routine that takes a
  radius: the concentric circles). It ends when the radius reaches `$22`.
- **The enemy torpedo**: on an enemy mothership (`$E2` set) at radius `$19`,
  `$916C` starts it (`$CF01`). `$CF04`, called every 16 frames, plays a
  pre-rendered animation: 31 frames of 128 bytes from a table at
  `$A000-$AF80`, copied into the shapes `$45` / `$46` (`$5140`) and shown as two
  X-expanded white sprites side by side (sprites 5 and 6, x `$8C` / `$A1`). So the
  rotating triangle is drawn in advance, not computed. After the 31st frame
  (about 10 seconds) it hits: five hits at once (`$CF8C`). To find: whether it can
  be shot down (the hit test's sprite slots) or dodged.
- **The friendly mothership**: tractor beam and repair, not traced yet; the
  repair list is at `$932D` ("ENTERING BASE SECTOR" `$3FB9`, see
  `SHIP-STATUS.md`).
- Entering a mothership sector: `$FBFB` / `$FC77`; mines `$71-$7C` (`$CCDF`,
  `$CD27`).

## Open questions

- Memory: the cockpit, the map and the fight together will not fit the current
  layout (code `$1D00-$2CFF`). Bank 1 RAM, or splitting code by screen, has to be
  decided before hyperspace joins the programs.
- The original runs the shot in its IRQ; the cockpit polls the raster. A raster
  IRQ (noted in `PLAN-C128-MAP-GUI.md`) would make adding the fight easier.

## Enhancement ideas (optional, from the user)

- **Target rectangle during the approach**: while turning toward a fighter group,
  draw a rectangle on the screen where the selected group is (the port knows its
  bearing and pitch), instead of only the numbers under the crosshair.
- **Elite-style 3D radar**: show each contact's height above or below the radar
  plane with a vertical line from its blip, like Elite's scanner.
