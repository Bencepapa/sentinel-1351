'use strict';
const Input = require('../src/input.js');

module.exports = function ({ boot, run, check }) {
  const { m, hooks, p: { symbols: s } } = boot('game', 'trace');
  m.dma = true;
  const R = m.ram, modes = [];
  const input = new Input(m, hooks, mode => modes.push(mode));
  const frames = (n = 1) => run(m, hooks, n, () => input.feed());
  const joy = (code, down = true) => input.setJoystick(code, down, false);
  const button = (name, down = true) => input.setButton('mouse', name, down);
  const protons = () => R[0x485A] * 256 + R[0x485B];
  const mouseMode = () => m.mouse.present && R[s.MPRES] && R[s.M_MPRES];
  const joystickMode = () => !m.mouse.present && !R[s.MPRES] && !R[s.M_MPRES];
  const noAction = () => !R[s.MAPSHOWN] && !R[s.TPF] && !R[s.TREQ];
  const cKey = down => m.setKey(7, 5, down);

  frames(120);
  const stock = protons();
  let directions = true;
  for (const [code, mask] of [['ArrowUp', 1], ['ArrowDown', 2], ['ArrowLeft', 4], ['ArrowRight', 8]]) {
    joy(code); frames(8);
    directions &&= (~R[s.JOY] & 31) === mask && noAction();
    joy(code, false);
  }
  joy('ArrowUp'); joy('ControlRight'); frames(14);
  check(directions && joystickMode() && (~R[s.JOY] & 31) === 17 && noAction() && protons() === stock,
    'c128 input: all directions steer, and joystick Up + Fire opens no map and launches no torpedo');
  joy('ArrowUp', false); joy('ControlRight', false);

  input.move(0, 4); frames();
  check(mouseMode() && !!R[s.MDY] && R[s.OLDX] === 0,
    'c128 input: vertical mouse motion selects the mouse at POTX $00 without a lost movement sample');
  button('right'); frames(4);
  const waiting = !R[s.MAPSHOWN] && R[s.RCNT] === 4;
  frames(8);
  button('right', false);
  frames(340);
  check(waiting && R[s.MAPSHOWN] && R[s.M_ICONDONE] && R[s.PTON] && protons() === stock,
    'c128 input: the right mouse button opens the map after its delay');

  const start = R[s.M_CURX];
  joy('ArrowLeft'); frames(); joy('ArrowLeft', false);
  const cursor = R[s.M_CURX], pointerHidden = !R[s.PTON];
  check(joystickMode() && cursor === (start + 9) % 10 && pointerHidden && R[s.MAPSHOWN],
    'c128 input: a fresh joystick direction takes over and moves the map cursor in one frame');
  input.move(1, 0); frames();
  check(mouseMode() && R[s.M_CURX] === cursor && R[s.PTON] && !R[s.RCNT],
    'c128 input: mouse motion takes the map pointer over at the current joystick sector');
  cKey(true); frames(8); cKey(false); frames(40);

  joy('ArrowUp'); joy('ControlRight'); frames(12);
  check(joystickMode() && noAction() && protons() === stock,
    'c128 input: fresh joystick Up + Fire after mouse use cannot trigger a mouse action');
  joy('ArrowUp', false); joy('ControlRight', false);
  button('left'); frames();
  const left = mouseMode() && !(R[s.JOY] & 0x10);
  button('right'); frames(18);
  const torpedo = R[s.TPF] && protons() === stock - 1 && (R[s.RCNT] & 0x80);
  joy('ControlRight'); frames();
  const joystickFire = joystickMode() && !(R[s.JOY] & 0x10) && !R[s.RCNT];
  joy('ControlRight', false);
  button('left', false); button('right', false); frames();
  check(left && torpedo && joystickFire && modes.join() === 'mouse,joystick,mouse,joystick,mouse,joystick',
    'c128 input: mouse Fire and the torpedo chord work, and fresh joystick Fire clears the mouse latch');

  const native = boot('game', 'trace');
  const N = native.m.ram, ns = native.p.symbols;
  native.m.dma = true;
  const nativeFrames = n => run(native.m, native.hooks, n);
  nativeFrames(120);
  const nativeMouse = N[ns.MPRES] === 1;
  native.m.joy2 = 21; nativeFrames(2);
  const nativeStick = !N[ns.MPRES] && !(N[ns.JOY] & 4) && !N[ns.TREQ] && !N[ns.TPF];
  native.m.joy2 = 0; nativeFrames(2);
  native.m.joy2 = 17; nativeFrames(12);
  const noAlias = !N[ns.MPRES] && !N[ns.MAPSHOWN] && !N[ns.TPF] && !N[ns.RCNT];
  native.m.joy2 = 0; native.m.moveMouse(4, 0); nativeFrames(2);
  check(nativeMouse && nativeStick && noAlias && N[ns.MPRES] && N[ns.M_MPRES],
    'c128 input: with valid pots, a new unshared joystick direction takes over and mouse movement takes control back');
};
