import json, sys
f = sys.argv[1]
d = open(f, 'rb').read()[2:]
J = json.load(open('layout.json'))
n = 0
RC, PR = J['RCRS'], J['PROBES']
for name, c in J['layout']:
    if name.startswith('RCR grid'):
        print('RCR grid (rows RCR; written value read back | A1 = common (shared) at probe):')
        print('probes:', ' '.join('%04X' % p for p in PR))
        for r in RC:
            vals = d[n:n+1+len(PR)]; n += 1 + len(PR)
            print('RCR %02X rb %02X |' % (r, vals[0]), ' '.join('  C ' if v == 0xA1 else (' ..  ' if v == 0xA0 else ' %02X ' % v) for v in vals[1:]))
        continue
    vals = d[n:n+c]; n += c
    print('%-70s %s' % (name, ' '.join('%02X' % v for v in vals)))
