// Per-program debugger profiles: what to watch, which cheats and events exist,
// which on-screen keys to show. Addresses are labels from the program's symbol
// table (js/c64-symbols.txt for the C64 game, the assembler's for the C128
// programs) or '$hex'.
//
//   watches: {name, at, size (bytes, default 1), fmt: 'dec' | 'hex' | 'digits'}
//            'digits' = consecutive HUD screen codes $70-$79 read as a number
//   cheats:  {id, name, help, freeze: [{at, size, value}]}   value omitted = keep current
//            {id, name, help, skip: 'LABEL'}                  the routine returns at once
//   events:  {name, at: 'LABEL', pause: bool}                 log (and pause) when entered
//   keys:    on-screen buttons: {label, mouse: 'left'|'right'|'both'} or {label, key: 'Space'}
'use strict';

var SentinelProfiles = {
  c64game: {
    title: 'C64 game (1351 patch)',
    watches: [
      { name: 'Shields', at: 'SHIELDS' },
      { name: 'Energy', at: 'ENERGY', size: 4, fmt: 'digits' },
      { name: 'Protons', at: 'PROTONS' },
      { name: 'Hits taken', at: 'HITS', size: 2 },
      { name: 'Systems', at: 'SYSTEMS', size: 8, fmt: 'bytes' },
      { name: 'Difficulty', at: 'DIFFLEVEL' },
      { name: 'Crosshair X', at: 'CURX' },
      { name: 'Crosshair Y', at: 'CURY' },
      { name: 'Shields lost', at: 'SHIELDSLOST', fmt: 'hex' },
      { name: 'Planet lost', at: 'PLANETLOST', fmt: 'hex' },
    ],
    cheats: [
      { id: 'invuln', name: 'Invulnerable', help: 'HIT returns at once: no system damage, shields stay', skip: 'HIT' },
      { id: 'shields', name: 'Freeze shields', help: 'Writes to SHIELDS are ignored', freeze: [{ at: 'SHIELDS' }] },
      { id: 'energy', name: 'Freeze energy', help: 'The four HUD energy digits stop counting', freeze: [{ at: 'ENERGY', size: 4 }] },
      { id: 'protons', name: 'Infinite protons', help: 'Writes to PROTONS are ignored', freeze: [{ at: 'PROTONS' }] },
      { id: 'planet', name: 'Planet survives', help: 'PLANETLOST stays 0', freeze: [{ at: 'PLANETLOST', value: 0 }] },
    ],
    events: [
      { name: 'Game over', at: 'GAMEOVER', pause: true },
      { name: 'Ship hit', at: 'HIT' },
      { name: 'System destroyed', at: 'SYSDOWN' },
      { name: 'Energy out', at: 'ENERGYOUT', pause: true },
      { name: 'Torpedo launched', at: 'TORPEDO' },
    ],
    keys: [
      { label: 'Fire / L', mouse: 'left' },
      { label: 'Map / R', mouse: 'right' },
      { label: 'Torpedo L+R', mouse: 'both' },
      { label: 'SPACE', key: 'Space' },
      { label: 'C=', key: 'AltLeft' },
      { label: 'RUN/STOP', key: 'Escape' },
    ],
    help: 'Mouse: crosshair. Left: fire, right: map, both: torpedo. Arrows + Right Ctrl: joystick. Alt = C= key.',
    fastStart: 'GAMEENTRY',     // run at full speed until the depacker reaches the game
  },
  cockpit: {
    title: 'C128 cockpit',
    watches: [
      { name: 'Crosshair X', at: 'CURX' },
      { name: 'Crosshair Y', at: 'CURY' },
      { name: 'Gun 1 X', at: 'G1X' },
      { name: 'Gun 2 X', at: 'G2X' },
      { name: 'Fire flag', at: 'FIREFLAG' },
      { name: 'Shot in flight', at: 'SHOTON', fmt: 'hex' },
      { name: 'Shot shape', at: 'SHOTSHP', fmt: 'hex' },
      { name: 'Shot path pos', at: 'SHIDX' },
      { name: 'Path points', at: 'NPTS' },
      { name: 'Shots fired', at: 'SHOTS', size: 2 },
      { name: 'Energy', at: 'HUDE', size: 4, fmt: 'digits' },
      { name: 'Overrun frames', at: 'OVRUN' },
    ],
    cheats: [
      { id: 'energy', name: 'Freeze energy', help: 'Shots stop costing energy', freeze: [{ at: 'HUDE', size: 4 }] },
    ],
    events: [
      { name: 'Shot launched', at: 'LAUNCH' },
    ],
    keys: [
      { label: 'Fire / L', mouse: 'left' },
      { label: 'T', key: 'KeyT' },
      { label: 'SPACE', key: 'Space' },
    ],
    help: 'Mouse or arrows: crosshair (the guns follow). Left button / Right Ctrl: phasor shot (hold to keep firing). T: tracking crosshair. SPACE: exit.',
  },
  map: {
    title: 'C128 sector map',
    watches: [
      { name: 'Cursor X', at: 'CURX' },
      { name: 'Cursor Y', at: 'CURY' },
      { name: 'Selected X', at: 'SELX' },
      { name: 'Tick counter', at: 'TICKC' },
      { name: 'Last message', at: 'LASTMSG' },
    ],
    cheats: [],
    events: [{ name: 'Tick', at: 'TICK' }],
    keys: [
      { label: 'Fire / L', mouse: 'left' },
      { label: 'R', key: 'KeyR' },
      { label: 'T', key: 'KeyT' },
      { label: 'V', key: 'KeyV' },
      { label: 'SPACE', key: 'Space' },
    ],
    help: 'Mouse or arrows: cursor. Left / Right Ctrl: select. R: new map. T: fast ticks. V: second display. SPACE: exit.',
  },
  flight: {
    title: 'C128 flight kernel',
    watches: [
      { name: 'Vanishing X', at: 'VPX' },
      { name: 'Vanishing Y', at: 'VPY' },
    ],
    cheats: [],
    events: [],
    keys: [{ label: 'Both buttons: exit', mouse: 'both' }],
    help: 'Mouse: vanishing point. Both buttons: exit.',
  },
};

if (typeof module !== 'undefined') module.exports = SentinelProfiles;
