// Quick checks for the out-of-energy feature: `node js/test/quick.js` (about 50 s; the full suite is `node js/test/run.js`,
// several minutes, and stays the check before any commit).
//
// Runs: out-of-energy.js in its quick mode (the tick, the flash, the trigger and the message, every gate, the stars' stages,
//       the world's clock, the warp-in, the flash in the map / docking / a jump, and the run-out inside a friendly and a
//       hostile base's raster tunnel), tunnel.js (the raster tunnel: palettes, IRQ chain, timing, hit flash, handover) and
//       hyperspace-freeze.js (the jump: world held, no late writes).
// Skips: everything else of run.js (flight, map, cockpit, original C64 comparisons, title, itch, ending, mines, banks,
//       overlay, joystick, function keys, mission messages, game end, the $A5 free-memory fill check), hyperspace-sid.js
//       (20 s), and out-of-energy.js's slow scenarios: the run-out in a jump (6, 8, 8b), the fight (9) and the new game
//       after dying out of energy (7).
// The harness (boot, run, check, resumeFromTitle) is copied from run.js: keep it in step.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const zlib = require('zlib');

const ROOT = path.join(__dirname, '..');
global.CPU6502 = require(path.join(ROOT, 'src/cpu6502.js'));
global.SentinelFont = require(path.join(ROOT, 'src/font.js'));
global.SentinelVideo = require(path.join(ROOT, 'src/video.js'));
global.SentinelDisasm = require(path.join(ROOT, 'src/disasm.js'));
const Debugger = require(path.join(ROOT, 'src/debugger.js'));
const Profiles = require(path.join(ROOT, 'src/profiles.js'));
const C128 = require(path.join(ROOT, 'src/machine.js'));
const Video = require(path.join(ROOT, 'src/video.js'));
const Hooks = require(path.join(ROOT, 'src/hooks.js'));
const Native = require(path.join(ROOT, 'src/native.js'));
const ctx = {};
vm.runInNewContext(fs.readFileSync(path.join(ROOT, 'programs.js'), 'utf8'), ctx);
const PROGRAMS = ctx.SENTINEL_PROGRAMS;
const OUT = process.argv[2] || path.join(__dirname, 'out');
fs.mkdirSync(OUT, { recursive: true });

let failures = 0;
function check(cond, msg) { console.log((cond ? 'ok   ' : 'FAIL ') + msg); if (!cond) failures++; }
const freeMemoryRuns = [];

function titleDefaultFrame(m, s, frame) {
  const {present, left, right} = m.mouse;
  const keys = m.keys[0], joy = m.joy2;
  m.mouse.present = m.mouse.left = m.mouse.right = false;
  m.keys[0] = m.ram[s.TITLEARM] && !m.ram[s.TITLEMENU] ? 1 << 6 : 0;
  const confirm = m.ram[s.TITLEARM] && m.ram[s.TITLEMENU] === 1;
  const advance = m.ram[s.INTROACTIVE] && m.ram[s.INTROARM];
  m.joy2 = confirm || advance ? 16 : 0;
  try {
    return frame();
  } finally {
    Object.assign(m.mouse, {present, left, right});
    m.keys[0] = keys;
    m.joy2 = joy;
  }
}

function resumeFromTitle(m, s, frame = () => m.runFrame()) {
  for (let f = 0; f < s.TITLECONFIRMFRAMES + 40 && m.ram[s.OVOWNER] === s.TITLEOWNER; f++) {
    if (!titleDefaultFrame(m, s, frame)) return false;
  }
  return m.ram[s.OVOWNER] !== s.TITLEOWNER;
}

function boot(name, mode, opts) {
  const p = PROGRAMS[name];
  const m = new C128(p.model);
  m.loadPrg(new Uint8Array(Buffer.from(p.prg, 'base64')));
  const hooks = new Hooks(m, p.symbols);
  const ported = Native.install(hooks, mode);
  m.start(p.entry);
  if (name === 'game' && !(opts && opts.atTitle)) {
    // Play fixtures start the default flight profile through the native UI.
    // Leave subsequent game-over resets at the title for each test to inspect.
    const s = p.symbols, frame = m.runFrame.bind(m);
    // Flight fixtures exercise their own map transitions. The actual first
    // map is covered by the title and packaged-page startup tests.
    hooks.skip('TITLEMAPOPEN');
    let bootingTitle = false, started = false;
    hooks.on('TITLEBOOT', () => { bootingTitle = true; });
    m.runFrame = function () {
      if (!started && bootingTitle) {
        // Keep fixture time independent of the overlay load and selector.
        for (let f = 0; f < 20 && m.ram[s.OVOWNER] !== s.TITLEOWNER; f++) {
          if (!frame()) return false;
        }
        if (m.ram[s.OVOWNER] !== s.TITLEOWNER) return false;
        started = resumeFromTitle(m, s, frame);
        if (!started) return false;
      }
      return frame();
    };
    if (!(opts && opts.lazyMines)) {
      // Older fixtures call MINES entries directly or time play with the
      // package already present. Start those scenarios with its init image.
      hooks.on('g_gi9', () => {
        m.ram.set(m.ram1.subarray(s.B1MINES, s.B1MINES + s.MNEXTRAEND - s.MNSTART), s.MNSTART);
        m.ram[s.OVOWNER] = 0x80;
      });
    }
  }
  if (name === 'game' && false) {   // (quick.js: the $A5 free-memory fill of run.js is skipped, it triples the run time)
    const s=p.symbols, record={armed:false, intact:true, frames:0, bad:null, at:new Error().stack.split('\n')[2]};
    m.freeMemoryRecord=record;
    freeMemoryRuns.push(record);
    // A loaded save state brings its own RAM (an older executable, BASIC's zero page):
    // the fill is taken again from the next frame on.
    const load=m.loadState.bind(m);
    m.loadState=function(...a){const r=load(...a);record.armed=false;return r;};
    const frame=m.runFrame.bind(m);
    m.runFrame=function() {
      const result=frame();
      // (free: the high bytes after MINES, the ending core's tail, the overlay manager's,
      // the loader's tail, and what the exit to BASIC left (no return to BASIC): the
      // cockpit's EXIT, START's saves, the VDC helper's 5 bytes, zero page but the
      // game's pointers $FB-$FE and the relocated rating's temp $2B/$2C (the original
      // $F440's), the stack page between the stub and $01C0)
      const free=[[s.MINEFREE,s.MINEEND],[s.ENDCOREEND,0xC60],[s.OVEND,0x1C00],[s.ENDLOADEREND,0x1D00],
        [s.CKEXITFREE,s.SPRCROSS],[s.CKSTARTFREE,s.g_st1],[s.VDCFREE,s.VDCFREE+5],
        [0x02,0x2B],[s.OEZPEND,0xFB],[0xFF,0x100],[0x100+s.B1STUBLEN,0x1C0]];
      if (!record.armed && m.mmuCR===0x3E && m.ram[s.GUNPACK]===(s.TORPA&255)) {
        for(const [lo,hi] of free) m.ram.fill(0xA5,lo,hi);
        record.armed=true;
      } else if (record.armed) {
        for(const [lo,hi] of free) for(let a=lo;a<hi;a++) if(m.ram[a]!==0xA5) {
          if(record.intact) record.bad=`$${a.toString(16)}=$${m.ram[a].toString(16)} frame ${record.frames} pc $${m.cpu.pc.toString(16)}`;
          record.intact=false;
        }
        record.frames++;
      }
      return result;
    };
  }
  return { m, hooks, ported, p };
}

// The cockpit starts by approaching a squadron; tests of the fight put it in a
// dogfight with ships to spare.
function dogfight(k) {
  const K = k.m.ram, s = k.p.symbols;
  K[s.APPR] = 0; K[s.APRUN] = 0; K[s.LRMODE] = 0; K[s.SQCOUNT] = 200; K[s.CURG] = 0;
  K[s.GSIZE] = K[s.GSIZE + 1] = K[s.GSIZE + 2] = 200;
}

function run(m, hooks, frames, each) {
  for (let i = 0; i < frames; i++) {
    if (each) each(i);
    if (!m.runFrame()) return false;
  }
  return true;
}
const t0=Date.now(), lap=n=>console.log('     ['+n+' done at '+Math.round((Date.now()-t0)/1000)+' s]');
require('./out-of-energy')({boot,run,check,resumeFromTitle,quick:true}); lap('out-of-energy');
require('./tunnel')({boot,run,check,snap:()=>{},fs,path,OUT});                  lap('tunnel'); // (OETPH's hook in MTFRAME must not change the raster tunnel's timing)
require('./hyperspace-freeze')({boot,run,check});                               lap('hyperspace-freeze');
console.log((failures ? failures + ' check(s) failed' : 'quick checks passed')+' in '+Math.round((Date.now()-t0)/1000)+' s');
process.exit(failures ? 1 : 0);
