# C128 port: status, and how the original's fight works

The native C128 cockpit (`c128-gui/cockpit/cockpit.asm`), joined with the map in
`c128-game`, grows feature by feature until it plays like the original. Each feature
is ported from the C64 code and checked against it.

## Status

Done: the cockpit and its raster schedule, the phasor shot, type-1 fighters, steering,
hits and explosions, enemy fire and the ship being hit, the approach with the long range
scanner, the tracking computer, the message row, the voice 1 sweeps, the map in the 3D
view, a squadron coming into the ship's sector.

Left, in a suggested order:

1. **Hyperspace** (see below): the phases, streaking stars, energy, countdown, the path plotted on the map, the map's erase, the border's pulse, the engine sound, the long range scanner, positioning, meteors, dodging and the deflector are in (`HYPSTART`, `HYPVB`, `HYPVIEW` in `c128-game/game.asm`, code at `$C000`); the abort and a destroyed coordinator are next.
2. **Proton torpedoes**: done (`GTORP`, `TSTEP`, `TKILL`, `TBLAST`, `HTSPR` in `c128-game/game.asm`): SPACE / both buttons, 32 animation frames unpacked a step at a time from `TORPA` into the shot's slots `$F3` / `$F4`, the kill of every fighter in view, the orange rings. The `$E000` code and data are packed into the 3D view's bitmap and unpacked by GAMEINIT (`lz_pack`, `GUNPACK`). Still: thrust (W, `$FEA7`).
3. **Squadron types 2 and 3**: done (`GSQTYPE`, `GSHLOAD`, `GTYPE`, `GESHP`, `GSTRX` / `GSTRY`, `GCOLCYC` in `c128-game/game.asm`): the type's shapes are copied into the fighters' sprite slots a shape a frame from masters at `$E600`, type 2 flies its own streams (the original's `$0600` / `$8100`), types 2 and 3 are multicoloured and twice as wide, their colours step, white on the last hit.
4. **Mothership and base sequences**, mines, docking.
5. **What the other destroyed systems disable**, their messages, and game over. So far
   the scanners, the sequencer and the tracking computer act on their counters.
6. **Fighters warping in** when lingering in an empty sector (the manual; `$F96B`).

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
   (the JS machine steals cycles for bad lines and sprites only with `m.dma`).

## Done

### Phasor shot

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
  test itself (`$B7BA`) compares the shot with the enemy sprites.

Port differences: the path is made 24 points per frame instead of all at once
(the original's main loop can spend a whole frame on it, the cockpit's polled
loop cannot); the phasor work runs between lines 78 and 194. The test compares
five shots frame by frame with the original (path, shape, position, colour,
position on the path): identical.

### Type-1 fighters, step (a) of the dogfight

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

### Steering, hits and explosions, steps (b) and (c)

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

Found in the original: a kill with the fighter's sprite above y 60 (or at 240
and below) jumps from `$3320` to `$3337` with a byte still on the stack, so the
interrupt's RTS goes astray (a crash, presumably rare in play); the port pulls
the byte. The explosion's points can reach bitmap rows 0-2, which in the port
hold sprite shapes, so the port does not plot there (hidden behind the HUD
anyway).

### Enemy fire and the ship being hit, step (d)

- **Enemy fire** (`EFRAME` / `EFIRE`, `$C947`): the fighters take turns; when the
  delay runs out (by difficulty) the one whose turn it is fires if it is shown at
  x `$44-$FF`, y `$6C-$B3`. The shot is sprite 2, single colour, doubled, its
  colour cycling, shapes `$67` up to `$70`, moving away from the middle of the
  view; at `$70` it reaches the ship. The original calls `$C947` once per main
  loop pass; the port calls it 13 times a frame (see Speeds).
- **The ship hit** (`SHIPHIT`, `$84D7` / `$85D9`, the map program's model): a
  random working system loses a point, the shields one point (HUD), below 0 the
  ship is lost (`SHIPLOST`; the game-over sequence is not ported, the cockpit goes
  on). Difficulty `DIFF` (0-4, default 0) sets systems, shields and the fire rate.
  The destroyed-system messages are not shown yet.
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

## One program, the approach, the scanners

`c128-game/` joins the cockpit and the map (see its README): the map opens in the 3D
view with the fight going on behind it, fire on another sector jumps there at once,
the world's clock runs all the time, the sector's squadron comes in groups, TARGETS and
the kills follow the map's COUNT. The cockpit picture's master copies are at
`$5000-$5FDF` (bank 0 RAM the VIC-IIe cannot use).

### The approach phase and the long range scanner

**Ported** (cockpit and c128-game): arrival (`ARRIVE`), the groups' layout
(`LAYOUT` / `LYPLACE`, `$3D58` / `$3DA6`), the long range scanner's row with its
readings and blip (`LRSCAN`, `APINIT`, `BLIPPOS`, `$3776` / `$3736` / `$38E8`), fire
choosing a group, closing in (`CLOSEIN`, `$C848`), the arrival check and the group
becoming fighters (`ARRCHK`, `GROUPIN`, `$C730` / `$C749`), the next group after a
group is down (`KILL`, `$3D23`), the radar marks in the scanner box in both modes
(`RADAR`, `MARKER`, `$305F` / `$3166` / `$3138`), the number under the crosshair and
its colour (`NUMBER`, `DIST`, `$3935` / `$2C43`), and shooting down the enemy shot
(`HITSHOT`, `$3287`). The test compares distance, readings, radar marks and the
number with the original in 600 random cases; a play test aligns a group, rushes
in and sees it arrive. Per frame the port steers 4 times, drifts twice and rushes
the distance of 16 passes at once; the layout runs a group a frame in the vertical
blank; the approach's work uses the 3D view's time (no phasor then). Not ported:
sprites for groups that come close.
On arrival the original leaves the groups where hyperspace put them; the port lays
them out at once.


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
size looked up in a table at `$ED00`, which is linear: 0-127 becomes 0-99
(`n * 99 / 127`), shown as two decimal digits. So each reading is the group's
offset along that axis in 256-unit steps, scaled to 0-99. Side and up both 0-3 = the
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

## Reference: what the original does

### Enemies

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

**Frame budget** (measured with `m.dma`, the VIC's stolen cycles): colours change in
the horizontal blank (`WAITST`: a second look at the raster halves the polling's jitter;
line 76's are timed by the bad line 75). In a fight the fighters and the tracking passes run
in the 3D view's free time, or at 2 MHz when a shot's launch used it up (the stars
then wait a frame). 2 MHz runs from line 251 to 47: lines 243-250 show the text row with the lower screws,
so the VIC-IIe needs its accesses there. The squadrons' move and a squadron's
arrival run in the 3D view's time too (`VIEWWORK`).

**Speeds** (the original measured with `m.dma`, which matched what the user saw in
VICE; rates measured without it are too fast): stars 0.44 pixels a frame (0.48 in an
empty sector, 0.38 in a fight), fighters 0.79 stream steps a frame, enemy fire 13 calls a
frame, tracking 5.85 passes a frame, a shot about 25 frames (it charges 7 first).

**Port notes.** The cockpit is frame-locked, the original is not: its rates are
in Speeds above. VIC bank 1 has exactly 16 sprite slots free (`$4C00-$4FFF`; `$5000-$5FFF` shows
the character ROM on the C128), so the shot and the fighters get one slot each,
refilled from shape tables kept elsewhere. Bank 0 RAM `$8000-$BFFF` is free with
the cockpit's MMU setting (`$0E`) for the new code and tables.

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
- the squadron marker in the bitmap (`$3166`, a small H): ported as the radar's marks
  (`MARKER`).

### Scanners and the tracking computer

- long range scanner (system 1, `$3A`, read at `$30EC`), short range scanner
  (system 2, `$3B`, read at `$30D8`, `$9A5A`), scan sequencer (system 6, `$3F`,
  `$3813`): the rectangle under the view (the "radar" with the circle) shows
  them; **done**;
- automatic tracking computer (system 4, `$3D`, read at `$89EB`, `$8A5A`):
  **done** (`TRKCHK`, `TRKFRAME`/`TPASS`, `TAIM`, `TMOVE`). A (or T) asks for it;
  its own main loop `$8A34` replaces the fight loop: no steering, the view turns
  toward the first live fighter and pulls it into the view, "AUTO TRACKING
  ENGAGED" scrolls in row 23 (the system message scroller `$9BE5`/`$9CD3`/`$13D5`,
  ported as `MSGSCR`/`MSGTICK`/`MSGFRAME`), the crosshair animates. A destroyed
  computer switches it off. See FINDINGS.md for the rates.

Each is disabled when its system counter reaches 0.

### Hyperspace (traced 2026-11-03, JS machine with `m.dma`)

A jump from the map (`$FC9A JSR $B3E0`) runs three loops, `$BA` = 1 throughout:

| Phase | Code | Frames (one jump) | What happens |
|---|---|---|---|
| Plot and accelerate | `$B3F6-$B550` | ~230 | the map stays; the flight path is plotted (`$2B14`); the speed `$F209` falls `$41` to `$03`, so the stars stream; the map is cleared at the end (`$B4D7-$B53A`) |
| Hyperspace | `$B55D-$B6CE` | ~480 (this jump; it depends on the distance) | `$DA`=3, `$E5`=3; the destination's groups are set up (`$3D79`); meteors, deflector, energy, scanner, countdown |
| Decelerate | `$B6CF-$B755` | ~120 | `$F209` back up to `$41`; `$B755-$B78A` restores the cockpit, `$B8`=0 |

In hyperspace, per main-loop pass:

- **Meteors** (`$288F`, 3 calls a pass): up to 7 slots (`$2813` active, `$280C` delay), sprites 1, 2, 4, 5, 6 (via `$98`), shapes from `$66` growing (the enemy-fire shapes), start at x `$7B-$BA`, y `$61-$A0`. A meteor that reaches full size hits the ship (`$84D7`) unless the deflector is on.
- **Dodging** (`$B8D9`, every 16 passes): the joystick moves every meteor away, more for bigger ones, in all four directions (`$96` bits 0-3).
- **Positioning** (`$9A95`, every 2 passes): the joystick moves the destination's slots: left/right x by `$40` (`$2BEF`), up/down depth by `$40` (`$2C27`). So the ship can arrive nearer to a target (the manual's tip for mothership minefields).
- **Deflector** (`$270D`, every 4 passes): fire (`$97`) sets `$FD` = `$0D` (the hit routine `$84D7` does nothing while `$FD` is set), recolours the view (`$BA99` into colour RAM) and plays a tone; while held it costs 15 energy a call (`$F8B2` + 5 x `$F8A1`). Measured: about 300 energy in 30 frames.
- **Energy** (`$F8A1`, every 8 passes): about 1 unit a frame, ten times the normal rate.
- **Length of the jump**: the hyperspace phase counts `$B3DA` down from `$2B13`, the number of points of the flight path that `$2B14` plots on the map (`$3580`, stored at `$2B6D`); a step takes 38 passes (`$B3DB` = `$26`). So a jump to the far corner of the map takes longer. The acceleration phase is fixed (`$3A` steps).
- Stars `$F0B4` at speed `$03` (the long streaks), the scanner's readings and blip (`$3736`, `$3776`), the countdown `$B3DA` drawn in text row 17-20 (`$0813`), the drift `$33B6` and the map's tick `$BE29` every 128 passes, enemy-fire-style explosions `$9DAA` / `$16B3`.
- **Abort**: Crsr (`$FDED`) in the first two phases ends the jump at once (`$B442`, `$B5DD`), random destination column 1-8 and row 1-4 (`$B5E2-$B5F9`).
- **Hyperspace coordinator destroyed** (`$3E`): the destination column is off by up to one (`$FCBD-$FCD0`).

**Sprites in hyperspace:** 1, 2, 4, 5, 6 are meteors, 0 and 3 the guns in the lower split, 7 the barrels; sprite 0 in the upper area (the crosshair) is hidden (y 0). So the crosshair sprite is free for a mouse pointer, in the C64 game and in the port.

**Mouse in hyperspace:** with a mouse, the 1351 patch turns motion into joystick directions (`MSYN`, `$B8` is not 0 in hyperspace), so a direction lasts one frame per movement: meteors move only a little, and there is no feedback. With the crosshair shown at the pointer and its offset from the centre held as a direction (the cockpit's rule, `DS`), steering in hyperspace works like flight.

- **Port:** the crosshair stays on in hyperspace with a mouse; the cockpit's steering mask gives `JOY`.
- **C64 patch:** needs a hook in the hyperspace loop and about 60 more bytes, and the patch has none left. Candidate: sprite shape `$3D` (`$4F40-$4F7F`), a fifth globe frame that the planet's cycle (`$39-$3C`) never shows and no code addresses; to confirm with a fill test in play.

Port order: (1) memory: room for about 2-3 KB (bank 1 or the RAM under the KERNAL, see the Status's note); (2) the hyperspace loop with stars, energy, countdown, deceleration and the arrival (no meteors); (3) meteors, dodging, deflector, hits (done: `HMALL` counts the original's 8.4 calls of `$288F` a frame off at once, `HSPRC` puts the meteors on sprites 1, 2, 4, 5, 6 through a JSR switched at `sprcj`, the shield's lines are drawn while accelerating, `HDEFL` holds voice 1; more code at `$E000`, loaded at `$6400` and moved by GAMEINIT); (4) positioning and the scanner (done: at the jump `HSCANGO` lays the destination's groups out and puts them level, `$B58B-$B5C8`; `HSCANF` positions them, `$9A95`, and reads them out, `$3776`; `HARRIVE` keeps the slots; the radar's mode, the blip and the circles go in the vertical blank); (5) the plotted path and acceleration on the map (done: the path, a 2 x 2 brown point a frame, `$2B14`; the map's lines erased as by `$B0F2` with `$B077` set, brown pixels kept, about 230 frames; the border's pulse, `$09B7`; the engine, `$10DF` / `$1123` on voice 3; the rush, `$094E`, at the jump); (6) abort and a destroyed coordinator; (7) the mouse pointer, then the same in the C64 patch.

### Hyperspace: earlier notes

From the map, fire picks a sector; `$B700` counts the jump (`$B3DA` up to
`$3A`, `$B3DB` every 6), the star field changes, `$B764` returns to the cockpit
and recentres the crosshair, `$FCB8` sets the new sector `$92` / `$93` (off by up
to a column when the hyperspace coordinator, system 5, is destroyed), `$FBFB`
checks what is in the sector (`$FC77` for a mothership). From the manual: Crsr aborts
the jump; W holds the booster; the long range scanner runs, meteoroids come, fire works
the deflector (blue flash and energy, or red and a shield without it). Memory: the map's
code is full up to `$C000`, so the new code goes in the glue (`$5300-$5FFF`), or bank 1.

### Mothership sequences

Approach ported in `MSECTOR` / `MSVIEW` / `MSRING` / `MSSTEP` in
`c128-game/game.asm`. Enemy STATE `$80` maps to original `$E2=1`; friendly
STATE `$FF` to `$E2=0` (the port stores the kind in `MSKIND`).

Original control flow, checked against the unpacked v10 code:

- Sector entry is `$FCE1`, with the mothership branch at `$FD3B`: `$E1=1`.
  Enemy: `$8C3D=1`, **GORGANITOR BASESTAR DETECTED**, yellow/orange, ten
  flips at five-frame intervals, and the downward `$0921` sweep. Friendly:
  `$8C3D=0`, **ENTERING BASE SECTOR**, the same message timing, no entry sweep.
  `$FBFB` dispatches a negative STATE to `$FC77`, which is map/path work;
  these addresses alone do not set up the mothership sequence.
- `$8C3F` / `$8C44` establish the original long-range/pre-approach phase:
  `$E2=1` only for STATE `$80`, otherwise zero; `$8E8F` and `$8ED1` clear.
  The distance check at `$8D1C` leads through `$9054` and the `$0F7F` wait,
  then `$8D56` calls `$909D` if the sector still contains a base. The mines
  and this preliminary positioning phase remain deferred; the port starts
  the ring approach after the sector's closing wipe.
- `$909D` sets the view colours, and `$90D9` resets both circle operands
  `$3668` / `$3674` to 1. Centre is `$50,$64`, initial radius 1. The
  callback `$EF6B` plots value 3, preserving existing value-2 pixels.
  `$8ED2` sets the matrix to `$19` for an enemy and `$1B` for a friend;
  colour RAM is 2 / 6. The port limits fills to view rows 4-17 and keeps
  the cockpit/radar intact.
- `$90F3`: **128 loop passes, not 128 video frames**, between increments
  of radius `$43`. The second circle operand grows by 3 for an enemy,
  by 1 for a friend, producing the unusual concentric shapes. From
  radius 12, `$8F05` also runs with `$8ED1=radius`: this is the central
  rectangular opening, now ported (`MSCINIT`, `MSVB`). `$8ED2` patches its
  starting x/y to 75/100, width to 10 and height to 1. At radius r, with
  n=r-12, x=75-ceil(n/2), y=100-ceil(n/2), width=10+n, height=1+n.
  `$B39A` includes both endpoints, so the first rectangle is 11 by 2
  multicolour pixels. Nested outlines fill the rectangle as it grows;
  no rounded-corner routine is used. Value-2 pixels survive later circles.
  `$953F` sets matrix `$11` for a friendly base, making the opening white.
  The port uses this stable palette for both kinds; enemy random colour
  flickering from `$953F` remains deferred.
- **Different endpoints:** enemy `$917A` returns at radius `$22`; friendly
  `$9184` returns at `$28`. `$9162` also returns when our torpedo's blast
  flag `$BAD1` is set. The port has both radius endpoints and terminates
  its approach when the player's torpedo reaches its blast phase; it
  does not clear the base's map cell or award a base kill.
- With `m.dma=true`, booting the C64 game through its title/difficulty
  screens and entering `$909D` gives **234 frames enemy / 265 friendly**
  from radius 2 to the final radius. Growth intervals are roughly 6-10
  frames, including the drawing time. The frame-locked port measures
  **229 / 268 frames**, respectively; its cadence is a measured
  approximation, with rendering allowed to continue across frames.
  Tests rerun the original measurement, allowing at most ten frames
  difference, and compare **all 74 rings pixel for pixel**.

Deferred sequences and known exits:

- Enemy `$916C` arms `$CF01` at radius `$19`, clearing `$CF02` repeatedly
  while the radius stays there. `$CF04`, called every 16 loop passes,
  copies 31 animation frames backwards from `$AF80` toward `$A000` into
  `$5140` (shapes `$45/$46`), using two expanded white sprites 5 and 6,
  x `$8C/$A1`. It uses the same source art as `TORPA`. `$CF8C` applies
  five hits. The old estimate of ten seconds assumed one loop pass per
  video frame: in the measured approach the active interval was frames
  158-201 (about 0.86 seconds). Shoot-down/dodging still needs tracing.
- On normal completion, `$8D66` calls `$918E`: only a friendly base,
  with `$BACE`, `$BAD1` and `$8C3E` all zero, runs its two path/ring
  tractor-beam effect. `$92E3` then skips enemies and enters the friendly
  status/repair sequence at `$932D`. Neither effect is ported.
- Mines (`$71-$7C`, `$CCDF/$CD27`), destroying a base and the cleanup at
  `$8F53` remain later work. No repair/refuel/proton grant runs in this port.

Port integration and limits:

- `SECTORIN` calls `MSECTOR` in the existing three-byte slot. Mothership
  work switches `shpj` from dormant BIT to JSR; flight/fights retain their
  former instruction sizes, addresses and idle cost. Star plot/erase
  operands switch while approaching so stars do not erase the rings.
  Existing JMP slots `vv2` and `g_vs2` switch from STARS to `MSVB` while
  in a mothership sector, returning directly to STARS when no opening
  update is pending. No extra idle-flight/fight instructions are added.
- New code lives in the `$E000` chunk, ending below `$EDC0`. Type-1
  masters now occupy `$2900-$2CBF`, reusing the disabled VDC's data area.
  The build asserts VDC is disabled. The packed image starts at `$6200`;
  `GINIT2` restores overwritten type-1 sprite slots after unpacking.
  Standalone cockpit/map programs retain their original memory layouts.
- Colour fills use one row per frame. Circle work checks raster line 174
  before each eight-point step, yielding before the gun split; work is deferred
  altogether when a phasor has already used the slot through line 150.
  The center is filled a bitmap row at a time at 2 MHz in vertical blank,
  checking `TLATE` at line 256+16 and replacing stars on those frames.
  Completed filled rectangles are pixel-equivalent to the original's
  cumulative nested outlines; the outer circle schedule stays separate. DMA tests
  record zero late `$D020/$D021` writes in the sensitive split windows
  and zero `OVRUN` for both approaches. VICE x128 remains the hardware
  timing reference.
- Opening/closing the map wipes the bitmap and restarts the approach.
  The port waits at the final image, allowing navigation; it does not yet
  perform the original beam/repair, enemy weapon or post-sequence cleanup.
- Observed in the C64 original (user, VICE): after the sequence the map comes
  up by itself (a friendly base has repaired the ship; an enemy base is too close
  and its one proton torpedo has been fired, destroyed or not). The mothership's
  sector is then the only one the map will not jump straight back to: the
  player must jump elsewhere first and return to try again. Any other sector
  can be targeted again whatever is in it. To port with the post-sequence work.

## Open questions

- Can the enemy mothership's torpedo be shot down or dodged?
- A raster IRQ for the lower strip would remove its last late frames (about 0.2% in a
  tracked fight); the polled schedule is good enough for now.

Ideas beyond the original are [GitHub issues](https://github.com/Bencepapa/sentinel-1351/issues).
