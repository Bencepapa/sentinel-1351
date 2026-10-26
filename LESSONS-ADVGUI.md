# Lessons learned: MOUSEGUI driver and the ADVGUI adventure engine

This file collects what went wrong or turned out to be non-obvious while building:
- the 1351 mouse/joystick GUI driver (`C:\dev\c64\mousegui`);
- the data-driven point-and-click engine in C (`C:\dev\c64\advgui`);
- its browser editor.

Each lesson is written so that it can be reused in the next C64 project.

## 1. C64 hardware and the driver

**Read the 1351 without busy-waiting.**
The SID needs the port selection in `$DC00` bits 7/6 to stay stable for 512
cycles. The KERNAL keyboard scan rewrites `$DC00` in every IRQ. Commodore's
driver solves this by busy-waiting 4 ms, which is too slow. A better way is to
push a fake interrupt frame (return address, status byte, three dummy bytes)
and `JMP (old vector)`. The KERNAL handler's `PLA/TAY/PLA/TAX/PLA/RTI` then
returns into your own code *after* the keyboard scan. Re-select the mouse port
there, and the pots are stable for a whole frame when the next IRQ reads them
first. This chains correctly with any other IRQ wedge.

**Leave `$DC00` as the KERNAL expects before chaining.**
UDTIM reads the STOP key from `$DC01` assuming `$DC00 = $7F`. With `$BF`
(port 2 selected), the `/` key acts as RUN/STOP. Set `$7F` before the KERNAL
part runs, and switch to `$BF` only afterwards.

**Read joysticks with all keyboard columns off.**
Write `$DC00=$FF` briefly, then read `$DC01` (port 1) and `$DC00` (port 2).
Keys then can't fake joystick bits.

**Port 1 mouse buttons and joystick fire still type ghost keys.**
They appear in the keyboard matrix. The driver offers to empty the keyboard
buffer (`$C6=0`) while port-1 lines are active.

**Auto-detect works.**
An empty port, or a joystick, reads `$FF` on both pots. Probe the ports in
turn, lock onto the first one that gives real values, and drop the lock after
about 50 frames of `$FF`.

**BASIC is slower than the user.**
A click can start and end between two BASIC loop passes. The short events
(click, drag start, drag end, right click) go into a small queue. Each one
stays visible until BASIC acknowledges it (`POKE 49168,0`) or a timeout runs
out. Live state (hover, held, dragging) goes into separate registers that are
never latched. Both are needed: the queue so nothing is missed, the live
registers for visual feedback.

**Don't trust where the screen is.**
Compute the sprite pointer address every frame from `$D018` and `$DD00`. A
program that moves the screen then still gets a pointer.

**Install first, configure after.**
`mg_install()` copies the whole driver image, including its empty area tables,
to `$C000`. Areas defined before the install were wiped silently. Any "copy
the blob, then call init" design has this trap.

## 2. Oscar64 (C on the 6502)

**It's a good fit.**
Single download, native code, `#embed` for binary data (driver and game data
go into one PRG), and `__asm { jsr $c000 }` to call machine code. The default
layout (program from `$0801`, stack up to `$A000`) leaves `$C000` and the tape
buffer free.

**The optimizer at `-O2` miscompiled real code.** Two cases:
1. An inlined 16-bit table read (`gd[o] | gd[o+1] << 8` with a computed `o`)
   took the high byte from `base + 1` instead of `offset + 1`. Item names and
   rule pointers came out wrong. Fix: one `__noinline` `rd16()` function for
   all such reads.
2. `s != 255 ? inv[s] : inst[k].item` lost its test completely. The compiler
   seems to assume an array index is in range, so "`s` is never 255". Fix:
   when a value is both "none = 255" and an array index, test against the
   array size (`s < NSLOTS`). Move the access into a small non-inlined helper.

**When behaviour is impossible, read `build/*.asm`.**
Oscar64 writes an annotated listing with source line numbers. A VICE
breakpoint plus the listing found both bugs within minutes, after an hour of
suspecting the game data.

**The software stack frames are static.**
`build/*.map` shows them (`sstack`). They are worth a look if memory looks
corrupted.

## 3. Engine design: game as data

**Separate content from the engine from day one.**
v1 had the puzzle hard-coded in C, and the editor request forced a rewrite.
v2 split it: JSON (editor) → `pack.py` → compact binary (`#embed`) → a small
interpreter. New rooms and puzzles have needed no C changes since.

**Keep rules simple.**
Each rule is trigger + item A + item B + conditions + actions, and the first
match wins. Engine defaults cover the rest: describe, go through doors,
"THAT DOES NOT WORK". That was enough for crafting, keys, fights, a winch
gate, an endless forest and eating apples.

**"A" and "B" must not mean "inventory" and "room".**
Combining only in the inventory was an arbitrary restriction. The context now
holds A and B as either an inventory slot or a floor object. The same actions
(remove, replace) work for both. Try combine rules in both orders, so each
recipe only needs to be written once.

**Many small surprises came from how actions combine:**
- An enemy defeated by an earlier action in the same rule must not bite back.
  The `hurt` action checks whether the target is still an enemy.
- The `hurt` message belongs to the hurt itself, not to a separate `msg`.
  Otherwise "IT BITES YOU BACK!" appears even when it didn't.
- When an action moves you to another room *and* says something, show that
  message instead of the room description, or "you walk for hours" gets
  wiped.
- Door settings (target, lock flag) belong to the object, not the item, so an
  item swap (closed gate → open gate) keeps them.

**Light is a world property, not an inventory property.**
"Lit" first meant "carrying a torch". A torch put down on the floor should
light the room too. Write conditions in terms of the world state.

**Weapons need a number.**
Without an attack power, ATTACK did the same damage with or without a stick,
and the player noticed at once.

**Text needs paging.**
Two lines of 38 characters are short. Word-wrapped pages with a blinking
`>`/`)` marker, and a click to continue, fixed the cut-off descriptions. The
editor shows how many pages each text needs.

## 4. Drawing on a text screen

**Redraw into a shadow buffer.**
Drawing the background and then the objects straight to screen RAM made every
object flash on each refresh, even on a click that changed nothing. Now
everything is drawn into a 1000+1000-byte shadow of screen and colour RAM.
Only the rows that were touched (dirty-row tracking) are copied once per loop.
Each cell goes straight from its old to its new value.

**Prove timing bugs with watchpoints.**
A screenshot can't show a one-frame flash. A VICE `watch store` on one screen
cell showed two writes (space, then object) before the fix and one after.

## 5. Testing in VICE without a human

**The remote monitor (`-remotemonitor`) is the test harness.**
- Connecting pauses emulation: always send `x` before disconnecting.
- Wait for breakpoints and watchpoints *inside* the same connection. A hit
  with no client connected opens VICE's own monitor window and blocks the port.
- `screenshot "file" 2` writes a PNG. Make several at once into one image
  (PIL) to review a whole scenario.

**Simulated input that exercises the real code path:**
- Move the pointer with the driver's own warp registers, or by poking its
  stored previous pot value; the next IRQ sees the difference as movement.
- Fake buttons and joystick by patching the operands of the driver's two port
  reads (`LDA $DC01` / `LDA $DC00`) to point at RAM, then poking that RAM.
- `keybuf text\n` (no quotes) types into the C64 keyboard buffer.

**Scripted scenarios break when the game changes.**
A test that walks to the cellar door failed once the user added "you can't
find the latch in the dark". Re-check a failed test against the current rules
before assuming the engine is broken.

**Read engine variables while it runs.**
Use the Oscar64 `.lbl` file to find them, and the monitor to read them
(`m addr addr`).

**The real 1351 path was never tested with a grabbed host mouse.**
Only through these simulations. Real-hardware checks are still worth doing.

## 6. The editor (Python server + plain JavaScript)

**A tiny local server is enough.**
It serves the page and VICE's character ROM, saves the JSON (backing up the
previous version), and runs pack, build and VICE. There's no build step for
the front end.

**Use the real character ROM and an accurate palette.**
Render the PETSCII from VICE's `chargen` into one sheet per colour. The
"greenish yellow" was the Pepto palette; Colodore looks like a real C64. The
same sheet can later be replaced by a custom charset.

**Browser dialogs aren't reliable in embedded browsers.**
`confirm()` and `prompt()` were silently cancelled in the app's browser pane,
so "Remove lit background" did nothing. Use in-page two-click confirmation
and inline inputs instead.

**Canvas mouse maths must use the drawn size.**
A flex column stretched the 256-pixel character palette, so clicks landed on
the wrong characters. Scale by `canvas.width / clientWidth` and stop the
stretching with CSS (`align-items: flex-start`, `flex: none`).

**Don't rebuild the DOM on every animation tick.**
The preview rebuilt the frame strip, including its Stop button, 7 times a
second. A click is mouse-down plus mouse-up on the same element, so Stop never
got clicked. Playback now redraws only the canvas.

**Undo is cheap.**
A stack of JSON snapshots of the whole game, taken before each change, was
enough.

## 7. Working on someone else's data, and tooling hygiene

**Never regenerate a file the user has edited.**
Once the user had drawn their own graphics into `demo.json`, the demo
generator was off limits. New content went in through an "extend" script that
adds only ids that are missing and makes a backup first.

**Tell the user when the file on disk changed under their open editor.**
Otherwise their next Save overwrites it.

**Windows Python defaults to cp1252.**
Patching a UTF-8 file with `open(p).read()` / `write()` corrupted `×`, `–`
and `…` in `editor.js`. Always pass `encoding='utf8'`.

**Long patches don't belong in inline shell heredocs.**
Quotes and backticks broke several of them. Write the patch script to a file
and run it.

**Keep a version folder per delivered step** (`versions/v1` … `v5`): PRG,
D64, sources, editor and game data. It made "what changed" and "go back"
trivial.

**Simple tools beat waiting for big ones.**
With no assembler installed, a 200-line two-pass 6502 assembler in Python
(full expressions, zero-page sizing in pass 1) was enough for a 2.5 KB driver.
