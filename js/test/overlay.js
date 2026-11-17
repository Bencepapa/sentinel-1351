'use strict';
// The overlay slot S1 ($E960-$F6F8, c128-game/overlay.asm): MINES is a package
// copied from bank 1; nothing outside a base sector touches the slot, the
// trampolines reload a missing package, a busy slot refuses to be overwritten,
// and a reset puts MINES back in its init state.
module.exports = function ({boot, run, check, fs, path, OUT}) {
  const call = (m, a, x) => {
    const c = m.cpu, saved = [c.pc, c.sp, c.p, c.x];
    c.push(255); c.push(243); c.pc = a; c.p |= 4; if (x !== undefined) c.x = x;
    let n = 0; while (c.pc !== 0xfff4 && n++ < 5e6) { c.step(); if (c.jam) throw Error(c.jam); }
    if (n >= 5e6) throw Error('call did not return: ' + a.toString(16));
    const carry = c.p & 1; [c.pc, c.sp, c.p, c.x] = saved; return carry;
  };
  const late = m => { let n = 0; for (let i = 0; i < m.vicLog.length; i += 4) { const l = m.vicLog[i], cy = m.vicLog[i + 1], r = m.vicLog[i + 2];
    if ((r === 32 || r === 33) && ((l >= 50 && l <= 76) || (l >= 230 && l <= 245)) && cy >= 16 && cy <= 55) n++; } return n; };
  const ready = () => { const k = boot('game', 'trace'); k.m.dma = true; run(k.m, k.hooks, 80); return k; };

  // ---- init: MINES decoded into S1 and copied to bank 1, the borrowed streams too --------------
  const k0 = ready(), m0 = k0.m, A0 = m0.ram, S = k0.p.symbols;
  const image = Buffer.from(A0.subarray(S.MNSTART, S.MNEXTRAEND));
  check(A0[S.OVOWNER] === 0x80 && !A0[S.OVJOB] && image.equals(Buffer.from(m0.ram1.subarray(S.B1MINES, S.B1MINES + image.length))) &&
    Buffer.from(A0.subarray(0x8100, 0x8400)).equals(Buffer.from(m0.ram1.subarray(S.B1STREAM, S.B1STREAM + 768))),
    `overlay: after init S1 holds MINES (${image.length} bytes), its image and the borrowed streams are in bank 1`);

  // ---- S1 empty and filled with $A5: flight, map, torpedo, a fight never touch it ------------------
  {
    // The same play with MINES in S1 and with S1 empty: the same frames, S1 untouched.
    const play = evict => {
      const k = ready(), m = k.m, A = m.ram, trace = [];
      if (evict) {
        check(call(m, S.OVLOAD, 0) === 0 && A[S.OVOWNER] === 0, 'overlay: OVLOAD 0 empties the slot');
        A.fill(0xA5, S.S1BASE, S.S1END);
      }
      const frames = (n, each) => { for (let i = 0; i < n; i++) { if (each) each(i); m.runFrame(); trace.push(late(m), A[S.OVRUN], A[S.HUDE + 3]); } };
      frames(150, i => m.moveMouse(i % 30 < 15 ? 3 : -3, i % 40 < 20 ? 2 : -2));
      frames(4, () => m.setKey(7, 5, true)); m.setKey(7, 5, false); frames(60);
      frames(4, () => m.setKey(7, 5, true)); m.setKey(7, 5, false); frames(40);
      A[S.TREQ] = 1; frames(120);
      const sel = A[S.M_SELY] * 10 + A[S.M_SELX];
      A[S.M_STATE + sel] = 1; A[S.M_COUNT + sel] = 3; call(m, S.SECTORIN);
      frames(600, f => { m.mouse.left = f % 9 === 0; m.moveMouse(f % 50 < 25 ? 2 : -2, 0); });
      m.mouse.left = false;
      return {k, m, A, trace: trace.join()};
    };
    const loadedRun = play(false), {k, m, A, trace} = play(true);
    let lateN = 0;
    const intact = A.subarray(S.S1BASE, S.S1END).every(v => v === 0xA5);
    check(intact && !A[S.OVMISS] && !m.stopped && trace === loadedRun.trace,
      `overlay: with S1 empty ($A5) flight, the map, a torpedo and a fight run without touching it, frame for frame as with MINES loaded (${A[S.OVMISS]} misses)`);
    // A base sector: the trampoline (MSOFF's OVMNOFF at the arrival) loads MINES.
    A[S.M_STATE + 24] = 0xFF; call(m, S.SECTORIN);
    const loaded = A[S.OVOWNER] === 0x80 && Buffer.from(A.subarray(S.MNSTART, S.MNEXTRAEND)).equals(image);
    let viewSeen = false, viewOk = false;
    const step = m.cpu.step.bind(m.cpu);
    m.cpu.step = function () { if (this.pc === S.MNVIEW && !viewSeen) { viewSeen = true; viewOk = A[S.OVOWNER] === 0x80; } return step(); };
    let tunnel = 0, refused = 0, tries = 0; lateN = 0;
    const r0 = A[S.OVREFUSE];
    for (let f = 0; f < 500; f++) {
      m.runFrame(); lateN += late(m); if (m.vic[0x1a] & 1) tunnel++;
      // While the tunnel runs, the slot refuses to be emptied (between frames: the IRQ
      // may be off after the last band, MINES' hooks are still installed).
      if (A[S.MSSTATE] === 16 && (A[S.vv2 + 1] | A[S.vv2 + 2] << 8) === S.MNVB && tries < 20) { tries++; if (call(m, S.OVLOAD, 0)) refused++; }
    }
    m.cpu.step = step;
    check(loaded && A[S.OVMISS] === 1 && viewSeen && viewOk && tunnel > 50 && !m.stopped,
      `overlay: entering a base sector with S1 empty loads MINES once (${A[S.OVMISS]} miss), byte for byte the init image; mines and the tunnel run (${tunnel} IRQ frames, ${lateN} late splits)`);
    check(tries === 20 && refused === 20 && A[S.OVREFUSE] - r0 === 20 && A[S.OVOWNER] === 0x80,
      `overlay: while MTIRQ and MINES' hooks run, OVLOAD refuses to replace MINES (${refused}/${tries} frames) and S1 keeps it`);
  }

  // ---- a normal game: MINES stays loaded through a base sector, no miss ------------------------------
  {
    const k = ready(), m = k.m, A = m.ram;
    A[S.M_STATE + 24] = 0xFF; call(m, S.SECTORIN);
    let lateN = 0; for (let f = 0; f < 500; f++) { m.runFrame(); lateN += late(m); }
    check(!A[S.OVMISS] && !A[S.OVREFUSE] && A[S.OVOWNER] === 0x80 && lateN === 0 && !A[S.OVRUN],
      `overlay: a base sector with MINES loaded: no miss, no refusal, ${lateN} late splits, ${A[S.OVRUN]} OVRUN`);
    // A death in the minefield, then the reset: MINES back in its init state.
    A[S.SHIPLOST] = 1; call(m, S.ENDARM);
    run(m, k.hooks, 330);
    A[S.ENDTIME] = 1; A[S.ENDTIME + 1] = 0; run(m, k.hooks, 120);
    check(!A[S.ENDMODE] && A[S.OVOWNER] === 0x80 && Buffer.from(A.subarray(S.MNSTART, S.MNEXTRAEND)).equals(image) && !A[S.OVMISS] &&
      Buffer.from(A.subarray(0x8100, 0x8400)).equals(Buffer.from(m0.ram1.subarray(S.B1STREAM, S.B1STREAM + 768))),
      'overlay: a reset after a minefield death reloads MINES (its init image) and the borrowed streams from bank 1');
  }

  // ---- the ENDING package: loaded a piece a frame in the view's time, complete before it is used -----
  const line = m => m.read(0xd012) + (m.read(0xd011) & 0x80 ? 256 : 0);
  const pieces = m => {          // the raster lines of the background copy's pieces (not OVLOAD's)
    const p = {first: 999, last: 0, n: 0}, step = m.cpu.step.bind(m.cpu);
    let depth = -1;
    m.cpu.step = function () {
      if (this.pc === S.B1GETY && depth < 0 && !(m.ram[S.OVSYNC] & 0x80) && m.ram[S.OVJOB] === 2) { p.first = Math.min(p.first, line(m)); depth = this.sp; p.n++; }
      if ((this.pc === S.ENDSCENE || this.pc === S.ENDWINBEGIN) && !p.entered) { p.entered = true; p.owner = m.ram[S.OVOWNER];
        p.same = Buffer.from(m.ram.subarray(S.ENDPKG, S.ENDINGEND)).equals(endingImage); }
      const r = step();
      if (depth >= 0 && this.sp > depth + 1) { p.last = Math.max(p.last, line(m)); depth = -1; }
      return r;
    };
    return p;
  };
  const endingImage = Buffer.from(m0.ram1.subarray(S.B1ENDING, S.B1ENDING + S.ENDINGEND - S.ENDPKG));
  for (const kind of ['death', 'victory']) {
    const k = ready(), m = k.m, A = m.ram, p = pieces(m);
    if (kind === 'death') { A[S.SHIPLOST] = 1; call(m, S.ENDARM); }
    else { A.fill(0, S.M_STATE, S.M_STATE + 60); A.fill(0, S.M_FLG, S.M_FLG + 4); A[S.ENDQUAL] = 1; call(m, S.ENDTRYWIN); }
    let loadedAt = -1, used = -1, lateN = 0, f = 0;
    for (; f < 400 && used < 0; f++) {
      m.runFrame(); lateN += late(m);
      if (loadedAt < 0 && A[S.OVOWNER] === 0x40) loadedAt = f;
      if (p.entered) used = f;
    }
    check(loadedAt >= 0 && loadedAt <= used && p.owner === 0x40 && !A[S.OVMISS] && p.same && p.n > 0 && p.first >= 78 && p.last < 194 && lateN === 0,
      `overlay: ${kind}: the ENDING package (${S.ENDINGEND - S.ENDPKG} bytes) is in S1 after ${loadedAt} frames, used after ${used}; ` +
      `${p.n} pieces in lines ${p.first}-${p.last}, ${A[S.OVMISS]} misses, ${lateN} late splits`);
  }
};
