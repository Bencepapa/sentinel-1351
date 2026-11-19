'use strict';
module.exports = function ({boot, run, check, snap, fs, path, OUT, resumeFromTitle}) {
  const atTitle = (m, A, S) => !A[S.ENDMODE] && A[S.OVOWNER] === S.TITLEOWNER &&
    A[S.TITLEARM] && !A[S.GENDONE] && !(m.vic[0x1a] & 1) &&
    (A[0xfffe] | A[0xffff] << 8) === S.NMIRTI &&
    ![S.vv2, S.sprcj].some(site => {
      const target = A[site + 1] | A[site + 2] << 8;
      return target >= S.S1BASE && target < S.S1END;
    });
  const call=(m,a)=>{
    const c=m.cpu, saved=[c.pc,c.sp,c.p];
    c.push(255);c.push(243);c.pc=a;c.p|=4;
    let n=0;while(c.pc!==0xfff4&&n++<2e6){c.step();if(c.jam)throw Error(c.jam);}
    if(n>=2e6)throw Error('ending call did not return: '+a.toString(16));
    const result={a:c.a,x:c.x,y:c.y};[c.pc,c.sp,c.p]=saved;return result;
  };
  const late=m=>{let n=0;for(let i=0;i<m.vicLog.length;i+=4){const [l,c,r]=m.vicLog.slice(i,i+3);
    if((r===32||r===33)&&((l>=50&&l<=76)||(l>=230&&l<=245))&&c>=16&&c<=55)n++;}return n;};
  const ready=()=>{const k=boot('game','trace');k.m.dma=true;run(k.m,k.hooks,80);return k;};
  const Video=require('../src/video.js');
  const vdcBlack=n=>{
    const px=new Uint32Array(Video.VDC_W*Video.VDC_H);
    for(const blink of [false,true]){
      Video.renderVdc(n,px,blink);
      if(!px.every(p=>(p&0xffffff)===0))return false;
    }
    return !(n.vdcReg[25]&0x40)&&n.vdcReg[26]===0&&n.vdcReg[10]===0x20;
  };
  // Seed boot text, blinking/reversed attributes and dirty glyphs. The old
  // loader overwrites all three with snapshots without ever blanking output.
  const startup=boot('game','trace'),sm=startup.m;
  // BASIC's SYS mapping exposes ROM at $4000-$7FFF. Model it here because the
  // normal JS boot maps RAM already; a pre-MMU JSR into the helper would fail
  // on a real C128 even though it passes ordinary emulator startup tests.
  sm.mmuCR=0;
  let bootRomReads=0;
  const read=sm.read.bind(sm);
  sm.read=function(a){
    if(a>=0x4000&&a<0x8000&&!(this.mmuCR&2)){bootRomReads++;return 0xff;}
    return read(a);
  };
  sm.vdcRam.fill(0xff);sm.vdcReg[25]=0x47;sm.vdcReg[26]=0xf0;
  sm.vdcReg[10]=0;sm.dma=true;
  const startCycles=sm.cpu.cycles;
  for(let i=0;i<100&&!vdcBlack(sm);i++)sm.cpu.step();
  check(vdcBlack(sm)&&sm.cpu.cycles-startCycles<400,
    'game: dirty VDC boot text/attributes/font and cursor blank within 400 entry cycles');
  check(bootRomReads===0,
    'game: VDC startup banks out BASIC before calling its RAM helper');
  let visibleWrite=false,snapshotWrites=0,startupBlack=true;
  const write=sm.vdcWrite.bind(sm);
  sm.vdcWrite=function(r,v){
    if(r===31){
      snapshotWrites++;
      if((sm.vdcReg[25]&0x40)||sm.vdcReg[26]!==0||sm.vdcReg[10]!==0x20)visibleWrite=true;
    }
    write(r,v);
  };
  for(let f=0;f<80;f++){sm.runFrame();startupBlack=startupBlack&&vdcBlack(sm);}
  check(snapshotWrites===0&&!visibleWrite&&startupBlack,
    'game: startup writes no VDC RAM (the store is bank 1) and the VDC stays black in both blink phases');
  const state=JSON.parse(fs.readFileSync(path.join(__dirname,'../../briefs/ref/c64-minefield.state.json'),'utf8'));
  const o=boot('c64game','trace'),g=ready(),m=g.m,A=m.ram,S=g.p.symbols,R=o.m.ram;
  o.m.loadState(o.m.stateFromText(JSON.stringify(state.state)));o.m.dma=true;
  check((A[S.nov3+1]|A[S.nov3+2]<<8)===S.VIEWWORK,
    'game: idle flight calls original VIEWWORK directly, with no ending poll overhead');
  check(R[0xf5b8]===60&&A[S.ENDQUAL]===R[0xf5b8],
    'game: victory initializes the same 60-check counter as original $F5B8');
  // $FD7F-$FD99 is the original sector formatter. Stop before arrival logic.
  let sectors=true;
  for(let row=0;row<6;row++)for(let col=0;col<10;col++){
    R[0x92]=A[S.M_SELX]=col;R[0x93]=A[S.M_SELY]=row;
    R[0x5465]=0x70;
    const c=o.m.cpu,saved=[c.pc,c.sp,c.p];c.pc=0xfd7f;c.p|=4;
    for(let i=0;i<30&&c.pc!==0xfd9a;i++)c.step();
    [c.pc,c.sp,c.p]=saved;
    call(m,S.SHOWSEC);
    sectors=sectors&&[0,1,4].every(i=>A[S.HUDSEC+i]===R[0x5465+i]);
  }
  // Also leave column 10: its tens digit must return to zero.
  A[S.M_SELX]=0;call(m,S.SHOWSEC);
  check(sectors&&A[S.HUDSEC]===0x70,
    'game: all 60 HUD sectors match original $FD7F, including 10.01 through 10.06 and leaving column 10');
  const dump=(n,name)=>{
    const bank=n.vicBank(),screen=bank+(n.vic[0x18]>>4)*0x400;
    const charset=bank+(n.vic[0x18]&14)*0x400;
    const regs={d018:n.vic[0x18],d011:n.read(0xd011),dd00:n.read(0xdd00),bank,screen,charset,pc:n.cpu.pc};
    for(const [label,bytes] of [['screen',n.ram.subarray(screen,screen+1024)],
      ['colour',n.colorRam],['charset',n.ram.subarray(charset,charset+2048)],
      ['bitmap',n.ram.subarray(bank+0x2000,bank+0x4000)]])
      fs.writeFileSync(path.join(OUT,name+'-'+label+'.bin'),Buffer.from(bytes));
    fs.writeFileSync(path.join(OUT,name+'-registers.json'),JSON.stringify(regs,null,2));
  };
  // Watch the live transition rather than only the settled title/rank screen.
  for(const kind of ['death']){   // (victory keeps the cockpit: see the original win screen below)
    const k=ready(),n=k.m,B=n.ram,T=k.p.symbols;
    B[T.SHIPLOST]=1;call(n,T.ENDARM);
    n.setBreak(T.end_clear,true);
    for(let f=0;f<300&&!n.breakInfo;f++)n.runFrame();
    dump(n,'game-end-'+kind+'-preclear');
    check(n.cpu.pc===T.end_clear&&(n.vic[0x11]&0x60)===0x60,
      'game: '+kind+' hides the old sprite/art bitmap before full-screen clearing');
    n.setBreak(T.end_clear,false);n.breakInfo=null;
    run(n,k.hooks,25);dump(n,'game-end-'+kind+'-title');
    check(n.vic[0x11]===0x3b&&n.vic[0x18]===0x18&&n.vicBank()===0x4000,
      'game: '+kind+' reveals the completed bitmap title in the correct VIC bank');
    R.fill(0,0x6000,0x8000);
    const titles=[[8,' THE BATTLE IS OVER'],[12,'  JARALOBA IS LOST']];
    const reports=[0xd25a,0xd639,0xd69d,0xd704];
    check(reports.every((address,i)=>{
      const expected=[];for(let row=0;row<5;row++)expected.push(...R.subarray(address+20*row,address+20*row+20),0);
      return Buffer.from(expected).equals(Buffer.from(B.subarray(T.ENDHEADS+105*i,T.ENDHEADS+105*i+105)));
    })&&[0,1,2,3].every(i=>(B[T.ENDHEADERLO+i]|B[T.ENDHEADERHI+i]<<8)===T.ENDHEADS+105*i),
      'game: the four death reports, unpacked from bank 1, match the original text bytes');
    let pixels=true;
    for(const [row,text] of titles){
      for(let i=0;i<text.length;i++){
        o.m.cpu.a=text.charCodeAt(i);o.m.cpu.x=row;o.m.cpu.y=i*2;call(o.m,0x0816);
      }
      for(let a=0x6000+row*320;a<0x6000+(row+1)*320;a++)
        pixels=pixels&&((B[a]&0xaa)===(R[a]&0xaa));
    }
    check(pixels,'game: '+kind+' title bitmap matches original renderer pixel for pixel');
    check(vdcBlack(n),'game: '+kind+' ending keeps the VDC black');
    snap(n,'game-end-'+kind+'-title');
    B[T.ENDTIME]=1;B[T.ENDTIME+1]=0;n.setBreak(T.end_copyread,true);
    for(let f=0;f<3&&!n.breakInfo;f++)n.runFrame();
    dump(n,'game-end-'+kind+'-reset');
    check(n.cpu.pc===T.end_copyread&&(n.vic[0x11]&0x60)===0x60,
      'game: '+kind+' restart hides the partial VDC matrix/art restoration');
    n.setBreak(T.end_copyread,false);n.breakInfo=null;
    run(n,k.hooks,100);
    check(vdcBlack(n),'game: '+kind+' restart keeps the VDC black');
    check(atTitle(n,B,T)&&!B[T.OVRUN], 'game: '+kind+' transition returns to TITLE without OVRUN');
  }
  // The rating, the statistics and the letters are the ENDING package's (S1): load it.
  m.cpu.x=2;call(m,S.OVLOAD);
  check(A[S.OVOWNER]===0x40,'game: the ENDING package loads into S1 for the direct calls below');
  let cases=0,match=true;
  const put=(r,a,v,n=2)=>{for(let i=0;i<n;i++)r[a+i]=(v>>>(8*i))&255;};
  for(let diff=0;diff<5;diff++)for(let win=0;win<2;win++)for(let planet=0;planet<2;planet++)for(let seed=0;seed<12;seed++){
    R[0xe0]=A[S.DIFF]=diff;R[0xf34b]=A[S.ENDVICTORY]=win?4:0;R[0xf431]=A[S.ENDPLANET]=planet;
    for(let i=0;i<60;i++)R[0x33c+i]=A[S.M_STATE+i]=0;
    [0,9,50,59].forEach((a,i)=>R[0x33c+a]=A[S.M_STATE+a]=(seed&(1<<i))?0x80:0);
    [12,17,42,47].forEach((a,i)=>R[0x33c+a]=A[S.M_STATE+a]=(seed&(1<<i))?0xff:0);
    for(const [a,b,v,n] of [[0xf432,S.ENDHITS,seed*71,2],[0xf434,S.ENDKILLS,seed*19+1,2],
      [0xf436,S.ENDRENER,seed*8931,3],[0xf439,S.ENDRPROTON,seed*3,2],[0xf43b,S.ENDSHOTS,seed*101,2]]){put(R,a,v,n);put(A,b,v,n);}
    const original=call(o.m,0xf440),ported=call(m,S.ENDRATING);
    match=match&&original.a===ported.a&&original.x===ported.x&&R[0xf43d]===A[S.ENDSCORE]&&R[0xf43e]===A[S.ENDSCORE+1];cases++;
  }
  check(match,`game: ${cases} original/port ratings match, all difficulties, victory/planet flags, kills, bases, energy, hits, shots and protons`);
  R.fill(0x79,0x543e,0x5442);R[0xf34b]=4;R[0xf86b]=1;put(R,0xf436,173,3);
  call(o.m,0xf9d6);
  A[S.ENDMODE]=2;A.fill(0,S.ENDENER,S.ENDENER+3);A.fill(0x79,S.HUDE,S.HUDE+4);
  call(m,S.ENDRATINGINPUT);
  check(R[0xf436]===174&&A[S.ENDRENER]===R[0xf436],
    'game: victory energy tally includes original $F9D6 full-meter overflow unit');
  R[0xf86b]=1;call(o.m,0xf9d6);call(m,S.ENDBASETALLY);call(m,S.ENDRATINGINPUT);
  check(R[0xf436]===175&&A[S.ENDRENER]===R[0xf436],
    'game: every completed repair also counts the original full-meter overflow unit');
  // Compare the renderer's actual bitmap pixels, not just its source strings.
  R.fill(0,0x6000,0x8000);A.fill(0,0x63c0,0x7680);
  A[S.ENDROW]=8;put(A,S.ENDTEXTP,S.ENDCLASSTEXT);
  call(m,S.ENDPRINT);
  o.m.cpu.a=67;o.m.cpu.x=8;o.m.cpu.y=0;call(o.m,0x0816);
  check(Buffer.from(R.subarray(0x6a00,0x6a10)).equals(Buffer.from(A.subarray(0x6a00,0x6a10))),
    'game: large ending letters match original $0816 pixel for pixel, using protected bitmap value 2');
  o.m.sidLog.length=m.sidLog.length=0;
  call(o.m,0x3350);call(o.m,0x274c);call(m,S.ENDALARM);
  check([0x404,0x402,0x401,0x405,0x406,0x403,0x40b,0x40d,0x407,0x40c,0x408,0x418]
    .every(a=>o.m.sid[a&31]===m.sid[a&31]),
    'game: death alarm and pulse-rattle SID setup match original $3350/$274C');
  const workspace=boot('game','trace'),wm=workspace.m,WA=wm.ram,WS=workspace.p.symbols;
  const before=Buffer.from(Uint8Array.from({length:0xa60},(_,i)=>(i*73+(i>>8)*19+0x37)&255));
  WA.set(before,0x200);wm.vdcRam.fill(0xA5);wm.dma=true;run(wm,workspace.hooks,80);
  // No return to BASIC: BASIC's $0200-$0C5F is not kept anywhere (bank 1 holds only
  // the store from the snapshot on), the core is installed over it.
  check(WS.ENDCOREEND<=0xc60&&WS.ENDLOADEREND<=0x1d00&&WS.ENDB1END<=0x6400&&wm.vdcRam.every(v=>v===0xA5)&&
    !wm.ram1.subarray(0x400,WS.ENDB1SNAP).some(v=>v)&&WS.EXIT===WS.CKEXITFREE&&
    !before.subarray(0,WS.ENDCOREEND-0x200).equals(Buffer.from(WA.subarray(0x200,WS.ENDCOREEND))),
    'game: ending core, loader and the bank-1 snapshot/payload fit their checked bounds; BASIC\'s low RAM is not kept (no EXIT), VDC RAM untouched');

  // Record the original death path from a real executable save, with DMA.
  o.m.loadState(o.m.stateFromText(JSON.stringify(state.state)));o.m.dma=true;R[0x8300]=255;
  const points={0x8869:'death',0x88d7:'scene',0xf34c:'report',0xf440:'rating'};
  for(const a of Object.keys(points))o.m.setBreak(+a,true);
  const t=o.m.frame,events={},palette=new Set(),sid=[];
  for(let f=0;f<850;f++){
    o.m.runFrame();
    if(o.m.breakInfo){const pc=o.m.breakInfo.pc;events[points[pc]]=o.m.frame-t;o.m.setBreak(pc,false);o.m.breakInfo=null;}
    for(let i=0;i<o.m.vicLog.length;i+=4)if(o.m.vicLog[i+2]===0x21&&o.m.frame-t<255)palette.add(o.m.vicLog[i+3]&15);
    if(o.m.frame-t<3)sid.push(...o.m.sidLog);
    if(events.rating!==undefined)break;
  }
  check(events.scene-events.death===254&&events.rating>600&&events.rating<625,
    `game: original DMA death timeline scene/report/rating ${events.scene}/${events.report}/${events.rating}`);
  fs.writeFileSync(path.join(OUT,'game-end-original.json'),JSON.stringify({events,palette:[...palette],sid},null,2));

  for(const planet of [false,true]){
    const k=ready(),n=k.m,B=n.ram,T=k.p.symbols;
    n.setBreak(T.frame,true);for(let f=0;f<3&&n.cpu.pc!==T.frame;f++)n.runFrame();
    const stackAtStart=n.cpu.sp;n.setBreak(T.frame,false);
    if(planet){B[T.M_DEAD+4]=1;call(n,T.ENDARM);}
    else {B[T.SHLD]=0;call(n,T.SHIPHIT);}
    const start=n.frame;let phase=-1,scene=-1,report=-1,rank=-1,lateCount=0,blocked=true;
    const bottomSprites=Buffer.from(B.subarray(0x7cc0,0x8000));
    const reportGlyph=Buffer.from(B.subarray(0x41f8,0x4200));
    B.fill(255,0x41f8,0x4200); // the temporary report block if planet loss interrupts docking
    B[T.SHLT]=3;B[T.SQTYPE]=3;B[T.SHLK]=5;B[T.shpj]=0x20;B[T.ETYPE]=3;call(n,T.GTYPE); // a type 3 fight just ended
    n.setBreak(T.ENDSCENE,true);n.setBreak(T.ENDREPORT,true);n.setBreak(T.ENDRATING,true);
    for(let f=0;f<800;f++){
      n.setKey(7,5,f>=10&&f<20);
      n.runFrame();
      if(f>=10&&f<25)blocked=blocked&&!B[T.MAPSHOWN];
      if(B[T.ENDMODE]&&phase<0)phase=n.frame-start;
      if(n.breakInfo){const pc=n.breakInfo.pc;if(pc===T.ENDSCENE)scene=n.frame-start;
        if(pc===T.ENDREPORT)report=n.frame-start;if(pc===T.ENDRATING)rank=n.frame-start;
        n.setBreak(pc,false);n.breakInfo=null;}
      if(scene<0)lateCount+=late(n);
      if(rank>=0){run(n,k.hooks,12);break;}
    }
    check(scene-phase===254,`game: ${planet?'planet loss':'shield death'} flashes over 255 inclusive DMA frames (${scene-phase} frame intervals)`);
    check(blocked,'game: map key cannot interrupt the death flash');
    check(Math.abs(rank-events.rating)<=12,
      `game: ${planet?'planet loss':'shield death'} report/rating ${report}/${rank} frames, original rating ${events.rating} (12-frame bound)`);
    check(n.vic[0x15]===0&&n.vic[0x11]===0x3b&&n.vic[0x18]===0x18&&B[T.ENDCLASS]<=7,
      'game: ending removes cockpit/sprites, keeps bitmap/stars and calculates class');
    check(!B[T.OVRUN]&&lateCount===0,`game: ending handover has ${lateCount} late splits and ${B[T.OVRUN]} OVRUN`);
    const letters=[];
    for(let a=0x6000;a<0x8000;a++)for(let shift=0;shift<8;shift+=2)
      if(((B[a]>>shift)&3)===2)letters.push([a,shift]);
    run(n,k.hooks,30);
    let stars=0;for(let a=0x63c0;a<0x7680;a++)for(let shift=0;shift<8;shift+=2)if(((B[a]>>shift)&3)===1)stars++;
    check(stars>0&&letters.every(([a,shift])=>((B[a]>>shift)&3)===2),
      'game: ending stars remain visible as pixel 1 and never erase bitmap letters');
    snap(n,planet?'game-end-planet':'game-end-death');
    B[T.ENDTIME]=1;B[T.ENDTIME+1]=0;
    run(n,k.hooks,100);
    check(atTitle(n,B,T),'game: death timeout returns to TITLE with S1 hooks and raster IRQ off');
    n.setBreak(T.frame,true);
    resumeFromTitle(n,T);
    for(let f=0;f<30&&n.cpu.pc!==T.frame;f++)n.runFrame();
    check(n.cpu.pc===T.frame&&n.cpu.sp===stackAtStart,
      'game: restart discards the abandoned frame return and preserves the caller stack');
    n.setBreak(T.frame,false);
    run(n,k.hooks,100);
    check(!n.stopped&&!B[T.ENDMODE]&&!B[T.SHIPLOST]&&B[T.SHLD]===40&&B[T.M_SELX]===4&&B[T.M_SELY]===2,
      'game: ending timeout restores a fresh game in sector 05.03');
    check(bottomSprites.equals(Buffer.from(B.subarray(0x7cc0,0x8000))),
      'game: reset restores all phasor, last-fighter, scanner and planet sprite slots');
    check(reportGlyph.equals(Buffer.from(B.subarray(0x41f8,0x4200))),
      'game: reset restores the report glyph if planet loss interrupts docking');
    check(B[T.SHLT]===1&&B[T.SQTYPE]===1&&B[T.SHLK]===0&&B[T.shpj]===0x2c&&B[T.ETYPE]===1&&B[T.sprmc]===0x29&&B[T.sprmc+1]===0x8f&&B[T.plshp]===0x38,
      'game: restart returns the fighter shape cache, type and sprite looks to type 1 (fighters render as at a fresh start)');
    const field=Buffer.from(B.subarray(0x63c0,0x7680));run(n,k.hooks,80);
    check(!B[T.OVRUN]&&!field.equals(Buffer.from(B.subarray(0x63c0,0x7680))),
      'game: reset resumes live stars without raster overruns');
  }
  const win=ready(),W=win.m.ram,V=win.p.symbols;
  W.fill(0,V.M_STATE,V.M_STATE+60);W.fill(0,V.M_FLG,V.M_FLG+4);
  [12,17,42,47].forEach(a=>W[V.M_STATE+a]=255);
  W[V.M_STATE+1]=1;run(win.m,win.hooks,20);
  check(!W[V.ENDMODE],'game: surviving squadron prevents victory after all enemy motherships are gone');
  W[V.M_STATE+1]=0;W[V.M_FLG]=1;call(win.m,V.ENDTRYWIN);run(win.m,win.hooks,20);
  check(!W[V.ENDMODE],'game: pending mothership attack prevents victory');
  W[V.M_FLG]=0;run(win.m,win.hooks,35);
  check(!W[V.ENDMODE]&&W[V.ENDQUAL]>0&&W[V.ENDQUAL]<60,
    'game: clearing every enemy starts the original 60-qualified-check victory countdown');
  run(win.m,win.hooks,520);
  check(W[V.ENDMODE]===2&&W[V.ENDVICTORY]===4&&W[V.ENDPHASE]>=1,
    'game: clearing every enemy and pending attack enters victory with the original rating bonus');
  snap(win.m,'game-end-victory');

  {   // the last enemy is removed by the map (no kill hook): the poll armed by an earlier kill must still see it
    const w2=ready(),X=w2.m.ram,Q=w2.p.symbols;
    X.fill(0,Q.M_STATE,Q.M_STATE+60);X.fill(0,Q.M_FLG,Q.M_FLG+4);
    [12,17,42,47].forEach(a=>X[Q.M_STATE+a]=255);
    X[Q.M_STATE+1]=1;X[Q.M_STATE+2]=1;X[Q.M_SELX]=1;X[Q.M_SELY]=0;X[Q.M_COUNT+1]=1;X[Q.CURG]=0;w2.m.cpu.x=0;call(w2.m,Q.KILLHK);run(w2.m,w2.hooks,20);
    check(!X[Q.ENDMODE]&&(X[Q.nov3+1]|X[Q.nov3+2]<<8)===Q.ENDVIEW,'game: a kill that leaves squadrons still arms the victory poll');
    X[Q.M_STATE+1]=0;X[Q.M_STATE+2]=0;run(w2.m,w2.hooks,600);
    check(X[Q.ENDMODE]===2&&X[Q.ENDVICTORY]===4,
      'game: victory fires on its own once the last squadron is gone by any path, without a planet shot');
  }
  {   // the original polls the win on the map's tick too (about 4.7 frames a poll while the map is up, a
      // cockpit frame per loop otherwise): the last kill returns to the map and the win fires there
    const w3=ready(),Y=w3.m.ram,P=w3.p.symbols,mm=w3.m;
    Y.fill(0,P.M_STATE,P.M_STATE+60);Y.fill(0,P.M_COUNT,P.M_COUNT+60);Y.fill(0,P.M_FLG,P.M_FLG+4);
    [12,17,42,47].forEach(a=>Y[P.M_STATE+a]=255);
    Y[P.M_SELX]=2;Y[P.M_SELY]=0;Y[P.M_STATE+2]=1;Y[P.M_COUNT+2]=1;Y[P.SQCOUNT]=1;
    mm.cpu.x=0;call(mm,P.KILLHK);run(mm,w3.hooks,3,()=>mm.setKey(7,5,true));mm.setKey(7,5,false);
    let winAt=-1;
    for(let f=0;f<900&&winAt<0;f++){run(mm,w3.hooks,1);if(Y[P.ENDMODE]===2)winAt=f;}
    check(Y[P.M_STATE+2]===0&&winAt>200&&winAt<330,
      'game: with the map up after the last kill the win polls keep running on the map tick and fire at '+winAt+' frames (original ~4.7 frames a poll)');
  }
  // The brief's low-shield save is the C128 program. Recreate its public
  // sector/ship state with current executable code and the current VDC backup.
  const supplied=JSON.parse(fs.readFileSync(path.join(__dirname,'../../briefs/ref/low-shield.state.json'),'utf8'));
  check(supplied.program==='game'&&supplied.state.model==='c128',
    'game: supplied low-shield fixture is identified correctly as the C128 port');
  const low=ready(),lm=low.m,L=lm.ram,LS=low.p.symbols,old=Buffer.from(supplied.state.arrays.ram,'base64');
  const streams=Buffer.from(L.subarray(0x8100,0x8400));
  L[LS.M_SELX]=old[LS.M_SELX];L[LS.M_SELY]=old[LS.M_SELY];
  L[LS.M_STATE+50]=128;call(lm,LS.SECTORIN);run(lm,low.hooks,30);
  for(const n of ['ENX','ENY','ENZ'])L.set(old.subarray(LS[n],LS[n]+2),LS[n]);
  L[LS.SHLD]=3;L.set(old.subarray(LS.SYSHP,LS.SYSHP+8),LS.SYSHP);
  let lost=-1,liveLate=0;
  for(let f=0;f<1500;f++){lm.runFrame();liveLate+=late(lm);if(L[LS.ENDMODE]){lost=f;break;}}
  check(lost>=0&&!L[LS.MSSTATE]&&!L[LS.HYPON]&&!lm.vic[0x1a],
    `game: low-shield minefield/incoming-proton scenario dies and stops its tunnel/base hooks (${lost} frames)`);
  run(lm,low.hooks,280);
  check(liveLate===0&&!L[LS.OVRUN]&&!lm.vic[0x15],
    `game: live minefield death removes sprites with ${liveLate} late splits and ${L[LS.OVRUN]} OVRUN`);
  L[LS.ENDTIME]=1;L[LS.ENDTIME+1]=0;run(lm,low.hooks,100);
  check(streams.equals(Buffer.from(L.subarray(0x8100,0x8400)))&&!L[LS.ENDMODE],
    'game: reset after minefield death restores all 768 borrowed movement-stream bytes');

  {   // The original victory ($F5B9) from the supplied C64 save: the map is open and
      // the last enemy gone. The port replays its sectors, statistics and energy.
    const save=JSON.parse(fs.readFileSync(path.join(__dirname,'../../briefs/ref/c64-last-enemy-map-then-win.state.json'),'utf8'));
    const c=boot('c64game','trace'),cm=c.m,C=cm.ram;
    cm.loadState(cm.stateFromText(JSON.stringify(save.state)));cm.dma=true;
    const pts={0xf5ed:'trigger',0xf600:'text',0xf696:'reveal',0xf606:'wait'};
    for(const a of Object.keys(pts))cm.setBreak(+a,true);
    const oe={},at={};let t0=0;
    for(let f=0;f<400&&oe.wait===undefined;f++){
      cm.runFrame();
      while(cm.breakInfo){
        const pc=cm.breakInfo.pc;cm.setBreak(pc,false);cm.breakInfo=null;
        if(pts[pc]==='trigger'){
          t0=cm.frame;at.energy=Array.from(C.subarray(0x543e,0x5442));at.diff=C[0xe0];at.map=C[0xb8];
          at.sectors=Array.from(C.subarray(0x33c,0x378));at.hits=C[0xf432]|C[0xf433]<<8;
          at.kills=C[0xf434]|C[0xf435]<<8;at.protons=C[0xf439]|C[0xf43a]<<8;at.shots=C[0xf43b]|C[0xf43c]<<8;
        }
        if(pts[pc]==='text')at.used=C[0xf436]|C[0xf437]<<8|C[0xf438]<<16;
        oe[pts[pc]]=cm.frame-t0;
      }
      if(oe.trigger!==undefined&&oe.full===undefined&&[0,1,2,3].every(i=>C[0x543e+i]===0x79))oe.full=cm.frame-t0;
    }
    run(cm,c.hooks,10);
    const letters=r=>{const out=[];for(let a=0x6000+4*320;a<0x6000+16*320;a++)for(let s=0;s<8;s+=2)out.push(((r[a]>>s)&3)===2?1:0);return out.join('');};
    const originalText=letters(C);
    snap(cm,'game-end-win-original');
    const k=ready(),n=k.m,B=n.ram,T=k.p.symbols;
    run(n,k.hooks,4,()=>n.setKey(7,5,true));n.setKey(7,5,false);run(n,k.hooks,40);
    const mapOpen=B[T.MAPSHOWN]===1&&!B[T.WIPE];
    B.set(at.sectors,T.M_STATE);B.fill(0,T.M_FLG,T.M_FLG+4);B[T.DIFF]=at.diff;B.set(at.energy,T.HUDE);
    put(B,T.HITS,at.hits);put(B,T.KILLS,at.kills-1);put(B,T.SHOTS,at.shots);put(B,T.ENDPROTON,at.protons);
    put(B,T.ENDENER,at.used-0xae,3);
    B[T.ENDQUAL]=1;call(n,T.ENDTRYWIN);
    n.setBreak(T.ENDWINSTART,true);let p0=-1;
    for(let f=0;f<40&&p0<0;f++){n.runFrame();if(n.breakInfo){p0=n.frame;n.setBreak(T.ENDWINSTART,false);n.breakInfo=null;}}
    const pe={};let lateCount=0,hud=0;
    for(let f=0;f<120;f++){
      n.runFrame();lateCount+=late(n);
      const d=n.frame-p0;
      if(pe.full===undefined&&[0,1,2,3].every(i=>B[T.HUDE+i]===0x79))pe.full=d;
      if(pe.reveal===undefined&&B[0x44a0]===0x14)pe.reveal=d;
      if(pe.wait===undefined&&B[T.ENDPHASE]===3)pe.wait=d;
      for(let i=0;i<n.vicLog.length;i+=4)if(n.vicLog[i+2]===0x18&&n.vicLog[i+3]===0x20)hud++;
    }
    let stars=0;for(let a=0x63c0;a<0x7680;a++)for(let s=0;s<8;s+=2)if(((B[a]>>s)&3)===1)stars++;
    snap(n,'game-end-win-port');
    fs.writeFileSync(path.join(OUT,'game-end-win-timeline.json'),JSON.stringify({original:oe,port:pe,stats:at},null,2));
    check(p0>0&&mapOpen&&!B[T.MAPSHOWN]&&B[T.ENDMODE]===2,
      `game: victory fires over the open map as in the save (map ${at.map}) and closes it`);
    check(['full','reveal','wait'].every(e=>Math.abs(pe[e]-oe[e])<=3),
      `game: victory energy full / text revealed / rank done at ${pe.full}/${pe.reveal}/${pe.wait} frames, original ${oe.full}/${oe.reveal}/${oe.wait} (3-frame bound)`);
    const portText=letters(B),cells=new Set();
    for(let i=0;i<portText.length;i++)if(portText[i]!==originalText[i]){const a=(i>>2);cells.add(`${4+Math.floor(a/320)}:${(a%320)>>4}`);}
    check(portText===originalText,
      `game: victory text block, numbers and rank (bitmap rows 4-15) match the original pixel for pixel${cells.size?' (row:character differing '+[...cells].join(' ')+')':''}`);
    check(hud>=200&&stars>0&&[0,1,2,3].every(i=>B[T.HUDE+i]===0x79)&&B[0x4400+4*40]===0x14&&B[0x4400+17*40]===0x1e,
      `game: victory keeps the HUD split (${hud} text-mode writes), cockpit and ${stars} star pixels; energy 9999, rows 4-16 purple`);
    check(lateCount===0&&!B[T.OVRUN],`game: victory scene has ${lateCount} late splits and ${B[T.OVRUN]} OVRUN`);
    const fresh=ready().m.ram;
    B[T.ENDTIME]=1;B[T.ENDTIME+1]=0;run(n,k.hooks,100);
    check(atTitle(n,B,T),'game: victory timeout returns to TITLE with S1 hooks and raster IRQ off');
    resumeFromTitle(n,T);
    run(n,k.hooks,15);
    check(!B[T.ENDMODE]&&(B[T.gplmode+1]|B[T.gplmode+2]<<8)===T.MAPSHOWN&&(B[T.germode+1]|B[T.germode+2]<<8)===T.MAPSHOWN,
      'game: victory restart restores the star plotter and a fresh game');
    check(Buffer.from(fresh.subarray(0x7680,0x8000)).equals(Buffer.from(B.subarray(0x7680,0x8000)))&&
      Buffer.from(fresh.subarray(0x48c8,0x4b40)).equals(Buffer.from(B.subarray(0x48c8,0x4b40)))&&
      Buffer.from(fresh.subarray(0x4400,0x47e8)).equals(Buffer.from(B.subarray(0x4400,0x47e8))),
      'game: restart unpacks the cockpit art, bottom sprites, matrix and hidden text rows from bank 1');
  }

  const waits=[];
  // (stop: RUN/STOP held from the death/victory to the reset as well: there is no return
  // to BASIC, the key does nothing; the reset comes on the same frame, the fresh game runs.)
  for(const kind of ['death','win'])for(const [button,stop] of [[true,false],[true,true],[false,false]]){
    const k=ready(),n=k.m,B=n.ram,T=k.p.symbols;
    if(kind==='death'){B[T.SHIPLOST]=1;call(n,T.ENDARM);}
    else {B.fill(0,T.M_STATE,T.M_STATE+60);B.fill(0,T.M_FLG,T.M_FLG+4);B[T.ENDQUAL]=1;call(n,T.ENDTRYWIN);}
    if(kind==='win'){   // victory: from the trigger ($F5ED), as the original's trace below
      n.setBreak(T.ENDWINSTART,true);for(let f=0;f<20&&!n.breakInfo;f++)n.runFrame();
      n.setBreak(T.ENDWINSTART,false);n.breakInfo=null;
      B.set([0x75,0x78,0x73,0x70],T.HUDE);   // the save's energy at the trigger: 5830
    }
    n.mouse.left=button;n.setBreak(T.ENDRESET,true);n.setKey(7,7,stop);n.setBreak(T.EXIT,stop);
    const start=n.frame;let at=-1,exitAt=-1;
    for(let f=0;f<23500;f++){n.runFrame();if(n.breakInfo){if(n.breakInfo.pc===T.EXIT){exitAt=n.frame;n.breakInfo=null;continue;}at=n.frame-start;break;}}
    // C64 references: death from the minefield save; victory from the supplied
    // last-enemy save (fire held from the trigger: 584; untouched: 19,040)
    const original=kind==='death'?(button?715:10410):(button?584:19040);
    if(stop){
      const plain=waits.find(w=>w.kind===kind&&w.button&&!w.stop).port;
      n.setBreak(T.ENDRESET,false);n.breakInfo=null;n.mouse.left=false;run(n,k.hooks,120);
      check(at===plain&&exitAt<0&&!n.stopped&&n.mmuCR===0x3E&&atTitle(n,B,T)&&B[T.SHLD]===40&&B[T.M_SELX]===4&&B[T.M_SELY]===2&&!B[T.OVRUN],
        `game: RUN/STOP held through the ${kind} ending does nothing: the same reset (${at}/${plain} frames), then TITLE`);
      n.setKey(7,7,false);
    }
    waits.push({kind,button,stop,original,port:at});
    if(!stop)check(Math.abs(at-original)<=10,
      `game: ${kind} ${button?'held-button':'automatic'} reset ${at} DMA frames, C64 reference ${original}`);
  }
  fs.writeFileSync(path.join(OUT,'game-end-reset-comparison.json'),JSON.stringify(waits,null,2));
};

