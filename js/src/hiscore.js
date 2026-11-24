// Score and hi-score of the game. The original has no point score: its end screen shows only a
// rank name and a class digit, both results of its rating routine ($F440, the C128 port's
// ENDRATING). The page's score is built from what the game counts (see js/README.md):
//
//     points = 100 * enemy motherships destroyed                 (0-4, the orange corners of the map)
//            + 10 * (difficulty + 1) * enemy fighters destroyed   (difficulty 0-4)
//   and only after a victory:
//            + 100 * friendly bases still standing                (0-4, the blue ones, "BASE STATIONS")
//            + remaining seconds out of 6000 (100 minutes)        (C64 original only: the C128 port keeps no clock)
//   (a loss earns neither, so dying early with nothing done scores 0)
//
// The rank and class on the end screen are the game's own (rate / rating below work them out the
// way the original does; the tests check the hooks against them). Pure logic (no DOM), so the
// headless tests drive it.
'use strict';

var SentinelHiscore = (function () {
  var CAP = [3, 4, 5, 6, 7];                     // $F5B3: the highest rank per difficulty
  var RANKS = ['SPACE DROID', 'TRAINEE', 'LIEUTENANT', 'CAPTAIN', 'COMMANDER', 'ADMIRAL', 'SENTINEL', 'STAR SENTINEL'];
  var KEY = 'sentinel-itch-hi-';
  var ORANGE = [0, 9, 50, 59], BLUE = [12, 17, 42, 47];   // map cells (6 rows of 10) of the 4 corner motherships / 4 bases ($2089 / $2085)
  var TIME_MAX = 6000;                                     // seconds: 100 minutes
  var PER_MOTHER = 100, PER_BASE = 100, PER_KILL = 10;

  // The tail of $F440: the 16 bit rating (lo = $F43D, hi = $F43E) to rank, class, value.
  function rate(lo, hi, diff) {
    var cap = CAP[Math.max(0, Math.min(4, diff | 0))], x, l = lo & 255, d = (hi & 255) - 0x80;
    if (d < 0) { x = 0; l = 0; }
    else if (d >= cap) { x = cap; l = 255; }
    else x = d;
    return { x: x, lo: l, cls: l >> 5, value: x * 256 + l };
  }

  // $F440 itself: the rating from the game's statistics, to the 16 bit value it leaves in
  // $F43D/$F43E. All arithmetic as the 8 bit code does it (it truncates in places).
  //   diff      difficulty 0-4 ($E0)               victory  the game was won ($F34B)
  //   planet    JARALOBA was lost ($F431)          hits     hits taken ($F432, 16 bit)
  //   kills     $F434 (16 bit)                     energy   $F436 (24 bit)
  //   protons   $F439 (16 bit)                     shots    $F43B (16 bit)
  //   mothers   enemy motherships destroyed (corner states other than $80)
  //   bases     friendly bases lost (base states other than $FF)
  function rating(i) {
    var lo = 0, hi = 0x80, t;
    function add16(v) { t = lo + (v & 255); lo = t & 255; hi = (hi + ((v & 0xFFFF) >> 8) + (t >> 8)) & 255; }
    function sub16(v) { t = lo - (v & 0xFF); var b = t < 0 ? 1 : 0; lo = t & 255; hi = (hi - ((v >> 8) & 255) - b) & 255; }
    var diff = i.diff | 0;
    if (i.victory) { var w = (diff + 1) << 7; lo = w & 255; hi = (0x80 + (w >> 8)) & 255; }
    add16((i.kills << 4) & 0xFFFF);
    add16((i.mothers << 6) & 0xFF);
    var lost = (i.bases << 5) & 0xFF;
    sub16(lost);
    sub16(((i.energy & 0xFFFFFF) >> 7) & 0xFFFF);
    if (i.planet) { sub16(((0x40 << Math.max(0, diff)) & 0xFF) | (lost << 8)); }   // (the high byte is the base term)
    sub16(((i.hits << 1) & 0xFFFF));
    sub16(i.shots & 0xFFFF);
    sub16((i.protons << 3) & 0xFFFF);
    return { lo: lo, hi: hi };
  }

  function rankIndex(x, diff, victory) {        // the end screen's name for X (the original shows only
    return (diff < 3 && !victory) ? (x & 3) : x; // four names after a defeat at the lower difficulties)
  }

  // The point score. st: diff 0-4, kills (enemy fighters destroyed), mothers (enemy motherships
  // destroyed), victory (the game was won), bases (friendly bases left) and elapsed (seconds on the
  // game's clock; null / undefined when the program keeps none: that term is then 0): those two count
  // only after a victory. Returns {points, parts}.

  function score(st) {
    st = st || {};
    var diff = Math.max(0, Math.min(4, st.diff | 0));
    var parts = {
      mothers: PER_MOTHER * Math.max(0, st.mothers | 0),
      bases: st.victory ? PER_BASE * Math.max(0, st.bases | 0) : 0,
      time: (!st.victory || st.elapsed === null || st.elapsed === undefined) ? 0 : Math.max(0, TIME_MAX - Math.max(0, st.elapsed | 0)),
      kills: PER_KILL * (diff + 1) * Math.max(0, st.kills | 0),
    };
    return { points: Math.min(999999, parts.mothers + parts.bases + parts.time + parts.kills), parts: parts };
  }

  // The map's corner cells: enemy motherships destroyed (state other than $80), bases standing ($FF).
  function mapCounts(cell) {
    var mothers = 0, bases = 0, i;
    for (i = 0; i < 4; i++) { if (cell(ORANGE[i]) !== 0x80) mothers++; if (cell(BLUE[i]) === 0xFF) bases++; }
    return { mothers: mothers, bases: bases };
  }

  // TIME in seconds: MM:SS as screen digits $70-$79, or null when the digits are absent.
  // The C64 clock starts at $544A. The C128 port exports the equivalent HUDTIME address.
  function hudSeconds(R, at) {
    if (at === undefined) at = 0x544A;
    var d = [R[at], R[at + 1], R[at + 3], R[at + 4]].map(function (v) { return v - 0x70; });
    for (var i = 0; i < 4; i++) if (!(d[i] >= 0 && d[i] <= 9)) return null;
    return (d[0] * 10 + d[1]) * 60 + d[2] * 10 + d[3];
  }

  function pad6(n) { return ('000000' + Math.max(0, Math.min(999999, n | 0))).slice(-6); }

  // The end of a game: the rating's low / high byte (the original's $F43D / $F43E), the difficulty,
  // whether it was won, the end screen's rank name index (optional) and the statistics for score().
  // Returns {points, text, parts, rank (index), name, cls (digit 1-8), victory}.
  function result(lo, hi, diff, victory, rank, stats) {
    var r = rate(lo, hi, diff), idx = rank !== undefined ? rank : rankIndex(r.x, diff, victory);
    var sc = score({ diff: diff, victory: !!victory, kills: stats && stats.kills, mothers: stats && stats.mothers, bases: stats && stats.bases, elapsed: stats && stats.elapsed });
    return { points: sc.points, text: pad6(sc.points), parts: sc.parts, rank: idx, name: RANKS[idx] || '', cls: (r.cls ^ 7) + 1, victory: !!victory };
  }

  // Best score per program, in the given storage (localStorage, or anything with getItem / setItem).
  // Storage that throws or is missing keeps the scores in memory for the session.
  function Store(storage) { this.s = storage || null; this.mem = {}; }
  Store.prototype.get = function (prog) {
    var v = null;
    try { if (this.s) v = this.s.getItem(KEY + prog); } catch (e) { v = null; }
    if (v === null || v === undefined) v = this.mem[prog];
    v = parseInt(v, 10);
    return isFinite(v) && v > 0 ? Math.min(v, 999999) : 0;
  };
  // Keeps the score when it beats the best. Returns {best, isNew}.
  Store.prototype.submit = function (prog, points) {
    var best = this.get(prog), isNew = points > best;
    if (isNew) {
      best = Math.min(points, 999999);
      this.mem[prog] = best;
      try { if (this.s) this.s.setItem(KEY + prog, String(best)); } catch (e) { /* memory only */ }
    }
    return { best: best, isNew: isNew };
  };

  // Calls onEnd(result) once per game over of the running program, at the moment the end screen's
  // rank is worked out. Returns {rearm()} (call it after loading a state taken before the end).
  //   c64game  $F3CE (just before JSR $F440, which uses up the counters): the statistics are read there:
  //            $F434 kills (it counts from 1), the map at $033C. The clock has no variable (only the HUD
  //            digits, which wrap at 60:00 and are cleared by the death scene), so the seconds are counted:
  //            $FAE9 is reached once per game second (from 0 at GAMEENTRY; after a state is loaded,
  //            rearm() starts from the HUD digits). The instruction after $F440 ($F3D1) has
  //            $F43D/$F43E (the rating), $E0 the difficulty, $F34B the victory flag; the game restarts
  //            at GAMEENTRY.
  //   game     the C128 port's ENDRANKSET (label end_rankok, inside the ENDING overlay package, so only
  //            while OVOWNER says that package is loaded): ENDSCORE, DIFF, ENDMODE (2 = victory), ENDRANK
  //            (the name already chosen). The statistics are read after ENDRATINGINPUT (ENDRANKSET + 3):
  //            ENDKILLS (from 1 as well), the map M_STATE, and HUDTIME plus CLOCKHOURS. The reset is ENDRESET.
  function watch(m, hooks, prog, sym, onEnd) {
    var done = false, pre = null, secs = 0;
    var rearm = function () { done = false; pre = null; secs = prog === 'c64game' ? (hudSeconds(m.ram) || 0) : 0; };
    if (prog === 'c64game') {
      hooks.on('$FAE9', function () { secs++; });
      hooks.on('$F3CE', function () {
        var R = m.ram, c = mapCounts(function (a) { return R[0x33C + a]; });
        pre = { diff: R[0xE0], kills: (R[0xF434] | (R[0xF435] << 8)) - 1, mothers: c.mothers, bases: c.bases, elapsed: secs };
      });
      hooks.on('$F3D1', function () {
        if (done) return;
        done = true;
        var R = m.ram;
        onEnd(result(R[0xF43D], R[0xF43E], R[0xE0], R[0xF34B] !== 0, undefined, pre));
      });
      hooks.on('GAMEENTRY', function () { done = false; pre = null; secs = 0; });
    } else if (sym.end_rankok !== undefined) {
      hooks.on(sym.ENDRANKSET + 3, function () {
        var R = m.ram;
        if (R[sym.OVOWNER] !== 0x40) return;
        var c = mapCounts(function (a) { return R[sym.M_STATE + a]; });
        var elapsed = null;
        if (sym.HUDTIME !== undefined && sym.CLOCKHOURS !== undefined) {
          elapsed = hudSeconds(R, sym.HUDTIME);
          if (elapsed !== null) elapsed += R[sym.CLOCKHOURS] * 3600;
        }
        pre = { diff: R[sym.DIFF], kills: (R[sym.ENDKILLS] | (R[sym.ENDKILLS + 1] << 8)) - 1, mothers: c.mothers, bases: c.bases, elapsed: elapsed };
      });
      hooks.on('end_rankok', function () {
        var R = m.ram;
        if (done || R[sym.OVOWNER] !== 0x40) return;
        done = true;
        onEnd(result(R[sym.ENDSCORE], R[sym.ENDSCORE + 1], R[sym.DIFF], R[sym.ENDMODE] === 2, R[sym.ENDRANK], pre));
      });
      hooks.on('ENDRESET', rearm);
    }
    return { rearm: rearm };
  }

  return { score: score, mapCounts: mapCounts, hudSeconds: hudSeconds, rate: rate, rating: rating, rankIndex: rankIndex, result: result, pad6: pad6, Store: Store, watch: watch, RANKS: RANKS, CAP: CAP, TIME_MAX: TIME_MAX };
})();

if (typeof module !== 'undefined') module.exports = SentinelHiscore;
