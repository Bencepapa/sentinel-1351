'use strict';
// A browser save state from before the bank-1 store (2026-11-17) has an empty bank 1,
// the KERNAL's preconfigurations and no copy stub at $0100, and the ending's
// resident code of its own build. Give it this build's, taken from a fresh boot of
// the same build (fresh: {ram, ram1, mmu}): the reset snapshot, the payload and
// the packages in bank 1 are init-time data (there is no EXIT backup any more); the ending's state
// (no ending running in these saves) starts fresh; an armed ending poll stays armed.
module.exports = function adoptBank1(m, fresh, S) {
  if (m.ram1.some(v => v)) return false;          // the state has its own bank 1
  const A = m.ram, F = fresh.ram;
  m.ram1.set(fresh.ram1);
  for (const r of [1, 2, 3, 4]) m.mmu[r] = fresh.mmu[r];
  const armed = (A[S.nov3 + 1] | A[S.nov3 + 2] << 8) !== S.VIEWWORK;
  const ranges = [[0x100, 0x100 + S.B1STUBLEN], [0x200, 0xC60], [0x1C10, 0x1D00],
    [S.MSUNPACK, S.ENDEVENTEND], [0x5258, 0x5300]];
  if (S.OVBASE !== undefined) ranges.push([S.OVBASE, S.OVEND]);
  for (const [s, e] of ranges) A.set(F.subarray(s, e), s);
  if (armed) { A[S.nov3 + 1] = S.ENDVIEW & 255; A[S.nov3 + 2] = S.ENDVIEW >> 8; }
  return true;
};
