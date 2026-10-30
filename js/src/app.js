// Browser front end: runs a program 50 times a second (or faster), draws the
// VIC and VDC screens, feeds mouse / touch / keyboard input, plays the SID log,
// and drives the debugger panels (CPU, watches, cheats, events, monitor,
// hooks, log, save states).
'use strict';

(function () {
  var $ = function (id) { return document.getElementById(id); };
  var Video = SentinelVideo, Dis = SentinelDisasm, h2 = Dis.h2, h4 = Dis.h4;

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

  var m = null, hooks = null, dbg = null, prog = null, progName = 'game', profile = null;
  var audio = new SentinelAudio(), audioFrame = 0;
  var vicCtx = $('vic').getContext('2d'), vdcCtx = $('vdc').getContext('2d');
  var vicImg = vicCtx.createImageData(Video.VIC_W, Video.VIC_H);
  var vdcImg = vdcCtx.createImageData(Video.VDC_W, Video.VDC_H);
  var vicPx = new Uint32Array(vicImg.data.buffer), vdcPx = new Uint32Array(vdcImg.data.buffer);
  var pendX = 0, pendY = 0, sens = 0.5;
  var running = true, fast = false, framesLeft = 0, mode = 'verify';
  var lastBreak = null;

  function boot(name) {
    progName = name;
    prog = SENTINEL_PROGRAMS[name];
    profile = SentinelProfiles[name];
    m = new C128(prog.model);
    m.loadPrg(base64(prog.prg));
    hooks = new SentinelHooks(m, prog.symbols);
    SentinelNative.install(hooks, mode);
    hooks.onMismatch = function (r) { dbg.say('mismatch in ' + r.name + ' (frame ' + r.frame + '): ' + r.diffs.join('; '), 'mismatch'); };
    ['STEP', 'DRAWCELL', 'TICK', 'MOVEPASS', 'CURSOR', 'VDCDRAW', 'MOVESTAR', 'DRAW7', 'ERASE7',
     'INPUT', 'STARS', 'GUNS', 'SPRCROSS', 'SPRGUNS', 'IRQ', 'LINE', 'PLOT', 'GAMEOVERCHK']
      .forEach(function (n) { if (prog.symbols[n] !== undefined) hooks.trace(n); });
    $('log').textContent = '';
    dbg = new SentinelDebugger(m, hooks, name, profile);
    dbg.onLog = logLine;
    m.start(prog.entry);
    audio.reset(audioFrame * 19656);
    fast = false;
    if (profile.fastStart) {               // unpack at full speed
      fast = true;
      hooks.on(profile.fastStart, function () { fast = false; });
    }
    running = true; framesLeft = 0; lastBreak = null;
    $('vdcwrap').style.display = name === 'map' ? '' : 'none';
    $('victag').textContent = prog.model === 'c64' ? 'VIC-II · C64' : 'VIC-IIe · 40 col';
    $('help').textContent = profile.help;
    setDownload();
    $('overlay').style.display = 'none';
    $('memaddr').value = prog.symbols.SHIELDS !== undefined ? 'SHIELDS' : (prog.symbols.CURX !== undefined ? 'CURX' : '$1D00');
    buildKeys(); showPad(); buildCheats(); buildEvents(); buildWatches();
    $('conout').textContent = '';
    con(prog.model.toUpperCase() + ' · ' + profile.title + ' · ' + Object.keys(prog.symbols).length + ' labels. Type help.');
    refresh(true);
  }

  // The link downloads the running program's own PRG, from the bytes embedded in the page.
  var downloadUrl = null;
  function setDownload() {
    var a = $('download');
    if (downloadUrl) URL.revokeObjectURL(downloadUrl);
    downloadUrl = URL.createObjectURL(new Blob([base64(prog.prg)], { type: 'application/octet-stream' }));
    a.href = downloadUrl;
    a.download = prog.file;
    a.textContent = 'Download ' + prog.file;
    a.title = prog.model === 'c64' ? 'For a C64 or x64sc: LOAD and RUN' : 'For a C128 or x128 in C128 mode: LOAD and RUN';
  }

  function base64(s) {
    var bin = atob(s), out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  function logLine(e) {
    var el = $('log');
    if (el.childNodes.length > 200) el.removeChild(el.firstChild);
    var d = document.createElement('div');
    d.className = e.kind; d.textContent = e.frame + '  ' + e.text;
    el.appendChild(d); el.scrollTop = el.scrollHeight;
  }

  // ---- running ----------------------------------------------------------------

  var last = 0, acc = 0, FRAME_MS = 1000 / 50;
  function tick(t) {
    requestAnimationFrame(tick);
    if (!last) last = t;
    var dt = t - last; last = t;
    if (!running || !m) { acc = 0; return; }
    var speed = $('speed').value, budgetEnd = performance.now() + 14, n;
    if (fast || speed === 'max') n = 1000;
    else { acc = Math.min(acc + dt * +speed, FRAME_MS * 4 * +speed); n = Math.floor(acc / FRAME_MS); acc -= n * FRAME_MS; }
    var ran = 0;
    for (var i = 0; i < n; i++) {
      if (!oneFrame()) break;
      ran++;
      if (framesLeft && --framesLeft === 0) { pause(); break; }
      if ((fast || speed === 'max') && performance.now() > budgetEnd) break;
    }
    if (ran) draw();
    if (ran && m.frame % 5 === 0) refresh(false);
  }

  // Run to the end of the frame. Returns false when the machine stopped or broke.
  function oneFrame() {
    feedMouse();
    var r = m.run();
    if (r === 'frame') {
      if (!fast && $('speed').value === '1') audio.frame(m, audioFrame++ * 19656);
      dbg.sample();
      return true;
    }
    if (r === 'break') { onBreak(); return false; }
    stopped();
    return false;
  }

  function onBreak() {
    var b = m.breakInfo || {};
    lastBreak = b;
    var why = b.type === 'watch' ? 'write to ' + dbg.name(b.addr) + ': $' + h2(b.old) + ' -> $' + h2(b.value) + ' by $' + h4(b.pc)
            : b.type === 'event' ? 'event: ' + b.name
            : 'breakpoint at ' + dbg.name(b.pc);
    dbg.say('Paused, ' + why, 'break');
    pause();
  }

  function pause() {
    running = false; framesLeft = 0;
    $('run').textContent = 'Run';
    m.video.renderTo(m.rasterLine());
    draw(); refresh(true);
  }
  function resume() {
    if (m.stopped) return;
    running = true; lastBreak = null;
    $('run').textContent = 'Pause';
    refresh(true);
  }

  function stepInstr(n) {
    if (running) pause();
    for (var i = 0; i < (n || 1); i++) {
      var r = m.stepInstruction();
      if (r === 'frame') dbg.sample();
      if (r === 'break') { onBreak(); return; }
      if (r === 'stopped') { stopped(); return; }
    }
    lastBreak = null;
    m.video.renderTo(m.rasterLine());
    draw(); refresh(true);
  }

  function stepFrames(n) {
    if (running) pause();
    lastBreak = null;
    for (var i = 0; i < n; i++) if (!oneFrame()) return;
    draw(); refresh(true);
  }

  function feedMouse() {
    // the 1351 reports 6 bits per axis; keep each frame's step inside that
    var dx = Math.max(-24, Math.min(24, Math.trunc(pendX)));
    var dy = Math.max(-24, Math.min(24, Math.trunc(pendY)));
    pendX -= dx; pendY -= dy;
    m.moveMouse(dx, dy);
  }

  function draw() {
    vicPx.set(m.video.px);
    vicCtx.putImageData(vicImg, 0, 0);
    if (!running && m.frameOpen) {           // paused inside a frame: show the beam
      var y = m.rasterLine() - 15;
      if (y >= 0 && y < Video.VIC_H) {
        vicCtx.fillStyle = 'rgba(255,60,40,0.85)';
        vicCtx.fillRect(0, y, Video.VIC_W, 1);
      }
    }
    if (progName === 'map') {
      Video.renderVdc(m, vdcPx, (m.frame >> 4) & 1);
      vdcCtx.putImageData(vdcImg, 0, 0);
    }
  }

  function stopped() {
    running = false;
    $('run').textContent = 'Run';
    $('overlay').style.display = '';
    $('overlay').textContent = (m.stopped === 'returned to BASIC' ? 'Returned to BASIC' : 'Stopped: ' + m.stopped) + ' - tap to restart';
    refresh(true);
  }

  // ---- panels -----------------------------------------------------------------

  function refresh(full) {
    if (!debugOn) return;                 // the panels are hidden
    // status line
    var st = $('status');
    var where = 'frame <b>' + m.frame + '</b> · line <b>' + m.rasterLine() + '</b> · PC <b>$' + h4(m.cpu.pc) + '</b>';
    var lbl = dbg.label(m.cpu.pc);
    if (lbl) where += ' ' + lbl;
    st.innerHTML = (fast ? 'Unpacking at full speed · ' : running ? 'Running · ' : '<span class="brk">Paused</span> · ') + where;
    $('framectr').textContent = 'frame ' + m.frame;
    $('breakwhy').textContent = lastBreak ? (lastBreak.type === 'watch' ? 'stopped by a write watch' : lastBreak.type === 'event' ? 'stopped by ' + lastBreak.name : 'breakpoint') : '';
    $('regs').textContent = dbg.registers();
    renderDisasm();
    renderWatches();
    renderEventCounts();
    renderHooks();
    renderMem();
  }

  function renderDisasm() {
    var pc = m.cpu.pc, peek = function (a) { return m.peek(a); };
    var start = Dis.backFrom(peek, pc, 4);
    var lines = dbg.disasm(start, 14);
    var html = lines.map(function (d) {
      var l = dbg.label(d.pc);
      return '<div data-a="' + d.pc + '" class="' + (d.pc === pc ? 'pc' : '') + '">' +
        '<span class="bp">' + (m.bpAt[d.pc] ? '●' : ' ') + '</span> $' + h4(d.pc) + '  ' +
        esc(d.bytes.map(h2).join(' ').padEnd(9)) + ' ' + esc(d.text) +
        (l ? '  <span class="lbl">' + esc(l) + '</span>' : '') + '</div>';
    }).join('');
    $('dis').innerHTML = html;
  }
  $('dis').addEventListener('click', function (e) {
    var row = e.target.closest('[data-a]');
    if (!row) return;
    var a = +row.dataset.a;
    m.setBreak(a, !m.bpAt[a]);
    dbg.say((m.bpAt[a] ? 'Breakpoint at ' : 'Breakpoint removed at ') + dbg.name(a), 'info');
    renderDisasm();
  });

  function esc(s) { return String(s).replace(/[&<>]/g, function (c) { return c === '&' ? '&amp;' : c === '<' ? '&lt;' : '&gt;'; }); }

  // watches: value (click to edit), history, freeze
  function buildWatches() {
    var t = $('watches');
    t.innerHTML = '<tr><th>name</th><th>address</th><th>value</th><th>last 5 s</th><th>freeze</th><th></th></tr>';
    dbg.watches.forEach(function (w, i) {
      var tr = document.createElement('tr');
      tr.innerHTML = '<td>' + esc(w.name) + '</td><td>$' + h4(w.addr) + (w.size > 1 ? '+' + w.size : '') + '</td><td class="val"></td><td><canvas width="96" height="22"></canvas></td>' +
        '<td><input type="checkbox" aria-label="Freeze ' + esc(w.name) + '"></td><td><button class="x" type="button" aria-label="Remove">×</button></td>';
      var val = tr.children[2], fr = tr.querySelector('input'), x = tr.querySelector('button');
      w.el = { val: val, canvas: tr.querySelector('canvas'), freeze: fr };
      val.addEventListener('click', function () {
        if (val.querySelector('input')) return;
        var inp = document.createElement('input'); inp.type = 'text'; inp.value = dbg.value(w);
        val.textContent = ''; val.appendChild(inp); inp.focus(); inp.select();
        var done = function (ok) {
          if (ok && inp.value.trim() !== '') {
            var v = /^\$/.test(inp.value.trim()) ? parseInt(inp.value.trim().slice(1), 16) : parseInt(inp.value, 10);
            if (!isNaN(v)) { dbg.setWatch(w, v); dbg.say('Set ' + w.name + ' = ' + v, 'info'); }
          }
          val.textContent = dbg.text(w);
        };
        inp.addEventListener('keydown', function (e) { if (e.key === 'Enter') done(true); if (e.key === 'Escape') done(false); });
        inp.addEventListener('blur', function () { done(true); });
      });
      fr.addEventListener('change', function () { dbg.freezeWatch(w, fr.checked); dbg.say((fr.checked ? 'Frozen ' : 'Unfrozen ') + w.name, 'cheat'); });
      x.addEventListener('click', function () { dbg.removeWatch(i); buildWatches(); });
      t.appendChild(tr);
    });
    renderWatches();
  }

  var sparkInk = null;
  function renderWatches() {
    if (!sparkInk) {
      var cs = getComputedStyle(document.documentElement);
      sparkInk = { line: cs.getPropertyValue('--accent').trim() || '#b5562c', dot: cs.getPropertyValue('--ink').trim() || '#222' };
    }
    dbg.watches.forEach(function (w) {
      if (!w.el) return;
      if (!w.el.val.querySelector('input')) w.el.val.textContent = dbg.text(w);
      w.el.freeze.checked = dbg.frozen(w);
      var c = w.el.canvas, g = c.getContext('2d'), n = w.filled;
      g.clearRect(0, 0, c.width, c.height);
      if (n < 2) return;
      var lo = Infinity, hi = -Infinity, i, v;
      for (i = 0; i < n; i++) { v = w.hist[(w.pos - n + i + 240) % 240]; if (v < lo) lo = v; if (v > hi) hi = v; }
      var span = hi - lo || 1;
      g.strokeStyle = sparkInk.line; g.lineWidth = 1.5; g.beginPath();
      for (i = 0; i < n; i++) {
        v = w.hist[(w.pos - n + i + 240) % 240];
        var x = (i / 239) * (c.width - 4) + 2, y = c.height - 3 - ((v - lo) / span) * (c.height - 6);
        if (i) g.lineTo(x, y); else g.moveTo(x, y);
      }
      g.stroke();
      g.fillStyle = sparkInk.dot; g.beginPath(); g.arc(x, y, 2, 0, 7); g.fill();
    });
  }

  $('addwatch').addEventListener('submit', function (e) {
    e.preventDefault();
    var t = $('watchaddr').value.trim();
    if (!t) return;
    try { dbg.addWatch(t); $('watchaddr').value = ''; buildWatches(); }
    catch (err) { dbg.say(err.message, 'mismatch'); }
  });

  function buildCheats() {
    var box = $('cheats');
    box.innerHTML = '';
    if (!profile.cheats.length) { box.innerHTML = '<p class="empty">No cheats for this program. Freeze any watch instead.</p>'; return; }
    profile.cheats.forEach(function (c) {
      var id = 'cheat-' + c.id;
      var el = document.createElement('label');
      el.className = 'toggle'; el.htmlFor = id;
      el.innerHTML = '<input type="checkbox" id="' + id + '"><span>' + esc(c.name) + '</span><small>' + esc(c.help) + '</small>';
      el.querySelector('input').addEventListener('change', function () { dbg.setCheat(c.id, this.checked); refresh(false); });
      box.appendChild(el);
    });
  }

  function buildEvents() {
    var box = $('events');
    box.innerHTML = '';
    if (!profile.events.length) { box.innerHTML = '<p class="empty">No events defined.</p>'; return; }
    profile.events.forEach(function (e, i) {
      var row = document.createElement('div');
      row.className = 'evrow';
      var on = !!dbg.eventsOn[e.name], pause = on && dbg.eventsOn[e.name].pause;
      row.innerHTML = '<span title="' + esc(e.at) + '">' + esc(e.name) + '</span><span class="n">0</span>' +
        '<input type="checkbox" aria-label="Log ' + esc(e.name) + '"' + (on ? ' checked' : '') + '>' +
        '<input type="checkbox" aria-label="Pause on ' + esc(e.name) + '"' + (pause ? ' checked' : '') + '>';
      var boxes = row.querySelectorAll('input');
      var upd = function () { dbg.setEvent(e, boxes[0].checked || boxes[1].checked, boxes[1].checked); if (boxes[1].checked) boxes[0].checked = true; };
      boxes[0].addEventListener('change', upd); boxes[1].addEventListener('change', upd);
      e.countEl = row.querySelector('.n');
      box.appendChild(row);
    });
  }
  function renderEventCounts() {
    profile.events.forEach(function (e) { if (e.countEl) e.countEl.textContent = dbg.eventsOn[e.name] ? dbg.eventsOn[e.name].count : '–'; });
  }

  function renderHooks() {
    var rows = [];
    for (var a in hooks.handlers) {
      var h = hooks.handlers[a];
      var state = !h.fn ? 'trace' : h.mode === 'trace' ? 'off' : h.mode === 'replace' ? (h.fn.length === 0 ? 'skipped' : 'JS') : (h.failed ? h.failed + ' FAIL' : h.verified + ' ok');
      rows.push('<tr><td>' + esc(h.name) + '</td><td>$' + h4(h.addr) + '</td><td>' + h.callsLastFrame + '</td><td class="' +
        (h.fn && h.mode === 'verify' ? (h.failed ? 'bad' : 'good') : '') + '">' + state + '</td></tr>');
    }
    $('hooks').innerHTML = '<tr><th>label</th><th>addr</th><th>calls/frame</th><th>state</th></tr>' + rows.join('');
  }

  function renderMem() {
    var a;
    try { a = dbg.parse($('memaddr').value); } catch (e) { $('mem').textContent = e.message; return; }
    $('mem').textContent = dbg.dump(a & 0xFFF0, 6).join('\n');
  }
  $('memaddr').addEventListener('input', renderMem);

  // ---- monitor console ----------------------------------------------------------

  var history = [], hpos = 0;
  function con(text, cls) {
    var out = $('conout'), d = document.createElement('div');
    if (cls) d.className = cls;
    d.textContent = text;
    out.appendChild(d);
    while (out.childNodes.length > 400) out.removeChild(out.firstChild);
    out.scrollTop = out.scrollHeight;
  }
  $('conform').addEventListener('submit', function (e) {
    e.preventDefault();
    var line = $('conin').value;
    $('conin').value = '';
    if (line.trim()) { history.push(line); hpos = history.length; }
    con('> ' + line, 'cmd');
    var out;
    try { out = dbg.exec(line); } catch (err) { out = [err.message]; }
    out.forEach(function (l) { con(l); });
    if (dbg.stepRequest) {
      var s = dbg.stepRequest; dbg.stepRequest = null;
      if (s.kind === 'instr') stepInstr(s.n); else stepFrames(s.n);
      con(dbg.registers());
    }
    if (dbg.resumeRequested) { dbg.resumeRequested = false; resume(); }
    if (/^(fr|uf|show)\b/.test(line.trim())) buildWatches();
    refresh(true);
  });
  $('conin').addEventListener('keydown', function (e) {
    if (e.key === 'ArrowUp' && hpos > 0) { this.value = history[--hpos]; e.preventDefault(); }
    if (e.key === 'ArrowDown') { hpos = Math.min(history.length, hpos + 1); this.value = history[hpos] || ''; e.preventDefault(); }
  });

  // ---- input ---------------------------------------------------------------------

  var screenEl = $('screen');
  screenEl.addEventListener('mousedown', function (e) {
    audio.start();
    if (!document.pointerLockElement && screenEl.requestPointerLock) {
      try { var p = screenEl.requestPointerLock(); if (p && p.catch) p.catch(function () {}); } catch (err) { /* not allowed */ }
      return;
    }
    if (e.button === 0) m.mouse.left = true;
    if (e.button === 2) m.mouse.right = true;
    e.preventDefault();
  });
  window.addEventListener('mouseup', function (e) {
    if (!m) return;
    if (e.button === 0) m.mouse.left = false;
    if (e.button === 2) m.mouse.right = false;
  });
  screenEl.addEventListener('contextmenu', function (e) { e.preventDefault(); });
  document.addEventListener('mousemove', function (e) {
    if (document.pointerLockElement !== screenEl || !running) return;
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
    if (lastTouch && running) { pendX += (t.clientX - lastTouch.x) * sens * 1.5; pendY -= (t.clientY - lastTouch.y) * sens * 1.5; }
    lastTouch = { x: t.clientX, y: t.clientY }; e.preventDefault();
  }, { passive: false });
  screenEl.addEventListener('touchend', function () { lastTouch = null; });

  function buildKeys() {
    var box = $('keys');
    box.innerHTML = '';
    profile.keys.forEach(function (k) {
      var b = document.createElement('button');
      b.type = 'button'; b.textContent = k.label;
      if (k.mouse) b.className = 'mouse';
      var down = function () {
        if (k.mouse === 'left' || k.mouse === 'both') m.mouse.left = true;
        if (k.mouse === 'right' || k.mouse === 'both') m.mouse.right = true;
        if (k.key) { var c = KEYS[k.key]; m.setKey(c[0], c[1], true); }
      };
      var up = function () {
        if (k.mouse) { m.mouse.left = false; m.mouse.right = false; }
        if (k.key) { var c = KEYS[k.key]; m.setKey(c[0], c[1], false); }
      };
      var on = function (e) { audio.start(); e.preventDefault(); down(); };
      var off = function (e) { e.preventDefault(); up(); };
      b.addEventListener('touchstart', on, { passive: false }); b.addEventListener('mousedown', on);
      b.addEventListener('touchend', off); b.addEventListener('mouseup', off); b.addEventListener('mouseleave', off);
      box.appendChild(b);
    });
  }

  // fire button (touch devices, and in full screen): the left mouse button
  var fireEl = $('firebtn');
  var fireDown = function (e) { audio.start(); e.preventDefault(); e.stopPropagation(); if (m) m.mouse.left = true; fireEl.classList.add('down'); };
  var fireUp = function (e) { e.preventDefault(); e.stopPropagation(); if (m) m.mouse.left = false; fireEl.classList.remove('down'); };
  fireEl.addEventListener('touchstart', fireDown, { passive: false });
  fireEl.addEventListener('touchend', fireUp, { passive: false });
  fireEl.addEventListener('touchcancel', fireUp, { passive: false });
  fireEl.addEventListener('mousedown', fireDown);
  fireEl.addEventListener('mouseup', fireUp);
  fireEl.addEventListener('mouseleave', function (e) { if (fireEl.classList.contains('down')) fireUp(e); });

  // map and proton buttons (full screen), as the program's profile maps them
  function padPress(k, on) {
    if (!m || !k) return;
    if (k.mouse === 'left' || k.mouse === 'both') m.mouse.left = on;
    if (k.mouse === 'right' || k.mouse === 'both') m.mouse.right = on;
    if (k.key) { var c = KEYS[k.key]; m.setKey(c[0], c[1], on); }
  }
  ['map', 'proton'].forEach(function (name) {
    var el = $('pad' + name);
    var k = function () { return profile && profile.pad ? profile.pad[name] : null; };
    var dn = function (e) { audio.start(); e.preventDefault(); e.stopPropagation(); padPress(k(), true); el.classList.add('down'); };
    var up = function (e) { e.preventDefault(); e.stopPropagation(); padPress(k(), false); el.classList.remove('down'); };
    el.addEventListener('touchstart', dn, { passive: false });
    el.addEventListener('touchend', up, { passive: false });
    el.addEventListener('touchcancel', up, { passive: false });
    el.addEventListener('mousedown', dn);
    el.addEventListener('mouseup', up);
    el.addEventListener('mouseleave', function (e) { if (el.classList.contains('down')) up(e); });
  });
  function showPad() {
    ['map', 'proton'].forEach(function (name) { $('pad' + name).classList.toggle('on', !!(profile && profile.pad && profile.pad[name])); });
  }

  // full screen: the screen alone, landscape where the device allows it; where
  // the Fullscreen API is missing (iPhone), the screen fills the window instead
  var fsBtn = $('fsbtn');
  function isFs() { return document.fullscreenElement === screenEl || document.webkitFullscreenElement === screenEl || screenEl.classList.contains('fs'); }
  function fsLabel() { fsBtn.textContent = isFs() ? '✕ Exit' : '⛶ Full screen'; }
  function lockLandscape() {
    try { var o = screen.orientation; if (o && o.lock) { var p = o.lock('landscape'); if (p && p.catch) p.catch(function () {}); } } catch (err) { /* not allowed */ }
  }
  fsBtn.addEventListener('mousedown', function (e) { e.stopPropagation(); });
  fsBtn.addEventListener('touchstart', function (e) { e.stopPropagation(); }, { passive: true });
  fsBtn.addEventListener('click', function (e) {
    e.stopPropagation();
    if (isFs()) {
      if (screenEl.classList.contains('fs')) screenEl.classList.remove('fs');
      else if (document.exitFullscreen) document.exitFullscreen().catch(function () {});
      else if (document.webkitExitFullscreen) document.webkitExitFullscreen();
      try { if (screen.orientation && screen.orientation.unlock) screen.orientation.unlock(); } catch (err) { /* ignore */ }
      fsLabel(); return;
    }
    var req = screenEl.requestFullscreen || screenEl.webkitRequestFullscreen;
    if (req) {
      var p = req.call(screenEl);
      if (p && p.then) p.then(lockLandscape, function () { screenEl.classList.add('fs'); fsLabel(); });
      else lockLandscape();
    } else screenEl.classList.add('fs');
    fsLabel();
  });
  document.addEventListener('fullscreenchange', fsLabel);
  document.addEventListener('webkitfullscreenchange', fsLabel);
  window.addEventListener('keydown', function (e) { if (e.key === 'Escape' && screenEl.classList.contains('fs')) { screenEl.classList.remove('fs'); fsLabel(); } });

  // debugger panels: hidden unless asked for (remembered in this browser)
  var debugOn = false;
  try { debugOn = localStorage.getItem('sentinel-debug') === '1'; } catch (err) { /* no storage */ }
  function setDebug(on) {
    debugOn = on; $('debug').checked = on;
    document.body.classList.toggle('nodebug', !on);
    try { localStorage.setItem('sentinel-debug', on ? '1' : '0'); } catch (err) { /* no storage */ }
    if (on && m) refresh(true);
  }
  $('debug').addEventListener('change', function () { setDebug(this.checked); });
  setDebug(debugOn);

  function typing(e) { var t = e.target.tagName; return t === 'INPUT' || t === 'SELECT' || t === 'TEXTAREA'; }
  window.addEventListener('keydown', function (e) {
    if (typing(e) || !m) return;
    audio.start();
    if (JOY[e.code]) { m.joy2 |= JOY[e.code]; e.preventDefault(); return; }
    var k = KEYS[e.code];
    if (k) { m.setKey(k[0], k[1], true); e.preventDefault(); }
  });
  window.addEventListener('keyup', function (e) {
    if (!m) return;
    if (JOY[e.code]) { m.joy2 &= ~JOY[e.code]; return; }
    var k = KEYS[e.code];
    if (k) m.setKey(k[0], k[1], false);
  });

  // ---- controls ----------------------------------------------------------------------

  $('program').addEventListener('change', function () { boot(this.value); });
  $('mode').addEventListener('change', function () {
    mode = this.value;
    for (var a in hooks.handlers) { var h = hooks.handlers[a]; if (h.fn && h.fn.length) h.mode = mode; }
    dbg.say('JS ports now in ' + mode + ' mode', 'info');
  });
  $('restart').addEventListener('click', function () { boot(progName); });
  $('overlay').addEventListener('click', function () { boot(progName); });
  $('run').addEventListener('click', function () { if (running) pause(); else resume(); });
  $('step').addEventListener('click', function () { stepInstr(1); });
  $('frame').addEventListener('click', function () { stepFrames(1); });
  $('frames50').addEventListener('click', function () { if (m.stopped) return; framesLeft = 50; resume(); });
  $('mute').addEventListener('change', function () { audio.setMuted(this.checked); });

  $('save').addEventListener('click', function () { dbg.save($('slot').value); slotButtons(); });
  $('load').addEventListener('click', function () {
    try { dbg.load($('slot').value); m.stopped = null; $('overlay').style.display = 'none'; draw(); refresh(true); }
    catch (err) { dbg.say(err.message, 'mismatch'); }
  });
  $('slot').addEventListener('change', slotButtons);
  function slotButtons() { $('load').disabled = !dbg.hasSlot($('slot').value); }

  // Export downloads a file only on a top-level page (GitHub Pages, local file);
  // inside a frame it copies the state as text instead.
  var framed = window.top !== window;
  $('export').title = framed ? 'Copy the state as text' : 'Download the state as a file';
  $('export').addEventListener('click', function () {
    var text = JSON.stringify({ program: progName, state: JSON.parse(m.stateToText()) });
    if (!framed) {
      var a = document.createElement('a');
      a.href = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
      a.download = 'sentinel-' + progName + '-frame' + m.frame + '.state.json';
      document.body.appendChild(a); a.click(); a.remove();
      dbg.say('Exported the state (frame ' + m.frame + ')', 'state');
      return;
    }
    var ok = function () { dbg.say('State copied as text (' + Math.round(text.length / 1024) + ' KB); Import takes the file back', 'state'); };
    try { navigator.clipboard.writeText(text).then(ok, function () { dbg.say('Copy was refused here; use the page on GitHub Pages to export files', 'mismatch'); }); }
    catch (err) { dbg.say('Copy was refused here', 'mismatch'); }
  });
  $('import').addEventListener('click', function () { $('importfile').click(); });
  $('importfile').addEventListener('change', function () {
    var f = this.files[0];
    if (!f) return;
    f.text().then(function (t) {
      var o = JSON.parse(t);
      if (o.program !== progName) { $('program').value = o.program; boot(o.program); }
      m.loadState(m.stateFromText(JSON.stringify(o.state)));
      m.stopped = null; $('overlay').style.display = 'none';
      dbg.say('Imported a state (frame ' + m.frame + ')', 'state');
      pause();
    }).catch(function (err) { dbg.say('Import failed: ' + err.message, 'mismatch'); });
    this.value = '';
  });

  boot('game');
  slotButtons();
  requestAnimationFrame(tick);
})();
