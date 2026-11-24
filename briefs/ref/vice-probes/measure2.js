// breakdown of the wait-loop cycles of one frame by loop and target line (flight, fight)
const {boot,run,dogfight}=require('./measure.js');
function breakdown(g, label, frames, drive){
  const {m,s,K}=g, c=m.cpu;
  const loops={frame:[s.frame,s.frame+7],wl1:[s.wl1,s.wl1+7],wst1:[s.wst1,s.wst1+5],w251:[s.w251,s.w251ok],vbw:[s.vbw,s.vbw+14]};
  const acc={};let nf=0;
  const step=c.step.bind(c);
  c.step=function(){const pc=this.pc,c0=this.cycles;const r=step();const d=this.cycles-c0;
    for(const k in loops){if(pc>=loops[k][0]&&pc<loops[k][1]){let key=k;if(k==='wl1'||k==='wst1')key+=' until line '+K[s.WLN]+(k==='wst1'?'':'');acc[key]=(acc[key]||0)+d;break;}}
    return r;};
  for(let i=0;i<frames;i++){if(drive)drive(i);m.runFrame();nf++;}
  c.step=step;
  console.log(label);
  for(const k of Object.keys(acc).sort())console.log('   ',k.padEnd(24),String(Math.round(acc[k]/nf)).padStart(6),'cycles/frame');
}
let g=boot();run(g,60);run(g,40,k=>{});
breakdown(g,'flight, empty sector',200,null);
g=boot();run(g,60);dogfight(g);run(g,20);
// arrival-free fight: use the jump? (here dogfight flag gives no fighters in "game"): skip
