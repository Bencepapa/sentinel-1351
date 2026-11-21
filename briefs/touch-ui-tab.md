# Task: touch controls redesign, fullscreen layout, Sentinel page buttons, Alt -> Tab for the C= (map) key (V1.0 polish)

Files: `js/itch-page.html` (CSS block "TOUCH CONTROLS"), `js/src/itch.js`, `js/src/input.js`, `js/page.html`, `js/src/app.js`
(the debugger page, built into `js/dist/sentinel.html` by `js/build.py` + `js/bundle.py`), `js/itch.py`, `js/test/itch.js`, `js/test/joystick.js`,
`js/README.md`. Build: `python js/build.py`, `python js/bundle.py`, `python js/itch.py`; test `node js/test/run.js` (ends "all checks passed";
several minutes). No commit/push.

## 1. Touch controls on the itch page and in the fullscreen view of both pages
Now on a touchscreen the big buttons shrink the playfield. Phones are not 4:3 so the buttons and the game fit side by side comfortably.
Make this layout (reference screenshot: `briefs/img-touch/reference.png` = a gamepad overlay with a thick coloured ring button with a thick label):
- All three buttons on the LEFT side of the screen, stacked vertically, smaller than now, drawn over/beside the game (the game may slide under
  the buttons when space is short; the game stays as large as possible, centred in the remaining area; do not shrink the playfield for the buttons).
- Bottom: **FIRE**, a round button with a thick coloured border (ring) and a thick bold label `FIRE`.
- Above FIRE: **MAP** and **PROTON** (label `MAP`, `PROTON`; the touch controls call them MAP and TORP today: rename the torpedo button to PROTON):
  rounded rectangles (not round), smaller, with a thick border, a smaller label; colours hint at their meaning: MAP yellow (border/label),
  PROTON white. Semi-transparent fill so the game shows through; large enough hit areas (min ~44 px tap size, with generous padding).
  Order from the top: MAP, PROTON, FIRE (FIRE nearest to the thumb at the bottom).
- Keep all CSS for the buttons in one clearly marked block, easy to restyle later. Multi-touch must still work (fire while steering by dragging
  anywhere else on the right side) and buttons must not swallow the drag-aim.
- Portrait and landscape: test the layout with the built-in browser or a headless check at e.g. 390x844 and 844x390 and a desktop size; report what you saw.

## 2. The `sentinel.html` page (debugger page) fullscreen / touch buttons
- The C128 version (program `game`) has no PROTON button (the on-screen keys of its profile lack the proton torpedo; the C128 port has torpedoes: both
  mouse buttons / Space): add the PROTON button for the C128 profile in `js/src/profiles.js` (`pad`/`keys`) so that the fullscreen touch pad has MAP and PROTON like the C64 profile.
- The C64 version's touch/fullscreen layout is not centred (the game is off-centre in fullscreen): centre it horizontally and vertically in the available area
  (in fullscreen and non-fullscreen), same layout as the itch page for the pad (left stack of three buttons).
- Check `js/src/app.js` `showPad`/fullscreen code and `js/page.html` CSS.

## 3. Alt -> Tab for C= (map)
`Alt+W` (5x speed) and `Alt+Q` (2x speed) clash with Alt being the C= key (opens the map): today the page delays Alt by 120 ms to tell a tap from a
chord. Map the C= key to **Tab** instead (on both pages; `preventDefault` so the browser focus does not move; keep Alt only for the hotkeys and stop sending
C= for Alt: Alt alone does nothing in the game), remove the 120 ms Alt delay logic if it becomes dead code, update the on-screen help texts, `js/README.md`,
the page help (e.g. profile `help` strings that say `C= (Alt)`), and the tests (`js/test/itch.js`, `js/test/joystick.js`, `js/test/input.js` if any).
The C128 version uses the same C= key mapping (`AltLeft` -> `Tab`); the keyboard on-screen buttons keep working.

## 4. Done when
`node js/test/run.js` ends "all checks passed"; the pages rebuilt; a short handover: what changed per item, how you checked the layouts (sizes), what is
unverified (real touch hardware). Do not touch `c128-game/` (a V1.0 PRG build with the user's `title-text.txt` is already built; do not change it).
