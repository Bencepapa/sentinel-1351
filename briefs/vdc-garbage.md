# Task: VDC (80-column) screen shows garbage

Branch feature/game-end (uncommitted work). The 80-column VDC screen used to stay blank
in the C128 game. Now: at start-up it shows ~1 s of C128 BASIC boot text + random coloured
blocks + cyan garbage (briefs/img-end/7.png), then a flickering pattern (6.png).
It appeared within the last few commits (compare `git log`, `git diff main -- c128-game/`
for VDC code: $D600/$D601 writes, VDC init/blank code, build.py, glue, ending code,
end-loader.asm, ending.asm). Find which change causes it (e.g. VDC writes with wrong
registers, or code/data landing in VDC RAM, or the ending code touching the VDC) and
fix so the VDC is cleanly blank from the start, as in main.
Rules: see PLAN-C128-COCKPIT.md "Handing the work on" (no code moved in glue/cockpit/map).
Build: python c128-game/build.py, python js/build.py, python js/bundle.py.
Test: node js/test/run.js (minutes; must end "all checks passed"). No commit/push.
Finish with a 5-line handover (cause, fix, tests).
