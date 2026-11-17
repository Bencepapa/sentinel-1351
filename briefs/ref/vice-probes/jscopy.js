const {boot}=require('./measure.js');
const C128=require('C:/dev/c64/sentinel/js/src/machine.js');
const GET=[0xA0,0x00,0x8D,0x02,0xFF,0xB1,0xF2,0x8D,0x01,0xFF,0x91,0xF4,0xC8,0xD0,0xF3,0xE6,0xF3,0xE6,0xF5,0xCA,0xD0,0xEC,0x60];
function measure(pages,den,dma,mhz,phase){
  const m=new C128('c128');m.write(0xFF00,0x3E);m.write(0xD501,0x3E);m.write(0xD502,0x7F);
  m.ram.set(GET,0x0100);
  // program: LDX #pages ; JSR $0100 ; JMP *   at $1D00
  m.ram.set([0xA2,pages,0x20,0x00,0x01,0x4C,0x05,0x1D],0x1D00);
  m.ram[0xF2]=0;m.ram[0xF3]=0x40;m.ram[0xF4]=0;m.ram[0xF5]=0x5C;
  m.vic[0x11]=den?0x1B:0x0B;m.vic[0x30]=mhz===2?1:0;m.dma=dma;
  m.start(0x1D00);m.stopped=null;
  // let the raster run to the wanted phase first (idle)
  m.cpu.pc=0x1D20;m.ram[0x1D20]=0x4C;m.ram[0x1D21]=0x20;m.ram[0x1D22]=0x1D;
  while(m.cycleInFrame()<phase)m.stepInstruction();
  m.cpu.pc=0x1D00;
  const t0=m.frame*19656+m.cycleInFrame();
  let n=0;while(m.cpu.pc!==0x1D05&&n++<1e6)m.stepInstruction();
  return Math.round(m.frame*19656+m.cycleInFrame()-t0);
}
for(const [den,dma,mhz] of [[0,false,1],[0,true,1],[1,false,1],[1,true,1],[0,true,2],[1,true,2]]){
  const r=[];for(const ph of [1000,5000,9000,13000])r.push(measure(1,den,dma,mhz,ph));
  const r3=[];for(const ph of [1000,5000,9000,13000])r3.push(measure(3,den,dma,mhz,ph));
  console.log(`DEN=${den} dma=${dma} ${mhz}MHz  1 page (raster cycles, 4 phases): ${r.join(' ')}   3 pages: ${r3.join(' ')}`);
}
