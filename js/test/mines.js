'use strict';
module.exports=function({boot,run,check,snap,fs,path,ROOT,OUT}) {
  function call(m,a) {
    const c=m.cpu,pc=c.pc,sp=c.sp,p=c.p,ax=c.a,xx=c.x,yx=c.y;c.push(255);c.push(243);c.pc=a;c.p|=4;
    let n=0;while(c.pc!==0xFFF4&&n++<2e6){c.step();if(c.jam)throw Error(c.jam);}
    if(n>=2e6)throw Error('mine call did not return');c.pc=pc;c.sp=sp;c.p=p;c.a=ax;c.x=xx;c.y=yx;
  }
  const late=m=>{let n=0,v=m.vicLog;for(let i=0;i<v.length;i+=4)
    if((v[i+2]===0x20||v[i+2]===0x21)&&((v[i]>=50&&v[i]<=76)||(v[i]>=230&&v[i]<=245))&&v[i+1]>=16&&v[i+1]<=55)n++;return n;};
  const o=boot('c64game','trace'),g=boot('game','trace'),m=g.m,S=g.p.symbols,A=m.ram,R=o.m.ram;
  run(o.m,o.hooks,300);m.dma=o.m.dma=true;run(m,g.hooks,60);
  // Fix randomness, allowing exact comparisons independent of instruction addresses.
  R.set([0xA9,0x07,0x60],0xBA85);A.set([0xA9,0x07,0x60],S.M_RND);
  const ohit=R[0x84D7],phit=A[S.SHIPHIT];
  R[0x84D7]=A[S.SHIPHIT]=0x60;
  let same=true,steps=0,impacts=0,trace=[];
  for(const kind of [0,1]) for(const difficulty of [0,2,4]) {
    R[0xE2]=A[S.MNKIND]=kind;R[0xE0]=A[S.DIFF]=difficulty;
    A.set(R.subarray(0xE9,0xF5),S.MNPOS);A.set(R.subarray(0xB1,0xB7),S.MNSHAPE);A[S.MNMSB]=R[0xF7];
    R[0xCF01]=A[S.MNPAUSE]=0;R[0x96]=A[S.JOYG]=0xFF;
    call(o.m,0xCC31);call(m,S.mn_cc31);
    for(let frame=0;frame<400;frame++) {
      for(let pass=0;pass<30;pass++) {
        R[0x96]=A[S.JOYG]=frame<150?0xFF:frame<230?0xFB:0xF7;
        R[0xDD]=A[S.HITFL]=0;R[0x9D6D]=A[S.EXPL2]=0;
        call(o.m,0xCC71);call(m,S.mn_cc71);steps++;
        same &&= R[0x98]===A[S.MNENA]&&R[0xF7]===A[S.MNMSB]&&
          Buffer.from(R.subarray(0xB1,0xB7)).equals(Buffer.from(A.subarray(S.MNSHAPE,S.MNSHAPE+6)))&&
          Buffer.from(R.subarray(0xE9,0xF5)).equals(Buffer.from(A.subarray(S.MNPOS,S.MNPOS+12)));
        if(R[0xDD])impacts++;
      }
      if(frame%30===0)trace.push({kind,difficulty,frame,enabled:A[S.MNENA],shape:[...A.subarray(S.MNSHAPE,S.MNSHAPE+6)],xy:[...A.subarray(S.MNPOS,S.MNPOS+12)]});
    }
  }
  check(same&&impacts>0,`game: mine positions/shapes/visibility and steering match original in ${steps} calls, ${impacts} impacts`);
  fs.writeFileSync(path.join(OUT,'mine-step-trace.json'),JSON.stringify(trace,null,2));
  // Original $B7BA uses the same low-byte hit box, noise, and no kill/energy bonus.
  let shots=true;
  const sid=m=>m.sidLog.filter((_,i)=>i%3!==0).join();
  for(let dx=-15;dx<=15;dx++) for(let dy of [-11,-9,0,9,11]) {
    R.fill(255,0xE9,0xF5);A.fill(255,S.MNPOS,S.MNPOS+12);
    R[0xE9]=A[S.SHOTX]=160;R[0xEA]=A[S.SHOTY]=140;
    R[0xEB]=A[S.MNPOS+2]=160+dx;R[0xEC]=A[S.MNPOS+3]=140+dy;
    R[0x98]=A[S.MNENA]=4;R[0x3370]=R[0x1616]=A[S.HITWIN]=1;
    R[0x160A]=A[S.EXPL]=0;R[0xCBFB]=A[S.mn_dcbfb]=1;R[0xCC01]=A[S.mn_dcc01]=1;
    o.m.sidLog.length=m.sidLog.length=0;
    call(o.m,0xB7BA);call(m,S.MNHIT);
    shots &&= R[0x98]===A[S.MNENA]&&R[0x160A]===A[S.EXPL]&&sid(o.m)===sid(m)&&
      (!R[0x160A]||(R[0x160C]===A[S.EXPX]&&R[0x160D]===A[S.EXPY]));
  }
  check(shots,'game: 155 mine phasor hit-box cases, burst centres and SID noise match original');
  // Force a full-sized mine to arrive. The normal damage paths must each take
  // one shield and one working-system point, without spending energy.
  R[0x84D7]=ohit;A[S.SHIPHIT]=phit;R[0xFD]=0;
  A.set([0xA9,7,0x60],S.RANDOM);
  R.fill(100,0x39,0x41);A.fill(100,S.SYSHP,S.SYSHP+8);
  R[0x844F]=A[S.SHLD]=40;R[0xF432]=R[0xF433]=A[S.HITS]=A[S.HITS+1]=0;
  R.fill(0,0xCC12,0xCC18);R[0xCC13]=1;R[0xCC2C]=1;
  R[0xCBE3]=R[0xCBE9]=R[0xCBEF]=1;R[0xCBF5]=6;R[0xB2]=0x72;
  R[0x98]=4;R[0x9D6D]=1;R[0xCF01]=0;
  A.set(R.subarray(0xCBE2,0xCC31),S.mn_dcbe2);
  A[S.MNSHAPE+1]=0x72;A[S.MNENA]=4;A[S.EXPL2]=1;A[S.MNPAUSE]=0;
  const energy=Buffer.from(A.subarray(S.HUDE,S.HUDE+4)),kills=A[S.KILLS];
  call(o.m,0xCC71);call(m,S.mn_cc71);
  check(R[0x844F]===39&&A[S.SHLD]===39&&R[0x40]===99&&A[S.SYSHP+7]===99&&
    R[0xF432]===1&&A[S.HITS]===1&&A[S.HITFL]&&R[0xDD]&&A[S.KILLS]===kills&&
    energy.equals(Buffer.from(A.subarray(S.HUDE,S.HUDE+4))),
    'game: original full-size mine takes one shield/system point, counts a hit, flashes, no score/energy bonus');
  // Directly exercise the original's band birth, rather than inferring it from art.
  const birthReturn=R[0xF1FA];R[0xF1FA]=0x60;R[0xD4]=0x80;o.m.cpu.x=0;
  call(o.m,0xF1D1);R[0xF1FA]=birthReturn;
  check(R[0xEFE3]===105,'game: original base-star generator actually starts at y=105');
  // Measure the real loops with DMA and identical held direction masks. The
  // patched mouse's DS is precisely a held joystick mask when off centre.
  const rates=[];
  for(const input of ['joystick','mouse-mask']) {
    const pair=[];
    for(const name of ['c64game','game']) {
      const g=boot(name,'trace'),m=g.m,A=m.ram,S=g.p.symbols;
      run(m,g.hooks,name==='game'?60:300);m.dma=true;
      const port=name==='game',xa=port?S.ENX:0x16,ya=port?S.ENY:0x1C,za=port?S.ENZ:0x22;
      if(port){A[S.M_STATE+24]=0x80;call(m,S.SECTORIN);}
      else {
        A[0xE1]=1;A[0x92]=A[0x93]=0;A[0x033C]=0x80;A[0x89]=1;
        A[0x3734]=1;A[0x9BE3]=A[0xBA]=A[0x88]=0;m.cpu.pc=0x8C44;
      }
      A.set([0xA0,0x90],xa);A.set([0x90,0x88],ya);A.set([0x90,0x94],za);
      m.joy2=4;run(m,g.hooks,20);
      if(port)A[S.MSGON]=0; // rate measurement starts after entry-message ownership
      A.set([0xA0,0x90],xa);A.set([0x90,0x94],za);
      let calls=0,writes=0,readings=[];const step=m.cpu.step.bind(m.cpu);
      m.cpu.step=function(){if(this.pc===(port?S.STEER:0x39C1))calls++;return step();};
      const digits=port?S.LRDIG:0x372C;
      for(let f=0;f<60;f++) {
        // Hold the mouse patch's combined direction mask at the JOY consumer;
        // cursor auto-centering is unrelated to this sustained-input rate.
        if(input==='mouse-mask') {
          m.joy2=0;const joy=port?S.JOY:0x96;
          const previous=m.cpu.step;
          m.cpu.step=function(){if(this.pc===(port?S.MNSTEER:0x39C1))A[joy]=0xFB;return previous.call(this);};
          m.runFrame();m.cpu.step=previous;
        } else m.runFrame();
        writes+=late(m);
        readings.push([A[digits],A[digits+1]].map(d=>d-0x70).reduce((a,b)=>10*a+b));
      }
      pair.push({name,calls,delta:A[xa]+256*A[xa+1]-0x90A0,digits:[...A.subarray(digits,digits+4)],readings});
      m.mouse.present=false;
      let level=true;
      for(const direction of [1,2]) {
        m.joy2=direction;run(m,g.hooks,20);
        level &&= A[ya+1]===0x88&&A[digits+2]===0x70&&A[digits+3]===0x70;
      }
      check(level,`game: ${name} DMA vertical input keeps the base pitch reading at 00`);
      if(port)check(writes===0&&A[S.OVRUN]===0,`game: ${input} steering rate trace: 0 late splits/OVRUN`);
    }
    rates.push({input,pair});
    check(Math.abs(pair[0].calls-pair[1].calls)<=12&&Math.abs(pair[0].delta-pair[1].delta)<200&&
      pair[0].digits.join()===pair[1].digits.join(),
      `game: ${input} 60 DMA frames original/port steering ${pair[0].calls}/${pair[1].calls}, coordinate delta ${pair[0].delta}/${pair[1].delta}, same readings`);
  }
  fs.writeFileSync(path.join(OUT,'mine-steering-rates.json'),JSON.stringify(rates,null,2));
  // The base lock is exact, front-only and independent of range. Once set it
  // stays set until base entry clears it, even after the readings change.
  {
    const g=boot('game','trace'),m=g.m,S=g.p.symbols,A=m.ram;
    m.dma=true;run(m,g.hooks,60);
    let rasterReads=0;
    const read=m.read;m.read=function(a){return a===0xD012?(rasterReads++===0?80:160):read.call(this,a);};
    let same=true;
    for(const depth of [0x80,0x88,0x94,0xA0]) for(const digit of [0x70,0x71,0x73,0x74]) {
      R.set([0xA0,0x88],0x16);A.set([0xA0,0x88],S.ENX);
      R.set([0x90,0x88],0x1C);A.set([0x90,0x88],S.ENY);
      R.set([0x90,depth],0x22);A.set([0x90,depth],S.ENZ);
      R.fill(0x70,0x372C,0x3730);A.fill(0x70,S.LRDIG,S.LRDIG+4);
      R[0x372D]=A[S.LRDIG+1]=digit;
      R[0x8E8F]=A[S.FLATCH]=0;A[S.MSROW]=1;A[S.APCNT]=5;A[S.JOY]=0xFF;
      call(o.m,0x8E90);rasterReads=0;call(m,S.MSPOS);
      const expected=depth>=0x88&&digit===0x70;
      same &&= !!R[0x8E8F]===expected&&!!A[S.FLATCH]===expected;
      if(expected) {
        R[0x23]=A[S.ENZ+1]=0x80;R[0x372D]=A[S.LRDIG+1]=0x79;
        A[S.APCNT]=5;call(o.m,0x8E90);rasterReads=0;call(m,S.MSPOS);
        same &&= !!R[0x8E8F]&&!!A[S.FLATCH];
      }
    }
    m.read=read;
    check(same,'game: original/port exact 00 lock at near/far depths, 01/03/04 and rear rejection, latch persists');
  }
  // Integrated DMA approach, prolonged enough to cover repeated mines and damage.
  for(const kind of [0x80,0xFF]) {
    const g=boot('game','trace'),m=g.m,S=g.p.symbols,A=m.ram;m.dma=true;run(m,g.hooks,60);
    const assets=[[0x4000,0x4400],[0x4C00,0x5000],[0x7CC0,0x8000],[0x6000,0x6300]].map(([a,b])=>[a,b,Buffer.from(A.subarray(a,b))]);
    A[S.M_STATE+24]=kind;call(m,S.SECTORIN);A[S.ENX+1]=0xA0;A[S.ENZ+1]=0x94;
    let writes=0,seen=new Set(),start=A[S.SHLD],hit=false;
    for(let f=0;f<40&&A[S.MNLOAD]!==12;f++){m.runFrame();writes+=late(m);}
    const raw=fs.readFileSync(path.join(ROOT,'../c128-gui/ref/sprites-4800.bin')).subarray(65*64,77*64);
    check(Buffer.from(A.subarray(0x6000,0x6300)).equals(raw),
      `game: ${kind.toString(16)} all twelve decoded mine shapes match the original asset bytes`);
    for(let i=0;i<12;i++){m.cpu.x=i;call(m,S.NEWSTAR);}
    check([...A.subarray(S.STARY,S.STARY+12)].every(y=>y===105),
      'game: minefield stars are born on original $F1E5 horizontal line y=105');
    A[S.FLATCH]=1;A[S.JOYG]=0xF0;call(m,S.MNVB);
    check(A[S.SHX]===0&&A[S.SHY]===0,'game: alignment lock suppresses star steering on both axes');
    A[S.FLATCH]=0;A[S.ENX+1]=0xA0;A[S.ENZ+1]=0x94;
    for(let f=0;f<1200;f++) {
      m.runFrame();if(f===600)snap(m,kind===0x80?'minefield-enemy':'minefield-friendly');writes+=late(m);hit ||= A[S.SHLD]<start;
      for(let i of [1,3,4,5]) if(A[S.MNENA]&(1<<(i+1)))seen.add(A[S.MNSHAPE+i]);
    }
    check(seen.size>5&&hit,`game: ${kind.toString(16)} live mines grow through ${seen.size} shapes and damage shields (${start}->${A[S.SHLD]})`);
    check(writes===0&&A[S.OVRUN]===0,`game: ${kind.toString(16)} minefield DMA: ${writes} late writes, ${A[S.OVRUN]} overruns`);
    A[S.ENX]=0xA0;A[S.ENX+1]=0x88;A[S.ENY]=0x90;A[S.ENY+1]=0x88;A[S.ENZ]=0x90;A[S.ENZ+1]=0x88;
    for(let f=0;f<400&&A[S.MSSTATE]!==2;f++){m.runFrame();writes+=late(m);}
    check(A[S.MSSTATE]===2&&assets.every(([a,b,bytes])=>bytes.equals(Buffer.from(A.subarray(a,b)))),
      `game: ${kind.toString(16)} mines hand over to rings and restore every borrowed/protected asset`);
    for(let f=0;f<45;f++) {
      m.runFrame();writes+=late(m);
      m.cpu.x=0;call(m,S.NEWSTAR);
    }
    check(A[S.STARY]===105&&A[S.MSSTATE]>=2&&A[S.MSSTATE]<4,
      `game: ${kind.toString(16)} star birth band persists through visible rings`);
    call(m,S.MSOFF);
    check(A[S.nsy]===0x20&&(A[S.nsy+1]|A[S.nsy+2]<<8)===S.RANDOM,
      'game: leaving base sequence restores random star births');
    check(writes===0&&A[S.OVRUN]===0,`game: ${kind.toString(16)} minefield handover DMA: ${writes} late writes, ${A[S.OVRUN]} overruns`);
  }
  // Keep live input tests separate from direct routine calls, which advance
  // the raster while restoring the caller's in-progress CPU instruction stream.
  for(const direction of [1,2]) {
    const g=boot('game','trace'),m=g.m,S=g.p.symbols,A=m.ram;
    m.dma=true;m.mouse.present=false;run(m,g.hooks,60);A[S.M_STATE+24]=0x80;call(m,S.SECTORIN);
    A[S.ENX+1]=0xA0;A[S.ENZ+1]=0x94;A[S.ENY]=0x90;A[S.ENY+1]=0x88;
    m.joy2=direction;let writes=0;
    for(let f=0;f<80;f++){m.runFrame();writes+=late(m);}
    check(A[S.ENY]===0x90&&A[S.ENY+1]===0x88&&A[S.SHY]===0&&A[S.MNLOAD]===12,
      `game: minefield vertical input ${direction} preserves pitch and base height`);
    check(writes===0&&A[S.OVRUN]===0,'game: vertical input: 0 late splits/OVRUN');
  }
  // Reopening the map during slot restoration must not resume a stale copy
  // pointer at $6300 and overwrite the thirteenth fighter slot.
  {
    const g=boot('game','trace'),m=g.m,S=g.p.symbols,A=m.ram;m.dma=true;run(m,g.hooks,60);
    const tail=Buffer.from(A.subarray(0x6300,0x63C0));
    A[S.M_STATE+24]=0xFF;call(m,S.SECTORIN);
    A[S.ENX]=0xA0;A[S.ENX+1]=0x88;A[S.ENY]=0x90;A[S.ENY+1]=0x88;A[S.ENZ]=0x90;A[S.ENZ+1]=0x88;
    let writes=0;
    for(let f=0;f<400&&!A[S.MNFIN];f++){m.runFrame();writes+=late(m);}
    const cleanup=!!A[S.MNFIN]&&A[S.MNLOAD]>0;
    call(m,S.MAPOPEN);run(m,g.hooks,50);call(m,S.MAPCLOSE);
    for(let f=0;f<160&&A[S.MSSTATE]===16;f++){m.runFrame();writes+=late(m);}
    check(cleanup&&A[S.MSSTATE]===2&&A[S.MNLOAD]===0&&tail.equals(Buffer.from(A.subarray(0x6300,0x63C0))),
      'game: map pause during mine cleanup resumes safely without touching the next sprite slot');
    check(writes===0&&A[S.OVRUN]===0,`game: mine cleanup/map pause: ${writes} late writes, ${A[S.OVRUN]} overruns`);
  }
};
