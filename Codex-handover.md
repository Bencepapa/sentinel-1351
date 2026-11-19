# Codex handover (Sentinel C64 -> C128 port)

Repo: `C:\dev\c64\sentinel` (GitHub `Bencepapa/sentinel-1351`), branch `feature/game-end` (pushed, last commit `213df2e`).
The user is a Hungarian speaker; reports and issue titles in English, chat in Hungarian is fine.

## Read first
- `PLAN-C128-COCKPIT.md`: sections "Status" and "Handing the work on" (rules: no code moved in glue/cockpit/map,
  new code in the `$E000` chunk through the slots or other free space, all bound checks in `build.py`, tests count
  late splits and OVRUN = 0, `m.dma = true` for timing).
- `c128-game/README.md` (memory map and free-byte tables), `briefs/memory-overlay-plan.md` (bank 1 store, overlay
  manager, ENDING package; BASIC return was removed, RUN/STOP does nothing).

## How to build and test
- `python c128-game/build.py`, `python js/build.py`, `python js/bundle.py`, `python js/itch.py`
- `node js/test/run.js` (several minutes; must end "all checks passed")
- VICE x128 (`C:\dev\c64\GTK3VICE-3.9-win64\bin\x128.exe +go64 -40col -controlport2device 3 -autostart c128-game\sentinel-c128-game.prg`),
  use a scratch config, the user's vice.ini must stay untouched.
- Do NOT commit or push; finish with a short handover (what changed, verified, memory left, uncertainties).
  Never commit `chatgpt_handover.md`, `scanner-test.log`, `vdc-root-check.log`, `.zen/`, `box_cover/`.

## Free memory (after the clock; verify with build.py output)
resident `$05CD-$0C5F` 1683 bytes; loader `$1C93-$1CFF` 109; cockpit holes `$1D14-$1D58` (69), `$1F79-$1FD8` (96);
helper pad 8; high 2; glue 1; packed 168; bank 1 about 47 KB; zero page `$02-$2A`,`$2D-$FA` (not `$2B/$2C` while
the rating runs); stack page `$0155-$01BF`.

## Task 1: issue #22 - hyperspace: the rattling sound is missing
During hyperspace flight the C64 original plays a rattling/clattering sound while flying. In the C128 port the
stronger engine sound, collisions, siren and explosions are there, but the rattling sound disappeared. Find out
whether it is a regression (compare with `main`/older commits: `git log`, earlier PRG builds) or was never
ported: trace the SID writes during hyperspace in the JS C64 machine (m.sidLog / SID register trace, `.zen/lib.js`
helpers, hooks) and in the port; port the missing voice/register writes with the same timing; add a test that
compares the SID write stream (hyperspace flight) with the original; respect the frame budget (spare cycles per
frame in hyperspace are small: min 3352, median about 10008; see `briefs/memory-overlay-plan.md` section 8).

## Task 2: F1 / F3 / F5 / F7 on the C128 (issue #23, findings in `briefs/fkeys.md`)
C64 behaviour (details, handlers and a C128 proposal with byte estimates are in `briefs/fkeys.md`):
- F1 (and Shift+F1 = F2): pause (latches `$9F`, mutes the SID, steady clock colon; joystick direction or fire
  resumes; no PAUSED text).
- F3: skips the rest of the friendly-base repair report (only while docking).
- F5: opens the difficulty menu from the title (5 levels, vertical joystick + fire).
- F7: from the title starts like F5; in play abandons the mission and returns to the title (re-initialises:
  difficulty to 0, world, shields, protons); after the death/victory report restarts. RESTORE = immediate restart.
The C128 port has no title screen yet (the game starts straight in the cockpit; the end screens reset the game),
so: implement F1 pause first (SID mute + the C128 clock must not tick while paused; the clock has a tick entry
point, see `briefs/c128-time.md` and the handover of the clock task in this repo), F3 repair-report skip if the
port has the report, F7 as "restart the game" (reuse the game-over reset path `ENDRESET`), F5 only if a difficulty
selection exists in the port (check; otherwise leave it for the title-screen work). Map the C64 F-keys to the C128
keyboard matrix positions (the C128 has its own F-key positions; keep the C64 key mapping for the C64 page).
Tests: pause freezes world tick, clock and SID; resume by fire/direction; F7 restarts like the reset path; all
existing timing tests stay green.

## Task 3: joystick vs mouse aliasing in the C128 port
On the patched C64 game the 1351's buttons share port 2's Up and Fire lines (Fire = left button, Up = right button,
both = torpedo). The browser pages now present only one device at a time (js/src/input.js, tests in
`js/test/joystick.js`) and the C64 game works with a joystick. The C128 port has the same hardware aliasing in its
own code: cockpit `INPUT` / `POTS` (in `c128-gui/cockpit/cockpit.asm`, joined into `c128-game/game.asm`) sets `MPRES`
from the raw POTX and reads the buttons; `MAPKEY` in `c128-game/game.asm` reads port 2 bits 0 and 4 as mouse buttons
when `MPRES` or `M_MPRES` is set. If both virtual devices are presented, Up (and Up + Fire) can open the map and
launch the torpedo; and the user observed in the C64 original that moving the mouse switches the game to mouse
mode so that the joystick then works only partially. Check that the C128 port switches mouse <-> joystick in both
directions without sticky state (a fresh joystick press after mouse use must switch back; directions must not become
buttons in joystick mode; the crosshair/cursor must work with the joystick on the map: the user could steer the ship
with a joystick but not move the cursor), make the detection flexible, and show nothing new in the game (the itch
overlay reads the mode from the page layer, see `js/src/input.js`). Add tests (joystick directions never open the
map or fire torpedoes in joystick mode; mouse still does; switching back and forth). Mind the memory rules above.

## Other open items (not part of these three tasks)
- Title screen (scrolling text, music, difficulty selector, Starfleet intro with the raster-opening bar), the
  "SECTOR CLEARED CAPTAIN" message + automatic map, damaged-system warning sound + message; the cover image
  (multicolor bitmap, optional bands with their own background colour, credit "Cover art by Tim Boxell,
  1983"); the VDC map/system display; a disk (D64) build. All planned in `briefs/memory-overlay-plan.md`.
- Open GitHub issues: #11, #12, #13, #14, #17 (older), #22, #23.
