# Online multiplayer: one star cluster, several ships

A design for later, not a build plan for now. The idea (from the user): a player
starts the game; others join the same game with their own ships. Everyone sees
the same sector map, the same squadrons moving, the same motherships and the same
planet under attack, and each other's ships on the map. The world is stored once
and every player changes it.

**Short answer: it is possible, and the game makes it easier than most.** The
shared part of Sentinel is small and slow: about 140 bytes of world state that
changes once every 256 frames (about 5 seconds). The fast part (flying, aiming,
shooting) stays inside each player's own game; there is no shared dogfight.

## Decisions so far (from the user)

- **Up to 8 players** per game (a simple cap; the host may choose fewer).
- **Player icons on the map**, in the player's chosen colour, not plain markers.
- **Short player names**, chosen by the players.
- **The host broadcasts messages**: joined, left, moved to sector x.y, ship
  destroyed, squadron destroyed, and short chat messages.
- **Difficulty stays as in the original** (it is already hard from level 3); the
  host picks it for the whole game.
- **WebRTC**, with the host player's browser as the server. Joining needs the
  host's game code; a saved server list is optional.
- **No shared dogfight.** At most 2 players in a sector. Each fights the squadron
  in their own game; a squadron already in battle with someone else is marked on
  the map. A radar blip for the other player in the same sector would be fun but
  is not needed.
- **The same last squadron**: whoever destroys it first wins; the other gets a
  message.

## What is shared and what is not

Everything below is from the C64 code (see `MAP-LOGIC.md`, `SHIP-STATUS.md`,
`js/c64-symbols.txt`).

### The world (one copy, owned by the host)

| What | Where in the C64 game | Size |
|---|---|---|
| sector state: empty, squadron type 1-3, orange / blue mothership | `$033C` (`STATE`), 60 sectors | 60 |
| squadron size per sector (ships left) | `$0378` (`COUNT`) | 60 |
| tick counter (squadron movement, mothership events) | `$BDAF` | 1 |
| corner mothership flags (come and go) | `$208D`-`$2090` | 4 |
| attack ring counters, destroyed flags (4 blue motherships + planet) | `$3E74`-`$3E78`, `$3E79`-`$3E7D` | 10 |
| planet lost (game over for everyone) | `$F431` (`PLANETLOST`) | 1 |
| difficulty | `$E0` | 1 |
| plus, per sector: engaged by which player (multiplayer only) | page | 60 |

It changes in `TICK` (`$BE29`, every 256 frames: `SURROUND`, `MOTHER`,
`MOVEPASS`) and when a player destroys ships.

**One squadron per sector.** A sector holds one squadron: a type (1-3, the icon
colour) and a ship count (`COUNT`; the map shows one, two or three icons by size).
So "two players in a sector" means two players and the same squadron (see
*Sectors and squadrons*).

### Each player (local, reported to the host)

- name, colour, player number;
- sector `$92` / `$93` (column, row): set on hyperspace arrival from the target
  `$DF` / `$DE` (`$FCB8`), off by up to a column when the hyperspace coordinator is
  destroyed;
- shields `$844F`, energy (the HUD digits), protons `$8450`, the eight systems
  `$39`-`$40`, hits `$F432`, shots `$F43B`;
- what the player is doing: on the map, in hyperspace, engaged with the sector's
  squadron, docked at a base, ship lost.

## Network: WebRTC with the host as the server

```
             ┌──────────── host's browser ────────────┐
  player 2 ──┤  the game (runs TICK, owns the world)  ├── player 3
  player 4 ──┤  + the world: snapshots, events, chat  ├── ...
             └────────────────────────────────────────┘
        (star topology: every player has one data channel to the host)
```

### Why it fits

- No game server to run or pay for: the host's own game already runs the
  strategic layer exactly as the original (it simply keeps its `TICK`); the
  others skip theirs (`hooks.skip('TICK')`) and apply the host's snapshots.
- The traffic is tiny: a world snapshot is about 200 bytes, a player update about
  20, sent once a second or on change. 8 players is nothing for a data channel.
- The host's game is the authority, so there is one order of events and
  conflicts resolve themselves.

### What WebRTC still needs

1. **Signalling**: two browsers have to exchange a connection offer and answer
   before the data channel opens. Options:
   - **PeerJS** and its free public signalling server: the host gets an id such
     as `SENTINEL-K7Q2`; a player types it or opens the join link. Easiest; the
     free server has no guarantees, but a game only needs it for the first second
     of each connection.
   - **Copy and paste** the offer and answer as text (no server at all). Works,
     but with up to 7 joiners it is clumsy for the host.
   - **Own tiny signalling** on a free tier (a Cloudflare Worker with a Durable
     Object, about 50 lines), if the public PeerJS server proves unreliable.
2. **Getting through home routers**: free public STUN servers (Google's) are
   enough for most connections. Some networks (strict mobile or corporate NAT)
   need a TURN relay; free TURN tiers exist (for example Metered's Open Relay) but
   are limited. Expect the odd player who cannot connect.
3. **Joining**: a **join link** with the game code in it (`.../#join-K7Q2`) is all
   most groups need: the host sends it in a chat. A public **game list** needs a
   place to store it: a free Cloudflare Worker + KV (each host registers name,
   code, players, difficulty, and refreshes it every 30 s; old entries expire).
   That can come later.

### When the host leaves

Every player already holds the full world (it is 200 bytes). The host
broadcasts the player list with everyone's peer id, so when the host disappears
the lowest remaining player number takes over: it starts running `TICK` again
from its copy, the others connect to it, and the game goes on (a message: "NAME
IS NOW THE HOST"). Without this, the game ends when the host closes the tab.

## Players

- **Names**: up to 8 characters, `A-Z`, `0-9` and a space: what the game's own font
  can show, so names can appear in the game's text too.
- **Colours**: 8 fixed colours, one per player number, chosen to stay apart from
  what the map already uses (squadrons light blue, light green and purple;
  motherships orange and blue; the planet cyan; the grid yellow). For example
  white, red, light red, green, brown, light gray, gray and dark gray in the C64
  palette; the browser overlay may use brighter versions of the same hues. A
  player can pick a free colour when joining.
- **Player number** 1-8, the host is 1; it decides the colour by default and the
  host-takeover order.

## The map

- **Player icons**: a small ship icon (our own design, about 5 x 5 pixels at the
  map's resolution) in the player's colour, in a corner of the sector cell so it
  does not cover the squadron icons; a second player in the same sector takes the
  opposite corner (at most 2 per sector). The own ship keeps the original's
  selected-sector box. Hovering (or the player list next to the map) shows the
  name.
  - C64 version: drawn by the page as an overlay over the emulator picture,
    aligned with the map cells (positions from `MAP-LOGIC.md`); no game code
    changes.
  - C128 port: drawn into the bitmap by the port, and as a coloured character on
    the second display (VDC), where there is room for the player list.
- **Engaged squadrons**: a squadron in battle with another player is marked in
  that player's colour (a frame around the cell, or the squadron icons tinted),
  and cannot be chosen as a hyperspace target while the sector is full.
- **The communications module** (system 7, `$40`): when it is destroyed, the
  player stops receiving the others' positions and messages until it is repaired
  at a base. It is the one system with 255 hit points on every level, so this
  rarely matters, but it gives the module a meaning.

## Sectors and squadrons

Version 1 keeps fights fully separate; version 2 lets two players share one.

**Version 1: one player per squadron.** Hyperspacing into a squadron's sector
engages it: the host marks the sector with the player's colour. Other players
cannot jump there while it is engaged (the map refuses the target with a
message). When the fight ends (squadron destroyed, player leaves, ship lost) the
mark goes. No two players ever fight the same ships, so nothing in a fight needs
syncing. Empty sectors, bases and mothership sectors can take two players.

**Version 2: two players, one squadron.** A second player may join an engaged
sector. Each still fights in their own game, but the squadron's ship count is
shared: every ship destroyed is reported to the host, which lowers `COUNT` and
tells the other player, whose game then removes one of its attackers (the
user's idea: kill an enemy ship locally when the other player downs one). The
last ship goes to whoever's report reaches the host first; the other player's
fight ends with "SQUADRON DESTROYED BY NAME". This needs to know how the game
holds the ships of a fight and how to remove one cleanly (see the open questions);
until then, version 1.

**Squadrons do not move while engaged.** The host's `TICK` may move squadrons
(`MOVEPASS`); a squadron in a fight should stay put. The host can skip moving
engaged sectors (a hook on `MOVECELL`-style code, or restoring them after the
pass); the original probably already handles the player's own sector somehow
(open question).

**Radar blip (optional).** Two players in one sector could see each other on the
radar: positions sent ~10 times a second between those two only, over an
unreliable (UDP-like) data channel. Cheap, but it needs the scanner code ported
first.

## Messages

The host is the only one who broadcasts; players send it events and chat.

| Event | Message (in the game's font, max 40 characters) |
|---|---|
| a player joins / leaves | `NAME JOINED THE BATTLE` / `NAME LEFT` |
| hyperspace arrival | `NAME IN SECTOR 05.03` |
| engages a squadron | `NAME ENGAGED IN SECTOR 05.03` |
| squadron destroyed | `NAME DESTROYED A SQUADRON` |
| ship lost | `NAME WAS DESTROYED` |
| docked at a base | `NAME DOCKED AT BASE 02.01` |
| host change | `NAME IS NOW THE HOST` |
| chat | `NAME: TEXT` (up to 24 characters, plus a few presets: HELP, ON MY WAY, BASE UNDER ATTACK) |

Where they appear:

- C64 version: a message line under the screen in the page (the game's own
  scroller is part of its code; writing into it is possible later with hooks).
- C128 port: the message line on the VIC-IIe screen (`LASTMSG` already exists in
  the map program) and the message area on the second display.

## Rules

- **Difficulty**: as the original, chosen by the host.
- **Time**: the strategic clock is the host's. Each player's game time and energy
  are their own.
- **Game over**: planet lost (`PLANETLOST`) ends the game for everyone. A player
  whose ship is lost (`SHIELDSLOST`) is out: watch the map, or rejoin at a base
  with a new ship (to decide).
- **Joining late**: the new player gets the current world and starts in the
  original start sector (5.3, next to the planet) or at a base.
- **Score**: each player keeps their own rating; the end screen lists everyone
  (squadrons destroyed, hits taken, time).
- **Cheats**: the page has a debugger; this is a game among friends, so the host
  does not police it.

## Phases

0. **Spike.** Two browsers, PeerJS, a join link; the host's `STATE` / `COUNT` sent
   to the other, its local tick skipped; destroy a squadron on the host and see it
   vanish on the other map.
1. **Shared strategic layer.** Snapshots on every tick, kill events from players,
   planet lost ends the game, late join.
2. **Players.** Names, colours, map icons, the player list, messages and chat.
3. **Engaged squadrons, version 1.** Marks on the map, refused targets, squadrons
   kept still while engaged.
4. **Host takeover** and the optional public game list.
5. **Version 2 sectors** (shared squadron, kill sync) and the **radar blip**,
   once the fight and the scanners are understood (C128 port work).

## Open questions

- Which code destroys a ship in a fight, and where does `COUNT` go down? (A
  write watch on `$0378` during a fight finds it.) How does the fight hold its
  attackers, and can one be removed mid-fight without breaking it?
- Can `MOVEPASS` move a squadron into or out of the player's sector during a
  fight, and what does the original do then?
- Does anything in the strategic layer read the player's sector (squadrons
  avoiding or chasing the player)? In a shared world, which player counts?
- Mothership and planet messages ("MOTHERSHIP ENGAGED IN BATTLE"): every player,
  or only those nearby?
