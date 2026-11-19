# Task: message queue / priority between game messages (C64 original vs the C128 port)

User report on the C128 port (branch feature/game-end): the messages now wait for each other. When a sector is
cleared while an earlier message is still showing, "SECTOR CLEARED CAPTAIN" waits in a queue, so the map
(which is opened by that message) may not appear in time, while new enemies already warp in and are beaten.
The queued messages then show at the wrong moment: e.g. a new enemy jumps in after the previous was beaten:
"Sector cleared captain" (late), then "Autotracking computer" near the end of the battle, meanwhile the enemies
are beaten: "LONG RANGE SCANNER" (system damage) message, then "Sector cleared captain", sometimes even later.
The user suspects the original had a PRIORITY: some messages interrupt/clear the waiting queue.

Do:
1. Investigate the ORIGINAL C64 message system (JS C64 machine, js/c64-symbols.txt, MAP-LOGIC.md, hooks; the print
   routine $27CD and the messages table/strings, `$3C84` "SECTOR CLEARED CAPTAIN" printed from `$3CDE`, system
   destroyed/damaged messages `$84F2`, "AUTOTRACKING COMPUTER" etc.; LASTMSG; .zen/messages.txt has an earlier
   dump): how a message is requested (a single slot? a queue? a priority/flag byte?), what happens when a new
   message is requested while another is being displayed or waits (overwrite, drop, queue, interrupt), the
   display duration/timing, which messages are tied to game state (sector cleared -> opens the map;
   mothership messages; damage; autotracking on/off) and whether they re-fire. Trace concrete scenarios with
   the JS machine (m.dma = true): clear a sector while a message is up; two messages within a few frames;
   damage message during a fight; save states in briefs/ref/*.state.json may help.
   Write the result below "## Findings" in this file: the data structure, the exact rules, the priorities, with
   addresses and a table message -> trigger -> priority/behaviour.
2. Compare with the C128 port's message code (c128-game/game.asm: the message printing, any queue, the SECTOR
   CLEARED / damage / autotracking requests; the cockpit and map message routines `MSG`-labelled symbols; run
   `git log --oneline -15` and look at recent changes that added a queue), reproduce the wrong ordering in a
   test (js/test/: scripted scenario with the JS machine, m.dma = true) and fix the port so it behaves like the
   original (same priority/overwrite/drop rules), without moving glue/cockpit/map code (see PLAN-C128-COCKPIT.md
   "Handing the work on"), within the free memory (see c128-game/README.md tables; Codex-handover.md lists them).
3. All existing tests stay green (node js/test/run.js ends "all checks passed", late splits/OVRUN 0). Build:
   python c128-game/build.py, python js/build.py, python js/bundle.py, python js/itch.py.
4. Branch feature/game-end. No commit/push. Final handover: the original's rules, the cause in the port, the
   fix, bytes used, what to check in VICE, uncertainties.

## Findings

### Original C64

The cockpit has **one mutable display slot**. Callers pass the text address and the two colours on the stack, with display mode in A, flip period in X and flip count in Y. Both entries, `$9BE5` and `$9C5C`, install the message immediately. They clear and re-arm the active byte at `$9BE3`, replace the character source (the operand at `$9D34/$9D35`), reload `$9BDC/$9BDD` and `$9BDE`, and rewrite the 40-character row at `$5798` and its colours at `$DB98`. The text is terminated by `$FF`. The entries use different scratch locations for the stacked return address and share the display state. `$27CD` is a separate immediate bitmap text printer (for example, the difficulty labels at `$871E`). It calls the glyph renderer at `$0816`.

Every print call replaces the current text, source pointer, period and remaining flips. There is no pending state, queue, priority comparison or retry after replacement. In a burst the order is the actual order of calls. `$9BE3` lets consumers such as the scanner at `$382D`, `$C6DE` and `$8CEB` decide when to use the row. `LASTMSG` is a bookkeeping byte in the C128 standalone map. On the C64, `SURROUND` calls the cockpit printer directly at each ring transition.

The IRQ calls `$13D5` from `$0BDB`. A standing message is copied at once and ticks at `$9CD3` once per frame. A scrolling message shifts one character every four gameplay frames, using two pixels of fine scroll per frame. `$9BDD` counts steps to the next colour flip and beep, `$9BE4` retains the flip phase, and `$9BDE` counts flips remaining. On expiry the text becomes light green. Standing text is erased, while scrolled text keeps the row until another routine repaints it. The table gives nominal durations without an intervening write.

| Notice and text address | Trigger and print call | Overwrite, duration and repeat behaviour |
|---|---|---|
| SECTOR CLEARED CAPTAIN `$3C84` | Last kill reduces `COUNT,X` to zero at `$3CD9`. `$3CDE` clears the sector and wave state and calls `$9C5C` at `$3D03`. | Immediate standing replacement, 15 frames × 32 flips. It fires once per clearance. Separately, `$3D14-$3D1A` sets map request `$B8=1` and delay `$BB=$37`. `$FB43` counts 55 foreground polls and checks the proton/warp guards before starting the map at `$FB74`. Overwriting this text leaves the map request intact. |
| SQUADRON DESTROYED SIR `$3CA4` | `$3D23` empties the current group with other groups still in the sector, then prints at `$3D3A`. | Immediate standing replacement, 5 × 25 frames. It starts the next approach through `$E3/$C597/$C598`, and can fire once per completed group. |
| WARNING THE GORGANITOR APPROACH `$C59D` | `$C7D4` at group arrival and `$1C55` at warp-in both reach `$C832`, which prints at `$C841` and starts the `$0930` siren. | Immediate standing replacement, 15 × 30 frames. Each arrival fires, including with a working tracking computer. |
| ALERT ENTERING GORGANITOR SECTOR `$C5C2`; OTHER SQUADRONS REMAINING `$C62B` | Arrival dispatch `$FCE1` uses `$FD23` for an occupied fighter sector or `$FD0B` when the remaining-squadrons flag `$C597` is set. | Immediate standing replacement, 10 × 10 or 5 × 8 frames, respectively, with the `$0921` sweep. A later arrival may fire again. |
| AUTO TRACKING ENGAGED `$1842` | `$89E6` takes an engagement request in `$62` if the computer `$3D` works and running latch `$64` is clear. The print is at `$8A2C`. | Immediate scrolling replacement, 8 characters × 18 flips at four frames per character. One print per engagement. `$8A4E` clears the tracking state when A/T disengages, targets run out or flight resumes. Computer failure also switches tracking off. These paths make no disengagement print. A fresh engagement can print again. |
| System destroyed `$8301,$8322,$8345,$8367,$838B,$83B2,$83D6,$83FC` | `$84D7` selects a working system. Only a decrement of `$39-$40` to zero reaches `$84F2`. Its eight cases print at `$8505/$852F/$854B/$8567/$8583/$859F/$85BB/$85D3`, then call `$0930`. | Immediate standing replacement, 5 × 53 frames. Covers phasors, long/short scanners, steller grid update, automatic tracking computer, hyperspace coordinator, long-range scan sequencer and communications. A nonzero HP result or a system already at zero produces no notice. Repair allows a later zero crossing. |
| MOTHERSHIP ENGAGED IN BATTLE `$3DDD`; MOTHERSHIP DESTROYED `$3E00` | `$3E7E` scans groups 0–3. A complete ring starts the 120-tick counter and prints at `$3F21`. Expiry prints at `$3F3D`, removes the base and latches its loss. | Immediate standing replacement, 15 × 15 frames plus siren. Breaking a ring resets its timer, so engagement may print again. Destruction fires once for that base. |
| JARALOBA IS SURROUNDED `$3E1F`; JARALOBA CEASES TO EXIST `$3E3F` | `$3E7E` checks the planet last, with starts/expiry at `$3ECF/$3EF0`. The 255-tick expiry sets `$F431` for the game-over poll at `$99F3`. | Same standing replacement and siren as the mothership ring notices. A fresh siege can print again after its ring breaks. The loss latches. If all five rings become full on one tick, the planet notice wins because its print is last. |
| ENTERING BASE SECTOR `$3FB9`; GORGANITOR BASESTAR DETECTED `$3FD9`; BASESTAR DESTROYED CAPTAIN `$8F31` | Friendly or enemy sector arrival at `$FD63/$FD46`, or a player-destroyed base at `$8F6B`; prints at `$FD77/$FD5A/$8F77`. | Same immediate standing replacement, base entry 5 × 10 frames and the destruction 20 × 15. Entry is per visit, destruction is per base. |

DMA traces in `js/test/mission-messages.js` use the C64 last-enemy save as a fight fixture. The approach warning was active when `$3CC4` called the sector-clear print. A scanner loss on the next frame replaced the clear text, and map setup still started after exactly 55 polls (32 PAL frames in this fixture). In a separate trace, the real fight loop started tracking a few frames into the approach warning. A nonfatal hit left the scroll running, the next hit replaced it with the standing scanner warning and siren, and the warning expired at 265 ticks without either earlier text replaying. A forced world tick with five full rings printed four engagement notices and then the planet notice, all in one pass. The next tick printed nothing.

### C128 port

`68fb1fc` added an eight-entry foreground FIFO in `mission-messages.asm` and made the strategic reader wait for both `MSGON` and the foreground FIFO. The eight-entry strategic FIFO came from `55c6dd6`. It retained `M_LASTMSG` for the debugger. The clear timer started when the delayed text was finally drawn. In the pre-fix regression, the row still held the approach warning after the kill and the map was absent after 35 frames. A longer probe showed clear first drawn at frame 1023 and the map starting at 1049. `0fb9b2a` suppressed the approach and arrival notices if tracking worked. The C64 trace shows both the arrival print and the subsequent engagement.

The joined game now records the latest request in `NOTICEPEND` for the next safe `VIEWWORK` slot. It can replace an active row or another pending request. Strategic events use that same byte, with `M_LASTMSG` still recording the latest ring event. The last kill arms a separate `CLEARTIME` immediately, using the port's existing 26-frame map target and its hyperspace, wipe and proton guards. Scanner computation continues while its text writes defer to the notice. Damage enters the shared slot from the regular hit, mine and enemy proton paths. Base entry/destruction may still draw in their scene's timed slot and supersede an older pending text. The planet-loss notice is published before handing over to the ending if it was still pending.

The port coalesces prints in one raster service window. The latest text wins even if the earlier C64 call would have drawn a partial frame or started a momentary sound. The port also measures the map delay in PAL frames, while the C64 delay varies with foreground poll rate. The DMA regression sees the clear row next, damage on the following frame, no stale tracking scroll, and map setup 26 frames after clear.

The resident notice module uses 655 bytes, down from 693, leaving 502 bytes before `$0C60`. The retired strategic FIFO space stays in place as padding and holds the 11-byte post-guns explosion helper. Skipping that work after its line-204 deadline removes two late writes reproduced in the pre-fix fight fixture. The packed low stream uses 3,186 bytes, down from 3,206, with 20 bytes before the tunnel stream. The build's fixed-symbol check and a comparison against `0fb9b2a` show that the relocated block, glue, map and cockpit symbols kept their addresses.

VICE x128 follow-up. In a fight with an active notice, clear the sector, trigger or observe a scanner loss, and check that the last event owns the row while the automatic map still opens on time. Repeat with a working tracking computer on warp-in and check the notice and siren during the transition. A local x128 monitor run could not start because the sandbox blocks VICE's AppData state directory, even with a scratch configuration.
