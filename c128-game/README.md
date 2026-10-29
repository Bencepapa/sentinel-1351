# c128-game: the cockpit and the sector map as one program

The first step toward the playable C128 game: `c128-gui/cockpit` and `c128-map`
joined into one `.prg`, without changing either standalone program.

```powershell
python c128-game/build.py
& "C:\C64\GTK3VICE-3.7-win64in8.exe" -40col -controlport2device 3 `
  -autostart c128-game\sentinel-c128-game.prg
```

In the browser page: **Program → C128 game (cockpit + map)**.

## How it plays

- The ship starts in sector 05.03 (map cell 4,2), empty as in the original.
- **C=** (Alt in the page) opens the map: the grid draw-in, the squadrons,
  motherships and planet, the cursor, the ticks (squadrons move, motherships
  attack) and the second display, all as in the standalone map program.
- **Fire on another sector** jumps there at once (hyperspace replaces this
  later). **SPACE** on the map goes back to the cockpit without a jump.
- In the cockpit the map decides what is there: a squadron's sector starts the
  approach (the cockpit's long range scanner: groups far away, fire chooses one,
  aligned in front the ship rushes in, the group becomes up to three fighters;
  all type 1 for now, whatever the squadron's type). TARGETS on the HUD shows the
  sector's ship count, each kill lowers it, the last one empties the sector on
  the map. SECTOR on the HUD follows the jump.
- Mothership sectors are empty in the cockpit for now.
- The ship (systems, shields, hits, difficulty) is one: the cockpit's model, and
  the map's second display shows it.

## How it is built

`build.py` reads both sources and `game.asm` (the glue):

- the map's source: every label and constant it defines gets the prefix `M_`
  (except the ship's shared variables), its code moves right after the cockpit's second code chunk, its
  second-display data from `$4000` to `$2900` (the cockpit's font is at `$4000`);
  a few patches make its set-up a subroutine, send SPACE and the sector choice
  back to the cockpit, make the start layout only once and start the cursor on
  the ship's sector;
- the cockpit's source: patches for the map key (C=, on a new press; SPACE too),
  the start, the waves and the kills;
- the bitmap at `$6000` is shared: coming back from the map, `RESTORE` copies the
  cockpit's picture back from master copies at `$5000-$5FDF` (CPU RAM the
  VIC-IIe cannot use): the sprite shapes kept in bitmap rows 0-2 and 23-24, the
  cockpit art, the colour matrix; the 3D view is cleared.

Every patch is checked to match exactly once, so a change in either program that
breaks the join stops the build with the patch that no longer fits.

Tests (`js/test/run.js`, "game:"): the start sector, the map opening, a jump into
a squadron's sector (fighters = the squadron's count up to 3, TARGETS), the HUD's
sector, the restored picture, kills emptying the sector, SPACE going back.

Next (planned): the map drawn over the cockpit with the fight going on behind it,
the world ticking while in the cockpit. Not yet: hyperspace, types 2 and 3,
motherships.
