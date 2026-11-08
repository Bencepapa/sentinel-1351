'use strict';
// Saved-state regression: the supplied C64 image is the executable reference.
module.exports=function({boot,run,check,fs,path,OUT}) {
  const file=n=>path.join(__dirname,'../../briefs/ref/'+n+'-minefield.state.json');
  const saved=JSON.parse(fs.readFileSync(file('c64'),'utf8'));
  const old=JSON.parse(fs.readFileSync(file('c128'),'utf8'));
  function call(m,a){const c=m.cpu,s=[c.pc,c.sp,c.p,c.a,c.x,c.y];c.push(255);c.push(243);c.pc=a;c.p|=4;let n=0;while(c.pc!==0xfff4&&n++<2e6)c.step();if(n>=2e6)throw Error('saved parity call '+a.toString(16));[c.pc,c.sp,c.p,c.a,c.x,c.y]=s;}
  function reference(){const g=boot('c64game','trace');g.m.loadState(g.m.stateFromText(JSON.stringify(saved.state)));g.m.dma=true;return g;}
  const late=m=>{let n=0;for(let i=0;i<m.vicLog.length;i+=4){const [l,c,r]=m.vicLog.slice(i,i+3);if((r===32||r===33)&&((l>=50&&l<=76)||(l>=230&&l<=245))&&c>=16&&c<=55)n++;}return n;};
  function pair(){
    const o=reference(),g=boot('game','trace'),m=g.m,A=m.ram,S=g.p.symbols,R=o.m.ram;
    m.dma=true;run(m,g.hooks,60);
    // The old save includes its old executable RAM. Loading it cannot test the
    // new build. Recreate the friendly sector using its public game entry path.
    A[S.M_STATE+24]=0xff;call(m,S.SECTORIN);
    for(let f=0;f<40&&A[S.MNLOAD]!==12;f++)m.runFrame();
    if(A[S.MNLOAD]!==12)throw Error('current approach did not enter minefield');
    A.set(R.subarray(0x16,0x18),S.ENX);A.set(R.subarray(0x1c,0x1e),S.ENY);A.set(R.subarray(0x22,0x24),S.ENZ);
    A[S.CURX]=R[0xb2d7];A[S.CURY]=R[0x120a];A.set(R.subarray(0x372c,0x3730),S.LRDIG);
    // Resume the saved message's remaining character-clock time, rather than
    // starting another complete 200-frame entry message in the current game.
    const framesToTick=R[0x13d3]===5?4:R[0x13d3]===3?3:R[0x13d3]===1?2:1;
    A[S.MSGCD]=(R[0x9bdd]-1)*4+framesToTick;A[S.MSGN]=R[0x9bde];A[S.MSGTG]=R[0x9be4];
    A[S.MSGC1]=R[0x9bdf];A[S.MSGC2]=R[0x9be0];
    for(let i=0;i<40;i++)m.write(S.COLROW+i,o.m.read(0xdb98+i)&15);
    const diagnostic=m.cpu.step.bind(m.cpu);
    m.cpu.step=function(){const pc=this.pc,n=m.vicLog.length;const result=diagnostic();if(m.vicLog.length>n&&late({vicLog:m.vicLog.slice(n)}))console.log('LATE PC',pc.toString(16));return result;};
    return {o,g,m,A,S,R};
  }
  const meta={c64PC:saved.state.cpu.pc,c128PC:old.state.cpu.pc,recreated:true};
  {
    const {g,S}=pair(),oldRam=Buffer.from(old.state.arrays.ram,'base64');
    meta.oldCodeDiffers=!oldRam.subarray(0xea16,0xf6f9).equals(Buffer.from(g.m.ram.subarray(0xea16,0xf6f9)));
    check(meta.oldCodeDiffers,'saved parity: C128 snapshot contains older resident code; current friendly approach recreated through SECTORIN');
  }
  const axes=[];
  for(const mouse of [false,true])for(const direction of ['left','right','up','down']){
    const {o,m,A,S,R}=pair();let same=true;const frames=[];
    R[0x4b]=mouse?0:0x80;A[S.MPRES]=mouse?1:0;
    const mask={left:0xfb,right:0xf7,up:0xfe,down:0xfd}[direction];
    for(let f=0;f<120;f++){
      R[0x96]=A[S.JOY]=mouse?0xef:mask;
      R[0x3fe]=A[S.MDX]=direction==='left'?252:direction==='right'?4:0;
      R[0x3ff]=A[S.MDY]=direction==='up'?4:direction==='down'?252:0;
      call(o.m,0xb2d8);call(m,S.CURSOR);
      const original=[R[0xb2d7],R[0x120a]],port=[A[S.CURX],A[S.CURY]];
      same &&= original.join()===port.join();frames.push({frame:f,original,port});
    }
    const axis=direction==='left'||direction==='right'?0:1;
    const end={left:0,right:254,up:165,down:135}[direction];
    check(same&&frames.at(-1).original[axis]===end,`saved parity: ${mouse?'mouse':'joystick'} ${direction}, all 120 cursor updates and limit ${end} match`);
    axes.push({mouse,direction,frames});
  }
  // Identical external inputs, each frame, through each game's actual main loop.
  // IRQ placement means the C64 consumes joystick input one frame later; retain
  // that latency in the trace and bound it explicitly, rather than hiding it.
  const replays=[];
  for(const action of ['left','right','up','down','fire','up+fire','SPACE','both']){
    const {o,m,A,S,R}=pair();const frames=[];let writes=0,live=true,cursor=true,refused=true;
    const p0=R[0x8450],p1=Buffer.from(A.subarray(0x485a,0x485c));
    const joy={left:4,right:8,up:1,down:2,fire:16,'up+fire':17,SPACE:0,both:0}[action];
    for(const k of [o.m,m]){k.mouse.present=action==='both';k.mouse.left=action==='both';k.mouse.right=action==='both';k.joy2=joy;k.setKey(7,4,action==='SPACE');}
    R[0x4b]=action==='both'?0:0x80;A[S.MPRES]=action==='both'?1:0;
    let launches0=0,launches1=0;
    for(const [k,pc,inc] of [[o.m,0x1467,()=>launches0++],[m,S.LAUNCH,()=>launches1++]]){const step=k.cpu.step.bind(k.cpu);k.cpu.step=function(){if(this.pc===pc)inc();return step();};}
    for(let f=0;f<120;f++){
      live &&= !!o.m.runFrame()&&!!m.runFrame();writes+=late(m);
      const original={cursor:[R[0xb2d7],R[0x120a]],digits:[...R.subarray(0x372c,0x3730)],lock:R[0x8e8f],xyz:[R[0x16],R[0x17],R[0x1c],R[0x1d],R[0x22],R[0x23]],message:R[0x9be3],colour:o.m.read(0xdb98)&15,protons:R[0x8450]};
      const port={cursor:[A[S.CURX],A[S.CURY]],digits:[...A.subarray(S.LRDIG,S.LRDIG+4)],lock:A[S.FLATCH],xyz:[A[S.ENX],A[S.ENX+1],A[S.ENY],A[S.ENY+1],A[S.ENZ],A[S.ENZ+1]],message:A[S.MSGON],colour:m.read(S.COLROW)&15,protons:[...A.subarray(0x485a,0x485c)],phase:A[S.MSSTATE],row:A[S.MSROW]};
      if(['left','right','up','down'].includes(action)&&f>2){const axis=action==='left'||action==='right'?0:1;cursor &&= Math.abs(original.cursor[axis]-port.cursor[axis])<=(axis?2:3);}
      refused &&= R[0x8450]===p0&&p1.equals(Buffer.from(A.subarray(0x485a,0x485c)))&&!A[S.TPF];
      frames.push({frame:f,original,port});
    }
    check(live&&cursor&&refused,`saved parity: ${action}, 120 live DMA frames, cursor within one input frame, minefield torpedoes refused without ammunition loss`);
    if(action==='fire'||action==='up+fire')check(launches0>0&&launches1>0,'saved parity: held fire launches phasors during the minefield in both games');
    if(action==='both')check(launches0===0&&launches1===0,'saved parity: both buttons suppress phasors as well as refusing the minefield proton');
    check(writes===0&&A[S.OVRUN]===0,`saved parity: ${action}: ${writes} late splits, ${A[S.OVRUN]} OVRUN`);
    replays.push({action,launches0,launches1,writes,overrun:A[S.OVRUN],frames});
  }
  // The saved entry message is already partway through its flashing lifetime.
  {
    const {o,m,A,S,R}=pair();let same=true,unchanged=true;const frames=[],row0=Buffer.from(R.subarray(0x5798,0x57c0)),row1=Buffer.from(A.subarray(S.LRROW,S.LRROW+40));
    for(let f=0;f<160;f++){
      const owned=!!R[0x9be3];call(o.m,0x13d5);call(m,S.MSGFRAME);call(m,S.MNREAD);
      same &&= !!R[0x9be3]===!!A[S.MSGON]&&(o.m.read(0xdb98)&15)===(m.read(S.COLROW)&15);
      if(owned&&R[0x9be3])unchanged &&= row0.equals(Buffer.from(R.subarray(0x5798,0x57c0)))&&row1.equals(Buffer.from(A.subarray(S.LRROW,S.LRROW+40)));
      frames.push({frame:f,original:{on:R[0x9be3],colour:o.m.read(0xdb98)&15},port:{on:A[S.MSGON],colour:m.read(S.COLROW)&15}});
    }
    check(same&&unchanged&&!R[0x9be3]&&!A[S.MSGON],'saved parity: remaining entry-message lifetime, colours and scanner ownership match every frame');
    meta.messageTail=frames;
  }
  {
    const {o,m,A,S,R}=pair(),frames=[];let writes=0,ring0=false,ring1=false,steers0=0,steers1=0,shots0=0,shots1=0;
    // Move the scenario to the centre line, then let the real scanner and
    // approach loops obtain their own 00 reading and latch. Do not set FLATCH.
    R.set([0xa0,0x88],0x16);A.set([0xa0,0x88],S.ENX);
    R.set([0x90,0x88],0x1c);A.set([0x90,0x88],S.ENY);
    // Retain the save's long depth until the message ends and lock can latch.
    for(const k of [o.m,m]){k.mouse.present=false;k.mouse.left=k.mouse.right=false;k.joy2=0;}
    R[0x4b]=0x80;A[S.MPRES]=0;
    const st0=o.m.cpu.step.bind(o.m.cpu),st1=m.cpu.step.bind(m.cpu);
    o.m.cpu.step=function(){if(this.pc===0x909d)ring0=true;if(ring0&&this.pc===0x39c1)steers0++;if(ring0&&this.pc===0x1467)shots0++;return st0();};
    m.cpu.step=function(){if(A[S.MSSTATE]===2)ring1=true;if(ring1&&this.pc===S.MNSTEER)steers1++;if(ring1&&this.pc===S.LAUNCH)shots1++;return st1();};
    let latched=false,lockFrame0=null,lockFrame1=null,stable=true;
    for(let f=0;f<650;f++){
      if(f===170){
        latched=!!R[0x8e8f]&&!!A[S.FLATCH];
        // Bring the locked approach near the base; the games still perform
        // their own settling, sprite handover and ring transitions.
        R.set([0x90,0x88],0x22);A.set([0x90,0x88],S.ENZ);
        o.m.joy2=m.joy2=20; // hold left and fire through the appearance
      }
      o.m.runFrame();m.runFrame();const lw=late(m);if(lw)console.log('TUNNEL LATE',f,A[S.MSSTATE],A[S.MSROW],A[S.MNLOAD],Array.from({length:m.vicLog.length/4},(_,i)=>m.vicLog.slice(i*4,i*4+4)).filter(v=>(v[2]===32||v[2]===33)&&((v[0]>=50&&v[0]<=76)||(v[0]>=230&&v[0]<=245))&&v[1]>=16&&v[1]<=55));writes+=lw;
      if(R[0x8e8f]&&lockFrame0===null)lockFrame0=f;
      if(A[S.FLATCH]&&lockFrame1===null)lockFrame1=f;
      if(f>170)stable &&= !A[S.SHX]&&!A[S.SHY]&&!!R[0x8e8f]&&!!A[S.FLATCH];
      frames.push({frame:f,original:{digits:[...R.subarray(0x372c,0x3730)],lock:R[0x8e8f],rings:ring0},port:{digits:[...A.subarray(S.LRDIG,S.LRDIG+4)],lock:A[S.FLATCH],phase:A[S.MSSTATE],row:A[S.MSROW],rings:ring1}});
    }
    check(latched&&stable,'saved parity: both real scanners reach 00, latch steering, and keep star steering locked under held left');
    check(ring0&&ring1&&steers0===0&&steers1===0&&shots0===0&&shots1===0,'saved parity: actual mine-to-mothership transitions keep steering and new phasor launches locked');
    check(writes===0&&A[S.OVRUN]===0,'saved parity: alignment/settling/rings, 0 late splits and 0 OVRUN');
    meta.handover={lockFrame0,lockFrame1,steers0,steers1,shots0,shots1,frames};
  }
  fs.writeFileSync(path.join(OUT,'mine-parity-saved-comparison.json'),JSON.stringify({meta,axes,replays},null,2));
};
