"use strict";
// Compare executable C64 IRQ writes, rather than a second copy of the band formula.
module.exports=function({boot,run,check,snap,fs,path,OUT}) {
  function call(m,a) {
    const c=m.cpu,s=[c.pc,c.sp,c.p,c.a,c.x,c.y];c.push(255);c.push(243);c.pc=a;c.p|=4;
    let n=0;const start=c.cycles;
    while(c.pc!==0xfff4&&n++<2e6)c.step();
    if(n>=2e6)throw Error('tunnel call did not return');
    [c.pc,c.sp,c.p,c.a,c.x,c.y]=s;return c.cycles-start;
  }
  const saved=JSON.parse(fs.readFileSync(path.join(__dirname,'../../briefs/ref/c64-minefield.state.json'),'utf8'));
  function reference(){const o=boot('c64game','trace');o.m.loadState(o.m.stateFromText(JSON.stringify(saved.state)));o.m.dma=true;return o;}
  function late(m){let n=0;for(let i=0;i<m.vicLog.length;i+=4){const [l,c,r]=m.vicLog.slice(i,i+3);if((r===32||r===33)&&((l>=50&&l<=76)||(l>=230&&l<=245))&&c>=16&&c<=55)n++;}return n;}
  const o=reference(),g=boot('game','trace'),m=g.m,S=g.p.symbols,A=m.ram,R=o.m.ram;
  m.dma=true;run(m,g.hooks,60);
  let idleCalls=0;const initial=m.cpu.step.bind(m.cpu);
  m.cpu.step=function(){if(this.pc===S.MTFRAME||this.pc===S.MTIRQ)idleCalls++;return initial();};
  run(m,g.hooks,30);
  check(idleCalls===0,'game: raster tunnel has no frame/IRQ calls outside the minefield');
  A[S.M_STATE+24]=255;call(m,S.SECTORIN);
  let start=false,writes=0;
  for(let f=0;f<35;f++){m.runFrame();writes+=late(m);start ||= !!(m.vic[0x1a]&1);}
  check(start&&A[S.MTAGE]>0,'game: entering a base sector installs and fades in the tunnel IRQ');
  // All colours, entry levels, exit levels and phase wraps against original code.
  let paint=true;const costs=[];
  for(const kind of [0,1])for(const fade of ['entry','exit'])for(let level=0;level<=4;level++)for(let phase=0;phase<256;phase+=7){
    R[0x9f]=1;R[0xe13]=phase;R[0xe2]=A[S.MNKIND]=kind;
    R[0xfd5]=fade==='entry'?level:255;R[0xf7f]=fade==='exit'?4-level:255;
    A[S.MTPHASE]=phase;A[S.MTAGE]=level;A[S.MSROW]=fade==='exit'?3:1;A[S.MSCLOCK]=level*16;
    // Avoid the phase=0 counter tick: test the post-tick level separately below.
    if((phase&15)===0)continue;
    costs.push(call(o.m,0xe21));call(m,S.MTPAINT);
    const eq=[0xde8,0xedc,0xedd,0xede].every((a,i)=>R[a]===A[S.MTINK+i]);if(!eq&&paint)console.log('paint mismatch',kind,fade,level,phase,[0xde8,0xedc,0xedd,0xede].map(a=>R[a]),[...A.subarray(S.MTINK,S.MTINK+4)]);paint &&=eq;
  }
  check(paint,'game: both tunnel palettes, entry/exit fades and phase wrap match C64 colour code');
  let entry=true;R[0xfd5]=0;R[0xf7f]=255;R[0xe2]=A[S.MNKIND]=0;A[S.MTAGE]=0;A[S.MSROW]=1;
  for(let phase=1;phase<=80;phase++){R[0xe13]=A[S.MTPHASE]=phase;call(o.m,0xe21);call(m,S.MTPAINT);const eq=[0xde8,0xedc,0xedd,0xede].every((a,i)=>R[a]===A[S.MTINK+i]);if(!eq&&entry)console.log('entry mismatch',phase,[0xde8,0xedc,0xedd,0xede].map(a=>R[a]),[...A.subarray(S.MTINK,S.MTINK+4)]);entry &&=eq;}
  check(entry,'game: entry fade reveals an inner band every 16 frames, matching original');
  // Reset the reference to its real main loop. Mature effect, distant base:
  // phase-keyed records account for the C64 updating its next frame at the bottom.
  const ref=reference(),Q=ref.m.ram;
  // Suppress mine impacts while measuring the tunnel itself: the original's
  // damage flash deliberately overwrites these palette bytes, including black.
  Q[0xcc71]=A[S.mn_cc71]=0x60;
  Q[0xfd5]=Q[0xf7f]=255;Q[0x17]=0x98;Q[0x23]=0xa0;
  A[S.ENX+1]=0x98;A[S.ENZ+1]=0xa0;A[S.MSROW]=1;A[S.MTAGE]=4;A[S.MNKIND]=0;
  const records=[new Map(),new Map()],frameWrites=[[],[]];
  for(const [index,k,pc,phaseAddr] of [[0,ref.m,0xefb,0xe13],[1,m,S.mt_write,S.MTPHASE]]) {
    const step=k.cpu.step.bind(k.cpu);
    k.cpu.step=function(){
      if(this.pc!==pc)return step();
      const phase=k.ram[phaseAddr],result=step(),v=k.vicLog;
      frameWrites[index].push({phase,write:[v[v.length-4],v[v.length-1]&15]});return result;
    };
  }
  for(let f=0;f<300;f++){
    for(const [index,k] of [[0,ref.m],[1,m]]){
      frameWrites[index]=[];k.runFrame();const rows=frameWrites[index];
      if(rows.length===8&&rows.every(r=>r.phase===rows[0].phase))records[index].set(rows[0].phase,rows.map(r=>r.write));
    }
    writes+=late(m);if(f===100)snap(m,'mine-tunnel');
  }
  let parity=true,maxDrift=0,count=0;const trace=[];
  for(const [phase,x] of records[0]) {
    const y=records[1].get(phase);if(!y)continue;
    count++;for(let i=0;i<8;i++){maxDrift=Math.max(maxDrift,Math.abs(x[i][0]-y[i][0]));parity &&= x[i][1]===y[i][1];}
    trace.push({phase,original:x,port:y});
  }
  check(parity&&count>=240&&maxDrift<=3,`game: tunnel C64 IRQ parity in ${count} phases, maximum raster drift ${maxDrift} lines (limit 3)`);
  check(writes===0&&A[S.OVRUN]===0,`game: tunnel DMA: ${writes} late splits, ${A[S.OVRUN]} OVRUN`);
  // Abort/map and ring handover must not leave a colour IRQ alive.
  call(m,S.MNRINGS);
  check(!(m.vic[0x1a]&1)&&A[S.VIEWBG]===0&&A[S.PHBUD+1]===48,'game: ring handover disables tunnel IRQ, clears background and restores phasor budget');
  fs.writeFileSync(path.join(OUT,'mine-tunnel-trace.json'),JSON.stringify({maxDrift,count,originalUpdateCycles:[Math.min(...costs),Math.max(...costs)],trace},null,2));
};
