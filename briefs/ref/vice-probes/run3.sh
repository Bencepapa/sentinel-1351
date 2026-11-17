#!/bin/bash
# usage: run2.sh <tag> [vice args]: run for LIM cycles (VICE exits by itself), then extract file RES from test.d64
cd "$(dirname "$0")"
tag=$1; shift
C1541=/c/dev/c64/GTK3VICE-3.9-win64/bin/c1541.exe
echo "" > mon_empty.txt
for attempt in $(seq 1 ${ATT:-2}); do
  taskkill //F //IM x128.exe >/dev/null 2>&1; sleep 0.5
  rm -f test.d64 RES; $C1541 -format test,01 d64 test.d64 >/dev/null
  timeout ${TMO:-100} /c/dev/c64/GTK3VICE-3.9-win64/bin/x128.exe -config ${CFG:-scratch.ini} -sounddev dummy -80col -warp -autostartprgmode 1 -moncommands mon_empty.txt -limitcycles ${LIM:-60000000} -exitscreenshot shot_$tag.png -8 test.d64 "$@" -autostart probe.prg > run_$tag.out 2>&1
  $C1541 test.d64 -read res RES >/dev/null 2>&1
  if [ -s RES ]; then cp RES res_$tag.bin; echo "got res_$tag.bin ($(stat -c %s RES) bytes, attempt $attempt)"; exit 0; fi
done
echo "NO RESULT"
