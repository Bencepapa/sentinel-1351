const fs=require('fs');let s=fs.readFileSync('briefs/compare-tunnel.cjs','utf8');s=s.slice(0,s.indexOf('A[S.M_STATE+24]=255'));s+=`
A[S.M_STATE+24]=255;call(m,S.SECTORIN);A.set([0xa0,0x88],S.ENX);A.set([0x90,0x88],S.ENY);A.set([0x90,0x88],S.ENZ);
function runCheck(tag){m.runFrame();let late=[];for(let i=0;i<m.vicLog.length;i+=4){let [l,c,r,v]=m.vicLog.slice(i,i+4);if((r===32||r===33)&&((l>=50&&l<=76)||(l>=230&&l<=245))&&c>=16&&c<=55)late.push([l,c,r,v]);}if(late.length)console.log(tag,late,'phase',A[S.MSSTATE],A[S.MSROW],A[S.MNLOAD],A[S.MNFIN]);}
for(let f=0;f<400&&!A[S.MNFIN];f++)runCheck('before'+f);console.log('cleanup',A[S.MNLOAD]);call(m,S.MAPOPEN);for(let f=0;f<50;f++)runCheck('map'+f);call(m,S.MAPCLOSE);for(let f=0;f<160&&A[S.MSSTATE]===16;f++)runCheck('after'+f);
`;fs.writeFileSync('briefs/map-tunnel.cjs',s);
