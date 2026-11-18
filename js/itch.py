"""Build the minimal itch.io page from itch-page.html.

  js/dist/itch.html   one self-contained file: the page, the scripts and the two programs
  js/dist/itch.zip    the same as index.html in a zip: what itch.io takes as an HTML5 game
  js/itch-dev.html    (with --dev) the same page loading src/*.js, for a local static server

Needs js/programs.js (python js/build.py makes it; this script does not touch it). Only the
two programs the page plays are embedded, with just the labels the page uses.
"""

import json
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = ['src/cpu6502.js', 'src/font.js', 'src/video.js', 'src/machine.js', 'src/hooks.js',
           'src/hiscore.js', 'src/pacing.js', 'src/audio.js', 'src/input.js', 'src/itch.js']
# the programs the page plays (C64 original with the 1351 patch, C128 port) and the labels it uses
PROGRAMS = {
    'c64game': ['GAMEENTRY', 'POTRD', 'OPOTX', 'OPOTY', 'RCNT'],
    'game': ['end_rankok', 'ENDRANKSET', 'ENDKILLS', 'M_STATE', 'OVOWNER', 'ENDSCORE', 'DIFF',
             'ENDMODE', 'ENDRANK', 'ENDRESET', 'HUDTIME', 'CLOCKHOURS'],
}


def read(path):
    with open(os.path.join(HERE, path), encoding='utf-8') as f:
        return f.read()


def programs_js():
    text = read('programs.js')
    data = json.loads(text[text.index('{'):text.rindex('}') + 1])
    out = {}
    for name, labels in PROGRAMS.items():
        p = dict(data[name])
        missing = [l for l in labels if l not in p['symbols']]
        if missing:
            sys.exit('%s: missing labels %s' % (name, missing))
        p['symbols'] = {k: v for k, v in p['symbols'].items() if k in labels}
        p.pop('code', None)
        out[name] = p
    return '// programs: ' + ', '.join(PROGRAMS) + ' (from js/programs.js)\nvar SENTINEL_PROGRAMS = ' + json.dumps(out, separators=(',', ':')) + ';'


def build_page(inline):
    page = read('itch-page.html')
    if inline:
        tags = ['<script>\n' + programs_js().replace('</script', '<\\/script') + '\n</script>']
        for s in SCRIPTS:
            tags.append('<script>\n' + read(s).replace('</script', '<\\/script') + '\n</script>')
    else:
        tags = ['<script src="programs.js"></script>'] + ['<script src="%s"></script>' % s for s in SCRIPTS]
    return page.replace('<!--SCRIPTS-->', '\n'.join(tags))


def main():
    html = build_page(True)
    os.makedirs(os.path.join(HERE, 'dist'), exist_ok=True)
    with open(os.path.join(HERE, 'dist', 'itch.html'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(html)
    zpath = os.path.join(HERE, 'dist', 'itch.zip')
    with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as z:
        info = zipfile.ZipInfo('index.html', date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, html.encode('utf-8'))
    if '--dev' in sys.argv:
        with open(os.path.join(HERE, 'itch-dev.html'), 'w', encoding='utf-8', newline='\n') as f:
            f.write(build_page(False))
    print('wrote js/dist/itch.html (%d KB) and js/dist/itch.zip (%d KB)'
          % (len(html.encode('utf-8')) // 1024, os.path.getsize(zpath) // 1024))


if __name__ == '__main__':
    main()
