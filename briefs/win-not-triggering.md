# Bug: winning never ends the game

User destroyed ALL enemy motherships (basestars) and fighters in the C128 port, TARGETS shows 00
(briefs/img-end/8.png), but the game does not end: no win ending. Death ending works.
Find the original C64's win trigger (trace in the JS C64 machine: what condition, counters,
routine, when it is checked, e.g. around the targets counter / GAMEOVERCHK $99F3 / $8869) and
check why the port (c128-game/end-events.asm, ending.asm, game.asm, js/test/game-end.js) does not
fire it in real play. Likely the existing win test forces the state instead of playing it out
(e.g. the check runs only at some moment, wrong counter, last kill by a different path such as
torpedo/hyperspace/mothership vs fighter). Reproduce with a test that kills the last enemy the
normal way, fix, keep all tests green. Rules: PLAN-C128-COCKPIT.md "Handing the work on".
Build: python c128-game/build.py, python js/build.py, python js/bundle.py. Test: node js/test/run.js
(must end "all checks passed"). Branch feature/game-end, no commit/push. 5-line handover.
