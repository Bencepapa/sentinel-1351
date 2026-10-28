# Sentinel sector map: how the strategic layer works

Findings from disassembling `Sentinel-1351_v8` (the C64 game). All addresses are
C64 memory addresses. The rules were read from the code and then checked by
running the original game's routines in VICE 3.7 next to the C128 port (see
"Verification"). The type names hunter / guard / drifter are my own labels.
The timing (about 5.1 s per tick) is from the code and matches the C128 port
running at PAL speed; it has not been timed in a long original play session.

## The map

- 10 columns x 6 rows = 60 sectors, index `idx = row*10 + col` (`$22D6`).
- Sector state `$033C[idx]`, count `$0378[idx]`:

| state | meaning | count |
|---|---|---|
| `$00` | empty | 0 |
| `$01` | squadron type 1 (**hunter**) | size 1-9 |
| `$02` | squadron type 2 (**guard** of the blue motherships) | size |
| `$03` | squadron type 3 (**drifter** toward the centre) | size |
| `$80` | orange mothership (corner) | 1 |
| `$FF` | blue mothership | 0 |

- The squadron icon shows the size: count 1-3 draws one ship, 4-6 two, 7+ three
  (`$2301`). The colour comes from the type: `$1E`, `$1D`, `$14` (`$22FE`).
- The player's sector is `$92` (column) / `$93` (row); the game starts at (4,2).

## Starting layout (`$20F1`)

1. Blue motherships (`$FF`, count 0) at indices 12, 17, 42, 47
   (columns 2 and 7 of rows 1 and 4) -- table `$2085`.
2. Orange motherships (`$80`, count 1) in the four corners 0, 9, 50, 59 -- table `$2089`.
3. N squadrons, N by difficulty (`$8422`): 10, 15, 24, 31, 44
   (skirmish, assault, battle, invasion, armageddon).
   Each gets a type `rnd & 3` (0 becomes 1, so type 1 is twice as common) and a
   size `(rnd & 7) + 2`, raised to at least 3 (sizes 3-9). They are placed in a
   random free cell: `idx = rnd & $3F`, indices 60-63 map to 56-59 (`$225D`).
4. The player's start sector (idx 24) is cleared afterwards.

The random generator (`$BA85`) is `seed = seed*9 + $35` XOR raster line `$D012`
XOR SID voice 3 oscillator `$D41B`.

## The tick

`$BE29` is called when the frame counter `$89` low byte is 0 in most map and
space loops (every 256 frames, about 5.1 s PAL), and every 128 frames in one
loop (`$B660`). Each tick:

1. `$BDAF` (starts at 30) is decremented.
2. `$9F9A` runs the mothership events (see below).
3. When `$BDAF & $0F == 0` (every 16 ticks) all squadrons move once (`$BE4C`).

## Squadron movement (`$BE4C`-`$BFD0`)

The pass visits sectors from the bottom-right (row 5, column 9) up to the
top-left, and builds the new map in a shadow copy (`$BDB1` / `$BDED`) that is
copied back at the end. Per squadron the move depends on its type:

| type | direction (dx, dy) | moves when |
|---|---|---|
| 1 hunter | one step toward the player's sector (sign of the difference, both axes) | every pass (16 ticks) |
| 2 guard | column table `$BF30`: 1,1,0,-1,-1,1,1,0,-1,-1; row table `$BF3A`: 1,0,-1,1,0,-1 -- it heads for the nearest blue mothership position (columns 2/7, rows 1/4) | when `$BDAF & $1F == 0` (every 32 ticks) |
| 3 drifter | column table `$BF08`: 1,1,1,1,0,0,-1,-1,-1,-1; row table `$BF12`: 1,1,0,0,-1,-1 -- it drifts toward the middle of the map | when `$BDAF & $3F == 0` (every 64 ticks) |

Rules shared by all types (`$BF79`):

- A squadron only moves into a completely **empty** cell (nothing there now, and
  nothing already placed there in the new copy). Squadrons never merge.
- If the diagonal target is occupied it tries the cell beside it (new column,
  old row), then the cell above/below (old column, new row), then stays.
- Motherships never move. A squadron in the **player's** sector never moves.
- Because the sectors are processed from the bottom-right, a squadron can move
  into a cell that was just vacated earlier in the same pass.

With the standard tick (5.1 s) a hunter moves about every 82 s, a guard every
164 s and a drifter every 328 s.

## Mothership events (`$9F9A`, difficulty 2 or higher only)

At skirmish and assault (`$E0` < 2) none of this happens. The mask for the tick
counter depends on the level (`$9F95`: `$FF,$FF,$7F,$7F,$3F`).

- When `$BDAF & mask == $30` (`$9FB2`): each corner that still has a mothership
  spawns a **type 1 squadron** of size 1-8 in the cell next to it (cells 1, 8,
  51, 58 -- table `$9F91`) if that cell is empty.
- When `$BDAF & mask == $15` (`$2091`): the corner motherships come and go.
  Skipped when the player is in a mothership sector. For each corner, a coin flip
  decides: a corner that was removed earlier (flag `$208D+n` set) and is empty
  returns as `$80`/1; a corner that still has its mothership leaves (flag set,
  cell emptied).

## Verification

The C128 port in `c128-map/` reimplements these rules. They were compared with
the original game's own routines running in VICE (same input, same result):

- Movement pass: the same 24 squadrons, the same player sector and tick values
  `$00`, `$10`, `$20`, `$40` give identical maps (16, 20, 24 and 24 sectors
  changed). The original only runs the pass when the tick value has a zero low
  nibble, and so does the port.
- Corner spawn followed by the movement pass in the same tick (`$30` is a
  multiple of 16, so they always coincide): identical maps; only the random sizes
  of the new squadrons differ.
- Corner toggling: both obey the rules in every trial (random outcomes differ).
- Start layout: 24 squadrons at difficulty 2, 4 blue and 4 orange motherships,
  sizes 3-9, the start sector empty.

## Not yet understood

- What `$3E7E` and `$C8D4` do inside the tick.
- Combat in the sector: `$3CD9` decrements the count when the player destroys a
  squadron, `$3F4A` clears a sector, `$CFE6` turns a type-2 squadron into
  type 3 with half the count (`$CFC8` loop).
- The blinking of a mothership when it is surrounded (probably `$2B14`).
- The animated planet in the player's sector.
