// Browser front end: runs a C128 program 50 times a second, draws the VIC-IIe
// and VDC screens, feeds mouse / touch / keyboard input, plays the SID log,
// and shows the hooked routines with their verification state.
'use strict';

(function () {
  var $ = function (id) { return document.getElementById(id); };
  var Video = SentinelVideo;

  // Commodore key matrix: [column (CIA1 port A bit), row (port B bit)]
  var KEYS = {
    Backspace: [0, 0], Enter: [0, 1], F7: [0, 3], F1: [0, 4], F3: [0, 5], F5: [0, 6],
    Digit3: [1, 0], KeyW: [1, 1], KeyA: [1, 2], Digit4: [1, 3], KeyZ: [1, 4], KeyS: [1, 5], KeyE: [1, 6], ShiftLeft: [1, 7],
    Digit5: [2, 0], KeyR: [2, 1], KeyD: [2, 2], Digit6: [2, 3], KeyC: [2, 4], KeyF: [2, 5], KeyT: [2, 6], KeyX: [2, 7],
    Digit7: [3, 0], KeyY: [3, 1], KeyG: [3, 2], Digit8: [3, 3], KeyB: [3, 4], KeyH: [3, 5], KeyU: [3, 6], KeyV: [3, 7],
    Digit9: [4, 0], KeyI: [4, 1], KeyJ: [4, 2], Digit0: [4, 3], KeyM: [4, 4], KeyK: [4, 5], KeyO: [4, 6], KeyN: [4, 7],
    Equal: [5, 0], KeyP: [5, 1], KeyL: [5, 2], Minus: [5, 3], Period: [5, 4], Semicolon: [5, 5], BracketLeft: [5, 6], Comma: [5, 7],
    Backslash: [6, 0], BracketRight: [6, 1], Quote: [6, 2], Home: [6, 3], ShiftRight: [6, 4], Slash: [6, 7],
    Digit1: [7, 0], Backquote: [7, 1], ControlLeft: [7, 2], Digit2: [7, 3], Space: [7, 4], AltLeft: [7, 5], KeyQ: [7, 6], Escape: [7, 7],
  };
  // Joystick in port 2 (not part of the matrix): arrows + Right Ctrl / Numpad 0
  var JOY = { ArrowUp: 1, ArrowDown: 2, ArrowLeft: 4, ArrowRight: 8, ControlRight: 16, Numpad0: 16 };

  var m = null, hooks = null, prog = null, progName = 'map';
  var audio = new SentinelAudio(), audioFrame = 0;
  var vicCtx = $('vic').getContext('2d'), vdcCtx = $('vdc').getContext('2d');
  var vicImg = vicCtx.createImageData(Video.VIC_W, Video.VIC_H);
  var vdcImg = vdcCtx.createImageData(Video.VDC_W, Video.VDC_H);
  var vicPx = new Uint32Array(vicImg.data.buffer), vdcPx = new Uint32Array(vdcImg.data.buffer);
  var pendX = 0, pendY = 0, sens = 0.5;
  var paused = false, mode = 'verify';

  function boot(name) {
    progName = name;
    prog = SENTINEL_PROGRAMS[name];
    m = new C128();
    m.loadPrg(base64(prog.prg));
    hooks = new SentinelHooks(m, prog.symbols);
    SentinelNative.install(hooks, mode);
    hooks.onMismatch = function (r) { log('mismatch in ' + r.name + ' (frame ' + r.frame + '): ' + r.diffs.join('; ')); };
    ['STEP', 'DRAWCELL', 'TICK', 'MOVEPASS', 'CURSOR', 'VDCDRAW', 'MOVESTAR', 'DRAW7', 'ERASE7']
      .forEach(function (n) { if (prog.symbols[n] !== undefined) hooks.trace(n); });
    m.start(prog.entry);
    audio.reset(audioFrame * 19656);
    $('vdcwrap').style.display = name === 'map' ? '' : 'none';
    $('help').textContent = name === 'map'
      ? 'Mouse/drag or arrows: cursor - left button / Fire: select - R new map - T fast ticks - V second display - SPACE exit'
      : 'Mouse/drag: vanishing point - both buttons: exit';
    $('overlay').style.display = 'none';
    $('log').textContent = '';
  }

  function base64(s) {
    var bin = atob(s), out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  function log(t) {
    var el = $('log');
    if (el.childNodes.length > 40) el.removeChild(el.firstChild);
    var d = document.createElement('div'); d.textContent = t; el.appendChild(d);
  }

  // ---- frame loop ----------------------------------------------------------

  var last = 0, acc = 0, FRAME_MS = 1000 / 50;
  function tick(t) {
    requestAnimationFrame(tick);
    if (!last) last = t;
    acc = Math.min(acc + (t - last), FRAME_MS * 4);
    last = t;
    if (paused || !m) return;
    var ran = 0;
    while (acc >= FRAME_MS) {
      acc -= FRAME_MS;
      feedMouse();
      var alive = m.runFrame();
      audio.frame(m, audioFrame++ * 19656);
      hooks.endFrame();
      ran++;
      if (!alive) { stopped(); break; }
    }
    if (ran) draw();
  }

  function feedMouse() {
    // the 1351 reports 6 bits per axis; keep each frame's step inside that
    var dx = Math.max(-24, Math.min(24, Math.trunc(pendX)));
    var dy = Math.max(-24, Math.min(24, Math.trunc(pendY)));
    pendX -= dx; pendY -= dy;
    m.moveMouse(dx, dy);
  }

  function draw() {
    Video.renderVic(m, vicPx);
    vicCtx.putImageData(vicImg, 0, 0);
    if (progName === 'map') {
      Video.renderVdc(m, vdcPx, (m.frame >> 4) & 1);
      vdcCtx.putImageData(vdcImg, 0, 0);
    }
    if (m.frame % 10 === 0) stats();
  }

  function stats() {
    var rows = [];
    for (var a in hooks.handlers) {
      var h = hooks.handlers[a];
      var state = !h.fn ? 'trace' : h.mode === 'trace' ? 'off' : h.mode === 'replace' ? 'JS' : (h.failed ? h.failed + ' FAIL' : h.verified + ' ok');
      rows.push('<tr><td>' + h.name + '</td><td>$' + ('000' + h.addr.toString(16).toUpperCase()).slice(-4) +
        '</td><td>' + h.callsLastFrame + '</td><td class="' + (h.fn ? (h.failed ? 'bad' : 'good') : '') + '">' + state + '</td></tr>');
    }
    $('hooks').innerHTML = '<tr><th>label</th><th>addr</th><th>calls/frame</th><th>' +
      (mode === 'replace' ? 'runs as' : 'verified') + '</th></tr>' + rows.join('');
    $('frame').textContent = 'frame ' + m.frame;
  }

  function stopped() {
    $('overlay').style.display = '';
    $('overlay').textContent = (m.stopped === 'returned to BASIC' ? 'Returned to BASIC' : 'Stopped: ' + m.stopped) + ' - tap to restart';
  }

  // ---- input ---------------------------------------------------------------

  var screenEl = $('screen');
  screenEl.addEventListener('mousedown', function (e) {
    audio.start();
    if (!document.pointerLockElement && screenEl.requestPointerLock) { screenEl.requestPointerLock(); return; }
    if (e.button === 0) m.mouse.left = true;
    if (e.button === 2) m.mouse.right = true;
    e.preventDefault();
  });
  window.addEventListener('mouseup', function (e) {
    if (e.button === 0) m.mouse.left = false;
    if (e.button === 2) m.mouse.right = false;
  });
  screenEl.addEventListener('contextmenu', function (e) { e.preventDefault(); });
  document.addEventListener('mousemove', function (e) {
    if (document.pointerLockElement !== screenEl) return;
    pendX += e.movementX * sens; pendY -= e.movementY * sens;
  });
  document.addEventListener('pointerlockchange', function () {
    $('lockhint').style.display = document.pointerLockElement ? 'none' : '';
  });

  // touch: drag moves the mouse, buttons below the screen click it
  var lastTouch = null;
  screenEl.addEventListener('touchstart', function (e) {
    audio.start();
    var t = e.touches[0]; lastTouch = { x: t.clientX, y: t.clientY }; e.preventDefault();
  }, { passive: false });
  screenEl.addEventListener('touchmove', function (e) {
    var t = e.touches[0];
    if (lastTouch) { pendX += (t.clientX - lastTouch.x) * sens * 1.5; pendY -= (t.clientY - lastTouch.y) * sens * 1.5; }
    lastTouch = { x: t.clientX, y: t.clientY }; e.preventDefault();
  }, { passive: false });
  screenEl.addEventListener('touchend', function () { lastTouch = null; });

  function holdButton(id, down, up) {
    var el = $(id);
    var on = function (e) { audio.start(); e.preventDefault(); down(); };
    var off = function (e) { e.preventDefault(); up(); };
    el.addEventListener('touchstart', on, { passive: false }); el.addEventListener('mousedown', on);
    el.addEventListener('touchend', off); el.addEventListener('mouseup', off); el.addEventListener('mouseleave', off);
  }
  holdButton('bLeft', function () { m.mouse.left = true; }, function () { m.mouse.left = false; });
  holdButton('bRight', function () { m.mouse.right = true; }, function () { m.mouse.right = false; });
  holdButton('bBoth', function () { m.mouse.left = m.mouse.right = true; }, function () { m.mouse.left = m.mouse.right = false; });
  [['kR', 'KeyR'], ['kT', 'KeyT'], ['kV', 'KeyV'], ['kSpace', 'Space']].forEach(function (k) {
    holdButton(k[0], function () { var c = KEYS[k[1]]; m.setKey(c[0], c[1], true); },
                     function () { var c = KEYS[k[1]]; m.setKey(c[0], c[1], false); });
  });

  window.addEventListener('keydown', function (e) {
    if (e.target.tagName === 'SELECT') return;
    audio.start();
    if (JOY[e.code]) { m.joy2 |= JOY[e.code]; e.preventDefault(); return; }
    var k = KEYS[e.code];
    if (k) { m.setKey(k[0], k[1], true); e.preventDefault(); }
  });
  window.addEventListener('keyup', function (e) {
    if (JOY[e.code]) { m.joy2 &= ~JOY[e.code]; return; }
    var k = KEYS[e.code];
    if (k) m.setKey(k[0], k[1], false);
  });

  // ---- controls --------------------------------------------------------------

  $('program').addEventListener('change', function () { boot(this.value); });
  $('mode').addEventListener('change', function () {
    mode = this.value;
    for (var a in hooks.handlers) if (hooks.handlers[a].fn) hooks.handlers[a].mode = mode;
    log('JS ports now in ' + mode + ' mode');
  });
  $('restart').addEventListener('click', function () { boot(progName); });
  $('overlay').addEventListener('click', function () { boot(progName); });
  $('pause').addEventListener('click', function () { paused = !paused; this.textContent = paused ? 'Resume' : 'Pause'; });
  $('mute').addEventListener('change', function () { audio.setMuted(this.checked); });

  boot('map');
  requestAnimationFrame(tick);
})();
