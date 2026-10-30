# Findings: bugs and quirks in the original

Things found in the C64 game (`Sentinel-1351_v9`, C64 addresses) while porting it
to the C128 and checking the port against the original routine by routine
(`js/test/run.js`). For each one: what the code does, what it causes in play,
and what the C128 port does. "Kept" means the port does the same, so that the
side-by-side tests stay exact; "fixed" means the port does what was clearly meant.

## Bugs

### 1. A kill near the top of the screen can crash the game (`$3320` → `$3337`)

When our shot destroys a fighter, the explosion's centre is worked out from the
sprite position. The x half is pushed on the stack (`$32FE PHA`). If the sprite's
y is above 60 or at 240 and below (`y - $32` outside `$0A-$BD`), `$3323` / `$3329`
branch to `$3337`, past the `PLA` at `$332B`. The byte stays on the stack, and
the routine (called from the raster interrupt via `$3244`) returns with `RTS` to an
address made of that byte and half of the real return address.

- In play: rare (a fighter shown that high is mostly behind the HUD), but when it
  happens the interrupt returns into the middle of nowhere: a crash or a hang.
- Found when the side-by-side test crashed the original (`illegal opcode $A7 at
  $F354`).
- Port: **fixed** (`hk2: PLA`). The test skips this case for the original.

### 2. The enemy shot's launch steps are computed and thrown away (`$C9C9-$CA37`)

At launch the code reads the firing fighter's movement streams to give the shot a
starting direction (`LDA ($04),Y`, `LDA ($0A),Y`, halved or quartered by
difficulty), then overwrites both results: `$CA13 LDA #$00 / STA $C90F` and
`$CA35 LDA #$00 / STA $C910`. On top of that, the self-modifying code that should
point the first read at the right fighter's stream stores the wrong register
(`$C9CC STA $C9F7` after `LDY $323E,X`; it should be `STY`), so the pointer
becomes the value of `$D017`.

- In play: every enemy shot starts without a direction; the direction comes only
  from the screen position afterwards (see 3). Harmless, since the result is
  dropped anyway.
- Port: **kept** (both steps start at 0; the dead computation is left out).

### 3. The enemy shot's direction test reads zero page `$04` instead of `#$04` (`$CB6E`)

`$CB6C LDA $F7 / AND $04` was meant to be `AND #$04` (the shot sprite's x bit 8
in the MSB shadow `$F7`): when the shot is beyond x = 255 its sideways direction
should stay. `$04` is the low byte of fighter 1's stream pointer, always `$00`, so
the test never holds and the direction is always recomputed from the low byte of
x.

- In play: a shot that crosses x = 255 is then steered as if it were at the left
  edge (it turns back left). Shots rarely get there.
- Port: **kept** (the step is always worked out; commented at `EFSTEPX`).

### 4. The second explosion checks x twice and y never (`$9DFF-$9E0B`)

When an enemy shot reaches the ship, 12 points burst where it was (`$9DAA`). The
start-up loop stores x, then compares `A` (still x) against the y limits `$C3` and
`$05` before loading y.

- In play: the y range is never checked at the start; the shot's y is always in
  range anyway (it ends inside `$59-$EF`).
- Port: **kept**.

### 5. The ship keeps losing systems after it is lost (`$84D7`)

Hits after the shields are gone still take hit points from the systems (from
`SHIP-STATUS.md`).

- In play: invisible, the game is over.
- Port: the map program stops at the hit that loses the ship; the cockpit keeps
  the original's behaviour for now (the game-over sequence is not ported).

### 6. The tracking computer's planet masks are read from zero page (`$8B75`-`$8BBB`)

While tracking, the aim (`$8B49`) builds a joystick-like mask in `$89CA` (`$FF`
with one bit cleared per direction) that turns the planet (`$B846`). The bits are
cleared with `AND $FB`, `AND $F7`, `AND $FE`, `AND $FD`: zero page, not the
immediates `#$FB`, `#$F7`, `#$FE`, `#$FD` that were meant (`$F7` is the sprite
x bit 8 shadow, the others hold whatever they hold).

- In play: the planet moves in odd directions, or not at all, while tracking
  (mostly `$89CA` = `$00`: all four directions at once, which cancel out).
- Port: no planet in the cockpit yet; not ported.

### 7. A jump from the map leaves the cursor boxes in the bitmap (`$FC96`)

The boxes are pixel value 2. In flight that value is black (`$FC13`: matrix `$10`),
and the stars and the hyperspace's erase (`$EEE6`) keep it. Only the map's other exit
clears the bitmap (`$FC4E JSR $BAB0`), so after a jump the boxes stay: unseen on the
black sky, but a white flash shows them, and stars vanish while crossing them.

- In play: black squares on the screen during hit flashes, until the map is next
  closed without a jump.
- C64 1351 patch: **fixed** (`$FC9D JSR JUMPCLR`, the same clear). Port: **not
  affected** (closing wipes the view).

## Quirks (behaviour that looks accidental but is part of the game)

| Where | What | Port |
|---|---|---|
| `$1527` | The phasor shot's colour is read with `LDX $1520 / LDA $1520,X`, which lands on `$1527`, a byte of its own code (`$13`): cyan. | kept |
| `$158E-$15B2` | At the end of the shot's path the stored position is loaded from the sound flag (`LDY $F8`): 0 when no other sound plays. | kept |
| `$33B6` | The drift's comparisons use a carry left over from unrelated code, so a drift step can differ by one unit from run to run. | the test sets the carry |
| `$3244` | The sprite collision register `$D01E` is read and stored at `$323C`, but the hit test uses positions only. | not ported |
| `$3CC4` | A kill decrements the HUD's TARGETS ones digit directly (`DEC $5476`), with no borrow from the tens digit. | kept |
| `$8301-$83FC` | The message reads "STELLER GRID UPDATE DESTROYED". | (messages not ported yet) |
| `$C6A9` | The approach loop draws the star field and more in every pass, so it makes only about 2.3-8 (on average 3.4) passes a frame; the scanner readings and the blip (`$3776`, every 16 passes) change about every 5 frames. | the port runs 3.4 passes a frame |
| `$9F51` | The radar's marks have no colour of their own: the band of colour RAM under the radar shifts one cell every 8 calls through black, greys and white, so a mark changes colour as the band passes over it. | ported |
| `$8A34` | The tracking computer runs its own main loop instead of the fight loop: no steering at all, about 6.2 passes a frame; enemy fire every pass, the streams every 6-8 passes and the drift every 4 (+2 per difficulty level), a shot launches only every 64th pass (up to ~10 frames late). It pulls only the first live fighter into a box around the view, 1-3 units every 3rd pass; the others stay in view by themselves. | the port runs the same schedule at 5.85 passes a frame (the original with the VIC's stolen cycles) |
| `$8C07` | The tracking key (A) is forgotten when released; the tracking loop looks at it only every 32 passes (~5 frames), so a very short tap may not stop tracking. | kept (A or T in the port) |
| `$FB95` | The planet's three cells on the map (row 10, columns 18-20) are all black, so the grid's lines under it are drawn but unseen; a white flash shows them. | the cells are black too, and kept free of lines |
| `$C947` | Enemy fire and the guns (`$9568`, every 16th frame) run at the speed of the main loop or the frame counter, so they are slower than they look: the guns follow the crosshair one step per 16 frames. | the port calls them at the same rates |

## How the enemy shot and our hits work (for players)

- **Our hits.** The shot can only hit during the last 10 points of its path, that
  is where the crosshair was when it was fired. It hits a fighter whose sprite is
  within 12 pixels across and 10 down of the shot's sprite (both measured from the
  sprites' corners), so: put the crosshair on the fighter, and lead a moving one so
  that it is there when the shot arrives. One hit per shot.
- **The enemy shot can be shot down** (`$3287`): our shot's hit test checks
  sprite 2, the enemy shot, first. A hit bursts it (12 points), the view flashes
  white and green, and the shot, still growing unseen, does no harm when it
  arrives, because the arrival only hurts if the sprite is still shown (`$CA71`).
- **It can miss by itself**: it moves away from the middle of the view as it grows
  (`$CB6C` / `$CBAA`); one fired from near an edge leaves the screen (x past the
  edge, y above `$59` or from `$F0` down) before it is full size, and is gone.
- **Fire rate**: a fighter fires when the delay runs out (by difficulty: 255, 176,
  112, 64, 16 calls of `$C947`, every 3rd main loop pass, about 16 passes a frame)
  and only while it is shown in the middle of the view. The C128 port's default
  difficulty was 1; it is now 0 (skirmish, the slowest).

- **The tracking computer is switched on and off with A** (`$8C07` reads key A,
  `$FDE7`). Only in a fight, and only while the computer works (system 4, `$3D`).
  It takes up to 2 frames to come on; then the crosshair turns into an animated
  bracket and "AUTO TRACKING ENGAGED" scrolls along the bottom row. While it is
  on, the stick does not steer: the view turns by itself toward the first live
  fighter and keeps it (and usually the whole group) on screen. Press A again to
  steer yourself; it is checked only every ~5 frames, so hold the key a moment.
  It also switches itself off when the group is gone, when the long range phase
  starts, when you use thrust (W), or when the computer is destroyed. The C128
  port uses A as well (T also works).

- **Tracking switches itself on at every arrival** (`$C7F7 STA $62`): when a group
  arrives and the short range fight begins, the computer is asked for at once, so
  (while it works) every dogfight starts with AUTO TRACKING ENGAGED; A turns it
  off. Only once it is destroyed do the fighters drift off the screen by default.
- **The upper HUD's border tells the approach** (`$0CCC`, the operand of
  `$0CCB LDX #$0E`): green while the chosen group is in front, red when it is also
  level sideways (side reading 0-3), yellow when up is 0-3 too. Then the ship
  rushes in: 12 depth steps a pass, the speed `$F209` falls from `$41` by 6 a pass,
  the engine's noise (voice 3) drops with it and every star's delay is cut to
  `$F209 / 4`, so the stars stream past.
- **The border pulses with the sound effects** (`$09AC`): while a voice 1 sweep
  plays (`$F8`) it runs through light gray, gray, dark gray, black and back (35
  steps, one a frame); otherwise it is light blue. The sweeps: entering a sector
  (down from `$50xx`, 8 x 30 frames, with "ALERT  ENTERING GORGANITOR SECTOR"),
  the rush (up from `$01xx`, 48 frames) and the siren at the arrival (up from
  `$1Exx`, 8 x 40 frames, with "WARNING  THE GORGANITOR APPROACH", which the
  tracking message replaces at once). The engine's noise is a burst on voice 3
  every 6th frame throughout (`$C379`).

## How our weapons use sprites

- **The phasor shot is a sprite, not a line in the bitmap.** The line routine
  `$3580` stores the shot's path as X and Y point lists in pages `$0400` and
  `$0500`, and sprite 1 steps through them. A press sets `$D0`.
- **The proton torpedo's request.** SPACE leaves a non-zero value in `$FDE5`. The
  game loops copy it into `$BACE`: every 32nd pass at `$2E1F` and `$9136`, and
  also at `$8AE5` in the tracking loop.
  While `$BACE` is set, the shot is dropped (`$1428` clears `$D0`), enemy fire
  stops (`$C947`) and the planet does not turn (`$B850`).
- **Launch (`$BADA`).** With no torpedoes left (`$8450`), the request is cleared
  and only a sound plays (`$BC6F`). Otherwise the count drops by one, the launch
  sound starts on voices 1 and 2 (`$BBB2`), and `$BACF` marks the flight.
- **Flight (`$BB1B`).** It uses two white sprites, 1 and 2, with x doubled and with
  multicolour, y doubling and the x high bits off. Their shapes are `$01` and `$02`
  (`$B1`, `$B2`), so they show `$4040-$40BF` in the `$4000` video bank. They start at
  x `$A0`, y `$C8` and `$DD`, and move up 2 pixels a step. Each step copies the next
  128 bytes of animation to `$4040` (`$BB5A`): 32 frames (`$BAD0`), `$A000-$AFFF`.
  This is the same data as the enemy torpedo's animation (`$CF04`), which shows it
  with shapes `$45`/`$46` at `$5140`.
- **End (`$BB70`).** The sprites go off, their colours return ($D028 `$0E`, $D029
  `$07`) and the flags clear. `$BAD1` then starts the blast (`$BBE4`), unless the
  check at `$BB81-$BB8D` skips it. The blast sets up `$160A-$160D` for the points
  and draws a growing ring around x `$50`, y `$64`, the middle of the 160x200 bitmap
  (`$3635`, `$364C`), with radius `$43` growing by 6 up to `$28`. The ring runs
  twice (`$BAD3`).
- **For a port:** the torpedo depends on far more than the shot: the animation
  data, the bitmap ring, the points and the three systems it holds back.

## From the manual (`manual.TXT`), not ported yet

- **Crsr aborts a hyperspace jump.** Hyperspace is not ported yet.
- **W holds the booster for warping**, and the fire button works the deflector in
  hyperspace: a hit with it on turns the view blue and costs energy, without it red
  and a shield.
- **A toggles Short and Long Range Scan** after a manual warp. In a fight the port
  uses A for tracking only.
- **Lingering in an empty sector:** Gamma Fighters warp in. The port brings in a
  squadron that moves into the sector; check `$F96B` (it starts the same arrival).
- **After a squadron is gone**, tracking ends, the scan returns to long range, and
  with no enemies left the Stellar Grid opens by itself.
- **Docking at a Base Station:** a status report, then repairs, fuel and one proton.
- **A proton destroys every ship on the screen** and is the only way to destroy a
  Base Star, through its entrance portal.
- **Mines** surround Base Stars and Base Stations; phasors can destroy them.
- **Cruisers** turn into Saucers 2:1 when a Base Station is destroyed.
- **Ratings** at the end: eight classes from Space Droid to Star Sentinel.

## Misnamed in earlier notes

- `$E3`, `$C847` and `$372C-$372F` (read by the steering `$39C1`) belong to the
  approach phase, not to the motherships: `$E3` = approaching a group, `$C847` =
  the chosen group is in front, `$372C-$372F` = the long range scanner's side and
  up digits. Renamed in the port (`APPR`, `INFRONT`, `LRDIG`).
