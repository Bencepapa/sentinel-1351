# Online multiplayer: one star cluster, several ships

A design for later, not a build plan for now. The idea (from the user): a player
starts the game; others join the same game with their own ships. Everyone sees
the same sector map, the same squadrons moving, the same motherships and the same
planet under attack, and each other's ships on the map. The world is stored once
and every player changes it.

**Short answer: it is possible, and the game makes it easier than most.** The
shared part of Sentinel is small and slow: about 140 bytes of world state that
changes once every 256 frames (about 5 seconds). The fast part (flying, aiming,
shooting) happens inside one sector and can stay local to each player at first.

## What is shared and what is not

Everything below is from the C64 code (see `MAP-LOGIC.md`, `SHIP-STATUS.md`,
`js/c64-symbols.txt`).

### The world (shared, one copy on the server)

| What | Where in the C64 game | Size |
|---|---|---|
| sector state: empty, squadron type 1-3, orange / blue mothership | `$033C` (`STATE`), 60 sectors | 60 |
| squadron size per sector | `$0378` (`COUNT`) | 60 |
| tick counter (squadron movement, mothership events) | `$BDAF` | 1 |
| corner mothership flags (come and go) | `$208D`-`$2090` | 4 |
| attack ring counters, destroyed flags (4 blue motherships + planet) | `$3E74`-`$3E78`, `$3E79`-`$3E7D` | 10 |
| planet lost (game over for everyone) | `$F431` (`PLANETLOST`) | 1 |
| difficulty | `$E0` | 1 |
| random seed for the strategic layer | `$BA85` uses its own seed | 1-2 |

That is the whole strategic layer. It changes in `TICK` (`$BE29`, every 256
frames: `SURROUND`, `MOTHER`, `MOVEPASS`) and when a player destroys squadrons in
a sector.

### Each player (local, reported to the server)

- sector position `$92` / `$93` (column, row); set on arrival from the target
  `$DF` / `$DE` (`$FCB8`), off by up to a column when the hyperspace coordinator is
  destroyed;
- shields `$844F`, energy (the HUD digits), protons `$8450`, the eight systems
  `$39`-`$40`, hits `$F432`, shots `$F43B`, game time;
- name and colour for the others' maps.

### Inside a sector (local at first)

The 3D view, enemy positions, shots, the tracking computer and the scanners all
run inside one player's game. Sharing these is a much bigger step (see phase 4).

## Architecture

```
  browser A ──┐                      ┌── browser B
  (game +     │  WebSocket: events   │   (game +
   JS hooks)  ├──────► world ◄───────┤    JS hooks)
              │        server        │
  browser C ──┘  (owns the world,    └── ...
                  runs the ticks)
```

### The server owns the world

One authoritative copy of the world per game. The server runs the strategic
layer (the tick) and broadcasts the result, so it can never disagree with itself.
Two ways to run the tick:

1. **Run the original code.** The JS emulator already runs the C64 game headless
   (`js/test/run.js` does it in Node). A server process can hold one machine per
   world and call `TICK` (`$BE29`) every 256 frames, exactly like the game. The
   strategic rules then match the original by construction, including its quirks.
2. **Run a JS port of the tick.** `MAP-LOGIC.md` already describes the rules and
   the C128 map program reimplements them, verified against the original. A JS
   port is easier to read and change (for example, to scale the number of
   squadrons with the number of players), and the hook system can verify it
   against the original routines the same way the cockpit's phasor port is
   checked.

Start with 1 (no rules to rewrite), move to 2 when the rules need to change for
multiplayer.

### Clients follow the world

Each browser still runs the full game; the JS hooks keep its world copy in step:

- **Skip the local tick.** `hooks.skip('TICK')`: squadrons move only when the
  server says so.
- **Apply world updates.** On every server update, write `STATE` / `COUNT` and the
  other world bytes into the game's memory and redraw the changed map cells (the
  game's own `DRAWCELL`-style routine, or force a full map redraw).
- **Report changes.** Hook the routines that change the world locally (a squadron
  destroyed in combat lowers `COUNT` for the player's sector; a mothership
  destroyed) and send them as events: `{type: 'kill', sector: 34, count: 1}`.
- **Report the ship.** Sector, shields, energy and similar every second or so, and
  at once on hyperspace arrival.

No change to the 6502 code is needed for the C64 version; everything above is
hooks and memory writes, the same tools the debugger uses.

### Conflicts

The world changes slowly, so conflicts are rare and simple:

- two players destroy the last squadron of the same sector: the server applies
  events in order and clamps `COUNT` at 0; the second report changes nothing;
- a squadron moves away while a player fights it: the server is right, the
  player's next update shows the sector empty and the local fight ends (the game
  already handles "the squadron left").

### Showing the other players

- **C64 version:** draw the other ships as an overlay on the map, aligned with the
  map cells (the page knows the map's cell positions from `MAP-LOGIC.md`). No game
  code involved. A small coloured marker per player, the name on hover.
- **C128 port:** a real map icon, drawn by the port into the bitmap and on the
  second display (VDC), where there is room for a player list next to the map.
- The communications module (`$40`, system 7) is a gift for this: when it is
  destroyed, the player stops receiving the others' positions until it is
  repaired at a base.

### Rules that need deciding

- **Time:** the strategic clock is the server's. A player's game time and energy
  are their own.
- **Difficulty:** per world, chosen by whoever creates it.
- **Game over:** planet lost (`PLANETLOST`) ends the game for everyone. A
  player whose ship is lost (`SHIELDSLOST`) is out: spectate, or rejoin at a base
  with a new ship (a choice for the user).
- **Score:** each player keeps their own rating; the world could show a shared
  result (planet saved, time, squadrons destroyed per player).
- **More players, more enemies?** The original difficulty table sets 10-44
  squadrons. With several ships the cluster empties fast; the JS tick (option 2)
  could add squadrons per player or speed up the corner motherships.
- **Joining late:** a new player gets the current world snapshot and starts at a
  base sector (the original start is sector 5.3, the planet's neighbour).

## Hosting

GitHub Pages serves the game but cannot run a server. Options, smallest first:

| Option | What it is | Cost / effort |
|---|---|---|
| one small Node process | WebSocket server, worlds in memory, the emulator for the tick | a cheap VM or a free tier (Fly.io, Railway, Render); restart loses worlds unless saved |
| Cloudflare Durable Objects | one object per world, WebSocket built in, state stored | small; the object holds the world and runs the tick on an alarm |
| WebRTC, host player | the first player's browser is the server | no server for the game, but still a signalling service to connect, and the world ends when the host leaves |

A Durable Object per world fits best: the world is tiny, it has one owner, and it
must survive restarts. The page would get a "Create world" / "Join world" (a link
with the world id).

Messages are small: a full world snapshot is about 140 bytes (base64 under 200),
a tick update is the changed cells, a player update is about 20 bytes.

## Phases

0. **Spike.** Two browsers, one tiny server, a shared `STATE` / `COUNT`: kill a
   squadron in one browser, see it vanish on the other's map. Proves the hook
   approach end to end.
1. **Shared strategic layer.** Server tick (original code in a headless
   machine), local tick skipped, events for kills and motherships, planet lost
   ends the world.
2. **Players on the map.** Positions, names, colours; the communications module
   rule.
3. **World lifecycle.** Create / join links, late join at a base, ship lost
   handling, end-of-game summary.
4. **Shared dogfights** (C128 port / JS only). Players in the same sector see each
   other's ships and the same enemies. This needs the enemy positions and AI of a
   sector to have one owner (the first player there, or the server), and the
   cockpit to draw other players as sprites. It is the hard part and depends on
   the dogfight port (radar, tracking, enemy AI) being done first.

## Open questions

- Which code destroys a squadron after a won fight, and where does `COUNT` go
  down? (Find with a write watch on `$0378` during a fight.)
- Does anything in the strategic layer read the player's sector (for example,
  squadrons avoiding or chasing the player)? If so, which player counts in a
  shared world?
- Mothership sequences and the planet attack have messages ("MOTHERSHIP ENGAGED
  IN BATTLE"): should every player see them, or only those nearby?
