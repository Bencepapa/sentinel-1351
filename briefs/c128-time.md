# Task: a game clock for the C128 port (TIME on the HUD)

The C128 game's HUD shows a fixed TIME 01:37 (never changes). The C64 original counts game seconds MM:SS up
(HUD digits `$70+d` at `$544A/B`, colon `$544C`, `$544D/E` in the C64; ticked at `$FAD7`, one game second per 60
main-loop ticks, reached via `$FAE9`; wraps at 60:00; it is cleared at a death scene). Port the clock:

- A counter (MM:SS) in the port, ticked exactly as the original does (trace it in the JS C64 machine; same
  cadence), shown on the HUD in the same place/format as the original, reset to 00:00 when a game starts or
  restarts (game over reset; a restart key like F7 may come later), frozen while the end screens run, not advanced
  while paused (a pause feature may come later: keep a clean tick entry point).
- The itch page (js/src/itch.js, js/src/hiscore.js) uses the time for the score: on a victory the bonus is
  6000 minus elapsed seconds (min 0). For the C128 it currently has no time term: read the new counter in the
  same way as the C64 counters are read (at the ending hook) and enable the term; update js/test/itch.js and
  js/README.md.
- Memory is tight: see PLAN-C128-COCKPIT.md "Handing the work on" and the c128-game/README.md memory tables
  (free: zero page $02-$2A,$2D-$FA; stack page $0155-$01BF; $0200-$0C5F 1801 bytes at $0557; loader 109 bytes
  $1C93-$1CFF; cockpit holes $1D14-$1D58 (69) and $1F79-$1FD8 (96); helper pad 8; bank 1 plenty). Rules:
  no code moved in glue/cockpit/map; bound checks in build.py; the HUD digit drawing may need a hook into the
  frame loop within the raster limits (late splits and OVRUN must stay 0, m.dma = true in timing tests).
  Estimated cost about 60 bytes code + 5 data.
- Tests: the clock ticks at the original's rate (compare frames per game second with the C64 machine), resets on
  restart, does not tick during the ending screens; all existing tests stay green (node js/test/run.js ends
  "all checks passed"). Build: python c128-game/build.py, python js/build.py, python js/bundle.py, python js/itch.py.
- Branch feature/game-end. Update README + PLAN status. No commit/push. End with a short handover (what changed,
  bytes used and left, what to check in VICE).
