import json,sys
d=open(sys.argv[1],'rb').read()[2:]
L=json.load(open('vlayout.json'))
for i,n in enumerate(L): print('%02X  %s'%(d[i],n))
