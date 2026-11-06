# Fix: the hang on arrival in the base's positioning phase (VICE x128)

Follow-up to `briefs/mothership-scanner-positioning.md` (same rules; read it and
`PLAN-C128-COCKPIT.md` "Handing the work on" again; no commit/push).

The user's VICE x128 test: the base shows correctly on the long range scanner while
flying, but **on arrival the program freezes** - only the engine's droning noise is
heard. Screenshot `briefs/img-scanner/1.png` (frozen state): the HUD's top and bottom
text strips show garbage (font/screen data of the wrong content, like a charset or
text-screen mix-up), the 3D view is black, the crosshair, radar box and guns remain.

## What to do

1. Reproduce it in the JS machine with `m.dma = true` (and a state at arrival in both an
   enemy and a friendly base sector, with joystick and mouse input, and with the
   scanner aligned by steering): the existing tests passed, so find what they miss
   (a real hang = a loop/stack/IRQ problem, or an unfinished state machine step; the
   garbage text strips suggest the screen/charset pointers or the `$4000` font area
   were overwritten - check whether the new code, its data or its unpack target
   overlaps live data, and whether any slot is left switched).
2. Fix the cause; add a test that fails before the fix (frames keep running, split
   timing OK, the rings start, strips intact after arrival, for both kinds).
3. Rebuild (`python c128-game/build.py`, `python js/build.py`, `python js/bundle.py`),
   run `node js/test/run.js` (must end "all checks passed"), update docs if needed.
4. Final message: root cause, the fix, what is verified, memory left.

Note: a previous agent (Codex) hit its usage limit mid-way, so the working tree may hold
half-finished edits for this fix (see `git diff` against the uncommitted positioning work
only if useful). Check `build.py` asserts still pass; finish or revert partial edits.

Findings of a previous (summary-only) agent: freeze not reproduced yet; existing JS tests
probably skip the real arrival path (`HARRIVE` -> `SECTORIN` -> `MSECTOR` -> `MSPOS`);
`loadPrg` writes straight to RAM, so JS does not model VICE's KERNAL LOAD (the second packed
stream staged at `$D000` and the `$FF05` tail are suspects: check what the real load and the
MMU config at init do to them; VICE x128 is at C:/dev/c64/GTK3VICE-3.9-win64/bin/x128.exe if
you can run it with a monitor/limitcycles). Mind that `HVBR` is patched by `MSPOSON` to read
`MSSTATE`: check every path that leaves `MSSTATE` nonzero (PLA PLA RTS aborts VBWORK).
