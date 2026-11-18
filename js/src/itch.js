// The minimal page (js/dist/itch.html, for itch.io): a C64 / C128 selector, then the game
// on the same canvas, with an overlay for the few messages, touch controls, hotkeys, quick
// save / load and the hi-scores. No debugger. See js/README.md ("The itch.io page").
//
//   M mute | Alt+W 5x | Alt+Q 2x | Ctrl+S quick save | Ctrl+L quick load | Ctrl+R back to the selector
'use strict';

(function () {
  var $ = function (id) { return document.getElementById(id); };
  var Video = SentinelVideo, HI = SentinelHiscore, Font = SentinelFont;

  var CONFIG = {
    dma: false,             // the VIC takes its bus cycles, as on the real chip (the timing tests run so)
    sens: 0.5,              // mouse counts per pixel of pointer movement
    touchSens: 0.9,         // touch: counts per game pixel dragged
    overlayMs: 3000,        // how long a message stays, then it fades
    fadeMs: 700,
  };
  // the selector's colours follow the entry that is selected: the C64's own blue / light blue, and the C128
  // C128's start-up screen (light green border and text on a dark gray background)
  var LIGHT_BLUE = 0xFFB55E6C, BLUE = 0xFF792835, LIGHT_GREEN = 0xFF84D29A, DARK_GRAY = 0xFF444444;     // $0E, $06 and $00 as 0xAABBGGRR
  var SCHEME_C64 = { border: LIGHT_BLUE, bg: BLUE, fg: LIGHT_BLUE };
  var SCHEME_C128 = { border: LIGHT_GREEN, bg: DARK_GRAY, fg: LIGHT_GREEN };   // the C128's start-up screen: light green border and text, dark gray background
  var MENU = [
    { label: 'C64', prog: 'c64game', scheme: SCHEME_C64 },
    { label: 'C128', prog: 'game', scheme: SCHEME_C128 },
  ];
  var MENU_X = 64, MENU_Y = 100, MENU_STEP = 40;    // the list in game pixels: double-size characters (16 px)

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
  var canvas = $('vic'), box = $('box'), stage = $('stage'), ovc = $('ov');
  var ctx = canvas.getContext('2d'), ovx = ovc.getContext('2d');
  var img = ctx.createImageData(Video.VIC_W, Video.VIC_H);
  var px = new Uint32Array(img.data.buffer);

  var scene = 'menu';                       // 'menu' | 'game'
  var m = null, hooks = null, prog = null, progName = '', watcher = null;
  var input = null;
  var audio = new SentinelAudio(), audioFrame = 0;
  var store = new HI.Store(safeStorage());
  var sel = 0;
  var speed = 1, fast = false, last = 0, pacer = new SentinelPacing.Pacer();
  var noLock = false;                       // pointer lock refused: use the plain pointer
  var touch = false;

  function safeStorage() {
    try { var s = window.localStorage; s.getItem('x'); return s; } catch (e) { return null; }
  }
  function base64(s) {
    var bin = atob(s), out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  // ---- text in the C64 font ----------------------------------------------------------

  function sc(ch) {                         // ASCII -> screen code (upper case / graphics set)
    var c = ch.charCodeAt(0);
    if (c >= 97 && c <= 122) c -= 32;
    if (c >= 65 && c <= 90) return c - 64;
    return c >= 32 && c <= 63 ? c : 32;
  }

  // ---- the selector ------------------------------------------------------------------

  function menuText(i) { return MENU[i].label + ' - HI ' + HI.pad6(store.get(MENU[i].prog)); }

  function drawMenu() {
    var x, y, i, sch = MENU[sel].scheme;
    for (i = 0; i < px.length; i++) px[i] = sch.border;
    for (y = 36; y < 236; y++) for (x = 32; x < 352; x++) px[y * Video.VIC_W + x] = sch.bg;
    MENU.forEach(function (e, n) {
      var t = menuText(n), inv = n === sel ? 128 : 0;
      for (var c = 0; c < t.length; c++) {
        var code = sc(t[c]) + inv, gx = MENU_X + c * 16, gy = MENU_Y + n * MENU_STEP;
        for (var r = 0; r < 16; r++) {
          var bits = Font.rom[code * 8 + (r >> 1)];
          for (var b = 0; b < 16; b++) px[(gy + r) * Video.VIC_W + gx + b] = (bits & (0x80 >> (b >> 1))) ? sch.fg : sch.bg;
        }
      }
    });
    ctx.putImageData(img, 0, 0); // (px is a view of img.data)
  }

  // which entry is at a canvas position (null: none)
  function menuHit(clientX, clientY) {
    var r = canvas.getBoundingClientRect(), cx = (clientX - r.left) * Video.VIC_W / r.width, cy = (clientY - r.top) * Video.VIC_H / r.height;
    for (var n = 0; n < MENU.length; n++) {
      var x0 = MENU_X - 16, x1 = MENU_X + menuText(n).length * 16 + 16, y0 = MENU_Y + n * MENU_STEP - 12, y1 = y0 + 40;
      if (cx >= x0 && cx < x1 && cy >= y0 && cy < y1) return n;
    }
    return null;
  }

  function showMenu() {
    releaseAll();
    scene = 'menu'; m = null; hooks = null; watcher = null; input = null; fast = false; speed = 1;
    overlay.clear('bottom'); overlay.clear('center'); overlay.clear('top'); overlay.clear('mode');
    if (document.pointerLockElement && document.exitPointerLock) document.exitPointerLock();
    audio.silence();
    stage.classList.remove('game');
    document.body.classList.remove('ingame');
    drawMenu();
  }

  // ---- starting a game ---------------------------------------------------------------

  function startGame(name, viaPointer) {
    progName = name;
    prog = SENTINEL_PROGRAMS[name];
    m = new C128(prog.model);
    m.loadPrg(base64(prog.prg));
    m.dma = CONFIG.dma;
    hooks = new SentinelHooks(m, prog.symbols);
    input = new SentinelInput(m, name === 'c64game' ? hooks : null, showInputMode);
    if (name === 'c64game') hooks.fixC64Original();
    watcher = HI.watch(m, hooks, name, prog.symbols, onGameOver);
    m.start(prog.entry);
    audio.reset(audioFrame * 19656);
    fast = false;
    if (name === 'c64game' && prog.symbols.GAMEENTRY !== undefined) {   // unpack at full speed
      fast = true;
      hooks.on('GAMEENTRY', function () { fast = false; });
    }
    speed = 1; pacer.reset();
    scene = 'game';
    stage.classList.add('game');
    document.body.classList.add('ingame');
    if (viaPointer) lockPointer();
    overlay.clear('bottom');
    overlay.clear('mode');
    if (input.mode) {
      if (viaPointer) input.select('mouse');
      else showInputMode(input.mode);
    }
  }

  function showInputMode(mode) { overlay.show('mode', [mode.toUpperCase()]); }

  function onGameOver(r) {
    var res = store.submit(progName, r.points);
    // one line in the black strip at the very top: the game's own end text fills the rest of the screen
    overlay.show('top', [['SCORE ' + r.text + (res.isNew ? ' NEW HI' : ''), 2]]);
  }

  // ---- running -------------------------------------------------------------------------

  function tick(t) {
    requestAnimationFrame(tick);
    var dt = last ? Math.min(t - last, 250) : 0; last = t;
    if (scene !== 'game' || !m) { pacer.reset(); overlay.draw(); return; }
    var ran = pacer.tick(dt, { speed: speed, isFast: function () { return fast; }, frame: oneFrame, now: function () { return performance.now(); }, budgetMs: 14 }).ran;
    if (ran && m) { px.set(m.video.px); ctx.putImageData(img, 0, 0); }
    overlay.draw();
  }

  // One emulated frame. False when the program has stopped (the page goes back to the selector).
  function oneFrame() {
    input.feed();
    var r = m.run();
    if (r === 'frame') {
      if (!fast && speed === 1) audio.frame(m, audioFrame++ * 19656);
      return true;
    }
    overlay.show('tl', ['STOPPED'], { scale: 2 });
    showMenu();
    return false;
  }

  function setSpeed(s) {
    if (s === speed) return;
    speed = s; pacer.reset();
    audio.silence();                          // the SID log is only played at normal speed
    if (speed === 1) overlay.clear('bottom'); else overlay.show('bottom', [speed === 2 ? '>>' : '>>>>>'], { scale: 2, sticky: true });
  }

  // ---- quick save / load -----------------------------------------------------------------

  var SAVE_KEY = 'sentinel-itch-state-';
  function buildSig() {                       // a state is only loaded into the build that saved it
    var s = prog.prg, h = 2166136261;
    for (var i = 0; i < s.length; i += 7) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
    return 'v1-' + (h >>> 0).toString(16);
  }
  var memSaves = {};                          // where the browser gives no storage (a sandboxed frame): this visit only
  function quickSave() {
    if (scene !== 'game' || !m) return;
    var text;
    try { text = buildSig() + '|' + m.stateToText(); } catch (e) { overlay.show('tl', ['SAVE FAILED'], { scale: 2 }); return; }
    memSaves[progName] = text;
    try { window.localStorage.setItem(SAVE_KEY + progName, text); } catch (e) { /* kept in memory */ }
    overlay.show('tl', ['SAVED'], { scale: 2 });
  }
  function quickLoad() {
    if (scene !== 'game' || !m) return;
    var t = null, sig = buildSig();
    try { t = window.localStorage.getItem(SAVE_KEY + progName); } catch (e) { t = null; }
    if (!t || t.indexOf(sig + '|') !== 0) t = memSaves[progName] || null;
    if (!t || t.indexOf(sig + '|') !== 0) { overlay.show('tl', ['NO SAVE'], { scale: 2 }); return; }
    try {
      m.loadState(m.stateFromText(t.slice(sig.length + 1)));
      m.stopped = null; fast = false;
      releaseAll();
      input.afterLoad();
      audio.reset(audioFrame * 19656);
      if (watcher) watcher.rearm();
      overlay.show('tl', ['LOADED'], { scale: 2 });
    } catch (e) { overlay.show('tl', ['LOAD FAILED'], { scale: 2 }); }
  }

  // ---- overlay: big white pixel text over the game ------------------------------------------
  // Slots include 'tl' (hotkeys and pointer hint), 'mode' (input), 'top' (score), and 'bottom' (speed).

  var overlay = (function () {
    var slots = {}, w = 0, h = 0, dirty = false;
    function resize() {
      var r = box.getBoundingClientRect(), d = window.devicePixelRatio || 1;
      w = Math.max(1, Math.round(r.width * d)); h = Math.max(1, Math.round(r.height * d));
      if (ovc.width !== w || ovc.height !== h) { ovc.width = w; ovc.height = h; }
      dirty = true;
    }
    // lines: strings (at o.scale, default 2 = 16 game pixels tall) or [string, scale]
    function show(slot, lines, o) {
      o = o || {};
      slots[slot] = { lines: lines.map(function (l) { return typeof l === 'string' ? [l, o.scale || 2] : l; }), sticky: !!o.sticky, plain: !!o.plain, until: performance.now() + CONFIG.overlayMs };
      dirty = true;
    }
    function clear(slot) { if (slots[slot]) { delete slots[slot]; dirty = true; } }
    function glyphs(g, text, x, y, u) {       // one line: x, y in device px of the top-left, u = device px per font pixel
      for (var i = 0; i < text.length; i++) {
        var code = sc(text[i]);
        for (var r = 0; r < 8; r++) {
          var bits = Font.rom[code * 8 + r];
          if (!bits) continue;
          for (var b = 0; b < 8; b++) {
            if (!(bits & (0x80 >> b))) continue;
            var x0 = Math.round(x + (i * 8 + b) * u), y0 = Math.round(y + r * u);
            g.rect(x0, y0, Math.round(x + (i * 8 + b + 1) * u) - x0, Math.round(y + (r + 1) * u) - y0);
          }
        }
      }
    }
    function draw() {
      var now = performance.now(), any = false, name;
      for (name in slots) {
        var s = slots[name];
        if (!s.sticky && now >= s.until + CONFIG.fadeMs) delete slots[name]; else any = true;
      }
      if (!any && !dirty) return;
      if (w === 0) resize();
      ovx.clearRect(0, 0, w, h);
      dirty = any;                            // keep redrawing while something fades
      var unit = w / Video.VIC_W;             // device px per game pixel
      for (name in slots) {
        var s2 = slots[name], total = 0, y = 0, us = s2.lines.map(function (l) {
          var u = Math.min(unit * l[1], 0.94 * w / (l[0].length * 8));   // a long line shrinks to fit
          total += 10 * u; return u;
        });
        var alpha = (s2.sticky || now < s2.until) ? 1 : Math.max(0, 1 - (now - s2.until) / CONFIG.fadeMs);
        ovx.globalAlpha = alpha * 0.95;
        ovx.fillStyle = '#fff'; ovx.shadowBlur = 0;                      // plain text, no glow
        ovx.beginPath();
        var y0 = name === 'tl' ? 14 * unit : name === 'mode' ? 34 * unit : name === 'top' ? 2 * unit : name === 'bottom' ? h - 20 * unit - total : (h - total) / 2;
        for (var li = 0; li < s2.lines.length; li++) {
          var t = s2.lines[li][0], u = us[li], right = w - t.length * 8 * u;
          var x = name === 'tl' ? 14 * unit : name === 'mode' ? right - 14 * unit : right / 2;
          glyphs(ovx, t, x, y0 + y, u);
          y += 10 * u;
        }
        ovx.fill();
      }
      ovx.globalAlpha = 1; ovx.shadowBlur = 0;
    }
    window.addEventListener('resize', resize);
    if (window.ResizeObserver) new ResizeObserver(resize).observe(box);
    return { show: show, clear: clear, draw: draw, resize: resize };
  })();

  // ---- pointer: mouse (captured), touch (drag to aim, buttons) -------------------------------

  // Capturing the mouse can be refused (a sandboxed frame, no focus, a browser without it): after two
  // requests that came to nothing the page uses the plain pointer instead.
  var lockPending = false, lockFails = 0;
  function lockFailed() {
    if (!lockPending) return;
    lockPending = false;
    if (++lockFails >= 2) noLock = true;
  }
  function lockPointer() {
    if (noLock || document.pointerLockElement === canvas) return;
    if (!canvas.requestPointerLock) { noLock = true; return; }
    lockPending = true;
    try { var p = canvas.requestPointerLock(); if (p && p.catch) p.catch(lockFailed); } catch (e) { lockFailed(); }
    setTimeout(lockFailed, 600);
  }
  document.addEventListener('pointerlockerror', lockFailed);
  document.addEventListener('pointerlockchange', function () {
    if (document.pointerLockElement === canvas) {
      lockPending = false; lockFails = 0;
      overlay.show('tl', ['ESC - RELEASE MOUSE'], { scale: 2, plain: true });
    } else if (input) input.clearButtons('mouse');
  });

  function setTouch(on) {
    if (touch === on) return;
    touch = on; document.body.classList.toggle('touch', on);
  }
  try { if (window.matchMedia && window.matchMedia('(pointer: coarse)').matches) setTouch(true); } catch (e) { /* ignore */ }

  var aim = null;                             // the touch that drags the crosshair
  stage.addEventListener('pointerdown', function (e) {
    try { window.focus(); } catch (err) { /* ignore */ }
    if (e.pointerType === 'touch' || e.pointerType === 'pen') setTouch(true);
    if (scene === 'game' && e.pointerType !== 'mouse' && !aim) {
      aim = { id: e.pointerId, x: e.clientX, y: e.clientY };
      try { stage.setPointerCapture(e.pointerId); } catch (err) { /* ignore */ }
      e.preventDefault();
    }
  });
  // Unlike pointerdown/up, mouse events report each button in a chord.
  stage.addEventListener('mousedown', function (e) {
    if (!input || scene !== 'game' || (e.button !== 0 && e.button !== 2)) return;
    if (document.pointerLockElement !== canvas && !noLock) {
      lockPointer();
      if (!input.mode) { e.preventDefault(); return; }
    }
    input.setButton('mouse', e.button === 0 ? 'left' : 'right', true);
    e.preventDefault();
  });
  window.addEventListener('mouseup', function (e) {
    if (input && (e.button === 0 || e.button === 2)) input.setButton('mouse', e.button === 0 ? 'left' : 'right', false);
  });
  window.addEventListener('pointerup', function (e) {
    if (aim && aim.id === e.pointerId) aim = null;
  });
  window.addEventListener('pointercancel', function (e) { if (aim && aim.id === e.pointerId) aim = null; });
  stage.addEventListener('pointerdown', function (e) {       // touch: the touched entry shows its colours at once
    if (scene !== 'menu' || e.pointerType === 'mouse') return;
    var n = menuHit(e.clientX, e.clientY);
    if (n !== null && n !== sel) { sel = n; drawMenu(); }
  });
  stage.addEventListener('pointermove', function (e) {
    if (scene === 'menu' && e.pointerType === 'mouse') {
      var n = menuHit(e.clientX, e.clientY);
      if (n !== null && n !== sel) { sel = n; drawMenu(); }
      return;
    }
    if (aim && aim.id === e.pointerId && scene === 'game') {
      var k = Video.VIC_W / (box.getBoundingClientRect().width || Video.VIC_W) * CONFIG.touchSens;
      input.move((e.clientX - aim.x) * k, (aim.y - e.clientY) * k);
      aim.x = e.clientX; aim.y = e.clientY;
      e.preventDefault();
    }
  });
  document.addEventListener('mousemove', function (e) {
    if (scene !== 'game' || !m) return;
    if (document.pointerLockElement === canvas || (!document.pointerLockElement && (noLock || input.mode) && stage.contains(e.target))) {
      input.move(e.movementX * CONFIG.sens, -e.movementY * CONFIG.sens);
    }
  });
  stage.addEventListener('click', function (e) {
    if (scene !== 'menu') return;
    var n = menuHit(e.clientX, e.clientY);
    if (n !== null) { sel = n; startGame(MENU[n].prog, !touch); }   // (a click may capture the mouse)
  });
  stage.addEventListener('contextmenu', function (e) { e.preventDefault(); });

  // touch buttons: FIRE = left, MAP = right, TORPEDO = both (the mouse buttons, as the game reads them)
  [['fire', 'left'], ['map', 'right'], ['torp', 'both']].forEach(function (b) {
    var el = $('b-' + b[0]);
    function dn(e) { e.preventDefault(); e.stopPropagation(); try { el.setPointerCapture(e.pointerId); } catch (err) { /* ignore */ } if (input) input.setButton(el, b[1], true); el.classList.add('down'); audioGesture(); }
    function up(e) { e.preventDefault(); if (input) input.setButton(el, b[1], false); el.classList.remove('down'); }
    el.addEventListener('pointerdown', dn);
    el.addEventListener('pointerup', up);
    el.addEventListener('pointercancel', up);
    el.addEventListener('lostpointercapture', up);
  });

  // ---- keyboard --------------------------------------------------------------------------------

  var altTimer = 0, altHeld = false, altSent = false, suppress = { AltLeft: false, ControlLeft: false };

  function setKeyCode(code, on) {
    var k = KEYS[code];
    if (k && m) m.setKey(k[0], k[1], on);
  }
  function mod(e) { return e.ctrlKey || e.altKey || e.metaKey; }

  // A hotkey was used: the game must not see the modifier that came with it
  function swallowModifiers() {
    clearTimeout(altTimer);
    if (altHeld) suppress.AltLeft = true;
    suppress.ControlLeft = true;
    setKeyCode('AltLeft', false); setKeyCode('ControlLeft', false);
    if (input) input.setJoystick('ControlRight', false);
    altSent = false;
  }

  function toggleMute() {
    audio.setMuted(!audio.muted);
    overlay.show('tl', [audio.muted ? 'MUTE ON' : 'MUTE OFF'], { scale: 2 });
  }

  function audioGesture() { if (!audio.running()) audio.start(); }
  ['keydown', 'pointerdown', 'pointerup', 'touchend', 'click'].forEach(function (n) {
    window.addEventListener(n, audioGesture, true);
  });

  window.addEventListener('keydown', function (e) {
    var code = e.code;
    // hotkeys (always: the browser's own meaning is cancelled)
    if (e.ctrlKey && !e.altKey && !e.metaKey && (code === 'KeyS' || code === 'KeyL' || code === 'KeyR')) {
      e.preventDefault();
      if (e.repeat) return;
      if (scene === 'game') {
        swallowModifiers();
        if (code === 'KeyS') quickSave(); else if (code === 'KeyL') quickLoad();
        else { overlay.show('tl', ['RESET'], { scale: 2 }); showMenu(); }
      }
      return;
    }
    if (e.altKey && !e.ctrlKey && !e.metaKey && (code === 'KeyW' || code === 'KeyQ')) {
      e.preventDefault();
      if (e.repeat || scene !== 'game') return;
      swallowModifiers();
      setSpeed(code === 'KeyW' ? (speed === 5 ? 1 : 5) : (speed === 2 ? 1 : 2));
      return;
    }
    if (code === 'KeyM' && !mod(e)) {
      e.preventDefault();
      if (!e.repeat) toggleMute();
      return;
    }
    if (scene === 'menu') {
      var handled = true;
      if (code === 'ArrowUp') { sel = (sel + MENU.length - 1) % MENU.length; drawMenu(); }
      else if (code === 'ArrowDown') { sel = (sel + 1) % MENU.length; drawMenu(); }
      else if (code === 'Enter' || code === 'NumpadEnter' || code === 'Space' || code === 'ControlRight' || code === 'Numpad0') {
        if (!e.repeat) startGame(MENU[sel].prog, false);
      }
      else if (code === 'Digit1' || code === 'Numpad1') { sel = 0; startGame(MENU[0].prog, false); }
      else if (code === 'Digit2' || code === 'Numpad2') { sel = 1; startGame(MENU[1].prog, false); }
      else handled = false;
      if (handled) e.preventDefault();
      return;
    }
    if (!m) return;
    if (SentinelInput.isJoystick(code)) { input.setJoystick(code, true, e.repeat); e.preventDefault(); return; }
    if (!KEYS[code]) return;
    e.preventDefault();
    if (code === 'AltLeft') {                // Alt is the C= key: held back briefly, in case it starts Alt+W / Alt+Q
      if (e.repeat) return;
      altHeld = true; suppress.AltLeft = false; altSent = false;
      clearTimeout(altTimer);
      altTimer = setTimeout(function () { if (altHeld && !suppress.AltLeft) { setKeyCode('AltLeft', true); altSent = true; } }, 120);
      return;
    }
    if (suppress[code]) return;
    setKeyCode(code, true);
  });

  window.addEventListener('keyup', function (e) {
    var code = e.code;
    if (code === 'AltLeft') {
      e.preventDefault();
      clearTimeout(altTimer);
      if (altHeld && !altSent && !suppress.AltLeft && m) {   // a quick tap: still a press, long enough to be seen
        setKeyCode('AltLeft', true);
        setTimeout(function () { setKeyCode('AltLeft', false); }, 80);
      } else setKeyCode('AltLeft', false);
      altHeld = false; altSent = false; suppress.AltLeft = false;
      return;
    }
    if (code === 'ControlLeft') suppress.ControlLeft = false;
    if (!m) return;
    if (SentinelInput.isJoystick(code)) { input.setJoystick(code, false); return; }
    if (KEYS[code]) setKeyCode(code, false);
  });

  function releaseAll() {
    clearTimeout(altTimer); altHeld = altSent = false; suppress.AltLeft = suppress.ControlLeft = false;
    aim = null;
    if (m) { m.keys.fill(0); input.release(); }
    ['fire', 'map', 'torp'].forEach(function (n) { $('b-' + n).classList.remove('down'); });
  }
  window.addEventListener('blur', releaseAll);
  document.addEventListener('visibilitychange', function () { if (document.hidden) releaseAll(); else last = 0; });

  // ---- go --------------------------------------------------------------------------------------

  overlay.resize();
  drawMenu();
  requestAnimationFrame(tick);

  window.SentinelItch = {           // for tests and the console
    state: function () { return { scene: scene, prog: progName, inputMode: input ? input.mode : null, speed: speed, fast: fast, frame: m ? m.frame : 0, audio: audio.kind, running: audio.running(), touch: touch }; },
    audio: audio, store: store, machine: function () { return m; }, start: startGame, menu: showMenu,
    frames: function (n) {          // n emulated frames at once, then draw (a page whose animation frames are throttled)
      for (var i = 0; i < n && m; i++) if (!oneFrame()) return;
      if (m) { px.set(m.video.px); ctx.putImageData(img, 0, 0); }
      overlay.draw();
    },
  };
})();
