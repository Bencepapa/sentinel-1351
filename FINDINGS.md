# Findings: bugs and quirks in the original

Things found in the C64 game (`Sentinel-1351_v8`, C64 addresses) while porting it
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

## Misnamed in earlier notes

- `$E3`, `$C847` and `$372C-$372F` (read by the steering `$39C1`) belong to the
  approach phase, not to the motherships: `$E3` = approaching a group, `$C847` =
  the chosen group is in front, `$372C-$372F` = the long range scanner's side and
  up digits. Renamed in the port (`APPR`, `INFRONT`, `LRDIG`).
