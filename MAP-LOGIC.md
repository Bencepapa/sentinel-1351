# Sentinel sector map: how the strategic layer works

Findings from disassembling `Sentinel-1351_v9` (the C64 game). All addresses are
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

0. `$3E7E` checks the attack rings around the blue motherships and the planet (below).
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

## Motherships under attack, and the planet (`$3E7E`, `$3F72`)

(Thanks to the user for the hint that it is the four sides that count.)

At the start of every tick `$3E7E` checks five groups of four sectors
(table `$3E60`):

| group | sectors (index) | what it surrounds |
|---|---|---|
| 0 | 2, 11, 13, 22 | blue mothership at 12 (up, left, right, down) |
| 1 | 7, 16, 18, 27 | blue mothership at 17 |
| 2 | 32, 41, 43, 52 | blue mothership at 42 |
| 3 | 37, 46, 48, 57 | blue mothership at 47 |
| 4 | 24, 25, 34, 35 | the 2x2 block in the middle of the map: **the planet JARALOBA** |

A cell counts as occupied when its state or count is non-zero (any squadron or
mothership). Diagonals do not matter. For each group (`$95` = occupied cells):

- fewer than 4 occupied: the attack counter `$3E74+group` is reset to 0;
- all 4 occupied and the mothership is not destroyed yet (`$3E79+group` = 0):
  - blue mothership: the first time the message **MOTHERSHIP ENGAGED IN BATTLE**
    is shown and the counter is set to 120; it counts down once per tick. At 0
    the message **MOTHERSHIP DESTROYED** appears, the mothership's cell is
    emptied (`$033C` and `$0378`), its destroyed flag is set and `$CFA7` runs
    (not yet understood);
  - planet (group 4): the message **JARALOBA IS SURROUNDED** starts a counter of
    255; at 0 **JARALOBA CEASES TO EXIST** sets the game-over flags
    (`$DD`, `$3E7D`, `$F431`).

So the defenders get about 120 ticks (10 minutes with the 5 s map tick, 5 minutes
with the 2.6 s tick of the flight loop) to break up the ring around a blue
mothership, and 255 ticks for the planet. If the ring is broken in time the
counter is simply reset.

The blinking is `$3F72`, run every frame while the map is shown: each blue mothership
that is not destroyed gets its icon colour from the counter. Counter 0: colour
`$06` (blue). Counter non-zero: a **random colour every frame**. The same routine
colours **sprite 1** (`$D028`): cyan (`$03`) normally, and incrementing every frame
while the planet is surrounded. So the planet is a sprite, and it flashes like the
motherships when it is surrounded.

## The planet sprite (`$1040-$10D5`)

The planet is **sprite 1**, started with the grid sweep (when `$B075` is set):

- position: sprite X `$A7` (167), Y `$7B` (123), i.e. centred on the grid junction in
  the middle of the map, where the four sectors of the planet's ring meet;
- single colour cyan (`$D028` = 3), not expanded, in front of the bitmap;
- four rotation frames: sprite pointers `$39`, `$3A`, `$3B`, `$3C` (blocks at
  `$4E40`, `$4E80`, `$4EC0`, `$4F00` in VIC bank 1), stepped every 8th frame
  (`$A0 & 7 == 0`), wrapping back to `$39`;
- the raster interrupt copies zero page `$B0-$B7` into the sprite pointers
  `$47F8-$47FF` every frame, so the frame variable of sprite 1 is `$B1`; its shadow
  enable bit is `$98` bit 1 and its position lives in `$E9` / `$EA`;
- the colour is then driven by `$3F72` (above): cyan, or cycling while surrounded.

When the sweep module is inactive (`$B075` = 0) the routine hides the sprite again.

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
- Attack rings (`$3E7E`): fresh rings, rings about to expire, a broken ring and an
  already destroyed mothership give identical sector maps, counters and flags in
  the original and the port. The planet-colour code (`INC $D028` every frame
  while surrounded, cyan otherwise) was confirmed to run in the port.
- Start layout: 24 squadrons at difficulty 2, 4 blue and 4 orange motherships,
  sizes 3-9, the start sector empty.

## Not yet understood

- `$C8D4`, once a tick: while a squadron sits in the player's sector and nothing is going
  on, it counts `$C8D3` down from 15 and then sets `$E3`, the approach. A squadron that moves
  in starts its arrival at the end of the move (`$BEDF`, `$1AF2`, ported).
- Combat in the sector: `$3CD9` decrements the count when the player destroys a
  squadron, `$3F4A` clears a sector, `$CFE6` turns a type-2 squadron into
  type 3 with half the count (`$CFC8` loop).
- What `$CFA7` does when a mothership is destroyed.
