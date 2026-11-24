# Sentinel C128 V1.0: keys and differences from the C64 original

Draft compiled from the project notes (briefs/, FINDINGS.md, Codex-handover.md, js/src/itch.js), not re-verified against the code. Items marked (?) need a check before release.

## Keys

| Key | Action |
|---|---|
| Mouse move | aim (1351 mouse) |
| Left button | fire (phasor) |
| Right button | map |
| Both buttons | proton torpedo |
| Arrow keys / joystick | steer (joystick mode); CTRL = fire |
| Space | proton torpedo (?) |
| Tab | map (the C= key) |
| F1 | pause (any aim movement resumes) |
| F3 | skip the rest of the friendly-base repair report (only while docking) |
| F5 | difficulty menu from the title (5 levels, vertical joystick + fire) |
| F7 | title: start; in play: abandon the mission and return to the title |
| W | warp: not implemented in the port (open issue #25) |

Itch page (`js/dist/itch.html`) and the debugger page (`js/dist/sentinel.html`) add:

| Key | Action |
|---|---|
| Alt+Q | 2x speed on/off (itch) |
| Alt+W | 5x speed on/off |
| Ctrl+S / Ctrl+L | quicksave / quickload (itch, per program, browser storage) |
| Ctrl+R | reset to the selector (itch) |
| M | mute (itch) |
| Touch | FIRE / MAP / PROTON buttons, `||` pause, `>>` 2x |

The audio is silenced on pause, speed change, and leaving the page.

## Differences from the C64 original (deliberate or known)

- F3 completes the repair report in about 29 frames (original: 730-1140); the original has no skip.
- F5 / F7 handling around the title and restart is the port's own (the original has no difficulty menu in this form).
- Hyperspace freezes the world tick (the original does not): a group seen before the jump is there on arrival (#13).
- Out of energy: implemented from the original's behaviour, with measured deviations: the star slow-down is about 510 frames (about 400 in the original), the warp-in timing differs by some tens of frames, the message blink rate and tone follow the port's own routines. In the raster tunnel the tunnel decelerates and stops, mines vanish, three fighters warp in. Energy does not tick or flash inside the tunnel (no bytes left).
- The energy flag is cleared on every new game, game over, victory and F7 restart.
- The first 20 ticks' delay of the original is missing (open).
- Known open: hyperspace meteors move like the original, but with the blue cursor the vertical direction looks inverted for the mouse (see the issue "hyperspace vertical control feels inverted with the mouse").
- Known test: `game: in a fight the splits' colours change off the screen` fails in the full suite (2 late $D020 writes); not visible in play.

## Fixes of original bugs in the port

See FINDINGS.md (the original's bugs found and what the port does about each) and blog/2026-11-bugs-in-sentinel.md.
