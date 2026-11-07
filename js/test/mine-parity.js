'use strict';
module.exports=function({boot,run,check,fs,path,OUT}) {
  function call(m,a){const c=m.cpu,save=[c.pc,c.sp,c.p,c.a,c.x,c.y];c.push(255);c.push(243);c.pc=a;c.p|=4;let n=0;while(c.pc!==0xfff4&&n++<2e6)c.step();if(n>=2e6)throw Error('parity call '+a.toString(16));[c.pc,c.sp,c.p,c.a,c.x,c.y]=save;}
  const o=boot('c64game','trace'),g=boot('game','trace'),m=g.m,A=m.ram,S=g.p.symbols,R=o.m.ram;
  run(o.m,o.hooks,300);run(m,g.hooks,60);m.dma=o.m.dma=true;
  // Stop precisely after the original installs its own bounds, rather than
  // guessing them from the sprite's visible position.
  R[0x92]=R[0x93]=0;R[0x33c]=0xff;R[0xE1]=1;
  o.m.cpu.pc=0x8c44;o.m.setBreak(0x8c91,true);o.m.runFrame();o.m.setBreak(0x8c91,false);
  check(R[0x3f8]===135&&R[0x3f9]===165&&R[0x336]===145,'parity: C64 minefield installs Y 135..165, centre 145 (10 above, 20 below)');
  call(m,S.MNENTER);A[S.MSSTATE]=16;
  let cursors=true;
  for(const mouse of [false,true]) for(const down of [false,true]) {
    R[0x4b]=mouse?0:0x80;A[S.MPRES]=mouse?1:0;
    R[0x120a]=A[S.CURY]=145;R[0x8420]=0;
    for(let f=0;f<80;f++) {
      R[0x96]=A[S.JOY]=mouse?0xef:down?0xfe:0xfd;
      R[0x3fe]=A[S.MDX]=0;R[0x3ff]=A[S.MDY]=down?4:252;
      call(o.m,0xb2d8);call(m,S.CURSOR);
      cursors &&= R[0x120a]===A[S.CURY];
    }
    cursors &&= A[S.CURY]===(down?165:135);
  }
  check(cursors,'parity: mouse and joystick cursor positions match C64 in both directions for every clamp step');
  call(m,S.MNOFF);
  check(A[S.BND+2]===88&&A[S.BNDH+2]===173&&A[S.YCEN]===129&&A[S.g_hk2+6]===(S.INPUT&255)&&A[S.g_hk2+7]===(S.INPUT>>8),
    'parity: base exit restores cursor bounds and direct INPUT hook (no idle wrapper)');
  // The standing entry message is ticked by the original fine-scroll clock:
  // five character ticks, four frames each. Both programs get the same clock
  // phase and toggle phase here; compare all 40 characters/colours every frame.
  const trace=[];
  for(const kind of [0x80,0xff]) {
    R.set([0xa9,0x87,0x48,0xa9,kind===0x80?0xd9:0xb9,0x48,0xa9,0x3f,0x48,0xa9,0x81,0xa2,5,0xa0,10,0x20,0xe5,0x9b,0x60],0x600);
    call(o.m,0x600);R[0x88]=0;R[0x13d4]=1;R[0x13d3]=5;R[0x9be4]=0;
    A[S.M_STATE+24]=kind;call(m,S.SECTORIN);A[S.MSSTATE]=1;A[S.MAPSHOWN]=A[S.WIPE]=0;
    const read=m.read;m.read=function(a){return a===0xd012?80:read.call(this,a);};call(m,S.MSVIEW);m.read=read;A[S.MSGTG]=0;
    let same=true;const row=Buffer.from(A.subarray(S.LRROW,S.LRROW+40));
    // Original text ends one byte earlier: compare the meaningful text and
    // require both row contents to stay unchanged until the final flip.
    const originalRow=Buffer.from(R.subarray(0x5798,0x57c0));
    const flips=[];let prev=0;
    for(let f=0;f<200;f++) {
      call(o.m,0x13d5);call(m,S.MSGFRAME);call(m,S.MNREAD);
      const col=o.m.read(0xdb98)&15;
      if(col!==prev){flips.push([f+1,col]);prev=col;}
      same &&= col===(m.read(S.COLROW)&15)&&!!R[0x9be3]===!!A[S.MSGON];
      if(f<199)same &&= row.equals(Buffer.from(A.subarray(S.LRROW,S.LRROW+40)))&&originalRow.equals(Buffer.from(R.subarray(0x5798,0x57c0)));
    }
    trace.push({kind,flips});
    check(same&&flips.length===10&&!A[S.MSGON],`parity: ${kind.toString(16)} entry text survives all 200 frames; ten original colour flips match frame by frame`);
  }
  fs.writeFileSync(path.join(OUT,'mine-parity-messages.json'),JSON.stringify(trace,null,2));
  // The original launch is in the mine/settle loops ($8CA3/$908A), absent
  // from the ring, enemy-proton and repair loops. Test the active input hook.
  call(m,S.MNENTER);A[S.MAPSHOWN]=A[S.WIPE]=A[S.HYPON]=A[S.HPEND]=0;
  let firing=true,refusal=true,lock=true;
  for(const state of [1,16,2,3,4,5,6,7,8,9,10,11]) {
    A[S.MSSTATE]=state;m.mouse.left=true;
    call(m,S.MNINPUT);
    if(state!==16)firing &&= !A[S.FIREFLAG]&&!A[S.SHOTARM]&&!A[S.SHOTON];
    else firing &&= !!A[S.FIREFLAG];
    A[S.TPF]=A[S.TREQ]=A[S.TSPP]=A[S.TMBP]=0;
    for(const action of [S.GSPACE,S.GBOTH]) {
      A[S.TPF]=A[S.TREQ]=A[S.TSPP]=A[S.TMBP]=0;
      const protons=Buffer.from(A.subarray(0x485a,0x485c));
      m.sidLog.length=0;call(m,action);call(m,S.GTORP);
      if(state!==2&&state!==3)refusal &&= !A[S.TPF]&&!A[S.TREQ]&&protons.equals(Buffer.from(A.subarray(0x485a,0x485c)))&&!m.sidLog.length;
    }
    A[S.JOYG]=0xf0;A[S.SHX]=A[S.SHY]=0;A[S.FLATCH]=0;A[S.FRMC]=2;
    if(state!==16){call(m,S.MNSTARSTEER);lock &&= !A[S.SHX]&&!A[S.SHY];}
  }
  check(firing,'parity: only mine/settling phase launches phasors; every later mothership phase refuses fire');
  check(refusal,'parity: SPACE/both buttons refuse silently without spending protons in mine/settling and finished base phases');
  check(lock,'parity: star steering remains locked through all ring, destruction and repair phases');
  m.mouse.left=false;call(m,S.MNOFF);
  const phases=[];
  for(const phase of ['mine','settle','rings']) for(const buttons of ['SPACE','both']) {
    const g=boot('c64game','trace'),m=g.m,R=m.ram;run(m,g.hooks,300);m.dma=true;
    R[0xE1]=R[0xE2]=1;R[0x88]=R[0xBA]=R[0xB8]=0;R[0x89]=1;
    R[0x033C]=0x80;R[0x92]=R[0x93]=0;R[0x17]=0xa0;R[0x23]=0x94;R[0x3734]=1;R[0x8450]=9;
    if(buttons==='SPACE')m.setKey(7,4,true);else {m.mouse.right=true;R[0x4b]=0;m.moveMouse(2,0);}
    m.mouse.left=true;
    let launches=0,steers=0,requests=0;const step=m.cpu.step.bind(m.cpu);
    m.cpu.step=function(){if(this.pc===0x1467)launches++;if(this.pc===0x39c1)steers++;if(this.pc===0xbada)requests++;return step();};
    m.cpu.p&=~4;m.cpu.pc=phase==='mine'?0x8c44:phase==='settle'?0x9054:0x909d;
    R[0xBAD1]=R[0xBACE]=0;R.set([0x4c,0,3],0x300);m.cpu.push(2);m.cpu.push(255);
    run(m,g.hooks,80);
    phases.push({phase,buttons,launches,steers,requests,protons:R[0x8450]});
    check(phase==='rings'?launches===0&&steers===0&&requests>0&&R[0x8450]<9:
      (buttons==='both'||launches>0)&&requests===0&&R[0x8450]===9&&(phase==='mine'||steers===0),
      `parity: C64 ${phase} 80 DMA frames, ${buttons}: ${launches} phasors, ${steers} steering calls, ${9-R[0x8450]} protons spent`);
  }
  fs.writeFileSync(path.join(OUT,'mine-parity-phases.json'),JSON.stringify(phases,null,2));
  {
    const g=boot('c64game','trace'),m=g.m,R=m.ram;run(m,g.hooks,300);m.dma=true;
    R[0x88]=R[0xBA]=R[0xE1]=R[0xD3]=0;R[0x3734]=1;R[0xC593]=3;
    R[0x9be3]=0;R[0x9be2]=0x80;R[0x13d4]=0;
    R.set([0xa0,0x88,0x90,0x89,0x80,0x87],0x16);
    R.set([0x90,0x88,0x90,0x88,0x90,0x88],0x22);m.cpu.pc=0xb3f6;
    const radar=[];
    for(let f=0;f<15;f++){m.runFrame();radar.push({frame:f,range:R[0xD3],depth:[...R.subarray(0x22,0x28)],y:[...R.subarray(0x305b,0x305e)],row:[...R.subarray(0x5798,0x57c0)]});}
    check(radar.every(f=>f.range===0&&f.row.every(c=>c===0x60))&&radar.some(f=>f.y.some(y=>y>=150)),
      'parity: C64 acceleration keeps short range, blanks readings and sends old contacts rapidly downwards');
    fs.writeFileSync(path.join(OUT,'mine-parity-jump-radar.json'),JSON.stringify(radar,null,2));
  }

  require('./mine-parity-states')({boot,run,check,fs,path,OUT});

  // Replay the user's matching C64 minefield save as well as synthetic callers.
  {
    const g=boot('c64game','trace'),m=g.m;
    const saved=JSON.parse(fs.readFileSync(path.join(__dirname,'../../briefs/ref/c64-minefield.state.json'),'utf8'));
    m.loadState(m.stateFromText(JSON.stringify(saved.state)));m.dma=true;
    const R=m.ram,protons=R[0x8450],trace=[];let bounded=true;
    for(let f=0;f<160;f++) {
      m.mouse.present=false;R[0x4b]=0x80;
      m.joy2=f<40?1:f<80?2:f<120?4:8;
      m.setKey(7,4,f>=20&&f<30);m.runFrame();
      if(f>=8)bounded &&= R[0x120a]>=135&&R[0x120a]<=165;
      trace.push({frame:f,cursor:[R[0xb2d7],R[0x120a]],digits:[...R.subarray(0x372c,0x3730)],lock:R[0x8e8f],protons:R[0x8450]});
    }
    check(bounded&&R[0x8450]===protons,'parity: supplied C64 minefield state, 160 DMA input frames keep measured bounds and refuse SPACE');
    fs.writeFileSync(path.join(OUT,'mine-parity-saved-state.json'),JSON.stringify(trace,null,2));
  }

};


