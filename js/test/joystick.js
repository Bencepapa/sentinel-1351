'use strict';
const Input = require('../src/input.js');

module.exports = function ({ boot, run, check }) {
  const { m, hooks, p: { symbols: s } } = boot('c64game', 'trace');
  hooks.fixC64Original();
  m.dma = true;
  const R = m.ram, modes = [];
  const input = new Input(m, hooks, mode => modes.push(mode));
  const frames = (n = 1) => run(m, hooks, n, () => input.feed());
  const joy = (code, down = true, repeat = false) => input.setJoystick(code, down, repeat);
  const mouse = (button, down = true) => input.setButton('mouse', button, down);
  const isJoystick = () => !!(R[s.MFLAG] & 0x80) && !m.mouse.present;
  const isMouse = () => !(R[s.MFLAG] & 0x80) && m.mouse.present;
  const key = (row, down) => m.setKey(7, row, down);
  const flight = () => !R[s.ATTRACT] && !R[s.COCKPIT];

  frames(300);
  joy('ControlRight'); frames(10); joy('ControlRight', false); frames(140);
  joy('Numpad0'); frames(10); joy('Numpad0', false); frames(190);
  check(flight() && isJoystick(), 'c64 input: joystick fire starts the title and difficulty menu');
  // The launch prompt itself opens the map on Fire or SPACE. Confirm the
  // current sector, then let the original's Fire debounce expire.
  joy('Numpad0'); frames(10); joy('Numpad0', false); frames(120);
  joy('Numpad0'); frames(12); joy('Numpad0', false); frames(180);
  check(flight() && R[s.JOYFIRE] === 0, 'c64 input: joystick fire confirms the current sector and enters flight');
  const saved = m.saveState(), protons = R[s.PROTONS];
  const restore = () => {
    m.loadState(saved);
    input.release();
    input.select('joystick');
    input.afterLoad();
    frames();
  };

  let noActions = true, rawDirections = true;
  for (const [code, mask] of [['ArrowUp', 1], ['ArrowDown', 2], ['ArrowLeft', 4], ['ArrowRight', 8]]) {
    joy(code); frames(8);
    rawDirections &&= (~R[s.JOYBYTE] & 31) === mask;
    noActions &&= flight() && !R[s.KEYMAP] && !R[s.KEYTORP] && R[s.PROTONS] === protons;
    joy(code, false);
  }
  joy('ArrowUp'); joy('ControlRight'); joy('Numpad0'); frames();
  const fire = R[s.JOYFIRE] === 1;
  joy('ControlRight', false); frames(8);
  check(rawDirections && noActions && fire && R[s.JOYFIRE] === 1 &&
    flight() && !R[s.KEYMAP] && !R[s.KEYTORP] && R[s.PROTONS] === protons,
  'c64 input: all arrows steer, Up + Fire only fires, and releasing one Fire key leaves the other held');

  restore();
  key(5, true); frames(12); key(5, false); frames();
  check(isJoystick() && R[s.COCKPIT] !== 0, 'c64 input: the C= keyboard key still opens the map in joystick mode');
  restore();
  key(4, true); frames(20); key(4, false); frames();
  check(isJoystick() && R[s.PROTONS] === protons - 1, 'c64 input: Space still launches a torpedo in joystick mode');

  restore();
  modes.length = 0;
  joy('ArrowUp'); joy('ControlRight');
  input.move(0, 4); frames();                   // POTX stays at $00, one tick from disconnected $FF
  joy('ArrowUp', true, true); frames(8);        // a held key's OS repeat must not take over
  check(isMouse() && m.sidRead(0x19) === 0 && m.joy2 === 0 && flight() && R[s.PROTONS] === protons,
    'c64 input: vertical-only mouse motion attaches at POTX $00 and masks held Up + Fire');
  joy('ArrowUp', false); joy('ControlRight', false);
  mouse('right'); frames(4);
  const waiting = flight() && R[s.RCNT] === 4;
  frames(8);
  check(waiting && R[s.COCKPIT] !== 0 && R[s.PROTONS] === protons,
    'c64 input: the right mouse button opens the map after five samples');
  mouse('right', false);
  joy('ArrowLeft'); frames();
  check(isJoystick() && m.sidRead(0x19) === 0xFF && (~R[s.JOYBYTE] & 31) === 4,
    'c64 input: a direction restores joystick mode and raw directions at POTX $00');

  restore();
  modes.length = 0;
  input.move(-1, 0); frames();                   // the other edge next to disconnected $FF
  mouse('left'); frames();
  const left = isMouse() && m.sidRead(0x19) === 0x7E && R[s.JOYFIRE] === 1;
  mouse('right'); frames(20);
  const chord = R[s.RCNT] >= 0x80 && R[s.JOYFIRE] === 0 && R[s.PROTONS] === protons - 1;
  joy('Numpad0'); frames();
  const switched = isJoystick() && R[s.JOYFIRE] === 1 && !m.mouse.left && !m.mouse.right;
  mouse('left', false);
  input.move(0, -1); frames();                   // right is still held, but the old chord latch is gone
  check(left && chord && switched && isMouse() && R[s.RCNT] === 1 &&
    modes.join() === 'mouse,joystick,mouse',
    'c64 input: mouse Fire and the torpedo chord work, Fire switches back at POTX $7E, and reconnect clears the chord latch');
  input.release(); frames();
  check(!m.joy2 && !m.mouse.left && !m.mouse.right && !R[s.RCNT],
    'c64 input: focus loss releases the virtual controls and removes the right-button delay');
};
