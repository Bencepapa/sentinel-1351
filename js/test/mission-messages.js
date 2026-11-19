'use strict';

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
    for (let i = 0; c.pc !== 0xFFF4 && i < 100000; i++) c.step();
    if (c.pc !== 0xFFF4) throw Error('Mission message fixture did not return');
    [c.pc, c.sp, c.p] = saved;
  }

  function row(r, s) {
    return String.fromCharCode(...r.subarray(s.LRROW, s.LRROW + 40)).replace(/[@`]/g, ' ').trim();
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
      valid &&= r[s.NOTICECOUNT] === 1;
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
        r[s.TON] = 1;
        call(m, s.TRKCHK);
        const oneNotice = r[s.NOTICECOUNT] === 1;
        for (let frame = 0; frame < 5; frame++) m.runFrame();
        const pointer = r[s.MSGP] | (r[s.MSGP + 1] << 8);
        check(oneNotice && !r[s.NOTICECOUNT] && r[s.MSGON] && (working
          ? r[s.MSGFINE] && pointer >= s.TMTEXT && pointer < s.TMTEXT + 4
          : !r[s.MSGFINE] && row(r, s).includes(warning)),
          `mission messages: ${route} shows only the ${working ? 'tracking' : 'Gorganitor'} notice`);
      }
    }
  }

  {
    const {m, s, r} = ready();
    r[s.SYSHP + 4] = 0;
    call(m, s.APPROACHNOTICE);
    call(m, s.TRACKNOTICE);
    for (let frame = 0; frame < 20; frame++) m.runFrame();
    const first = row(r, s);
    const waiting = r[s.NOTICECOUNT];
    const before = r.slice(s.LRROW, s.LRROW + 40);
    call(m, s.HREAD);
    call(m, s.HREADCLEAR);
    const intact = before.every((value, index) => r[s.LRROW + index] === value);
    r[s.MSGCD] = r[s.MSGN] = 1;
    for (let frame = 0; frame < 8; frame++) m.runFrame();
    check(first.includes('GORGANITOR APPROACH') && waiting === 1 && intact &&
      !r[s.NOTICECOUNT] && r[s.MSGFINE],
      'mission messages: tracking waits for the approach notice and hyperspace readings leave the row intact');
  }

  {
    const {m, s, r} = ready();
    r.fill(0, s.SYSHP, s.SYSHP + 8);
    r[s.SYSHP] = 1;
    call(m, s.MISSIONHIT);
    const queued = r[s.NOTICECOUNT] === 1;
    call(m, s.MISSIONREPAIRED);
    call(m, s.MSOFF);
    for (let i = 0; i < 5; i++) m.runFrame();
    check(queued && !r[s.NOTICECOUNT] && r[s.SYSLAST] === 0xFF && !row(r, s).endsWith('DESTROYED'),
      'mission messages: friendly repair discards an obsolete system warning');
  }
};
