# V1.0 test notes (user, 2026-11-21, to retest next day)

## 1. Red fighters on arrival that vanish (seen 2x, not reproducible since)
- Jumped to a sector while fighters were warping in on the player; they stayed with the player until the hyperspace tunnel's stars.
- Long range scanner showed no enemy at the jump, but on arrival 3 red fighters circled on screen, then disappeared; the scanner showed nothing.
- User theory: these are the earlier warp-in fighters that kept running their routine for 1-3 s (during deceleration or right after), taking the red colour of the micrometeors.
- To check: the hyperspace freeze (#13) should stop the world tick in all phases. Look for fighter/enemy objects or their sprite/colour state that survive the jump (warp-in sequence in progress at jump start), and whether the meteor colour (red) and the fighter share a colour/object slot.

## 2. Stars stay on screen
- Stars stay on the screen between the map closing and the hyperspace start, then are cleared from the game view, but their trace stays forever on the radar (scanner). Related to #11 (stars lag/stay on the map).

## 3. Proton torpedo explosion looks slow
- Not compared with the original yet.

## 4. Cursor locked during the briefing (C128), free in the original (user, 2026-11-21)
- C128: the pointer/cursor cannot be moved while the Starfleet briefing is shown. C64 original: it can be moved, and it can go behind the message window (sprite priority: the part under the window is hidden, not visible through it).
- To do: measure the original (sprite position register writes and priority `$D01B` during the briefing) and match: cursor movable during the briefing, hidden where it passes behind the window. Touches title/briefing code: do after the "flash after briefing" fix (same area).

## 5. Flash between briefing end and map (C128)
- Original has none. Agent working on it (see conversation).
