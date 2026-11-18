# Task: minimal itch.io page (js/), game selector, overlay, touch, hotkeys, hi-scores

New build target: a second, minimal HTML page (e.g. `js/dist/itch.html`, single file like `sentinel.html`,
built by js/build.py + js/bundle.py or a new js/itch.py; keep the existing debugger page unchanged).
It is meant to be uploaded to itch.io as an HTML5 game (https://itch.io/docs/creators/html5): itch embeds
it in an iframe and adds its own Full-screen button, so do NOT add a fullscreen button; the page must work
inside an iframe (no popups, audio start on first user gesture, sizing to the iframe, keyboard focus).

## Look
- Empty, minimalist: only the game canvas. No explanatory text, no links, no debugger.
- Before the game starts: a BASIC/PETSCII-style selector drawn in the C64 font (js/src/font.js) on a
  C64-looking blue/light-blue screen: two entries `C64` / `C128`, chosen with the mouse, touch, or keyboard
  (up/down/Enter, or the digits). The selected AND hovered entry is shown in inverse video.
  Next to each entry the stored hi-score: `C64 - HI 000000`, `C128 - HI 000000` (see below).
- Choosing starts the matching program ('c64game' = C64 original with the 1351 patch, 'game' = C128 port;
  see js/src/app.js boot(), js/programs.js, profiles) at normal speed with the fast-start unpacking as the
  debugger page does. Mouse capture works as in the debugger page (pointer lock); touch is a separate mode.

## Overlay (CRT/old-TV style big white text over the game, not part of the emulated screen)
Large white pixel/PETSCII-like text with a slight glow, shown for about 3 s then fading, at fixed positions:
- top: pointer-lock hint when the game captures the mouse: e.g. `ESC RELEASES MOUSE` (short, once per capture)
- top-left: `MUTE ON` / `MUTE OFF` (3 s) on key M (mute toggles the audio output)
- bottom: `>>` while 2x speed, `>>>>>` while 5x (shown as long as active)
- `RESET` (brief) on CTRL+R, which returns to the selector; `SAVED` / `LOADED` on quicksave/quickload
- at game over (win or loss, either program): show the achieved score and rank for 3 s, store it (see below)

## Keys (prevent browser defaults for these, incl. CTRL+S/L/R and ALT+W; the game must not also receive them)
M mute | ALT+W 5x speed toggle (as in the debugger page) | a 2x speed toggle on a free key (propose one that
does not clash with game keys, e.g. ALT+Q, and document it in README) | CTRL+S quicksave | CTRL+L quickload
(state in localStorage, per program, like the debugger page's save slots; guard with try/catch) | CTRL+R reset ->
back to the selector.

## Touch
If touch is detected (first touchstart / pointer type touch / maxTouchPoints), show touch controls: FIRE, MAP,
TORPEDO buttons (as the debugger page's on-screen keys/pad: profile `pad`/`keys`) plus touch aiming (drag = crosshair).
The buttons only need a clean, simple, semi-transparent first version; the user will refine the look later
(keep their CSS in one easy to edit block).

## Hi-score
At game over of either program: read the score and rank from the game's memory (C64: the same values the original
prints on the end screen: find the addresses with the JS tools / hooks (rating routine $F440, energy used,
kills ...; the C128 port has ENDRENER, ENDHITS, ENDKILLS, ENDRPROTON, ENDSHOTS) and show `SCORE nnnnnn` + rank
name. If the original has no single point score, derive one from the rating inputs and document the formula.
Store the best per program in localStorage (try/catch) and show it in the selector as `C64 - HI 000000`.
Detect game over with hooks (C64: GAMEOVER $8869, win check $F5B9; C128: the ending routines; see js/src/hooks.js,
profiles).

## Audio (important)
Issue #14 (https://github.com/Bencepapa/sentinel-1351/issues/14): SID audio sometimes fails to start (AudioWorklet
blob blocked). Fix it for this page: no blob worklet (use a data/module URL that works under itch's iframe CSP, or a
ScriptProcessor fallback), start/resume the AudioContext on the first user gesture (the selector click/key), retry on
visibility change, and make it work when embedded in an iframe. Test what you can headlessly; say what is unverified.

## Rules
- Do not break the debugger page or tests: `node js/test/run.js` must still end "all checks passed" (add tests for
  pure logic like the hi-score store/parsing; DOM parts by careful review or a small smoke test).
- Single self-contained file for upload (inline JS/CSS/programs), keep the size reasonable; add a short section to
  js/README.md (how to build, how to upload to itch, the key list).
- Do not touch c128-game/. No commit/push. Final handover: what was built, files, how to test in a browser,
  what is unverified.
