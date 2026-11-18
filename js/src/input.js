// Browser input shared by the debugger and itch pages.
'use strict';

var SentinelInput = (function () {
  var JOY = { ArrowUp: 1, ArrowDown: 2, ArrowLeft: 4, ArrowRight: 8, ControlRight: 16, Numpad0: 16 };
  var BUTTON = { left: 1, right: 2, both: 3 };

  function Input(m, hooks, onMode) {
    this.m = m;
    var s = hooks && hooks.symbols;
    var c128 = this.c128 = s && s.GPOTS !== undefined ? s : null;
    this.exclusive = !!(c128 || s && s.POTRD !== undefined);
    this.mode = this.exclusive ? 'joystick' : null;
    this.onMode = onMode;
    this.joy = new Set();
    this.buttons = new Map();
    this.dx = this.dy = 0;
    this.sampledMode = null;
    if (this.exclusive) {
      m.mouse.present = false;
      var self = this;
      hooks.on(c128 ? 'GPOTS' : 'POTRD', function () {
        if (self.sampledMode === self.mode) return;
        self.sampledMode = self.mode;
        var mouse = self.mode === 'mouse';
        // MOVCHK keeps the previous sample for +/-1 jitter. Seed the old pots
        // at a device change so even $00/$7E <-> $FF is detected without a jump.
        if (c128) {
          if (mouse) {
            m.ram[s.OLDX] = self.baseX;
            m.ram[s.OLDY] = self.baseY;
          }
          m.ram[s.GPOTCONNECTED] = mouse ? 1 : 0;
        } else {
          m.ram[s.OPOTX] = mouse ? self.baseX : 0xFF;
          m.ram[s.OPOTY] = mouse ? self.baseY : 0;
          m.ram[s.RCNT] = 0;  // discard the right-button delay/latch from the previous connection
        }
        self.sync();
      });
    }
  }

  Input.isJoystick = function (code) { return Object.hasOwn(JOY, code); };

  Input.prototype.baseline = function () {
    this.baseX = this.m.mouse.x << 1;
    this.baseY = (this.m.mouse.y << 1) ^ 0xFF;
  };

  Input.prototype.select = function (mode) {
    if (!this.exclusive || this.mode === mode) return;
    this.mode = mode;
    if (mode === 'mouse') this.baseline();
    else this.dx = this.dy = 0;
    if (this.c128) {
      this.sampledMode = null;
      this.sync();  // Pause and the ending read digital lines without polling the pots.
    }
    if (this.onMode) this.onMode(mode);
  };

  Input.prototype.sync = function () {
    if (this.exclusive && !this.c128 && this.mode !== this.sampledMode) return;  // C64 switches at POTRD
    var mouse = this.mode !== 'joystick', joystick = this.mode !== 'mouse';
    var joy = 0, buttons = 0;
    if (joystick) this.joy.forEach(function (code) { joy |= JOY[code]; });
    if (mouse) this.buttons.forEach(function (mask) { buttons |= mask; });
    this.m.joy2 = joy;
    if (this.exclusive) this.m.mouse.present = mouse;
    if (this.c128 && !mouse) this.m.ram[this.c128.MPRES] = 0;  // MAPKEY can run before GPOTS
    this.m.mouse.left = !!(buttons & BUTTON.left);
    this.m.mouse.right = !!(buttons & BUTTON.right);
  };

  Input.prototype.setJoystick = function (code, down, repeat) {
    if (down) {
      if (repeat || this.joy.has(code)) return;
      this.joy.add(code);
      this.select('joystick');
    } else {
      this.joy.delete(code);
    }
    this.sync();
  };

  Input.prototype.setButton = function (source, button, down) {
    var mask = BUTTON[button];
    var old = this.buttons.get(source) || 0;
    var next = down ? old | mask : old & ~mask;
    if (old === next) return;
    if (next) this.buttons.set(source, next);
    else this.buttons.delete(source);
    if (down) this.select('mouse');
    this.sync();
  };

  Input.prototype.move = function (dx, dy) {
    if (!dx && !dy) return;
    this.select('mouse');
    this.dx += dx;
    this.dy += dy;
  };

  Input.prototype.feed = function () {
    // The 1351 wraps at 64 counts. Keep each frame below half that range.
    var dx = Math.max(-24, Math.min(24, Math.trunc(this.dx)));
    var dy = Math.max(-24, Math.min(24, Math.trunc(this.dy)));
    this.dx -= dx;
    this.dy -= dy;
    this.m.moveMouse(dx, dy);
  };

  Input.prototype.clearButtons = function (source) {
    this.buttons.delete(source);
    this.sync();
  };

  Input.prototype.release = function () {
    this.dx = this.dy = 0;
    this.joy.clear();
    this.buttons.clear();
    this.m.joy2 = 0;
    this.m.mouse.left = this.m.mouse.right = false;
  };

  Input.prototype.afterLoad = function () {
    if (!this.exclusive) return;
    this.sampledMode = null;
    this.baseline();
    if (this.c128) this.sync();
  };

  return Input;
})();

if (typeof module !== 'undefined') module.exports = SentinelInput;
