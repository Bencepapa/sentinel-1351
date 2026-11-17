'use strict';
// The C128 MMU and RAM bank 1 in the JS machine (js/src/machine.js), against what VICE x128 3.9
// does (measured 2026-11-17; briefs/memory-overlay-plan.md, "Measurements (step 0-1)").
module.exports=function({boot,run,check,fs,path,ROOT}) {
  const C128=require(path.join(ROOT,'src/machine.js'));
  const Video=require(path.join(ROOT,'src/video.js'));
  const Debugger=require(path.join(ROOT,'src/debugger.js'));
  const hex=v=>v.toString(16).toUpperCase().padStart(2,'0');

  const fresh=opts=>{const m=new C128('c128',opts);m.write(0xFF00,0x3E);return m;};     // bank 0, all RAM, I/O
  // a call of machine code (a stub in the stack page) with the return trap at $FFF4
  function call(m,addr,regs){
    const c=m.cpu,saved=[c.pc,c.sp,c.p,c.a,c.x,c.y];
    c.push(0xFF);c.push(0xF3);c.pc=addr;c.p|=4;
    if(regs){if(regs.a!==undefined)c.a=regs.a;if(regs.x!==undefined)c.x=regs.x;}
    const start=c.cycles;let n=0;
    while(c.pc!==0xFFF4&&n++<1e6){c.step();if(c.jam)throw Error('jam in stub call '+c.jam);}
    if(n>=1e6)throw Error('stub call did not return');
    const used=c.cycles-start;
    [c.pc,c.sp,c.p,c.a,c.x,c.y]=saved;return used;
  }

  // ---- register defaults and semantics (VICE: SYS from BASIC) -------------------------
  {
    const m=new C128('c128');
    const regs=[];for(let i=0;i<12;i++)regs.push(m.read(0xD500+i));
    check(regs.map(hex).join(' ')==='00 3F 7F 01 41 37 04 00 F0 01 F0 20',
      `banks: MMU registers $D500-$D50B at start as in VICE (${regs.map(hex).join(' ')})`);
    m.write(0xD501,0xA1);m.write(0xD502,0xB2);m.write(0xD503,0xC3);m.write(0xD504,0xD4);
    check([1,2,3,4].map(i=>m.read(0xD500+i)).join()==='161,178,195,212'&&m.mmuCR===0,
      'banks: $D501-$D504 store the preconfigurations and leave CR alone');
    m.write(0xD501,0x3E);m.write(0xD502,0x7F);m.write(0xD503,0x01);m.write(0xD504,0x41);
    // any read or write of $FF01-$FF04 loads CR from the register (VICE: reads load too)
    const seq=[];
    m.write(0xFF01,0x99);seq.push(m.mmuCR);m.write(0xFF02,0x00);seq.push(m.mmuCR);m.write(0xFF03,0xFF);seq.push(m.mmuCR);m.write(0xFF04,0x12);seq.push(m.mmuCR);
    check(seq.map(hex).join(' ')==='3E 7F 01 41','banks: a store to $FF01-$FF04 loads CR from PCRA-D whatever is stored (3E 7F 01 41)');
    m.write(0xFF01,0);
    const rd=[];for(let k=2;k<=4;k++){const v=m.read(0xFF00+k);rd.push(hex(v)+'>'+hex(m.mmuCR));m.write(0xFF01,0);}
    check(rd.join(' ')==='7F>7F 01>01 41>41','banks: a read of $FF02-$FF04 returns the register and loads CR (VICE does too)');
    m.write(0xD500,0x7E);
    check(m.read(0xFF00)===0x7E&&m.read(0xD500)===0x7E,'banks: $D500 and $FF00 are the same register');
    // CR is readable in every configuration
    const crs=[0x3E,0x7E,0xBE,0xFE,0x3F,0x7F,0x01,0x00,0x0E,0x10,0x20,0xC1];
    const back=crs.map(v=>{m.write(0xFF00,v);return m.read(0xFF00);});
    check(back.join()===crs.join(),'banks: CR reads back the written value in every configuration');
    m.write(0xFF00,0x3E);
    m.write(0xD50B,0x55);m.write(0xD508,0x00);
    check(m.read(0xD50B)===0x20&&m.read(0xD508)===0xF0,'banks: the version register is read only, the unused page-pointer bits read as 1');
  }

  // ---- bank selection (VICE: CR bit 6; bit 7 is ignored with 128 KB) -------------------
  {
    const m=fresh();
    const at=(cr,a,v)=>{m.write(0xFF00,cr);if(v!==undefined)m.write(a,v);const r=m.read(a);m.write(0xFF00,0x3E);return r;};
    at(0x3F,0x4000,0x10);at(0x7F,0x4000,0x11);
    check(at(0x3F,0x4000)===0x10&&at(0x7F,0x4000)===0x11&&m.ram[0x4000]===0x10&&m.ram1[0x4000]===0x11,
      'banks: CR bit 6 selects RAM bank 0 / 1 ($3F / $7F) and the banks are separate');
    at(0xBF,0x4000,0x12);
    const r1=[0x3F,0x7F,0xBF,0xFF].map(c=>hex(at(c,0x4000)));
    at(0xFF,0x4000,0x13);
    const r2=[0x3F,0x7F,0xBF,0xFF].map(c=>hex(at(c,0x4000)));
    check(r1.join()==='12,11,12,11'&&r2.join()==='12,13,12,13',
      `banks: CR bit 7 is ignored (writes in $BF/$FF land in bank 0/1; reads ${r1.join(' ')} then ${r2.join(' ')}, as VICE)`);
    // I/O and colour RAM are one for both banks
    m.write(0xD800,0x07);m.write(0xFF00,0x7E);const c1=m.read(0xD800)&15;m.write(0xD800,0x09);m.write(0xFF00,0x3E);
    check(c1===7&&(m.read(0xD800)&15)===9,'banks: colour RAM $D800 is the same in both banks');
    // RAM below the I/O area: a bank-1 view with CR bit 0 set reads bank 1's $D000
    m.ram1[0xD500]=0x77;m.write(0xFF00,0x7F);const under=m.read(0xD500);m.write(0xFF00,0x3E);
    check(under===0x77,'banks: with I/O off ($7F) $D000-$DFFF is bank 1 RAM');
  }

  // ---- the RCR grid: common RAM, zero page and stack (VICE grid of 21 RCR values x 25 probes) -------
  {
    const PROBES=[0x0010,0x01D0,0x0200,0x03FF,0x0400,0x0BFF,0x0C00,0x0FFF,0x1000,0x1BFF,0x1C00,0x1FFF,0x2000,0x3FFF,0x4000,
                  0xBFFF,0xC000,0xDFFF,0xE000,0xEFFF,0xF000,0xFBFF,0xFC00,0xFEFF,0xFFF0];
    const VICE={0x00:'CC.......................',0x01:'CC.......................',0x02:'CC.......................',0x03:'CC.......................',
      0x04:'CCCC.....................',0x05:'CCCCCCCC.................',0x06:'CCCCCCCCCCCC.............',0x07:'CCCCCCCCCCCCCC...........',
      0x08:'CC....................CCC',0x09:'CC..................CCCCC',0x0A:'CC................CCCCCCC',0x0B:'CC..............CCCCCCCCC',
      0x0C:'CCCC..................CCC',0x0D:'CCCCCCCC............CCCCC',0x0E:'CCCCCCCCCCCC......CCCCCCC',0x0F:'CCCCCCCCCCCCCC..CCCCCCCCC',
      0x44:'CCCC.....................',0x84:'CCCC.....................',0xC4:'CCCC.....................',0xF0:'CC.......................',
      0xFF:'CCCCCCCCCCCCCC..CCCCCCCCC'};
    let bad=[];
    for(const rcr of Object.keys(VICE).map(Number)){
      const m=fresh();m.write(0xD506,rcr);
      if(m.read(0xD506)!==rcr)bad.push('readback '+hex(rcr));
      let row='';
      for(const a of PROBES){
        m.write(0xFF00,0x3F);m.write(a,0xA0);m.write(0xFF00,0x7F);m.write(a,0xA1);m.write(0xFF00,0x3F);
        row+=m.read(a)===0xA1?'C':'.';
      }
      if(row!==VICE[rcr])bad.push(hex(rcr)+' '+row+' != '+VICE[rcr]);
    }
    check(bad.length===0,`banks: common RAM by RCR (sizes 1/4/8/16 KB, bottom bit 2, top bit 3, zero page and stack always) matches VICE for 21 values${bad.length?': '+bad.slice(0,3).join('; '):''}`);
    // the common RAM is one array: a store in bank 1 shows in bank 0 and the other way round
    const m=fresh();m.write(0xD506,0x05);m.write(0xFF00,0x7F);m.write(0x0C00,0x5A);m.write(0xFF00,0x3F);
    check(m.read(0x0C00)===0x5A&&m.ram[0x0C00]===0x5A&&m.ram1[0x0C00]===0,'banks: common RAM is stored in the bank-0 array only');
  }

  // ---- zero page and stack in bank 1 mode; page pointers --------------------------------
  {
    const m=fresh();
    m.write(0xFF00,0x7F);m.write(0xF6,0x42);m.write(0x01F0,0x43);m.write(0xFF00,0x3E);
    check(m.ram[0xF6]===0x42&&m.ram[0x01F0]===0x43&&m.ram1[0xF6]===0&&m.ram1[0x01F0]===0,
      'banks: zero page and stack are bank 0 in a bank-1 configuration (default pointers)');
    // the pointers relocate them: page 0 -> physical page $30 of bank 1 ($D507 = $30, $D508 = $01)
    m.write(0xD507,0x30);m.write(0xD508,0x01);m.write(0x10,0x99);
    check(m.ram1[0x3010]===0x99&&m.ram[0x10]===0,'banks: $D507/$D508 move page 0 (here to bank 1 page $30)');
    m.write(0xD507,0x00);m.write(0xD508,0x00);
    check(m.read(0x10)===m.ram[0x10]&&!m.bankedRam,'banks: restoring the pointers returns to the flat fast path');
  }

  // ---- the plan's copy primitive: a stub in the stack page, byte by byte ------------------------
  {
    // exactly the bytes assembled for and run in VICE x128 (B1GET: bank 1 -> bank 0, B1PUT: bank 0 -> bank 1)
    const GET=[0xA0,0x00,0x8D,0x02,0xFF,0xB1,0xF2,0x8D,0x01,0xFF,0x91,0xF4,0xC8,0xD0,0xF3,0xE6,0xF3,0xE6,0xF5,0xCA,0xD0,0xEC,0x60];
    const PUT=[0xA0,0x00,0xB1,0xF2,0x8D,0x02,0xFF,0x91,0xF4,0x8D,0x01,0xFF,0xC8,0xD0,0xF3,0xE6,0xF3,0xE6,0xF5,0xCA,0xD0,0xEC,0x60];
    const m=fresh();
    m.ram.set(GET,0x0100);m.ram.set(PUT,0x0120);
    m.write(0xD501,0x3E);m.write(0xD502,0x7F);
    // LCG pattern, 3 pages, different in every page
    let v=7;const pat=new Uint8Array(0x300);
    for(let p=0;p<3;p++){for(let i=0;i<256;i++){pat[p*256+i]=v;v=(v*5+3)&255;}v=(v+1)&255;}
    m.ram.set(pat,0x5800);
    m.ram[0x4000]=0x10;
    const copy=(addr,src,dst,pages)=>{m.ram[0xF2]=src&255;m.ram[0xF3]=src>>8;m.ram[0xF4]=dst&255;m.ram[0xF5]=dst>>8;return call(m,addr,{x:pages});};
    const cyP3=copy(0x0120,0x5800,0x4000,3);
    check(Buffer.from(m.ram1.subarray(0x4000,0x4300)).equals(Buffer.from(pat))&&m.ram[0x4000]===0x10,
      'banks: B1PUT stub copies 3 pages bank 0 -> bank 1 through $FF02/$FF01 (bank 0 untouched)');
    check(m.mmuCR===0x3E,'banks: the stub leaves the bank-0 configuration (CR $3E) behind');
    m.ram.fill(0,0x5C00,0x5F00);
    const cyG3=copy(0x0100,0x4000,0x5C00,3);
    check(Buffer.from(m.ram.subarray(0x5C00,0x5F00)).equals(Buffer.from(pat)),'banks: B1GET stub copies the 3 pages back, byte for byte');
    // under the I/O area: bank 1 RAM at $D000 through the same stub
    copy(0x0120,0x5800,0xD000,1);m.ram.fill(0,0x5F00,0x6000);copy(0x0100,0xD000,0x5F00,1);
    check(Buffer.from(m.ram.subarray(0x5F00,0x6000)).equals(Buffer.from(pat.subarray(0,256)))&&m.ram[0xD000]===0,
      'banks: bank 1 RAM beneath $D000 (I/O off in the stub) is reachable, bank 0 beneath it is not touched');
    const cyG1=copy(0x0100,0x4000,0x5C00,1);
    const perByte=(cyG3-cyG1)/512;
    check(perByte>=23.9&&perByte<=24.1&&Math.abs(cyG3-cyP3)<=3,
      `banks: the copy takes ${perByte.toFixed(2)} cycles a byte (${cyG1} for a page; VICE x128 measured 6159 net at 1 MHz, 24.06 a byte)`);
  }

  // ---- the VIC reads the bank RCR bit 6 names ---------------------------------------------------
  {
    // hires bitmap at $2000, screen $0400: bank 0 solid on yellow/white..., bank 1 empty on green: the pixel shows
    // which bank the VIC read
    function picture(vicBank1,swap){
      const m=fresh();
      const b0=swap?m.ram1:m.ram,b1=swap?m.ram:m.ram1;       // swap: the same data in the other bank
      b0.fill(0xFF,0x2000,0x4000);b0.fill(0x17,0x0400,0x0800);
      b1.fill(0x00,0x2000,0x4000);b1.fill(0x25,0x0400,0x0800);
      m.write(0xD011,0x3B);m.write(0xD016,0xC8);m.write(0xD018,0x18);m.write(0xD020,0);m.write(0xD021,0);
      m.write(0xDD00,0x03);
      m.write(0xD506,vicBank1?0x44:0x04);
      m.video.beginFrame();m.video.renderTo(312);
      return Array.from(m.video.px.subarray(160*Video.VIC_W+Video.VIC_W/2,160*Video.VIC_W+Video.VIC_W/2+8));
    }
    const a=picture(false,false),b=picture(true,false),c=picture(true,true);
    check(a.join()!==b.join()&&a.join()===c.join(),
      'banks: RCR bit 6 makes the VIC draw the bitmap and colours from RAM bank 1 (VICE: bitmap, matrix, charset, sprites all from bank 1)');
    const m=fresh();m.write(0xD506,0x44);
    check(m.vicRam()===m.ram1&&new C128('c128').vicRam()!==null&&new C128('c64').vicRam()!==undefined,'banks: vicRam() is bank 1 with RCR bit 6');
    // no character ROM image in the VIC's bank 1 (VICE): the matrix cell at $1000 reads RAM
    const v=m.video;m.ram1[0x1008]=0x5A;
    check(v.vicByte(0,0x1008)===0x5A,'banks: the VIC sees no character ROM image in RAM bank 1 (VICE)');
    const m0=fresh();m0.ram[0x1008]=0x5A;
    check(m0.video.vicByte(0,0x1008)!==0x5A,'banks: ...but sees it in bank 0');
  }

  // ---- the VDC RAM: 16 KB wraps at $3FFF (VICE default), 64 KB is an option ------------------------
  {
    const vdcSet=(m,a,v)=>{m.write(0xD600,18);m.write(0xD601,a>>8);m.write(0xD600,19);m.write(0xD601,a&255);m.write(0xD600,31);m.write(0xD601,v);};
    const vdcGet=(m,a)=>{m.write(0xD600,18);m.write(0xD601,a>>8);m.write(0xD600,19);m.write(0xD601,a&255);m.write(0xD600,31);return m.read(0xD601);};
    const m16=fresh(),m64=fresh({vdcKb:64});
    for(const m of [m16,m64])[[0x0000,0x11],[0x4000,0x22],[0x8000,0x33],[0xC000,0x44],[0xFFFF,0x55]].forEach(([a,v])=>vdcSet(m,a,v));
    const r16=[0x0000,0x4000,0x8000,0xC000,0xFFFF].map(a=>hex(vdcGet(m16,a)));
    const r64=[0x0000,0x4000,0x8000,0xC000,0xFFFF].map(a=>hex(vdcGet(m64,a)));
    check(m16.vdcKb===16&&r16.join(' ')==='44 44 44 44 55'&&r64.join(' ')==='11 22 33 44 55',
      `banks: the VDC RAM is 16 KB by default (addresses wrap at $3FFF: ${r16.join(' ')}; VICE x128's 16 KB mode only ignores address bit 14, 22 22 44 44 55) and 64 KB as an option (${r64.join(' ')})`);
    // the address register stays 16 bits (VICE: R18/R19 = $4000 after a write at $3FFF) and a fill wraps with the RAM
    vdcSet(m16,0x3FFF,0x66);
    const hi=(m16.write(0xD600,18),m16.read(0xD601)),lo=(m16.write(0xD600,19),m16.read(0xD601));
    check(hi===0x40&&lo===0,'banks: the VDC address register counts on to $4000 after $3FFF');
    m16.write(0xD600,24);m16.write(0xD601,0);vdcSet(m16,0x3FFE,0x5A);m16.write(0xD600,30);m16.write(0xD601,3);
    check([0x3FFD,0x3FFE,0x3FFF,0x0000,0x0001].map(a=>vdcGet(m16,a)).map(hex).join(' ')==='00 5A 5A 5A 5A','banks: a VDC fill over the end wraps to $0000 (as VICE)');
    const gm=boot('game','trace');
    check(gm.m.vdcKb===16,'banks: the page and the tests start with the 16 KB VDC');
  }

  // ---- states: bank 1 is saved when used, old states load with bank 1 empty ---------------------------------
  {
    const m=fresh();m.ram1[0x4000]=0xAB;m.write(0xD506,0x45);m.write(0xFF00,0x7F);
    const st=m.stateFromText(m.stateToText(m.saveState()));
    const n=new C128('c128');n.loadState(st);
    check(n.ram1[0x4000]===0xAB&&n.mmuCR===0x7F&&n.read(0xFF00)===0x7F&&n.mmu[6]===0x45&&n.cpuBank===1&&n.read(0x4000)===0xAB,
      'banks: save state keeps bank 1, CR and RCR');
    const e=fresh(),se=e.saveState();
    check(se.arrays.ram1===undefined,'banks: an empty bank 1 is not written into the state (fixtures keep their size)');
    // an old state: no ram1, no banks marker, MMU registers all zero
    const old=m.saveState();delete old.arrays.ram1;delete old.banks;old.arrays.mmu=new Uint8Array(12);old.mmuCR=0x3E;
    const o=new C128('c128');o.ram1[0x10]=1;o.loadState(old);
    check(o.ram1[0x10]===0&&o.mmu[6]===4&&o.mmu[9]===1&&o.read(0xF0)===o.ram[0xF0]&&!o.bankedRam&&o.mmuCR===0x3E,
      'banks: states from before bank 1 load with bank 1 empty and the default MMU registers');
    const f=path.join(ROOT,'../briefs/ref/c128-minefield.state.json');
    if(fs.existsSync(f)){
      const saved=JSON.parse(fs.readFileSync(f,'utf8')),g=boot('game','trace');
      g.m.ram1[0x1234]=9;
      g.m.loadState(g.m.stateFromText(JSON.stringify(saved.state)));
      let ok=!g.m.stopped&&g.m.ram1.every(x=>!x)&&g.m.mmu[6]===4&&!g.m.bankedRam;
      for(let i=0;i<10&&ok;i++)ok=g.m.runFrame()&&!g.m.stopped;
      check(ok,'banks: the supplied C128 minefield state still loads (bank 1 empty) and runs 10 frames');
    }
  }

  // ---- the game never touches bank 1, RCR or the preconfigurations -----------------------------------------------
  {
    const g=boot('game','trace'),m=g.m;
    run(m,g.hooks,300);
    check(!m.ram1.some(v=>v)&&m.mmu[6]===4&&m.mmu[1]===0x3F&&m.mmu[2]===0x7F&&m.mmu[3]===1&&m.mmu[4]===0x41&&m.mmu[7]===0&&m.mmu[9]===1,
      'banks: the game leaves bank 1 empty and the MMU registers at their defaults while it plays (300 frames)');
  }

  // ---- debugger ------------------------------------------------------------------------------------------------
  {
    const gd=boot('game','trace'),m=gd.m;m.ram1[0x2000]=0xC3;m.ram[0x2000]=0x11;const before=m.ram[0x2001];
    const d=new Debugger(m,gd.hooks,'game',{watches:[],cheats:[],events:[],keys:[]});
    const lines=d.exec('m1 2000 1'),w=d.exec('>1 2001 aa bb');
    check(/C3/.test(lines[0])&&m.ram1[0x2001]===0xAA&&m.ram1[0x2002]===0xBB&&m.ram[0x2001]===before&&m.peekBank(1,0x2000)===0xC3&&m.peekBank(0,0x2000)===0x11,
      'banks: the debugger shows (m1) and writes (>1) bank 1');
  }
};
