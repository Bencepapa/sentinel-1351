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
- **SPACE (or both mouse buttons) launches a proton torpedo** (the HUD's PROTONS count): the original's pre-drawn rotating torpedo flies up the view for 32 steps, then every ship in view goes down and orange rings spread from the middle. With none left, a click. **RUN/STOP leaves.**
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
- In mothership sectors the long range scanner first shows the base's position and X/Y/Z readings. Steering moves it; exact 00 side and 00 up in front locks steering, and depth closes at the original base loop's rate. Fire still shoots, but does not select another target. As in the original, the base is a radar mark without the cyan animated fighter-selection sprite. Near enough in front, the ship settles for about 194 frames, then waits about 70 frames before the rings and rectangular opening grow as in the original. Enemy bases flicker and turn white in alternating phases; friendly bases stay white but share the same hidden phase. A proton destroys a base only if its opening has appeared and the phase is on when the torpedo arrives; a miss preserves the base's colours and the approach continues. A kill shows BASESTAR DESTROYED CAPTAIN, a burst and expanding erasing rings, then clears the sector. Every base sequence returns to the map; that sector cannot be selected straight back until you jump elsewhere. A surviving friendly base draws its white tractor rays, types the full-screen eight-system report with coloured scanning blocks and repair beeps, recharges energy, repairs the ship and grants one proton before the map returns. Tractor rays reach the guns; docking restores the cockpit and all sprite shapes for the next fight. An enemy base fires a white incoming proton at radius 25: it cannot be shot down or dodged, takes five shield/system hits, then returns to the map with the same re-entry lock. Friendly bases never fire. Mines are still to come. Opening and closing the map before the sequence ends restarts the approach.
- Strategic warnings (a mothership engaged/destroyed, JARALOBA surrounded/lost) now appear on the cockpit message line even with VDC off.
- The ship (systems, shields, hits, difficulty) is one: the cockpit's model.
- The second display (VDC) is off in this program for now: its updates take more
  time than a frame has to spare while the cockpit runs.

## How it is built

### Memory map (2026-11-07)

Bank 0, inclusive addresses. F = flight/approach, D = dogfight, M = mothership
(including docking/destruction), H = hyperspace. "Resident" means reserved in
**all four modes**, even if that mode is not currently executing the code. Small
padding gaps below are not advertised as feature space. The map remains live
behind the cockpit, including while closed; its world arrays are never scratch.

| Range | Contents and lifetime |
|---|---|
| `$0C60-$19F8` | 3,481-byte resident relocated mothership/repair/message/positioning/enemy-proton block. Used in M, message jobs also F/D/H; retained in every mode. Original bank-0 contents saved/restored. |
| `$1C01-$1C0C` | BASIC SYS stub; init only. |
| `$1C0D-$1CFF` | Loader-to-entry padding; reserved. |
| `$1D00-$28D6` | Cockpit first code/state chunk; resident F/D/M/H. |
| `$28D7-$28F5` | Repair art-restore helper; resident, executes M. |
| `$28F6-$28F7` | Padding. |
| `$28F8-$28FF` | Saved repair glyph; resident master, M. |
| `$2900-$2CBF` | Fifteen type-1 fighter masters; resident, F/D/M cleanup. Replaces disabled VDC assets. |
| `$2CC0-$2CDD` | Repair words and eight lengths; resident, M. |
| `$2CDE-$2CFA` | Repair helper; resident, M. |
| `$2CFB-$2CFF` | Padding. |
| `$2D00-$2DFF` | Bitmap Y low-byte table (200 entries), then padding. Shared with map, F/D/M/H. |
| `$2E00-$2EFF` | Bitmap Y high-byte table (200 entries), then padding. Shared, F/D/M/H. |
| `$2F00-$2F4F` | Bitmap X low/high tables (40 entries each), shared F/D/M/H. |
| `$2F50-$2FED` | Repair system names (158 bytes); resident, M. |
| `$2FEE-$2FFA` | Repair helper; resident, M. |
| `$2FFB-$2FFF` | Padding. |
| `$3000-$33E7` | Original colour RAM image; resident master, init and scene restoration. |
| `$33E8-$33FD` | Repair helper; resident, M. |
| `$33FE-$33FF` | Padding. |
| `$3400-$35FF` | Phasor X/Y path buffers; F/D/M. Not available as persistent scratch in H. |
| `$3600-$3680` | Long-range scanner scale, 129 bytes; F/D/M/H. |
| `$3681-$368C` | Repair helper; resident, M. |
| `$368D-$368F` | Padding. |
| `$3690-$36CF` | Digit-sprite master; F/D/M/H. |
| `$36D0-$3767` | Two 76-byte tractor-beam paths; resident, M. |
| `$3768-$37FD` | Repair helper; resident, M. |
| `$37FE-$37FF` | Padding. |
| `$3800-$39BF` | Seven type-2 fighter masters; resident F/D/M cleanup. |
| `$39C0-$3BBF` | Eight type-3 fighter masters; resident F/D/M cleanup. |
| `$3BC0-$3BCF`, `$3BD1-$3BFF` | Repair helpers; resident M (one padding byte at `$3BD0`). |
| `$3C00-$3D3B` | Map STATE/COUNT/NEWST/NEWCT/DIRTY: five 60-byte arrays at `$3C00/$3C40/$3C80/$3CC0/$3D00`, with four-byte gaps. Live F/D/M/H. |
| `$3D3C-$3D5F` | Reserved map-table padding (ship systems use the shared cockpit variables). |
| `$3D60-$3DFA` | Repair charging code; resident, M. |
| `$3DFB-$3DFF` | Padding. |
| `$3E00-$3FFF` | Type-2 X movement streams; resident, F/D. Disabled VDC text aliases are unusable. |
| `$4000-$43FF` | VIC character font; displayed HUD/text F/D/M/H. |
| `$4400-$47E7` | Bitmap screen matrix; live F/D/M/H. |
| `$47E8-$47FF` | Matrix padding and sprite pointers; reserve the whole tail. |
| `$4800-$4BE7` | HUD/bottom text and docking report screen; live F/D/M/H. |
| `$4BE8-$4BFF` | Text padding and sprite-pointer tail; reserved. |
| `$4C00-$4FFF` | Crosshair, tracking, guns, approach blips, planet and barrel sprite slots; protected in every mode. |
| `$5000-$5257` | 600-byte cockpit matrix master for map close; resident F/D/M/H. CPU-only RAM (VIC sees character ROM). |
| `$5258-$52FF` | Reserved padding. |
| `$5300-$5DFE` | Glue code/state; resident F/D/M/H. `$5D63-$5DF0` is the init decoder, reclaimed as 142 bytes of frame pointers, mothership state, timing and repair state. UPEND/GSEED/GUNPK2 stay intact. |
| `$5DFF` | One glue byte free; do not move existing code. |
| `$5E00-$5FFF` | Packed high-image start at load; becomes 512-byte type-2 Y streams at init, resident F/D. |
| `$6000-$63BF` | Fighter sprite slots, protected F/D/M/H; enemy proton temporarily borrows `$6000-$607F`. Init temporarily uses `$6000-$6D98` for the low-RAM backup, then restores all slots. |
| `$63C0-$767F` | 3D-view bitmap: stars/fight, map, rings and hyperspace. Packed image occupies through `$6D21` at load, then is dead. The 2,398-byte packed margin `$6D22-$767F` is **load-time capacity**, not persistent runtime RAM. |
| `$7680-$7CBF` | 1,600-byte cockpit bitmap art, always protected. |
| `$7CC0-$7F3F` | Ten phasor/shot sprite slots; player proton borrows the first two; restored from TSHOT. Protected in every mode. |
| `$7F40-$7FFF` | Last fighter shape, scanner line and fifth planet frame; protected in every mode. |
| `$8000-$84FF` | Type-1 movement streams; resident F/D. |
| `$8500-$A996` | Cockpit second code/state chunk; resident F/D/M/H. |
| `$A997-$A99F` | Alignment padding. |
| `$A9A0-$BFC2` | Map code/state; resident, world runs F/D/M/H. |
| `$BFC3-$BFFC` | Repair helper; resident M. |
| `$BFFD-$BFFF` | Padding. |
| `$C000-$CFF9` | High glue/hyperspace code and buffers; resident F/D/M/H. |
| `$CFFA-$CFFF` | Padding. |
| `$D000-$D051` | RAM beneath I/O: init STR2Y packed stream; dead afterwards. Visible addresses are hardware in gameplay. |
| `$D052-$D0FF` | Staging padding; not directly accessible with gameplay MMU `$3E`. |
| `$D100-$DD72` | RAM beneath I/O: 3,187-byte packed low-code stream at load/init. Consumed before backup installation. |
| `$DD73-$DEFF` | Staging padding. |
| `$DF00-$DF8D` | RAM beneath I/O: 142 runtime bytes staged at load, copied to the reclaimed decoder before backup installation. PRG ends here. |
| `$DF8E-$DFFF` | No load-time payload; reserved staging/backup tail. |
| `$D200-$DF98` (runtime) | **3,481-byte original low-RAM backup**, replacing consumed staging. Required until EXIT in F/D/M/H; never scratch. I/O remains visible over it. |
| `$E000-$E95F` | Resident proton/type/hyperspace code/state; packed then installed at init, F/D/M/H. |
| `$E960-$EA15` | Resident init/copy/exit helpers (182 bytes); only init and exit execute them. |
| **`$EA16-$F6F8`** | **3,299 bytes free for new code/data in every mode**, no overlay or restore needed. Use the existing hooks. |
| `$F6F9-$FE7F` | Unchanged 1,927-byte TORPA stream; resident, player and enemy protons. |
| `$FE80-$FEFF` | TSHOT, 128 bytes of original shot masters; resident, F/D/M restoration. End of decoded high image. |
| `$FF00-$FF04` | MMU configuration registers, never ordinary payload. |
| `$FF05-$FFF9` | Reserved KERNAL/vector area; never stage loaded data here (native LOAD stops at `$FF00`). |

The new choice is permanent relocation, rather than a runtime overlay. All 3,481
bytes originally at `$E960-$F6F8` move by exactly `$DD00` to `$0C60-$19F8`;
relative branches and indexed accesses keep their low bytes and page crossings.
No code in the cockpit, map or `$5300` glue moves. The 2,206 pre-existing symbols
below `$E000` are frozen in `fixed-symbols.json` and checked by every game build.
Low RAM is borrowed only after all KERNAL loading has finished. With interrupts
disabled and no KERNAL calls during gameplay, its editor/BASIC workspace is not
used by the game; EXIT restores it before restoring the caller's MMU and IRQs.

Init first decodes the high image. `GINIT3` selects 2 MHz/MMU `$3F`, saves the
original low RAM into the consumed packed bitmap at `$6000`, decodes STR2Y and
the low block from `$D000/$D100`, installs the 142 runtime bytes from `$DF00`,
then copies the saved workspace beneath I/O to `$D200`. It returns at 1 MHz/MMU
`$3E`; GINIT2 restores fighter slots and clears the view before showing it.
Only EXIT selects `$3F` again to restore the saved workspace. The former
MSUNPACK code remains inert in the relocated block to preserve all page offsets.

Measured margins: **3,299 high**, **2,398 packed**, **1 glue** byte, versus 0/68/1
before. The new archive uses 3,187 of the 3,584 staging bytes before `$DF00`.
All sprite, art, stream, decoder-reclamation and native LOAD bounds remain
checked; superseded separate positioning/enemy-stream checks are replaced with
whole-low-block and archive/table/backup bounds. No runtime unpacking is added.

`node js/test/run.js` independently decodes the archive, checks CPU-installed
bytes and original-workspace backup, checks both low-RAM boundaries and EXIT,
and fills the entire free high range with `$A5` across the existing gameplay
scenarios. Its old executable save-state fixture is explicitly relocated by
the replay test; old browser save states are not automatically migrated.
VICE x128 remains the user's final check, especially cold LOAD, docking, a
subsequent fight/hyperspace jump, and RUN/STOP back to BASIC.
Verification on 2026-11-07: game build, JS build, bundle and the full Node suite
all pass ("all checks passed"); 42 game boots retain the free-range pattern,
and DMA late split writes / OVRUN remain zero.

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

Not yet: hyperspace's abort, thrust (W), mothership mines and
the second display while flying, game over, and the destroyed-system messages.


The base positioning code lives in `$E000`, through the existing shape and blank
hooks. Hyperspace lays out one base slot and arrival preserves it. The normal
cockpit steering is suppressed during positioning; the radar mark is erased
before switching back to close range. DMA tests compare the original's readings,
radar mark and frames to the ring start for friendly and enemy bases. The port
uses a frame-locked approximation of the original loop's rate (up to five passes/frame, with a raster deadline),
including its exact 00/00 lock and in-front/distance-below-$0600 exit.

Memory now follows the 2026-11-07 map above: 3,299 high, 2,398 packed and 1 glue
byte free; low code is installed once with original workspace saved beneath I/O.
The unchanged 1,927-byte animation ends at TSHOT `$FE80`. The PRG ends at `$DF8D`,
below the KERNAL LOAD limit `$FF00`. All pre-existing symbols below `$E000` stay fixed.
The temporary SPRCROSS/HTSPR wrapper keeps incoming sprites visible even when phasor work defers the view hook; MSOFF
restores both hooks.

Incoming-proton decoding runs in the blank, armed through existing mothership
hooks at radius 25, with zero additional work in idle flight/fights. Its two
shapes borrow `$6000-$607F`; the next squadron reloads every fighter shape.
Tests compare all 31 reverse frames, sprite positions/expansion, launch and impact
SID writes, five hits, forced deflector and friendly/destroyed gates, protected
assets, map return/re-entry lock, and DMA split timing. The measured original
attack lasts 43 frames; the port takes 43 normally (also with an overlapping
player proton) and 50 under continuous steering/fire because its approach drawing is frame-locked. The original can
restart its launch twice in one frame; the port restarts once per frame while
the ring remains at radius 25. Please compare animation, hit flash/sound and
the following map in VICE x128.

Enemy-proton layout correction (2026-11-06): original shadows `$F1/$F2` and
`$F3/$F4` are X/Y pairs. Sprites 5/6 both use X `$A0`, with Y `$8C`/`$A1`:
the two 21-row shapes stack vertically. The previous port transposed X/Y,
placing the lower half beside the upper half. ETSPR now writes the correct
registers with identical code size/cycles; decode order, pointers, art and
horizontal-only expansion are unchanged. Regression checks compare all 31
frames with original `$CF04` and player TDEC, and replay the supplied pre-launch
save state with DMA, dumping per-frame pointers, bytes, X/Y and expansion to
`js/test/out/enemy-proton-saved-state-trace.json`. Memory margins remain 0 high,
66 packed and 1 glue byte; all bounds remain enabled.

Player proton/base overlap (2026-11-06, issue #15): ring work, centre drawing
and palette painting previously gated on any nonzero TPF, freezing the approach
behind an unfinished ring. These gates now allow flight (TPF=1); decoding keeps
its persistent source/output separately, while post-flight blast/flash (TPF>=2)
still excludes shared drawing scratch. Radius/phase cadence is unchanged. Two
small branch/comparison rewrites pay for the gates, keeping high code the same
size and all build bounds enabled. Memory left: 0 high, 66 packed, 1 glue byte.
The game tests replay the supplied C64 in-flight state with DMA and record radius
($43, loaded at $90F3), bias, phase countdown ($953D), phase ($953E), kill flag
($8C3E), flight and SID activity alongside the port. In the 18 remaining reference flight
frames, radius stays within one step and the phase countdown within four calls
(about eight frames); this retains the existing frame-locked approximation.
Endpoint-during-flight checks cover both base kinds. VICE x128 visual confirmation
remains with the user.


Friendly-base proton colour correction (2026-11-06, issue #16): `$BB81` leaves
`$BAD1=0` on any miss (phase 0 or no opening), and `$BBE4` immediately returns.
Neither friendly nor enemy misses change any of the 520 colour RAM cells in
rows 4-16, the border or background. Phase-1 hits with an opening paint those
cells orange (8), leaving border/background unchanged; the blast routine itself
does not restore their colour. The port incorrectly invented an orange flash
and restoration on misses. MSBLAST now clears TPF on a miss; the legacy MSFLASH
path is no longer entered. Padding preserves the saved-state entry addresses.
Successful base blasts now also skip the fighter blast's white restoration,
matching the original orange palette until scene cleanup.
DMA regression tests call the original directly, record every frame in
`js/test/out/base-blast-colour-trace.json`, and compare both kinds, phases and
pre-opening/opening radii. Hits retain the port's bounded row-fill latency
(up to seven frames), rather than the original's immediate whole-view fill.
Outside-$E000 symbol addresses are unchanged, and every build bound remains.
Current memory left: 0 high-code bytes, 68 packed bytes and 1 glue byte.
VICE x128 visual confirmation remains with the user.
