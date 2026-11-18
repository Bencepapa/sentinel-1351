# Task: C64 version (1351 patch) cannot be played with a joystick; mouse/joystick detection

User report (C64 version "c64game" = the original with our 1351 mouse patch; JS pages js/dist/sentinel.html and
js/dist/itch.html; joystick = arrow keys + Right Ctrl / Numpad0 on port 2, `m.joy2`):
- With the joystick the game is not playable: the arrow keys open the map and throw a torpedo (so the direction
  lines are read as the 1351's mouse buttons; on the patched game port 2 the 1351's buttons share the joystick lines).
- User remembers that the ORIGINAL game detects whether a joystick or a mouse is used and configures itself.
  Observation: when the game is started from the menu with Fire (Enter / Ctrl) and then started with the joystick
  from the TITLE screen, the joystick works fine (flight steering works; the crosshair cannot be moved with the
  joystick, but turning the ship works), but as soon as the mouse is moved the game switches to mouse mode and the
  joystick then works only partially. So somewhere in the code there is a mouse-detect routine that sets a flag.

Do:
1. Investigate (JS C64 machine, c64-symbols, hooks, the patch source/sources under mouse/ and js/programs.js, the
   1351 patch code: presence check at $0B43 substituted by the patch; keyscan idle PA value $7F -> $BF; right button
   = map, both = torpedo): how the original decides joystick vs mouse (the flag, the detect routine, what is read from
   port 2 / SID pots $D419/$D41A, what the joystick does in each mode, why directions become buttons in mouse mode).
   Document it in this file below "## Findings".
2. Make the input mode flexible: joystick input should work (steer, fire, map via a sensible key or button, torpedo)
   and moving the mouse should switch to mouse mode, and using the joystick (a direction or fire after mouse use)
   should switch back; no stuck state. Prefer a fix in the JS page layer (how `m.joy2`/mouse state are presented to
   the patched game: e.g. only present joystick lines when in joystick mode and mouse buttons when in mouse mode),
   and only change the patched game code if necessary; the original must stay recognisable.
3. Show the detected input mode on the itch page overlay (e.g. `JOYSTICK` / `MOUSE`, 3 s when it changes) and keep
   Fire selectable with Ctrl (Right Ctrl and Numpad0 already; also allow Left Ctrl? only if it does not clash with
   Ctrl+S/L/R hotkeys) and Enter in the selector.
4. Tests (pure logic or via the JS machine: joystick directions in joystick mode must not open the map or fire
   torpedoes; mouse buttons still do; switching back and forth) in js/test/; all existing tests stay green
   (node js/test/run.js ends "all checks passed"). Rebuild: python js/build.py, python js/bundle.py, python js/itch.py.
5. The C128 port has its own INPUT routine (joystick steers, cursor limits): note what the same situation is there,
   but do not change c128-game/ in this task.
Branch feature/game-end. No commit/push. End with a short handover: cause, fix, what is verified, uncertainties.

## Findings

### C64 disk and 1351 patch

- The unpatched `Sentinel.d64` has a digital joystick path. The raster IRQ's `$0B43` is `LDA $A0 / AND #$03`. Its `$0BB0` calls `$B2D8`, which reads CIA1 port A (`$DC00`, control port 2) into `$96` and decodes active-low bit 4 into `$97` and the cockpit fire request `$D0`. The difficulty menu also reads `$DC00` at `$864A`. The original disk's game payload has no SID POTX/POTY reads. Device detection belongs to the 1351 patch.
- `js/build.py` embeds `Sentinel-1351_v10.prg` as `c64game` in `js/programs.js`. In the patch, `$0B43` calls `POTRD` at `$02DB`, which replays the overwritten instructions so the IRQ branch still sees the same zero flag. The scan exits at `$FE30/$FE68/$FEA0` now leave CIA1 PA at `$BF` instead of `$7F`. Bits 7–6 select control port 2 for SID sampling between frames. `POTRD` reads `$D419/$D41A`, inverts Y, and runs `MOVCHK` to get signed, wrapping deltas. It compares the retained X sample in Y with `$FF` and rotates that result into bit 7 of `MFLAG` (`$4B`). A set bit means joystick or empty port.
- The patched `$0BB0` calls `JOYIN` (`$02A2`). With the mouse absent, `JOYIN` passes the raw active-low direction lines and Fire through to `$96/$97`. Those directions steer the ship and drive the original-style crosshair steps when the cursor update runs at `$0D19`. X moves three pixels a step and Y two, within the current limits and with inverted pitch. The update is gated by the attract and view flags and respects the game's horizontal lock at `$8420`. On the map the original sector cursor uses joystick directions. The difficulty menu uses `$96` after the patch. The original startup also has a prompt at `$998E` where Fire or Space advances to the sector map.
- With the mouse present, `MBTN` reads the left button on Fire (bit 4) and the right button on Up (bit 0). Right alone writes the map flag `$FDEC` after five samples. Both write the Space/torpedo flag `$FDE5`, suppress the phasor request, and latch out the map until the right button is released. `MBTN` masks the right button out of the direction byte. The mouse moves the cockpit crosshair by its POT deltas, with a ±12 px dead zone for steering. Other screens synthesize directions from mouse motion, and the map uses the mouse pointer. With both virtual devices wired at once, ArrowUp looks like Right Mouse and ArrowUp + Fire looks like the torpedo chord. The other joystick direction bits can still pass through, even while the crosshair follows the mouse path.

### Browser pages

- `machine.js` models the hardware wiring by combining `m.joy2` with the mouse buttons on the same lines. It starts with `mouse.present = true` and returns `$FF` for an absent or unselected pot. That setup can make the patched detector see a mouse even before any browser pointer movement. `hooks.fixC64Original()` works around an unrelated VIC raster IRQ issue during startup and arrival.
- Both browser pages now start keyboard play in joystick mode. Nonzero pointer movement or a mouse/touch button selects mouse mode. A new direction or Fire press selects joystick mode. The shared browser input handler switches the virtual device before `POTRD` executes and presents only that device's lines. It seeds `OPOTX/OPOTY` for the new connection and clears the previous mouse-button latch. `MOVCHK` retains the old sample on ±1 jitter, so an unseeded switch between POTX `$00` or `$7E` and the absent `$FF` can otherwise keep the previous mode. The game runs its existing detection and cursor code.
- Arrow keys steer, Right Ctrl or Numpad 0 fires, Left Alt sends C= for the map, and Space sends the torpedo key. In the itch selector, Enter and both Fire bindings start the selected version. Left Ctrl retains its keyboard and hotkey role. The itch overlay shows the C64 input mode for three seconds before fading.

### C128 port

- The joined port uses the cockpit's own `INPUT` in `c128-gui/cockpit/cockpit.asm`. Its `POTS` checks the raw POTX against `$FF` and sets `MPRES` before filtering the deltas. With no mouse it takes directions and Fire from `JRAW`. With a mouse it masks Up and combines the other raw lines with the steering mask; its crosshair follows mouse deltas. The joystick cursor uses the port's clamped ±3/±2 steps.
- The joined port's `MAPKEY` in `c128-game/game.asm` checks C= and, when cockpit `MPRES` or map `M_MPRES` is set, reads port 2 bits 0 and 4 as mouse buttons. If both virtual devices are presented there, Up and Up + Fire can alias the map and torpedo again (subject to that mode's weapon/map rules). The C64-specific browser switch does not apply to the C128 port.
