Probe tools behind the "Measurements (step 0-1)" section of briefs/memory-overlay-plan.md.
Run them in an empty scratch directory (they write probe.prg, test.d64, res_*.bin there).

VICE x128 (never touches the user's vice.ini: -config <scratch file>):
  python gen.py              MMU / bank 1 / common RAM / copy stub / timing / VDC probe -> probe.prg + layout.json
  bash run3.sh <tag>         autostart it in x128 (-80col -warp, d64 attached), the program SAVEs its results
                             (RES) to the d64; extracted with c1541 -> res_<tag>.bin
  python dec.py res_<tag>.bin
  python genvic2.py          the VIC bank 1 probe (sprite-background collisions); BLK=1|2 picks the VIC block;
                             decode with python decv.py res_<tag>.bin
  Options: CFG=<ini> for another config (e.g. [C128] VDC64KB=1), extra x128 options after the tag,
  DEN=1 (gen.py) leaves the display on in the timing section.

JS machine (node):
  measure.js [flight|fight|hyper|base]   spare processor cycles per frame in the frame loop's wait loops (m.dma = true)
  measure2.js                            the same for an empty sector, by wait loop and target line
  jscopy.js                              the copy stub's time on the JS machine, with / without the VIC's DMA
