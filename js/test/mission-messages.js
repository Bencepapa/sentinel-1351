'use strict';

const fs = require('fs');
const path = require('path');

module.exports = function ({boot, run, check}) {
  function ready() {
    const {m, hooks, p: {symbols: s}} = boot('game', 'trace');
    m.dma = true;
    run(m, hooks, 80);
    return {m, s, r: m.ram};
  }

  function call(m, address) {
    const c = m.cpu, saved = [c.pc, c.sp, c.p];
    c.push(0xFF);
    c.push(0xF3);
    c.pc = address;
    c.p |= 4;
    for (let i = 0; c.pc !== 0xFFF4 && i < 100000; i++) {
      if (m.hooks.at[c.pc]) m.hooks.enter(c.pc);
      else c.step();
    }
    if (c.pc !== 0xFFF4) throw Error('Mission message fixture did not return');
    [c.pc, c.sp, c.p] = saved;
  }

  function row(r, s) {
    return String.fromCharCode(...r.subarray(s.LRROW, s.LRROW + 40)).replace(/[@`]/g, ' ').trim();
  }

  function lateWrites(m) {
    let late = 0;
    for (let i = 0; i < m.vicLog.length; i += 4) {
      const line = m.vicLog[i], cycle = m.vicLog[i + 1], register = m.vicLog[i + 2];
      if ((register === 0x20 || register === 0x21) && cycle >= 16 && cycle <= 55 &&
          ((line >= 50 && line <= 76) || (line >= 230 && line <= 245))) late++;
    }
    return late;
  }

  // Use the original fight loop at the saved raster phase, with one enemy and
  // another occupied sector to keep the victory screen out of the experiment.
  function originalFight() {
    const {m, hooks} = boot('c64game', 'trace');
    const {state} = JSON.parse(fs.readFileSync(path.join(__dirname,
      '../../briefs/ref/c64-last-enemy-map-then-win.state.json'), 'utf8'));
    m.loadState(m.stateFromText(JSON.stringify(state)));
    m.dma = true;
    const r = m.ram;
    for (const a of [0xB8, 0xB9, 0x62, 0x64, 0xE3, 0xE1, 0xBA, 0xBACE, 0xBAD1, 0xFB, 0xFD]) r[a] = 0;
    r[0xBB] = 1;
    r.fill(0, 0x033C, 0x03B4);
    r[0x033C] = r[0x033D] = r[0x0378] = r[0x0379] = 1;
    r[0x5476] = 0x71;
    r[0x5F] = r[0xC593] = 1;
    r[0xC594] = r[0xC595] = r[0xC596] = 0;
    return {m, hooks, r};
  }

  const originalRow = {LRROW: 0x5798};
  {
    const {m, hooks, r} = originalFight();
    let polls = 0, mapPoll = 0;
    hooks.on(0xFB43, () => polls++);
    hooks.on(0xFB74, () => { if (!mapPoll) mapPoll = polls; });
    call(m, 0xC832);
    m.runFrame();
    const approach = row(r, originalRow);
    call(m, 0x3CC4);
    const before = polls;
    const cleared = row(r, originalRow) === 'SECTOR CLEARED CAPTAIN' &&
      r[0xB8] === 1 && r[0xBB] === 55 && r[0x9BDE] === 32;
    m.runFrame();
    r.fill(0, 0x39, 0x41);
    r[0x3A] = 1;
    call(m, 0x84D7);
    const damaged = row(r, originalRow) === 'LONG RANGE SCANNER DESTROYED' && r[0x9BDE] === 53;
    let frames = 1;
    while (!mapPoll && frames < 60) {
      m.runFrame();
      frames++;
    }
    check(approach.includes('GORGANITOR APPROACH') && cleared && damaged && mapPoll - before === 55,
      `C64 messages: last kill replaces approach, damage replaces clear, map starts after ${mapPoll - before} polls (${frames} PAL frames)`);
  }
  {
    const {m, hooks, r} = originalFight();
    let tracking = 0, sirens = 0;
    hooks.on(0x8A2C, () => tracking++);
    hooks.on(0x0930, () => sirens++);
    call(m, 0xC832);
    for (let i = 0; i < 3; i++) m.runFrame();
    r[0x3D] = 2;
    r[0x62] = 1;  // the fight loop consumes this request through $89E6
    for (let i = 0; i < 8; i++) m.runFrame();
    const scrolled = tracking === 1 && r[0x64] && r[0x13D4] === 1 && r[0x9BDE] === 18;
    r.fill(0, 0x39, 0x41);
    r[0x3A] = 2;
    call(m, 0x84D7);
    const nonfatal = r[0x3A] === 1 && r[0x13D4] === 1;
    call(m, 0x84D7);
    const damaged = !r[0x3A] && !r[0x13D4] && row(r, originalRow) === 'LONG RANGE SCANNER DESTROYED';
    const duration = r[0x9BDD] === 5 && r[0x9BDE] === 53;
    for (let i = 0; i < 265; i++) m.runFrame();
    check(scrolled && nonfatal && damaged && duration && sirens === 2 && tracking === 1 && !r[0x9BE3],
      'C64 messages: tracking replaces approach within a few frames, only zero HP replaces tracking and no warning replays');
  }
  {
    const {m, hooks, r} = originalFight();
    const prints = [];
    hooks.on(0x9C24, () => prints.push(r[0x9D34] | r[0x9D35] << 8));
    r.fill(0, 0x3E74, 0x3E7E);
    for (let i = 0; i < 20; i++) r[0x033C + r[0x3E60 + i]] = 1;
    call(m, 0x3E7E);
    const winner = row(r, originalRow);
    call(m, 0x3E7E);
    check(prints.join(',') === [0x3DDD, 0x3DDD, 0x3DDD, 0x3DDD, 0x3E1F].join(',') &&
      winner === 'JARALOBA IS SURROUNDED' && row(r, originalRow) === winner,
      'C64 messages: five ring events print in scan order, the planet notice wins and the next tick prints nothing');
  }

  {
    const {m, s, r} = ready();
    r[s.SYSHP + 4] = 0;
    call(m, s.APPROACHNOTICE);
    for (let i = 0; i < 3; i++) m.runFrame();
    const warning = row(r, s);
    call(m, s.TRACKNOTICE);
    r[s.M_SELX] = r[s.M_SELY] = 0;
    r[s.M_STATE] = r[s.M_COUNT] = r[s.SQCOUNT] = 1;
    r[s.M_STATE + 1] = 1;
    m.cpu.x = 0;
    call(m, s.KILL);
    m.runFrame();
    let late = lateWrites(m);
    const first = row(r, s);
    r.fill(0, s.SYSHP, s.SYSHP + 8);
    r[s.SYSHP + 1] = 1;
    call(m, s.MISSIONHIT);
    let damaged = -1, opened = -1, tracking = false;
    for (let i = 1; i <= 35; i++) {
      m.runFrame();
      late += lateWrites(m);
      if (damaged < 0 && row(r, s) === 'LONG RANGE SCANNER DESTROYED') damaged = i;
      if (opened < 0 && r[s.MAPSHOWN]) opened = i;
      tracking ||= !!r[s.MSGFINE];
    }
    check(warning.includes('GORGANITOR APPROACH') && first === 'SECTOR CLEARED CAPTAIN' &&
      damaged === 1 && opened === 26 && !tracking && !late && !r[s.OVRUN],
      `mission messages: clear replaces approach, damage replaces clear, map opens on schedule (damage ${damaged}, map ${opened}, ${late} late splits, ${r[s.OVRUN]} OVRUN)`);
  }

  {
    const {m, s, r} = ready();
    r[s.M_SELX] = r[s.M_SELY] = 0;
    r[s.M_STATE] = r[s.M_COUNT] = r[s.SQCOUNT] = 1;
    r[s.M_STATE + 1] = 1; // another enemy sector keeps the victory screen out
    m.cpu.x = 0;
    call(m, s.KILL);
    let seen = -1, opened = -1;
    for (let i = 0; i < 60; i++) {
      m.runFrame();
      if (seen < 0 && row(r, s) === 'SECTOR CLEARED CAPTAIN') seen = i;
      if (r[s.MAPSHOWN]) {
        opened = i;
        break;
      }
    }
    check(seen >= 0 && opened - seen === 26 && !r[s.M_STATE] && !r[s.OVRUN],
      `mission messages: last kill clears its sector, shows the notice and opens the map after ${opened - seen} frames`);
  }

  {
    const {m, s, r} = ready();
    r[s.M_SELX] = r[s.M_SELY] = r[s.CURG] = 0;
    r[s.M_STATE] = r[s.GSIZE] = 1;
    r[s.M_COUNT] = r[s.SQCOUNT] = 4;
    m.cpu.x = 0;
    call(m, s.KILL);
    for (let i = 0; i < 5; i++) m.runFrame();
    const before = r.slice(s.LRROW, s.LRROW + 40);
    r[s.GSEL] = 0;
    r[s.ENX + 1] = 0x90;
    r[s.ENY + 1] = 0x84;
    call(m, s.lr7);
    const digits = r.slice(s.LRDIG, s.LRDIG + 4);
    call(m, s.SCANZEROX);
    call(m, s.SCANZEROY);
    check(row(r, s) === 'SQUADRON DESTROYED SIR' && before.every((value, i) => r[s.LRROW + i] === value) &&
      !r[s.CLEARTIME] && !r[s.MAPSHOWN] && r[s.M_COUNT] === 3,
      'mission messages: the scanner leaves the squadron notice intact with fighters still in the sector');
    r[s.MSGCD] = r[s.MSGN] = 1;
    call(m, s.MSGTICK);
    call(m, s.lr7);
    check(!r[s.MSGON] && r[s.LRROW + 9] === 0x7B &&
      digits.every((value, i) => r[s.LRDIG + i] === value),
      'mission messages: scanner keeps computing while the notice owns the row, then resumes display');
  }

  {
    const {m, s, r} = ready();
    const names = ['PHASOR CANNONS', 'LONG RANGE SCANNER', 'SHORT RANGE SCANNER',
      'STELLAR GRID', 'AUTOMATIC TRACKING COMPUTER', 'HYPERSPACE COORDINATOR',
      'LONG RANGE SCAN SEQUENCER', 'COMMUNICATIONS MODULE'];
    let valid = true;
    for (let i = 0; i < names.length; i++) {
      r.fill(0, s.SYSHP, s.SYSHP + 8);
      r[s.SYSHP + i] = 2;
      call(m, s.MISSIONHIT);
      valid &&= r[s.SYSHP + i] === 1 && r[s.SYSLAST] === 0xFF;
      r[s.MSGON] = 0;
      call(m, s.MISSIONHIT);
      valid &&= r[s.NOTICEPEND] === i + 8;
      for (let frame = 0; frame < 4; frame++) m.runFrame();
      valid &&= row(r, s) === names[i] + ' DESTROYED' && r[s.SYSLAST] === 0xFF &&
        r[s.SNDON] && r[s.SNDHI0] === 0x1E;
    }
    check(valid && !r[s.OVRUN], 'mission messages: each destroyed system names itself and starts the warning siren');
  }

  {
    for (const [route, warning] of [
      ['APPROACHNOTICE', 'GORGANITOR APPROACH'],
      ['ENTERNOTICE', 'ENTERING GORGANITOR SECTOR']
    ]) {
      for (const working of [false, true]) {
        const {m, s, r} = ready();
        r[s.SYSHP + 4] = working ? 1 : 0;
        call(m, s[route]);
        m.runFrame();
        const announced = row(r, s).includes(warning);
        r[s.TON] = 1;
        call(m, s.TRKCHK);
        for (let frame = 0; frame < 5; frame++) m.runFrame();
        const pointer = r[s.MSGP] | (r[s.MSGP + 1] << 8);
        check(announced && !r[s.NOTICEPEND] && r[s.MSGON] && (working
          ? r[s.MSGFINE] && pointer >= s.TMTEXT && pointer < s.TMTEXT + 4
          : !r[s.MSGFINE] && row(r, s).includes(warning)),
          `mission messages: ${route} announces the encounter; ${working ? 'engagement replaces it' : 'a broken computer leaves it up'}`);
      }
    }
  }

  {
    const {m, s, r} = ready();
    r[s.SYSHP + 4] = 0;
    call(m, s.APPROACHNOTICE);
    for (let frame = 0; frame < 20; frame++) m.runFrame();
    const first = row(r, s);
    const before = r.slice(s.LRROW, s.LRROW + 40);
    call(m, s.HREAD);
    call(m, s.HREADCLEAR);
    const intact = before.every((value, index) => r[s.LRROW + index] === value);
    call(m, s.TRACKNOTICE);
    for (let frame = 0; frame < 8; frame++) m.runFrame();
    check(first.includes('GORGANITOR APPROACH') && intact && !r[s.NOTICEPEND] && r[s.MSGFINE],
      'mission messages: tracking replaces a live approach notice and hyperspace readings leave the row intact');
  }

  {
    const {m, s, r} = ready();
    r.fill(0, s.SYSHP, s.SYSHP + 8);
    r[s.SYSHP] = 1;
    call(m, s.MISSIONHIT);
    const pending = r[s.NOTICEPEND] === 8;
    call(m, s.MISSIONREPAIRED);
    call(m, s.MSOFF);
    for (let i = 0; i < 5; i++) m.runFrame();
    check(pending && !r[s.NOTICEPEND] && r[s.SYSLAST] === 0xFF && !row(r, s).endsWith('DESTROYED'),
      'mission messages: friendly repair discards an obsolete system warning');
  }
};
