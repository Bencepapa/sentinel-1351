# Sentinel: the ship's systems and damage

Findings from the C64 code (`Sentinel-1351_v9`), read by disassembly and checked
against the memory image. All addresses are C64 addresses. Nothing here has been
watched over a long play session yet, so treat the exact rates as "from the code".

## The eight systems

Zero page `$39-$40` holds one **hit-point counter** per system. The names come from
the table at `$9245`, the "destroyed" messages from `$8301-$83FC`.

| n | zero page | system | message when destroyed |
|---|---|---|---|
| 0 | `$39` | PHASOR CANNONS | PHASORS DESTROYED CAPTAIN |
| 1 | `$3A` | LONG RANGE SCANNER | LONG RANGE SCANNER DESTROYED |
| 2 | `$3B` | SHORT RANGE SCANNER | SHORT RANGE SCANNER DESTROYED |
| 3 | `$3C` | STELLAR GRID | STELLER GRID UPDATE DESTROYED |
| 4 | `$3D` | AUTOMATIC TRACKING COMPUTER | AUTOMATIC TRACKING COMPUTER DESTROYED |
| 5 | `$3E` | HYPERSPACE COORDINATOR | HYPERSPACE COORDINATOR DESTROYED |
| 6 | `$3F` | LONG RANGE SCAN SEQUENCER | LONG RANGE SCAN SEQUENCER DESTROYED |
| 7 | `$40` | COMMUNICATIONS MODULE | COMMUNICATIONS MODULE DESTROYED |

A system works while its counter is non-zero and is destroyed at 0.

Together with the HUD values (shields, energy, protons) the ship has about ten
things that can run out, which is probably what "ten subsystems" refers to.

## Starting values (`$8451`, by difficulty `$E0`)

| system | skirmish | assault | battle | invasion | armageddon |
|---|---|---|---|---|---|
| phasor cannons | 255 | 10 | 5 | 5 | 5 |
| long range scanner | 255 | 10 | 6 | 4 | 4 |
| short range scanner | 4 | 3 | 2 | 2 | 2 |
| stellar grid | 6 | 4 | 4 | 4 | 4 |
| tracking computer | 3 | 3 | 3 | 3 | 3 |
| hyperspace coordinator | 4 | 4 | 4 | 4 | 4 |
| scan sequencer | 2 | 2 | 2 | 2 | 2 |
| communications module | 255 | 255 | 255 | 255 | 255 |

(255 means effectively indestructible.) The tables are at `$8427`, `$842C`, `$8431`,
`$8436`, `$843B`, `$8440`, `$8445`, five bytes each; `$40` is always `$FF`.

Shields (`$844F`) start at 40, 30, 25, 25, 25 (table `$844A`); the HUD shows them
(skirmish starts with SHIELDS 40).

## A hit (`$84D7`, then `$85D9`)

Called from `$2953`, `$CA7B`, `$CD3B` and `$CF90` (the ship is hit). It does nothing
while `$FD` is non-zero. Otherwise:

1. Pick a random system `rnd & 7`; if its counter is already 0, pick again (up to
   256 tries, then give up and skip the system damage).
2. Decrement the counter. At 0 the system is destroyed and its message is printed
   (the phasors also switch off the firing state).
3. Always (`$85D9`): count the hit (`$F432/$F433`) and take one shield point
   (`$844F`). When the shields would go below 0 the ship is lost (`$8300` is set).

So every hit costs one shield point *and* one hit point of a random working system.
Short range scanner, tracking computer, scan sequencer and hyperspace coordinator
have few hit points and go down first; phasors and the long range scanner last on
the harder levels.

## Where the systems are used

The counters are read by other code, which is what a destroyed system disables
(the effects themselves are not traced yet): `$39` at `$1424`, `$3529`; `$3A` at
`$30EC`; `$3B` at `$30D8`, `$9A5A`; `$3C` at `$216D`, `$FC77`; `$3D` at `$89EB`,
`$8A5A`; `$3E` at `$FCBD`; `$3F` at `$3813`; `$40` at `$5899`.

## Repair and the status screen

The text block at `$9497` holds the words REPAIRED and OPERATIONAL, and the routine
at `$932D` lists the eight systems (`$DD` = working, `$72` = destroyed) when the
ship is in a base sector ("ENTERING BASE SECTOR", `$3FB9`). Exactly what is repaired
and how is not traced yet; the C128 panel restores the starting values when the
player visits a base (simplification, marked in the code).

## Verification (C128 port against the original)

The C128 map program has a ship model that follows these rules (`SHIPINIT`,
`SHIPHIT`). Hit for hit it was compared with the original's own routine `$84D7`
running in VICE, difficulty 2 (shields 25):

- every hit takes exactly one hit point from one working system and one shield
  point (total hit points lost = number of hits, in both);
- shields reach 0 after 25 hits; the 26th hit sets the game-over flag (original
  `$8300` = `$FF`, port `SHIPDEAD` = 1);
- the communications module (255 hit points) absorbs about one hit in eight.

One difference: the original keeps damaging systems after the ship is lost, the
port stops at the 26th hit (the game would be over). Which system a given hit
takes is random in both, so only these invariants can be compared.

The panel was checked on the captured second display: all systems OK at the start,
destroyed systems in red with DOWN, shields, hits taken, INTACT / LOST and the
original destroyed-message ("PHASORS DESTROYED CAPTAIN").

## Not understood yet

- What each destroyed system disables, and the repair rules at a base station.
- The meaning of `$FD`, which blocks damage while non-zero.
