# c128-game: the cockpit and the sector map as one program

The first step toward the playable C128 game: `c128-gui/cockpit` and `c128-map`
joined into one `.prg`, without changing either standalone program.

```powershell
python c128-game/build.py
& "C:\dev\c64\GTK3VICE-3.9-win64\bin\x128.exe" +go64 -40col -controlport2device 3 `
  -autostart c128-game\sentinel-c128-game.prg
```

It is the browser page's default program.

## How it plays

- The ship starts in sector 05.03 (map cell 4,2), empty as in the original.
- **C=** (Alt in the page) or the **right mouse button** (held alone for 5 frames, as
  in the C64 patch) opens the map **in the cockpit's 3D view**, as in the
  original in flight: the view wipes a row a frame, and the grid
  draws in with its beeps; the HUD, the radar, the guns and the scanner row stay.
  The same key again closes it (the view wipes back, the stars return).
- **The fight goes on behind the map**: the stars keep moving, the fighters fly
  behind its lines and icons, enemy shots still hit the ship. While the map is
  open the mouse moves its cursor and turns the stars (no phasor, no steering).
- **The mouse moves a + pointer** over the grid (enhancement); the cursor box
  follows the sector under it. Without a mouse the joystick steps the box.
- **Fire on another sector** closes the map and jumps there through hyperspace: the stars speed up (about 4.5 s), then streak into lines while the energy runs out ten times as fast and the steps left count down in big digits over the radar, then slow down (about 2.4 s). A step is a point of the map's flight path (the longer of 12 x columns and 16 x rows), 13.5 frames each, so the far corner takes longest. First the path is plotted on the map, a brown point a frame with beeps, while the map's lines are erased from both sides (the brown path and boxes stay); the upper HUD's border pulses through grays, and the engine's noise rises while the ship accelerates, holds in the jump and falls while it slows down. When the jump begins, the radar silently switches to long range and shows the destination's groups with the first group's readings (00 for an empty sector; no blip until the arrival); steering moves them nearer or farther, left or right (the original's positioning), and on arrival the approach starts with them where they were put. With a mouse the crosshair becomes the hyperspace cursor once the map is gone, until the arrival (as the H test): it steers while the mouse moves, changes colour, spins its digits and springs back to the centre when the mouse rests; while the ship slows down its digits count from 999 to 000. In the jump meteors come (five at most, as the original's): they grow, drift outward and hit the ship at full size (flash, a system hit, the rattle) unless steered away or met with the deflector: fire turns the view green and shows the shield's lines, at 10 energy a frame. The abort comes later. Fire on the ship's own sector just closes the map.
- **The world runs all the time**: the map's clock (squadrons move every 16th
  tick, motherships attack, the planet's ring) ticks as often as in the original on a real machine (every 33 frames with the map open, 44 in flight, 54 in a fight, 200 while the tracking computer flies), whether the map is open or not; the icons are only drawn while it is open (cells that changed
  are drawn a few a frame).
- In a squadron's sector the cockpit's approach begins (the long range scanner:
  groups far away, fire chooses one, aligned in front the ship rushes in, the
  group becomes up to three fighters; all type 1 for now, whatever the squadron's
  type). TARGETS shows the sector's ship count, each kill lowers the map's COUNT,
  the last one empties the sector on the map. SECTOR on the HUD follows the jump.
- **A squadron coming into the ship's sector** (at the end of a move, `$BEDF`): 24
  points rush to three places with a sound (`$1AF2`), three fighters appear there,
  the warning sounds and the dogfight starts. A squadron of fewer than 3 becomes 3,
  as in the original.
- Mothership sectors are empty in the cockpit for now.
- The ship (systems, shields, hits, difficulty) is one: the cockpit's model.
- The second display (VDC) is off in this program for now: its updates take more
  time than a frame has to spare while the cockpit runs.

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
- the star field shares the bitmap with the map: while it is open a star is
  pixel value 1 (white) and touches only empty pixels, like the original
  (`GPLOT`, `GERASE`); the planet's three cells stay free of lines;
- the squadrons' move (`MOVEPASS`) runs six sectors a frame (`MVSTEP`): at once it
  took about 100 lines and tore one frame's picture;
- the map draws into the 3D view's bitmap rows 3-17; opening and closing wipe
  those rows a row a frame and set their colours (yellow lines, brown boxes; or
  the cockpit's again, the matrix from a master copy at `$5000`, CPU RAM the
  VIC-IIe cannot use); the cockpit's hooks (`INPUTV`, `VIEWVB`, `TICKHK`,
  `KILLHK`, `EMPTYHK`) call the map's input, frame work and clock.

Every patch is checked to match exactly once, so a change in either program that
breaks the join stops the build with the patch that no longer fits.

Timing: the VIC-IIe takes cycles from the processor on bad lines and sprite lines,
and the JS machine runs without that unless `m.dma` is set. The game's split and fight
tests set it; VICE stays the reference for anything near a limit. The map's code ends
just below `$C000`: more code in the cockpit's second chunk needs a move (the build
stops if it does not fit).

Tests (`js/test/run.js`, "game:"): the start sector, the world ticking with the
map closed, the map opening in the view (art and HUD untouched, no overrun), a
jump into a squadron's sector (the approach begins, TARGETS), the HUD's sector,
the view's colours back, kills emptying the sector, C= closing the map, the right
button, fire on the ship's own sector, a squadron coming in, the splits' timing.

Not yet: hyperspace's abort, proton torpedoes, thrust (W), motherships and
bases, the second display while flying, game over, and the destroyed-system messages.
