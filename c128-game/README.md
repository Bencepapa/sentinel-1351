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

- Cold boot and game-over restart open the cockpit title with the C64 wordmark
  and animated credits over the stars. **F5**, **F7**, joystick fire or a 1351
  left click opens the difficulty selector. Move the crosshair with a port-2
  joystick or mouse. Skirmish, Assault, Battle, Invasion and Armageddon run
  from easiest to hardest. Press fire or left click again to fire the phasor
  and confirm. The chosen name flashes with SID pulses for about three
  seconds (the original's welcome ribbon scrolls from the accept, blinking
  and beeping every 12 frames, the engine hum bursts every sixth frame), then the
  48-line Starfleet briefing opens, types, holds for 240 frames and closes. The
  stars, crosshair and guns stay in the view. The map opens automatically. Release the confirmation button and
  press **Fire** or **Space** to advance early.
- The title plays the original's three-voice SID tune once per title visit
  (13,150 SID writes, the same frames as the C64: `js/test/title-music.js` compares
  every write). Opening the selector (F5, F7, Fire) switches the three controls off and
  starts the engine hum ($C38E: voice 3 noise, volume `$1F`); the original has no
  sound of its own when the selection moves (traced with joystick and mouse), only
  the hum, which bursts again every sixth frame from the confirm to the map.
  The tune, the welcome ribbon and the briefing text are the original's: the
  build copies them from the disk's `SN1` (`title_music` and `title_briefing` in
  `build.py`, player in [title-music.asm](title-music.asm), briefing in
  [title-intro.asm](title-intro.asm)). To use another tune or text, change those
  two functions. Edit the scroller in [title-text.txt](title-text.txt) and rebuild;
  its punctuation glyphs take a font slot only when the text uses them. The scroller
  file lists its glyphs. Unsupported characters are reported with their line and
  column.
- The ship starts in sector 05.03 (map cell 4,2), empty as in the original.
- **TIME** starts at `00:00`, advances one game second per 60 gameplay frames,
  and wraps after `59:59`. The colon blinks every 30 frames. The clock freezes
  when either ending starts and clears when the game restarts.
- **C=** (Alt in the page) or the **right mouse button** (held alone for 5 frames, as
  in the C64 patch) opens the map **in the cockpit's 3D view**, as in the
  original in flight: the view wipes a row a frame, and the grid
  draws in with its beeps; the HUD, the radar, the guns and the scanner row stay.
  The same key again closes it (the view wipes back, the stars return).
- **The fight goes on behind the map**: the stars keep moving, the fighters fly
  behind its lines and icons, enemy shots still hit the ship. While the map is
  open the mouse moves its cursor and turns the stars (no phasor, no steering).
- **The mouse moves a + pointer** over the grid (enhancement); the cursor box
  follows the sector under it. In joystick mode the stick steps the box.
  The browser switches on a new joystick press or mouse action. On a native
  port with valid mouse pots, Down, Left or Right selects joystick control
  and mouse movement switches back. Up and Fire share the mouse-button lines
  and follow the active device.
- **SPACE (or both mouse buttons) launches a proton torpedo** (the HUD's PROTONS count): the original's pre-drawn rotating torpedo flies up the view for 32 steps, then every ship in view goes down and orange rings spread from the middle. With none left, a click. **RUN/STOP does nothing**: the game never returns to BASIC (since 2026-11-17; reset the machine to leave).
- **Fire on another sector** closes the map and jumps there through hyperspace: the stars speed up (about 4.5 s), then streak into lines while the energy runs out ten times as fast and the steps left count down in big digits over the radar, then slow down (about 2.4 s). A step is a point of the map's flight path (the longer of 12 x columns and 16 x rows), 13.5 frames each, so the far corner takes longest. First the path is plotted on the map, a brown point a frame with beeps, while the map's lines are erased from both sides (the brown path and boxes stay); the upper HUD's border pulses through grays, and the engine's noise rises while the ship accelerates, holds in the jump and falls while it slows down. When the jump begins, the radar silently switches to long range and shows the destination's groups with the first group's readings (00 for an empty sector; no blip until the arrival); steering moves them nearer or farther, left or right (the original's positioning), and on arrival the approach starts with them where they were put. With a mouse the crosshair becomes the hyperspace cursor once the map is gone, until the arrival (as the H test): it steers while the mouse moves, changes colour, spins its digits and springs back to the centre when the mouse rests; while the ship slows down its digits count from 999 to 000. In the jump meteors come (five at most, as the original's): they grow, drift outward and hit the ship at full size (flash, a system hit, the rattle) unless steered away or met with the deflector: fire turns the view green and shows the shield's lines, at 10 energy a frame. The abort comes later. Fire on the ship's own sector just closes the map.
- **The world runs all the time**: the map's clock (squadrons move every 16th
  tick, motherships attack, the planet's ring) ticks as often as in the original on a real machine (every 33 frames with the map open, 44 in flight, 54 in a fight, 200 while the tracking computer flies), whether the map is open or not (except in hyperspace, where it holds still from the path plot to the arrival: the groups seen on the long range scanner are there on arrival; the original keeps ticking in the jump and lost them in about a third of all jumps: issue #13, MAP-LOGIC.md); the icons are only drawn while it is open (cells that changed
  are drawn a few a frame).
- **F3 / Shift+F3** during a friendly base's repair report ends the system checks and refills the energy at once; the ship is repaired and gets its proton as before. (The original ends only the checks, its refill, +9 a frame, still runs: with a drained ship F3 seemed dead.) A tap while the text is typed counts when the checks start; F3 does nothing anywhere else.
- In a squadron's sector the cockpit's approach begins (the long range scanner:
  groups far away, fire chooses one, aligned in front the ship rushes in, the
  group becomes up to three fighters; all type 1 for now, whatever the squadron's
  type). TARGETS shows the sector's ship count, each kill lowers the map's COUNT,
  the last one empties the sector on the map. SECTOR on the HUD follows the jump.
- **A squadron coming into the ship's sector** (at the end of a move, `$BEDF`): 24
  points rush to three places with a sound (`$1AF2`), three fighters appear there,
  the warning sounds and the dogfight starts. A squadron of fewer than 3 becomes 3,
  as in the original.
- In mothership sectors the long range scanner first shows the base's position and X/Y/Z readings. Only sideways steering moves it; pitch input is ignored. Exact 00 side and 00 up in front locks steering, and depth closes at the original base loop's rate. Fire shoots in the mine/settling phase; later base phases refuse phasors. It does not select another target. As in the original, the base is a radar mark without the cyan animated fighter-selection sprite. After the bounded shape loading, near enough in front, the ship settles for about 184 frames, then, while the tunnel fades out (one band pair every 16 frames), waits 64-80 frames before the rings and rectangular opening grow as in the original. Enemy bases flicker and turn white in alternating phases; friendly bases stay white but share the same hidden phase. A proton destroys a base only if its opening has appeared and the phase is on when the torpedo arrives; a miss preserves the base's colours and the approach continues. A kill shows BASESTAR DESTROYED CAPTAIN, a burst and expanding erasing rings, then clears the sector. Every base sequence returns to the map; that sector cannot be selected straight back until you jump elsewhere. A surviving friendly base draws its white tractor rays, types the full-screen eight-system report with coloured scanning blocks and repair beeps, recharges energy, repairs the ship and grants one proton before the map returns. Tractor rays reach the guns; docking restores the cockpit and all sprite shapes for the next fight. An enemy base fires a white incoming proton at radius 25: it cannot be shot down or dodged, takes five shield/system hits, then returns to the map with the same re-entry lock. Friendly bases never fire. Before the rings, four multicolour mines grow and drift through the scanner approach. They can be shot down or dodged sideways; an undodged full-size mine takes a shield and a system point. New stars start on a horizontal band throughout positioning and the visible rings; aligning exact 00/00 in front locks star steering at any depth. The lock remains latched until a new sequence. The ?3 fighter-approach threshold does not apply to bases. DMA comparison found the original slightly faster than the port under sustained horizontal input (65?66 versus 60 steering updates in 60 frames); horizontal speed has been retained. The port clears surviving mines in a short cleanup tail before the rings, restoring the borrowed fighter sprite slots instead of retaining the original frozen-sprite bug. As in the original, the map cannot be opened during a base's sequence (positioning, mines, rings, destruction, docking, repair): the original reads C= only in its flight, fight and approach loops ($FB43), never in its base loops ($8C44, $90F3) (issue #19).
- Strategic warnings (a mothership engaged/destroyed, JARALOBA surrounded/lost) now appear on the cockpit message line even with VDC off.
- Shield death and the loss of JARALOBA end the game: 255 frames of flashing
  and noise, then the cockpit disappears into a star field with the original
  large ending text, report, rank and class. Clearing every enemy and pending
  mothership attack wins after the original 60 qualifying checks in flight (or
  on the map). Victory is the original's single screen: the HUD, cockpit,
  crosshair and stars stay, the view (or the open map) wipes clear, the energy
  refills to 9999, then VICTORY IS YOURS / JARALOBA IS SAFE, the six statistics
  (energy used, shields lost, enemy killed, protons and phasors fired, base
  stations) and SPACE DROID ... CLASS n appear as in the original. Fire restarts after the original
  waiting interval; otherwise it restarts automatically (about 3.5 minutes for
  death and 6.3 for victory at PAL speed). Restart restores the cockpit, ship,
  sprite slots and movement streams, then opens the title. Confirming a difficulty
  generates a new world in sector 05.03.
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
| `$0002-$002A`, `$002D-$00FA`, `$00FF` | **Zero page, 248 bytes free** (the game uses `$FB-$FE`, and the relocated original rating `$F440` its temp `$2B/$2C`; BASIC's/the KERNAL's zero page is not kept: no return to BASIC). |
| `$0100-$0154` | The bank-1 copy stub in common RAM below the stack (`bank1.asm`; the stack never goes below `$01EA`). `$0155-$01BF` (107 bytes) is free common RAM below the stack. |
| `$0200-$055C` | Resident ending checks, statistics, reset and snapshot helpers in `ending.asm`. |
| `$055D-$05DA` | Resident TIME clock, staged with the ending core. 119 code bytes and 7 data bytes. |
| `$05DB-$0BC9` | Later resident helpers, including the TITLE entry, first-jump MINES loader, first-map handoff and briefing raster handlers. |
| `$0BCA-$0C5F` | **150 bytes free** in every mode. |
| `$0C60-$19F8` | 3,481-byte resident relocated mothership/repair/message/positioning/enemy-proton block. Used in M, message jobs also F/D/H; retained in every mode. |
| `$19F9-$1A09` | 17 bytes in C128 BASIC's free ML area, installed with the block: `ENDCROSS`, the victory's input hook (issue #20). |
| `$1A0A-$1A0F` | 6 bytes free. |
| `$1A10-$1BFE` | The overlay manager (`overlay.asm`, installed by B1INIT from staging), including S1's owner, the loader, MNREQ and the trampolines. `$1BFF` is free. |
| `$1C01-$1C0C` | BASIC SYS stub; init only (dead after init). |
| `$1C0D-$1C0F` | Loader-to-entry padding. |
| `$1C10-$1CF4` | `ENDINIT` and `TITLESTORE` at init, plus resident bank 1 and reset helpers. |
| `$1CF5-$1CFF` | **11 bytes free** in the loader's tail. |
| `$1D00-$28D6` | Cockpit first code/state chunk; resident F/D/M/H. Two holes left by the exit to BASIC (same size, nothing moved): **`$1D14-$1D58` 69 bytes** (START's saves of the caller's state; START jumps over them) and **`$1F79-$1FD8` 96 bytes** (the old `EXIT`; the label stays). `SAVMMU`-`SAV1D` (`$28A3-$28B0`) are dead variables left in place (12 of them restored by the reset snapshot). |
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
| `$3400-$35FF` | Middle TITLE stream at load. `TITLESTORE` clears both pages for the phasor X/Y path buffers before play. |
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
| `$4000-$43FF` | VIC character font. TITLE borrows eight blank glyphs at `$40F8-$4137` and restores them before the briefing. |
| `$4400-$47E7` | Bitmap screen matrix; live F/D/M/H. |
| `$47E8-$47FF` | Matrix padding and sprite pointers; reserve the whole tail. |
| `$4800-$4BE7` | HUD/bottom text and docking report screen; live F/D/M/H. During an ending the hidden rows hold the death reports and rank names (`$4900-$4B13`), unpacked from VDC RAM; reset unpacks the whole screen's master. |
| `$4BE8-$4BFF` | Text padding and sprite-pointer tail; reserved. |
| `$4C00-$4FFF` | Crosshair, tracking, guns, approach blips, planet and barrel sprite slots; protected in every mode. |
| `$5000-$5257` | 600-byte cockpit matrix master for map close; resident F/D/M/H. CPU-only RAM (VIC sees character ROM). |
| `$5258-$52FC` | Ending/sector helpers (`ENDVDCBLANK`; its 5 displaced START bytes `$52C0-$52C4` are free since the exit to BASIC went), then `ARROWS`/`ARPIX` (a squadron coming in, issue #18) and `GMAPTOG` (no map in a base's sequence, issue #19). |
| `$52FD-$52FF` | 3 bytes free. |
| `$5300-$5DFE` | Glue code/state; resident F/D/M/H. `$5D63-$5DF0` is the init decoder, reclaimed as 142 bytes of frame pointers, mothership state, timing and repair state. UPEND/GSEED/GUNPK2 stay intact. |
| `$5DFF` | One glue byte free; do not move existing code. |
| `$5E00-$5FFF` | Packed high-image start at load; becomes 512-byte type-2 Y streams at init, resident F/D. |
| `$6000-$63BF` | Fighter sprite slots, protected F/D/M/H; enemy proton temporarily borrows `$6000-$607F`. Init temporarily uses `$6000-$6D98` for the low-RAM backup, then restores all slots. |
| `$63C0-$767F` | 3D-view bitmap. At load, the high archive ends at `$75D7` and the last TITLE stream uses `$75E0-$7669`. Both are consumed before the view is drawn. |
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
| `$D052-$D05F` | Staging padding; hidden beneath I/O during gameplay. |
| `$D060-$DCE5` | 3,206-byte packed low-code stream at load/init, consumed before backup installation. |
| `$DCE6-$DEFE` | Tunnel stream staging (`MTSTAGE`), consumed before backup installation; `$DEFF` is the one byte left. |
| `$DF00-$DF8D` | RAM beneath I/O. During init, 142 runtime bytes are staged here for the reclaimed decoder. |
| `$DF8E-$DFFF` | No load-time payload; reserved staging/backup tail. |
| `$D200-$DFFF` (runtime) | Free RAM beneath I/O after init (data only, MMU `$3F`): the low-RAM backup moved to bank 1 (2026-11-17). |
| `$E000-$E95F` | Resident proton, type and hyperspace code after init. The load image above `$E000` holds the packed resident core and ENDING, the bank-1 payload, `B1INIT`, the overlay manager and the first TITLE stream through `$FEF1`. The other TITLE stream ranges and workspaces are in the [overlay plan](../briefs/memory-overlay-plan.md#load-and-runtime-space). |
| `$E960-$F6F8` | **S1, the overlay slot**. `GINIT3` runs here at init. TITLE (`$E963`) owns it at boot and after a reset. MINES (`$EA16-$F6F6`) loads during the first jump or at a base arrival. ENDING (`$E970-$F129`) owns it during a death or victory. |
| `$F6F7-$F6F8` | Two bytes free in every mode (no package uses them). |
| `$F6F9-$FE7F` | Unchanged 1,927-byte TORPA stream; resident, player and enemy protons. |
| `$FE80-$FEFF` | TSHOT, 128 bytes of original shot masters; resident, F/D/M restoration. End of decoded high image. |
| `$FF00-$FF04` | MMU configuration registers, never ordinary payload. |
| `$FF05-$FFF9` | Reserved KERNAL/vector area; never stage loaded data here (native LOAD stops at `$FF00`). |

The new choice is permanent relocation, rather than a runtime overlay. All 3,481
bytes originally at `$E960-$F6F8` move by exactly `$DD00` to `$0C60-$19F8`;
relative branches and indexed accesses keep their low bytes and page crossings.
No code in the cockpit, map or `$5300` glue moves. The 2,206 pre-existing symbols
below `$E000` are frozen in `fixed-symbols.json` and checked by every game build.
Low RAM is taken only after all KERNAL loading has finished. With interrupts
disabled and no KERNAL calls during gameplay, its editor/BASIC workspace is the
game's; since 2026-11-17 nothing of it is kept (no return to BASIC).

Init first decodes the high image. `GINIT3` selects 2 MHz/MMU `$3F`, saves the
original low RAM into the consumed packed bitmap at `$6000`, decodes STR2Y and
the low block from `$D000/$D100`, installs the 142 runtime bytes from `$DF00`,
then copies the saved workspace beneath I/O to `$D200`. It returns at 1 MHz/MMU
`$3E`; GINIT2 restores fighter slots and clears the view before showing it.
(Before the bank-1 store, EXIT selected `$3F` again to restore the saved workspace;
there is no EXIT any more.) The former
MSUNPACK code remains inert in the relocated block to preserve all page offsets.

Measured margins after the raster tunnel follow-up: **2 high**, **91 packed**, **1 glue** byte.
The low archive uses 3,189 of the 3,584 staging bytes before `$DF00`.
All sprite, art, stream, decoder-reclamation and native LOAD bounds remain
checked; superseded separate positioning/enemy-stream checks are replaced with
whole-low-block and archive/table/backup bounds. The mine art alone is decoded at base entry; no runtime code overlay is added.

`node js/test/run.js` independently decodes the archive, checks CPU-installed
bytes and original-workspace backup, checks both low-RAM boundaries and EXIT,
and fills the entire free high range with `$A5` across the existing gameplay
scenarios. Its old executable save-state fixture is explicitly relocated by
the replay test; old browser save states are not automatically migrated.
VICE x128 remains the user's final check, especially cold LOAD, docking, a
subsequent fight/hyperspace jump, and RUN/STOP back to BASIC.
Verification on 2026-11-07: game build, JS build, bundle and the full Node suite
all pass ("all checks passed"); all game boots retain the free-range pattern,
and DMA late split writes / OVRUN remain zero.

`build.py` reads both sources, `game.asm` (the glue), and `mines.asm` (the resident minefield):

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

Not yet: hyperspace's abort, thrust (W), the second display while flying,
and the remaining destroyed-system effects/messages.


The base positioning code lives in `$E000`, through the existing shape and blank
hooks. Hyperspace lays out one base slot and arrival preserves it. The normal
cockpit steering is suppressed during positioning; the radar mark is erased
before switching back to close range. DMA tests compare the original's readings,
radar mark and frames to the ring start for friendly and enemy bases. The port
uses a frame-locked approximation of the original loop's rate (up to five passes/frame, with a raster deadline),
including its exact 00/00 lock and in-front/distance-below-$0600 exit.

Memory now follows the 2026-11-07 map above: 0 high, 253 packed and 1 glue
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
Memory left at this base-blast follow-up: 0 high-code bytes, 68 packed bytes
and 1 glue byte.
VICE x128 visual confirmation remains with the user.


Minefield verification (2026-11-07): the game tests compare 72,000 mine calls,
155 phasor hit cases, damage and SID noise with the original; verify all twelve
sprite shapes, original y=105 star births and steering lock; and count late
splits/OVRUN through live fields and their handover. The port uses bounded
30/15-call ceilings and alternating six-star updates, rather than the original
variable main-loop rate. The final fourteen wait frames restore borrowed
slots. See the plan's "Minefield before the rings" for exact entry/exit traces,
intentional approximations and VICE checks. No code below `$E000` moved.

At the 2026-11-07 minefield build, JS build, bundle and full Node suite passed
("all checks passed"). All then-new minefield DMA scenarios, including map
pause during cleanup, had zero late writes and zero OVRUN. Margins then: 0 high
/253 packed /1 glue byte. The PRG still ends at `$DF8D`, below the native LOAD limit.

Minefield follow-up: the original resets base vertical high at `$8CB2` every
pass. The port now does this too and ignores pitch for base and star steering.
Lock tests cover 00 acceptance at near/far depths, rear rejection, 01/03/04
rejection and latch persistence against `$8E90`; the original's ?3 check belongs
to the fighter approach. Sustained DMA joystick/mouse-mask traces are written to
`js/test/out/mine-steering-rates.json`, including every frame's side reading.
The birth band is retained through visible rings and random births return on
sequence exit. Regression log: `js/test/out/minefield-fixes-complete.log`.


Parity corrections (2026-11-07): cursor Y is restricted to the original 135..165,
centre 145, through the base sequence. Both entry messages retain their text
for all ten colour flips (200 frames); scanner initialization no longer clears
them and readings wait for the message. Steering stays locked through rings,
destruction and repair. Mine/settling ignores SPACE/both-button torpedoes
silently without spending ammunition; ring phases accept them under the usual
phase/radius/count rules. Later base phases do not launch phasors. Normal
input and star hooks return on sequence exit with no idle wrapper.

The C64 also sends its former short-range contacts rapidly downward during
jump acceleration; destination long range begins after acceleration. The port
keeps its existing bounded radar cleanup, not an exact old-contact animation.
See the plan's parity section for addresses, tests and this remaining visual
approximation. Free memory at that parity correction was 0 resident /253 packed
/1 glue byte.

Final parity validation: all four required build/bundle/test commands pass; full suite ends with all checks passed. Log: js/test/out/minefield-parity-complete.log. New DMA parity/base/repair scenarios have 0 late writes and 0 OVRUN. No commit or push.


Supplied-state parity round (2026-11-07): js/test/mine-parity-states.js loads
the user's C64 save and recreates its friendly-base approach in the current
build (the C128 save embeds older code). Eight mouse/joystick clamp traces
match exactly, including X 0..254; live identical-input traces cover four
directions, fire, joystick up+fire, SPACE and both buttons. The saved message
tail matches colours/expiry and retains its row. A real 00 scanner lock and
both settling/ring transitions retain locked stars and suppress new phasors.

Fixed an additional discrepancy: the mouse's both-button chord now suppresses
phasors during the minefield, matching C64 v10; refused protons remain silent
and free. The mouse-presence gate preserves joystick up+fire. The active base
input hook alone changes; normal flight keeps direct INPUT. Leaf-only PTR
scratch pays for the added instructions without moving any fixed lower code.
Memory left at the supplied-state parity round: **1 resident, 246 packed, 1 glue byte**; backup
$F3F8-$F6F7, resident end $F6F7 and native PRG end $DF8D.

Trace: js/test/out/mine-parity-saved-comparison.json. Input polling can differ
by one frame; mine/shot cadence and old-contact radar cleanup at jump start
remain bounded approximations. The existing radar tests confirm the original
downward departure and the port's correct destination scanner. VICE visual
confirmation remains with the user.

Final supplied-state validation: python c128-game/build.py, python js/build.py,
python js/bundle.py and node js/test/run.js all pass. Full-suite log:
js/test/out/minefield-parity-states-final.log (all checks passed; 71 game boots
retain the free-memory pattern). Every new live DMA state replay and handover
reports 0 late split writes and 0 OVRUN. No commit or push.

## Raster tunnel follow-up (2026-11-09)

The coloured `$D020/$D021` tunnel bands are now part of the minefield port.
The palette is refreshed on phase/fade changes rather than every frame, and
the line table uses the original C64 values with the repeated constant prefix
folded out. The raster IRQ is installed only through the minefield hooks.
At the ring handover `MTOFF` disables the IRQ and clears the VIC colours;
the final mine sprite-slot restore is serviced in the blank hook, not during
the visible view pass.

Verification: 256-phase C64/port raster comparison, maximum 2-line drift;
saved-state steering/fire replay and ring handover report zero late split writes
and zero OVRUN. The full `node js/test/run.js` suite ends with `all checks
passed`. The 80/94 entry takes 340 port / 331 original frames, within the
existing ten-frame bound. Current build margin: **9 high / 88 packed / 1 glue**
byte. Recheck the turning/fire/final-fade appearance in VICE x128.

## Raster tunnel: hit flash, exit fade, close boundaries (2026-11-10)

- **Hit flash** (C64 `$139A`, table `$1311`): in the tunnel a ship hit no longer
  paints the cockpit's flash colour from line 76 down to the first band (the
  white strip under the HUD). Each flash step shows one frame of one colour
  over every band, the outer area and the middle strip (white, orange, white,
  yellow, white, black); the middle strip and faded bands keep the step's
  colour until the next step, as in the original. `MTFRAME` clears `FLASHC`
  and watches `FLN`; the palette is repainted every frame while `HITFL` runs.
- **Exit fade** (C64 `$9097` arms `$0F7F`, `$0F80`, `$8D3E`): it is now a level
  (`MTEXIT`) that rises in step with the 16-frame colour shift during the last
  settling stage (`MSROW` 3), blackening one band pair, inner first. That
  stage's clock is held until level 5, so the rings start 16 frames after the
  tunnel is fully black, whatever the phasor load (formerly a fixed 70-tick
  clock, not in step with the shift, and stretched by deferred view passes).
  The mine sprites are restored from level 4 (16 frames).
- **Close boundaries**: when the next band boundary is on the following
  raster line the IRQ now waits for it (as the C64's `$0F08` does) instead of
  setting a compare that could already be past; the old code lost the whole
  lower half of the chain for two frames in every 16 (phases 1-2), leaving the
  inner colour over the bottom half.
- `MTSHOT` is merged into the end of `MTFRAME`; the constant middle-strip lines
  live in the table's data.
- Tests: hit-flash sequence against the C64 table, full IRQ chain every frame,
  exit-fade steps against the original in the saved-state alignment (original
  +7/23/39/55, rings +70; port +11/27/43/59, rings +75), and the base timing
  check now compares the settled stage (within 10 frames) and the exit-fade
  wait (64-81 frames in both games; 80/94: port 271/351, original 264/331).
  `node js/test/run.js`: all checks passed. Margins: 2 high / 91 packed / 1 glue.


## Game-end workspace and restart (2026-11-11)

`ending.asm` adds death, planet-loss and victory, the original `$F440` rating,
four death reports, rank/class, bitmap lettering, SID effects, and fire/timeout
restart. See the plan's "Game endings" for the original addresses, statistical
quirks, measured timings and bounded cadence differences.

The extra workspace is `$0200-$0C5F` (code through `$0C5E`), saved in VDC RAM
before installation. `end-loader.asm` occupies previously unused BASIC-stub
padding `$1C10-$1CFF`. The ending image is loaded at `$E000-$EA5F`, then copied
before the existing high-image decoder overwrites that staging. The PRG now
ends at `$EA5F`, below the unchanged `$FF00` native LOAD limit. Existing lower
symbols, glue, cockpit and map code retain their addresses.

The disabled VDC's first 16K holds the original workspace and reset snapshots.
At program entry, `ENDVDCBLANK` disables VDC attributes (register 25) and sets
both monochrome colours to black (register 26), and disables the cursor (register
10), before delays or snapshot writes.
This hides boot text and all screen/attribute/font data even while it changes;
the RAM remains available for the snapshot. The helper uses matrix-master padding.
This includes protected `$7CC0-$7FFF` sprites, which the full-screen bitmap
clear temporarily erases. Reset restores them and re-decodes all 768 bytes of
movement streams borrowed by mines. The existing `$D200` low-workspace backup
is never overwritten; EXIT restores both borrowed workspaces before returning
to BASIC. The second display must remain disabled while this snapshot is live.
Immutable mine art, stream data, init/event helpers and the retired decoder are not
copied into the reset snapshot.

Final margins: **2 high / 91 packed / 1 glue bytes**; new workspace **1**,
loader **0**, VDC **13** bytes. `build.py` checks every boundary and the frozen
symbols. No code overlay is installed during play: only startup copies the
ending image, and reset restores the startup snapshot.

`js/test/game-end.js`, invoked by the "game:" suite, compares 240 original
ratings, bitmap pixels, SID setup, death/report timing and restart waits. It
checks RUN/STOP workspace restoration, both death causes, victory blockers,
restored sprite slots, and actual minefield/proton death recreated from the
supplied C128 low-shield save. The C64 original reference uses the C64 minefield
save because `low-shield.state.json` identifies itself as C128.

The original pass-counted waits are modeled using measured PAL frame counts;
held-button restarts differ by at most four frames in the checked scenario.
The pulse rattle uses 24 substeps/frame and letter colours change every six
frames. VICE x128 visual/audio confirmation remains outstanding. No commit
or push. Validation log: `js/test/out/game-end-all-checks.log`.

## Game-end display fixes (2026-11-15)

The full-screen ending handover and restart now use invalid VIC mode `$7B`
(black, with bad lines retained) while clearing/rebuilding display memory.
Previously `$3B` exposed the old bitmap sprite slots/cockpit art during the
clear, and exposed the partially restored matrix/art during the VDC copy.
The completed title switches back to `$3B`; the flight loop restores its own
raster splits after restart. Death and victory share this path.

The HUD's rightmost column was an older port bug, also present on `main`:
`SHOWSEC` wrote character `$7A` after the leading zero, displaying `0..01`.
The original `$FD7F-$FD99` explicitly formats column 10 as `10`; all 60 sectors
now match its bytes, and leaving column 10 resets the tens digit.

The fixed-address `SHOWSEC` slot calls a helper in unused CPU-only padding
`$5258-$52AB`, immediately after the 600-byte matrix master. The ending energy
hook also lives there to free ending workspace. No existing lower symbols move;
build bounds cover the new chunk. Margins: 2 resident / 91 packed / 1 glue,
32 ending-workspace / 0 loader / 13 VDC bytes, plus 84 unused helper bytes.

DMA regressions in `js/test/game-end.js` stop at the actual clear and VDC restore,
check the black mode, dump screen/colour/charset/bitmap memory and
`$D018/$D011/$DD00` to `js/test/out/game-end-*-registers.json` and companion
`.bin` files, and compare both title bitmaps with the original renderer.
`end-fixes-before.log` records five failures when the old sector bytes and visible
transition mode are reinstated in RAM; the same checks pass with the fixes.
The screenshots `game-end-death-title-vic.png` and
`game-end-win-title-vic.png` show the settled displays. VICE confirmation of the
reported visual glitch remains for the user.

Validation: `python c128-game/build.py`, `python js/build.py`,
`python js/bundle.py` and the full `node js/test/run.js` pass.
`js/test/out/game-end-fixes-all-checks.log` ends with `all checks passed`;
84 game boots retain the free-memory pattern. Victory automatic restart is
22,679 DMA frames, matching the C64 reference exactly. No commit or push.


## VDC startup blanking (2026-11-15)

The ending snapshots use VDC RAM at the boot screen, attribute and font addresses.
Unlike main, which leaves that RAM alone, the ending loader overwrote it while
its display remained enabled. This produced both the initial boot-text mixture
and the later blinking garbage. `VDCON=0` only suppresses map updates; it does
not blank the hardware display.

START now calls `ENDVDCBLANK` immediately after selecting RAM in the MMU,
before any settling delay or snapshot write. Calling the helper at `$52AC`
before banking out BASIC would execute ROM on a native SYS start. It sets
register 26 to black foreground/background, disables
attributes with register 25, and disables the cursor with register 10. Thus all
screen/attribute/font data stays visually black, including during snapshots,
endings and restart. VDC RAM remains backup storage; clearing it after saving
would destroy restart/EXIT data. This starts at executable entry; the program
cannot alter the display before LOAD/RUN transfers control to it.

The five-byte entry replacement preserves every existing cockpit address.
The helper occupies CPU-only padding through `$52C4`, leaving 59 helper bytes;
other margins remain 2 resident / 91 packed / 1 glue, 32 ending-workspace /
0 loader / 13 VDC bytes. Tests seed dirty boot RAM and cursor, check blanking
within 400 CPU cycles, model BASIC's initial ROM mapping, check both blink
phases throughout startup and snapshot writes, and check
death/victory endings and restart. Restoring the old entry bytes fails the new
startup regression. VICE visual confirmation is still outstanding.
`python c128-game/build.py`, `python js/build.py`, `python js/bundle.py` and the full `node js/test/run.js` pass; `js/test/out/vdc-entry-verified.log` ends with `all checks passed` (85 boots). No commit or push.

Final validation after the MMU ordering fix: `js/test/out/vdc-final-all-checks.log`
ends with `all checks passed` (85 boots). The two startup regressions fail with
the original entry restored and pass with this build; see
`js/test/out/vdc-startup-before-after.log`. The PRG, browser export and bundle
match. Local VICE launch exits before emulation because the sandbox blocks
its user state directory under `AppData/Roaming/vice`.

## Original victory screen and the VDC payload (2026-11-17)

Victory now follows the original's one screen (`$F5B9`/`$F5ED`), inside the
normal frame loop so the HUD, cockpit, crosshair and stars stay. At the 60th
qualifying check `ENDWINSTART` stops input, fire, the map key and jumps (as
death does), closes the map if it is open and wipes the view back a row a frame
(`MAPCLOSE`), and points the star plotter at its protected pixel-1 mode. Then,
one bounded step per frame in the 3D view's time (`ENDWINFRAME`):

- the energy refills, 154 units a frame (`$F6A7` adds one a main-loop pass;
  measured 4,170 passes in 27 DMA frames);
- the original's 220-byte text block (`$D100`, rows 4-14) is drawn hidden,
  16-pixel letters as `$0816`, with the six numbers (`$D505`, including its
  leading-zero rules, the `$EA00`/60000 overflow mark and the one-less energy
  value its carry-clear `$D1F0` call shows) and then rows 4-16 turn purple
  (`$F696`);
- the rank's row (`$F3CE`: 13-character name, CLASS, digit) is drawn visible;
- the wait: fire after 527 frames, or the timeout after 18,983 (`$F60D`).

Port vs original from `briefs/ref/c64-last-enemy-map-then-win.state.json`
(the map is open at the trigger), DMA frames from the trigger: energy full
29/28, text revealed 54/53, rank done 57/56, held-fire restart 584/584,
automatic restart 19,039/19,040. Bitmap rows 4-15 match the original pixel for
pixel. The crosshair does not follow the mouse during the wait (the original's
1351 interrupt moves it; the port keeps all input off, as death does).

Memory re-plan: the old short victory scene is gone and the reset no longer
snapshots `$4400-$4BFF` (2,048) and `$7680-$7FFF` (2,432): these hold exactly
their load-time bytes at the snapshot, so `build.py` packs them (run-length,
`ENDUNPACK`) into a VDC payload. The payload, staged at `$EA60` and saved by
`ENDSETUP` before GINIT2, also holds the victory text template (read and
written in place, the numbers and rank are written into it) and the four death
reports plus the eight rank names (unpacked into the hidden text rows at the
death scene / the victory's rank step). The freed VDC RAM bridges the smallest
gaps between snapshot ranges (never through I/O), cutting 44 descriptors to 23.
Margins: workspace 8, loader 3, VDC 256 bytes (plus up to 255 of payload
alignment); high 2 / packed 91 / glue 1 unchanged. No lower symbol moved.
`build.py` checks the masters against the PRG bytes, the payload/VDC bounds and
the number-table layout. Validation: `js/test/out/win-screen-all-checks.log`.
VICE x128 confirmation remains with the user. No commit or push.

## Issues #18-#21 (2026-11-17)

- **#18, a squadron coming in under fire.** The 24 points (`ARRSTEP`) had no
  raster limit: 8 points a frame took 45-95 lines (four `PIXADDR` calls a point).
  After a shot's launch (`LAUNCH`, lines 88-167) or during its flight the points
  started late and ran over the guns' sprites (line 194) and the gray strip's
  split (233), into the next frame. Now a point is not begun after line
  `ARLIM` = 184; the rest wait for the next frame. A point computes its address
  once for both rows (`ARDRAW`, `ARROWS`, `ARPIX`): about 430 instead of 625
  cycles, so idle frames still do 8 points (the same pixels frame for frame,
  60/61 frames). The fighters' set-up (`ARREND`, about 50 lines) waits for a
  frame where it can begin before line 150 (`ARRFX` 4). The routine was
  rewritten in place: `ARRSTEP` and `ARREND` keep their addresses (6 spare bytes
  at `$5B1B-$5B20`); 11 internal labels left `fixed-symbols.json`.
- **#19, the map in a base's sequence.** `GMAPTOG` refuses C= / the right
  button while `MSSTATE` is non-zero. The map is never open then (`MSOFF` comes
  before the automatic `MAPOPEN`).
- **#20, the victory screen's crosshair.** `ENDWINSTART` points the input hook
  at `ENDCROSS` instead of an RTS: `INPUT` moves the crosshair and the guns as
  the original's interrupt does (mouse or joystick, the same 3/2 pixel steps,
  the glide back to the centre), then fire, the A/T tracking request and
  steering are cleared (so `ENDWINSTART` no longer sets `JOY` itself). Reset
  restores the hook from its snapshot. The moving crosshair and guns shift the
  view's time a little; the text's one-job-a-frame step (job 6, the rank names'
  unpack, takes about 114 lines) had no raster limit and once ran over the gray
  strip's split: a job is no longer begun after line `ENDJOBLINE` = 108.
- **#21, the fighters after a reset.** `ENDRESET` entered `g_gi2` (the type-1
  slot restore) with X = `$FF` left by `MRGLYPHBACK`, so it copied one byte a
  page: a borrowed enemy proton ($6000-$607F, the large white "shot" of the
  report is a near fighter with shape `$81`) or a type 2/3 fight stayed in the
  slots. `LDX #0` first. The enemy shot itself ($7CC0-$7F3F, hires by design)
  was never wrong.

Memory: glue unchanged in size; helper pad 9 bytes left (`$52F7-$52FF`); ending
workspace 0 bytes left; low block +17 bytes into `$19F9-$1BFF` (archive staging now ends
one byte below `$DF00`). Tests: `js/test/bugs.js` (supplied saves with this
build's changed code copied in, C64 references, fresh-boot DMA runs).

## Bank 1 store, the overlay slot S1, the ENDING package (2026-11-17, plan steps 2-4)

`briefs/memory-overlay-plan.md` steps 2, 3 and 4 (its section 9 has the details and
the bank-1 map). The game behaves as before; the ending timings against the original
are unchanged (death report/rating 613/615, original 612; victory 29/54/57, original
28/53/56; resets 711/10410/584/19039 frames).

- **Bank 1 is the store** (`bank1.asm`). An 85-byte copy stub in common RAM at
  `$0100-$0154`: `B1GET`/`B1PUT` (pages, 24 cycles a byte), `ELREAD`/`ELWRITE` (a byte
  at the address `ELVADR` set, moving on, as the VDC's address register did), `NMIB1`
  (an RTI). `B1INIT` (init only, staged above the payload) saves `$0100-$0154`,
  `$D501-$D504` and bank 1's `$FFFA-$FFFF`, sets PCRA `$3E` / PCRB `$7F` and bank 1's
  vectors to `NMIB1`, then copies `$0200-$1BFF`, the ENDING package and the payload
  into bank 1 and installs the overlay manager. EXIT (`ENDRESTORE`) puts all of it
  back. VDC RAM is not written any more (its display stays blanked: `ENDVDCBLANK`);
  `GINIT3` no longer saves low RAM (no `$D200` backup, no `$6000` temp).
- **S1** (`overlay.asm`): `OVOWNER` (`$80` MINES, `$40` ENDING), `OVSTART`/`OVSTEP`
  (a resumable copy, 32 bytes between raster checks, pieces only begun in lines
  78-175), `OVLOAD` (all at once), `OVINIT` (MINES' image and `$8100-$83FF` into bank 1
  with the snapshot). `OVSTART` refuses (`OVREFUSE`) while `$D01A` bit 0 is set or
  `vv2`/`sprcj` point into MINES, and points `$FFFE` back at `NMIRTI`. MINES keeps every
  byte and address (`$EA16-$F6F6`). The reset snapshot leaves S1 out: the reset
  reloads MINES and the borrowed streams from bank 1 (`ENDSTREAMS`). The torpedo's
  request check is resident (`MNREQ`); a sector's arrival calls `MNOFF` through
  `OVMNOFF` (with MINES out of S1 it does the rest of MNOFF itself) and a base
  sector's arrival goes through `OVBASEIN` (loads MINES if it is missing, counting
  `OVMISS`); the base sequence's own calls into MINES stay direct (no cycle added in
  the positioning loop). `build.py` (`audit_s1`) fails on any other resident
  instruction with an operand in S1.
- **The ENDING package** (`ending.asm`): a resident core at `$0200-$0556` (with the
  snapshot copy `ENDCOPY`, now whole pages through the stub, and its descriptors) and
  the package linked at `$E970` (1,918 bytes). `ENDSTOP` (death and victory) starts
  the load; the death flash loads it a piece a frame (in S1 after 17 of the 255
  frames), the victory in its first 13 frames (the wipe takes 15). `ENDSCENE` and the
  victory's text are entered through trampolines (`OVENDING`) that complete a load
  that is not complete. Init is shorter (play begins at frame 48, was 53).

Memory left: `$0557-$0C5F` **1,801 bytes** (all modes), `$1A0A-$1A0F` 6, `$1BF8-$1BFF`
8, loader 14, high 2, packed 168, glue 1, helper pad 9. The PRG ends at `$F932`.
Tests: `js/test/overlay.js` (S1 filled with `$A5` while MINES is out: flight, map,
torpedo and a fight frame for frame as with MINES in; a base reloads it; refusal
while the tunnel runs; the reset's reload; the ENDING package's background load,
its pieces' raster lines, no miss), `js/test/banks.js` (the game's bank-1 use, the
stub below the stack), `run.js` (EXIT restores the stub's page, bank 1's vectors and
the PCRs), `game-end.js` (no VDC RAM written). Old browser saves (`briefs/ref`) get
this build's bank 1, stub and ending core in the tests (`js/test/old-state.js`).
VICE x128: see the plan's section 9 for what to check. No commit or push.

## No return to BASIC (2026-11-17)

The user's decision, after RUN/STOP's exit to BASIC hung in VICE: the game does not
return to BASIC, and BASIC's memory (zero page, `$0200-$1BFF`, bank 1 with BASIC 7's
variables and strings, the KERNAL/BASIC vectors) is the game's.

- **RUN/STOP does nothing.** The frame loop's check (`LDA CIA1PB / BMI nostop`) keeps
  its bytes and its branch, so a frame without RUN/STOP takes exactly the same cycles;
  with RUN/STOP held three NOPs replace the old `JMP EXIT` and the SPACE check follows
  as usual. The only restart is the game-over reset (`ENDRESET`, unchanged). A soft
  reset on RUN/STOP was not chosen: it would have to stop whatever runs at that moment
  (tunnel IRQ, a package load, hyperspace, a base sequence) the way `ENDQUIET`/`ENDSTOP`
  do at a death, a new path with its own risks; resetting the machine leaves the game.
- **Removed**: `ENDRESTORE` (loader); `B1INIT`'s copy of `$0200-$1BFF` into bank 1
  (`B1LOW` `$1000-$29FF`), its save of the stub page, the PCRs and bank 1's vectors
  (`B1STACK` `$2A00`, the `B1TEMP` page at `$FE00`); the cockpit's `EXIT` routine and
  START's saves of the caller's state (both turned into free space of the same size by
  `build.py` patches: no cockpit address moves, `EXIT`/`SPRCROSS`/`cpc` are where they
  were); `ENDVDCBLANK`'s save of `PTR` (5 bytes, left as free space so that
  `ARROWS`/`ARPIX` keep their addresses); the build's reservation of bank 1's
  `$F000-$FEFF` (BASIC 7 strings). `B1INIT` still installs the stub, sets PCRA `$3E`/PCRB
  `$7F` and bank 1's vectors (`NMIB1`), and loads the manager, the ENDING package and
  the payload. The bank-1 layout of the store is unchanged (snapshot `$2C00`, payload
  `$4D00`, streams `$6400`, MINES `$7000`, ENDING `$7E00`), and so are the snapshot's 22
  descriptors (the gap-bridging budget still uses the old 16 K VDC formula, which
  reserved `$0A60` bytes for the EXIT copy: the reset restores exactly the bytes it did).
- Moved: only `ENDQUIET` and `ENDSTREAMS` (in the loader page, `$1CB3`/`$1CD1` ->
  `$1C54`/`$1C72`; two `JSR`s in the ending core follow). Every other symbol keeps its
  address; the PRG differs only in the loader page, the two cockpit holes, the 5-byte
  helper hole, those two core operands and the init staging (`B1INIT`, which is 84 bytes
  shorter: the PRG ends at `$F8DE`).

Free memory now (bytes; "before" is the build just before this change):

| Area | Free now | Before | Where |
|---|---|---|---|
| Zero page | **248** | 0 (BASIC's/KERNAL's) | `$02-$2A`, `$2D-$FA`, `$FF` (the game uses `$FB-$FE`; the relocated rating, original `$F440`, uses `$2B/$2C` as its temp, as the original does) |
| Stack page (common RAM) | **107** | (not advertised) | `$0155-$01BF`, below the stack (lowest SP measured `$EA`) |
| `$0200-$0C5F` (core `$0200-$0556`) | 1,801 | 1,801 | `$0557-$0C5F`, every mode |
| BASIC's free ML area | 14 | 14 | `$1A0A-$1A0F` (6), `$1BF8-$1BFF` (8) |
| Loader page | **109** | 14 | `$1C93-$1CFF` (`ENDRESTORE` was here); `$1C00-$1C3A` (BASIC stub, `ENDINIT`) is dead after init |
| Resident cockpit holes | **165** | 0 | `$1D14-$1D58` (69, START's saves), `$1F79-$1FD8` (96, the old EXIT) |
| Helper pad | **8** | 3 | `$52C0-$52C4` (5, `ENDVDCBLANK`'s PTR save), `$52FD-$52FF` (3) |
| Old ARRSTEP block | 6 | 6 | `$5B1B-$5B20` |
| Glue | 1 | 1 | `$5DFF` |
| High (after MINES) | 2 | 2 | `$F6F7-$F6F8`, every mode |
| Packed margin (load time) | 168 | 168 | before `$7680` |
| S1 / ENDING package | 1,563 of S1 while ENDING is in; 130 of its 8 bank-1 pages | same | ENDING `$E970-$F0ED` (1,918); S1 `$E960-$E96F`, `$F0EE-$F6F8` |
| Load window (staging) | **1,569** | 1,485 | PRG now ends `$F8DE` (was `$F932`): `B1INIT` 111 bytes (was 195) |
| Bank 1 | **47,861** | 36,864 | `$0400-$2BFF` (10,240), `$5500-$63FF` (3,840), `$6700-$6FFF` (2,304), `$7D00-$7DFF` (256), `$8600-$FEFF` (30,976), `$FF05-$FFF9` (245) |
| VDC RAM | 16 K | 16 K | unused (display blanked) |

Dead but left in place: `SAVMMU`-`SAV1D` (`$28A3-$28B0`, 14 bytes; 12 of them are in the
reset snapshot, so they could hold reset-initialised variables).

Tests: the EXIT tests are gone (`run.js` "normal EXIT restores...", "EXIT restores the
stack page...", `game-end.js` "RUN/STOP restores every borrowed ending-workspace byte").
New: init writes no copy of BASIC's RAM, stack page, vectors or PCRs into bank 1 and
leaves BASIC 7's bank-1 areas alone; RUN/STOP held for 100 frames in flight and over
the map does nothing (the old EXIT and START holes are never executed, MMU stays `$3E`,
the map still opens); RUN/STOP held from a death and from a victory to the reset gives
the reset on the same frame as without it, then a fresh game. Every game boot now also
fills the new free areas (loader tail, both cockpit holes, the 5 helper bytes, zero page
`$02-$2A`/`$2D-$FA`/`$FF`, the stack page `$0155-$01BF`) with `$A5` and checks them
across all scenarios (a loaded save state re-arms the fill). The first run of that check
found the rating's `$2B/$2C`: the relocated `$F440` keeps the original's zero-page temp
(so before this change an ending also wrote BASIC's `$2B/$2C`). Validation: `python c128-game/build.py`, `python js/build.py`, `python js/bundle.py`, full `node js/test/run.js` ends with "all checks passed"; ending timings unchanged (death report/rating 613/615, victory 29/54/57, resets 711/10410/584/19039 DMA frames), 0 late splits / 0 OVRUN in every DMA scenario. No commit or push.

VICE x128: RUN/STOP in flight, over the map, in a base sequence, during the death flash
and on the victory screen should do nothing; the death and victory endings and their
restarts as before.
