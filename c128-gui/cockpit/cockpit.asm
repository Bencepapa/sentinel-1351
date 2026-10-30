; Sentinel cockpit for the native C128 (VIC-IIe, 40 columns).
;
; The picture is built the way the original does it: the raster is polled and the
; video mode, border and background colours are switched at fixed lines (see
; c128-gui/README.md, "Raster schedule"): a text strip with the HUD on top, the
; multicolor bitmap for the 3D view and the cockpit art, a text strip at the bottom.
; The 3D view is a star field. The crosshair (sprite 0, shape $7D) follows the
; 1351 mouse or the joystick in port 2 with the logic of the original mouse patch;
; the two guns (sprites 0 and 3, shapes $7E / $7F, shown below the 3D view) follow it
; with the original's gun routine ($9568). Fire launches the phasor shot (sprite 1,
; shapes $70 down to $67) from a gun to the crosshair, as the original does
; ($1424, $1467, $1526, the line routine $3580; see "the phasor shot" below).
;
; Data placed by build.py: COLORDATA, the tables, the character set ($4000), the color
; matrix ($4400), the text screen ($4800), the sprite shapes ($4C00) and the cockpit
; art in the bitmap. Nothing may live at $5000-$5FFF: the C128's video chip reads the
; character ROM there (VIC address $1000-$1FFF) even in VIC bank 1, which turned the
; text and the sprites into noise in the first test.

MMUCR   = $FF00
CIA1PA  = $DC00
CIA1PB  = $DC01
CIA2PA  = $DD00
VICENA  = $D015
BORDER  = $D020
BG      = $D021
FAST    = $D030
POTX    = $D419
POTY    = $D41A
SPRPTR  = $47F8         ; sprite pointers (matrix at $4400)
BITMAP  = $6000
COLOR   = $D800
YLO     = $2D00
YHI     = $2E00
XLO     = $2F00
XHI     = $2F28
COLORDATA = $3000
PATHX   = $3400         ; phasor shot path, x / 2 (original $0400)
PATHY   = $3500         ; and y (original $0500)
HUDE    = $483E         ; the four energy digits of the HUD (original $543E)
HUDS    = $4832         ; the two shield digits of the HUD (original $5432)
EFPASS  = 16            ; the original's main loop passes per frame in a fight (enemy fire)
TARGETS = $4876         ; the last digit of TARGETS on the HUD (original $5476)
LRTAB   = $3600         ; the long range scanner's scale 0-128 -> 0-99 (original $ED00, build.py)
DIGF    = $3690         ; the digits drawn under the crosshair (original sprite $64, build.py)
LRROW   = $4B98         ; text row 23: the long range scanner (original $5798)
COLROW  = $DB98         ; its colours
BLPTR   = $36           ; sprite pointers $36-$38: the blip, shapes $4C-$4E
PASSES  = 8             ; main loop passes of the original per frame in a fight
SHOTPTR = $F3           ; sprite pointers of the shot shapes $67-$70: $F3-$FC (bitmap rows
                        ; 23-24, never shown as bitmap); the fighters: ENPTR
STREAMS = $8000         ; type-1 movement streams (original $E800-$ECFF): pages $80-$84
PTR     = $FB
NSTARS  = 12
DDLY    = $40           ; frames of calm before the crosshair glides back
DZ      = 12            ; steering dead zone around the center
NDZ     = 244           ; -DZ

        * = $1D00
START:  SEI
        LDA MMUCR
        STA SAVMMU
        LDA #$0E        ; bank 0 RAM + I/O + KERNAL ROM
        STA MMUCR
        LDA PTR
        STA SAVPTRL
        LDA PTR+1
        STA SAVPTRH
        LDA CIA1PA
        STA SAVPA
        LDA CIA2PA
        STA SAVC2
        LDA $D011
        STA SAV11
        LDA $D016
        STA SAV16
        LDA $D018
        STA SAV18
        LDA VICENA
        STA SAVENA
        LDA BORDER
        STA SAVBOR
        LDA BG
        STA SAVBG
        LDA FAST
        STA SAVFAST
        LDA $D01B
        STA SAV1B
        LDA $D01D
        STA SAV1D
        LDA FAST        ; 1 MHz
        AND #$FE
        STA FAST
        LDA CIA2PA
        AND #$FC
        ORA #$02        ; VIC bank 1: $4000-$7FFF
        STA CIA2PA
        LDA #0
        STA VICENA

        LDX #0          ; color RAM from the captured cockpit
cpc:    LDA COLORDATA,X
        STA COLOR,X
        LDA COLORDATA+256,X
        STA COLOR+256,X
        LDA COLORDATA+512,X
        STA COLOR+512,X
        LDA COLORDATA+768,X
        STA COLOR+768,X
        INX
        BNE cpc

        LDA #$BF        ; let the SID settle on port 2 before the first read
        STA CIA1PA
        LDX #16
set1:   LDY #0
set2:   DEY
        BNE set2
        DEX
        BNE set1
        LDA POTX
        STA OLDX
        LDA POTY
        EOR #$FF
        STA OLDY

        LDA #$0F        ; SID volume for the phasor sound
        STA $D418
        JSR SHIPINIT    ; systems and shields by difficulty
        JSR EFRESET
        JSR SECSTART    ; a squadron in the sector (c128-game: the map's start sector)
        LDA #$80        ; the star field
        STA SEED
        LDX #NSTARS-1
stinit: JSR NEWSTAR
        JSR PLOTSTAR
        DEX
        BPL stinit

; ================= the frame, driven by the raster =================
frame:  LDA $D012       ; still in the border of the old frame (lines 251-255)? wait for the wrap
        CMP #251
        BCS frame
        LDA #56
        JSR WAITLN
        LDA #1          ; the one line of white at the top of the HUD
        STA BG
        STA BORDER
        LDA #$1B
        STA $D011
        LDA #$08
        STA $D016
        LDA #$20        ; text: screen $4800, character set $4000
        STA $D018
        LDA #58
        JSR WAITLN
        LDA HUDBRD      ; upper HUD: the border ($0CCC: light blue, the sound's pulse,
        STA BORDER      ; the approach's green / red / yellow), dark gray background
        LDA #$0B
        STA BG
        LDA #74
        JSR WAITLN
        LDA #1          ; two white lines
        STA BG
        STA BORDER
        LDA #75
        JSR WAITLN
        LDA #$3B        ; multicolor bitmap: the 3D view and the cockpit art
        STA $D011
        LDA #$18
        STA $D016
        STA $D018
        LDA #76
        JSR WAITLN
        LDA FLASHC      ; black (white with the map open: VIEWBG), or the colour
        BNE vbg1        ; of a hit flash ($0B26, $0A4D)
        LDA VIEWBG
vbg1:   STA BG
        LDA #77
        JSR WAITLN
        LDA FLASHC
        BNE vbg2
        LDA VIEWBG
vbg2:   STA BORDER
        LDA #78
        JSR WAITLN
        JSR SPRCROSS    ; the crosshair
        JSR FIREPH      ; the phasors, while the 3D view is drawn (the original runs
        LDA SHOTARM     ; $1424 in its interrupt and launches from its main loop,
        BEQ nolaunch    ; $2DFC; here the time until line 194 is free)
        LDA TRUN        ; (tracking: only every 64 passes, TLOK)
        BEQ dolaunch
        LDA TLOK
        BEQ nolaunch
        LDA #$00
        STA TLOK
dolaunch:
        JSR LAUNCH
nolaunch:
        JSR SWEEPSND    ; the phasor sound is swept 6 times a frame while a shot
        JSR SWEEPSND    ; flies: once in $1424, 3 times after it ($0C3B-$0C41),
        JSR SWEEPSND    ; at line 194 ($0C60) and at line 233 ($0CBA)
        LDA APPR        ; approaching (no phasor then): the approach loop's passes
        BEQ nov         ; in the 3D view's time
        JSR APPASSES
nov:    LDA TRUN        ; tracking: its passes too
        BEQ nov2
        LDA #112
        JSR TRKSL2
nov2:    LDA #182        ; the explosions use what is left of the 3D view's time
                        ; (a point takes up to 11 lines)
        STA EXLIM
        JSR EXPLODE
        JSR EXPLODE2
        LDA #194
        JSR WAITLN
        JSR SPRGUNS     ; sprites 0 and 3 become the two guns
        JSR SWEEPSND
        JSR FIGHT       ; the fighters (the time until line 230 is free; the star
                        ; field fills the vertical blank)
        LDA #218
        STA EXLIM
        JSR EXPLODE
        JSR EXPLODE2
        LDA #230
        JSR WAITLN
        LDA #0
        STA VICENA
        LDA #233
        JSR WAITLN
        LDA #$0B        ; text strip: the one character tall gray line
        STA BORDER
        STA BG
        LDA #$1B
        STA $D011
        LDA STRIPX      ; (the message row's fine scroll, $0A4A)
        STA $D016
        LDA #$20
        STA $D018
        JSR SWEEPSND
        LDX #0          ; black below it: written as early as possible in line 242
        LDY #$08
w242:   LDA $D012
        CMP #242
        BCC w242
        STX BORDER
        STX BG
        STY $D016

        JSR INPUTV      ; vertical blank: mouse, cursor, guns (at 1 MHz: lines
        LDA APPR        ; (no shots while approaching: fire chooses a group)
        BEQ vbf
        LDA #$00
        STA FIREFLAG
vbf:
        LDA #251        ; 242-250 are still in the display window)
        JSR WAITLN
        LDA FAST        ; 2 MHz in the border, lines 251-47: the VIC-IIe fetches
        ORA #$01        ; nothing there (sprites are off, no bad lines), so the
        STA FAST        ; processor gets twice the time (I/O accesses stay 1 MHz)
        JSR VIEWVB      ; the star field (or the map's frame, c128-game)
        JSR VBWORK      ; steering, drift, enemy fire, the radar
        JSR TICKHK      ; (c128-game: the world's clock, $BE29)
vbw:    BIT $D011       ; after the wrap (line 256-311 read as 0-55 with bit 7
        BMI vbw         ; of $D011 set), the rest of the border: the explosions
        LDA $D012
        CMP #251
        BCS vbw
        LDA #40         ; (a point takes up to 4 lines at 2 MHz)
        STA EXLIM
        JSR EXPLODE
        JSR EXPLODE2
        LDA $D012       ; count frames whose work ran past line 47 (should stay 0)
        CMP #48
        BCC vbok
        CMP #251
        BCS vbok
        INC OVRUN
vbok:   LDA FAST        ; 1 MHz again before the display window
        AND #$FE
        STA FAST
        LDA #$7F        ; SPACE leaves
        STA CIA1PA
        LDA CIA1PB
        AND #$10
        BNE nospace
        JMP EXIT
nospace:LDA #$BF        ; port 2 pots for the next frame
        STA CIA1PA
        JMP frame

WAITLN: STA WLN         ; A = raster line: wait until it is reached or already passed
wl1:    LDA $D012
        CMP WLN
        BCC wl1
        RTS

EXIT:   LDA #0
        STA VICENA
        STA $D404
        STA $D418
        LDA SAV11
        STA $D011
        LDA SAV16
        STA $D016
        LDA SAV18
        STA $D018
        LDA SAVENA
        STA VICENA
        LDA SAV1B
        STA $D01B
        LDA SAV1D
        STA $D01D
        LDA SAVC2
        STA CIA2PA
        LDA SAVPA
        STA CIA1PA
        LDA SAVBOR
        STA BORDER
        LDA SAVBG
        STA BG
        LDA SAVFAST
        STA FAST
        LDA SAVMMU
        STA MMUCR
        LDA SAVPTRL
        STA PTR
        LDA SAVPTRH
        STA PTR+1
        CLI
        RTS

; ---------------- sprites ----------------
; Sprite 0 is the crosshair in the 3D view: shape $7D, or $49-$4B animated while a
; target is tracked (T), original $1290-$12E0.
SPRCROSS:
        LDA $D01B       ; in front of the bitmap
        AND #$FE
        STA $D01B
        LDA $D01D       ; not expanded
        AND #$FE
        STA $D01D
        LDA #$30        ; shape $7D of the original, moved to $4C00
        LDX TRACK
        BEQ sc1
        LDA TRFRAME
sc1:    STA SPRPTR
        LDA XPOS
        STA $D000
        LDA MAPSHOWN    ; (the map open: sprite 1 is its planet, set by the map;
        BEQ scs         ; sprite 0 the map's mouse pointer, a black +)
        LDA #$3F
        STA SPRPTR
        LDA PTSX
        STA $D000
        LDA PTSY
        STA CURYS
        LDA $D010
        AND #$FE
        ORA PTSXH
        JMP sc2
scs:    LDA $D010
        AND #$FC
        ORA XMSB
        LDX SHOTXH      ; sprite 1: the phasor shot
        BEQ sc2
        ORA #$02
sc2:    STA $D010
        LDA CURY
        LDX MAPSHOWN
        BEQ sc3
        LDA CURYS
sc3:    STA $D001
        LDA NUMCOL      ; white, light green while the target is behind ($3934)
        LDX MAPSHOWN    ; (the map's pointer: white)
        BEQ sc4
        LDA #$01
sc4:    STA $D027
        JSR SPRENEMY    ; sprites 4-6: the fighters
        JSR SPR7        ; sprite 7: the guns' barrels, the radar's scan line
        LDA MAPSHOWN
        BNE scm
        LDA SHOTSHP     ; shapes $67-$70 are pointers $F3-$FC here
        CLC
        ADC #$8C        ; SHOTPTR - $67
        STA SPRPTR+1
        LDA SHOTX
        STA $D002
        LDA SHOTY
        STA $D003
scm:    LDA EFX         ; sprite 2: the enemy shot
        STA $D004
        LDA EFY
        STA $D005
        LDA $D010
        AND #$FB
        ORA EFMSB
        STA $D010
        LDA EFSHP       ; shapes $67-$70 -> pointers $F3-$FC
        CLC
        ADC #$8C
        STA SPRPTR+2
        LDA MAPSHOWN    ; the map open: the pointer (if a mouse), the planet
        BEQ scv
        LDA PTON
        ORA #$02
        BNE scv2
scv:    LDA SHOTVIS
        ASL A
        ORA #1
scv2:   ORA #$80        ; (sprite 7)
        ORA EVIS
        ORA EFVIS
        STA VICENA
        RTS

; Below the 3D view the same two slots show the gun shapes (original $120B-$126F):
; sprite 0 = left gun $7E, sprite 3 = right gun $7F, both twice as wide, behind the
; bitmap, gray; while a shot is in flight the gun it came from is red ($1241).
SPRGUNS:LDA $D01B       ; both guns behind the bitmap (the bases stand in front of them)
        ORA #$09
        STA $D01B
        LDA $D010
        AND #$FE
        ORA #$08        ; the right gun is beyond x = 255
        STA $D010
        LDA G1X
        STA $D000
        LDA G2X
        STA $D006
        LDA G1Y
        STA $D001
        LDA G2Y
        STA $D007
        LDA #$34        ; the guns $7E / $7F of the original
        STA SPRPTR
        LDA #$35
        STA SPRPTR+3
        LDA #$0C
        LDX #$0C
        LDY SHOTON
        BEQ sg3
        LDY SHOTGUN     ; 1: the left gun fired
        CPY #$01
        BNE sg2
        LDA #2
        JMP sg3
sg2:    LDX #2
sg3:    STA $D027
        STX $D02A
        LDA $D01D
        ORA #$09
        STA $D01D
        LDA SHOTVIS
        ASL A
        ORA #$89        ; (and sprite 7)
        ORA EVIS
        ORA EFVIS
        STA VICENA
        RTS

; ---------------- the star field ----------------
; Like the original: NSTARS stars start anywhere in a 128 x 128 square around the
; fixed vanishing point (79,99) and drift straight away from it at about 1.25
; pixels per frame (the original's speed), then start again somewhere else.
STARS:  INC FRMC
        LDA #0          ; steering shifts every star (the original: +-2 pixels, here every 2nd frame):
        STA SHX         ; stick left -> stars right, up -> stars up, as in the original
        STA SHY
        JSR TSTARS      ; tracking: the computer turns the view
        BCS nosh
shj:    LDA FRMC
        LSR A
        BCS nosh
        LDA JOYG
        LSR A
        BCS sh1
        DEC SHY
        DEC SHY
sh1:    LSR A
        BCS sh2
        INC SHY
        INC SHY
sh2:    LSR A
        BCS sh3
        INC SHX
        INC SHX
sh3:    LSR A
        BCS nosh
        DEC SHX
        DEC SHX
nosh:   JSR STARTK
        LDX #NSTARS-1
stl:    JSR ERASESTAR
        JSR MOVESTAR
        JSR PLOTSTAR
        DEX
        BPL stl
        RTS

NEWSTAR:JSR RANDOM      ; X = star: x 16-143, y 36-141 (the 3D view)
        AND #$7F
        CLC
        ADC #16
        STA STARX,X
nsy:    JSR RANDOM
        AND #$7F
        CLC
        ADC #36
        CMP #142
        BCS nsy
        STA STARY,X
        LDA #0
        STA STARV,X
        RTS

MOVESTAR:
        LDA #0
        STA DIRX
        STA DIRY
        LDA STARX,X
        SEC
        SBC #79
        BCS mx1
        EOR #$FF
        ADC #1
        DEC DIRX
mx1:    STA ADX
        LDA STARY,X
        SEC
        SBC #99
        BCS my1
        EOR #$FF
        ADC #1
        DEC DIRY
my1:    STA ADY
        LDY NT0         ; steps this frame (STARTK: faster while rushing)
        STY NTICK
mloop:  LDA ADX         ; the longer axis steps every time, the other one by slope
        CMP ADY
        BCC majy
        JSR STEPX
        LDA STARV,X
        CLC
        ADC ADY
        CMP ADX
        BCC mst
        SBC ADX
        STA STARV,X
        JSR STEPY
        JMP mnext
majy:   JSR STEPY
        LDA STARV,X
        CLC
        ADC ADX
        CMP ADY
        BCC mst
        SBC ADY
        STA STARV,X
        JSR STEPX
        JMP mnext
mst:    STA STARV,X
mnext:  DEC NTICK
        BNE mloop
        LDA STARX,X
        CLC
        ADC SHX
        STA STARX,X
        LDA STARY,X
        CLC
        ADC SHY
        STA STARY,X
        LDA STARX,X     ; out of the 3D view: a new star
        CMP #2
        BCC msnew
        CMP #158
        BCS msnew
        LDA STARY,X
        CMP #26
        BCC msnew
        CMP #142
        BCS msnew
        RTS
msnew:  JMP NEWSTAR

STEPX:  LDA DIRX
        BNE sxm
        INC STARX,X
        RTS
sxm:    DEC STARX,X
        RTS

STEPY:  LDA DIRY
        BNE sym
        INC STARY,X
        RTS
sym:    DEC STARY,X
        RTS

PLOTSTAR:
        STX SAVEX
        LDA STARX,X
        STA POSX
        LDA STARY,X
        STA POSY
        JSR PIXADDR
        LDA (PTR),Y
        ORA MASK3,X
        STA (PTR),Y
        LDX SAVEX
        RTS

ERASESTAR:
        STX SAVEX
        LDA STARX,X
        STA POSX
        LDA STARY,X
        STA POSY
        JSR PIXADDR
        LDA (PTR),Y
        AND CLEARM,X
        STA (PTR),Y
        LDX SAVEX
        RTS

PIXADDR:LDY POSY
        LDA YLO,Y
        STA PTR
        LDA YHI,Y
        CLC
        ADC #$60
        STA PTR+1
        LDA POSX
        LSR A
        LSR A
        TAX
        LDA XLO,X
        CLC
        ADC PTR
        STA PTR
        LDA XHI,X
        ADC PTR+1
        STA PTR+1
        LDY #0
        LDA POSX
        AND #$03
        TAX
        RTS


; ---------------- input, cursor, guns ----------------
; Once per frame in the vertical blank. The 1351 (port 2) moves the crosshair, its
; left button fires; without a mouse the joystick moves it, as in the original.
INPUT:  JSR POTS
        LDA #$FF        ; port 2 lines (the keyboard columns are all off)
        STA CIA1PA
        LDA CIA1PA
        STA JRAW
        JSR TKEYS       ; A / T: the tracking computer; the tracking crosshair
tno:    LDA MPRES
        BEQ ijoy
        LDA JRAW        ; mouse: its buttons, the steering mask makes the directions
        ORA #$01        ; the right button is wired to UP
        AND DS
        AND DS2
        STA JOY
        JMP icur
ijoy:   LDA JRAW
        STA JOY
icur:   LDA DS          ; the guns lean with the crosshair's offset from the center
        AND DS2
        STA JOYG
        LDA JOY         ; fire pressed: set the fire flag (original $02CB-$02D6:
        AND #$10        ; it is only ever set here; releasing fire does not clear it,
        BNE nofire      ; the end of the shot does)
        LDA #$01
        STA FIREFLAG
nofire: JSR CURSOR
        LDA CURX        ; crosshair sprite position
        CLC
        ADC #$2D
        STA XPOS
        LDA #0
        ROL A
        STA XMSB
        INC GFRM        ; the guns take a step every 16th frame only (the original
        LDA GFRM        ; calls $9568 when its frame counter $A0 & $0F = 0, $0C2B):
        AND #$0F        ; they follow the crosshair slowly
        BNE ig1
        JSR GUNS
ig1:    RTS

; Crosshair update (original $B2D8-$B399 as patched for the mouse).
CURSOR: LDA MPRES
        BEQ cjoy
        LDA JOY
        AND #$10
        EOR #$10        ; non-zero while firing
        ORA MDX
        ORA MDY
        BNE mmove
        JMP IDLE
mmove:  LDY #DDLY
        STY DTIMER
        LDX MDX
        LDY MDY         ; +back: forward moves the crosshair up
        JMP CAPPLY
cjoy:   LDA JOY
        AND #$1F
        CMP #$1F
        BNE cjact
IDLE:   DEC DTIMER
        BEQ DRIFT
        RTS
DRIFT:  LDA #1          ; idle: glide back to the center, one step per frame
        STA DTIMER
        LDX #0
        LDA #$7E
        CMP CURX
        BEQ dr1
        LDX #1
        BCS dr1
        LDX #$FF
dr1:    LDY #0
        LDA YCEN
        CMP CURY
        BEQ CAPPLY
        LDY #1
        BCS CAPPLY
        LDY #$FF
        BNE CAPPLY
cjact:  LDY #DDLY       ; joystick: X +-3, Y +-2 per frame (up moves the crosshair down)
        STY DTIMER
        LDX #0
        LDY #0
        LSR A
        BCS cj1
        INY
        INY
cj1:    LSR A
        BCS cj2
        DEY
        DEY
cj2:    LSR A
        BCS cj3
        DEX
        DEX
        DEX
cj3:    LSR A
        BCS CAPPLY
        INX
        INX
        INX
CAPPLY: STY CD          ; X = dx, Y = dy (signed)
        STX OLDV
        LDA CURX
        LDX #0
        JSR CLAMP
        STA CURX
        LDA CD
        STA OLDV
        LDA CURY
        LDX #2
        JSR CLAMP
        STA CURY
        RTS

; A = A + OLDV (signed), clamped to BND+X .. BND+1+X, then SIDE
CLAMP:  LDY OLDV
        BMI clneg
        CLC
        ADC OLDV
        BCS clhi
        CMP BNDH,X
        BCC SIDE
clhi:   LDA BNDH,X
        BCS SIDE
clneg:  CLC
        ADC OLDV
        BCC cllo
        CMP BND,X
        BCS SIDE
cllo:   LDA BND,X
; A = position on axis X: DS,X = the joystick direction it stands for
SIDE:   PHA
        SEC
        SBC CEN,X
        BMI sneg
        CMP #DZ+1
        LDA PMSK,X
        BCS sst
sctr:   LDA #$FF
        BNE sst
sneg:   CMP #NDZ
        LDA NMSK,X
        BCS sctr
sst:    STA DS,X
        PLA
        RTS

; 1351: pots -> MDX / MDY (the same as Sentinel's MOVCHK)
POTS:   LDA POTX
        CMP #$FF        ; stuck at $FF: no mouse
        BEQ nomouse
        LDA #1
        BNE setmp
nomouse:LDA #0
setmp:  STA MPRES
        LDA POTX
        LDY OLDX
        JSR MOVCHK
        STA MDX
        TYA
        STA OLDX
        LDA POTY
        EOR #$FF
        LDY OLDY
        JSR MOVCHK
        STA MDY
        TYA
        STA OLDY
        RTS

MOVCHK: STY OLDV
        TAY
        SEC
        SBC OLDV
        ASL A
        CMP #$80
        ROR A
        CMP #$FF
        BEQ mvzero
        CMP #$80
        ROR A
        BEQ mvzero
        RTS
mvzero: LDY OLDV
        LDA #0
        RTS

; The guns (original $9568-$9632): they lean with the direction in JOYG (the crosshair's
; offset from the center, as the mouse patch derives it) and return to rest at the center. G1 = left gun, G2 = right gun.
GUNS:   LDA JOYG
        AND #$0F
        CMP #$0F
        BNE gd0
        JMP REST
gd0:    LSR A           ; up
        BCS gdn
        LDY G1Y
        CPY #$D2
        BCS gu1
        INC G1Y
gu1:    LDY G2Y
        CPY #$D2
        BCS gdn
        INC G2Y
gdn:    LSR A           ; down
        BCS glf
        LDY G1Y
        CPY #$CC
        BCC gd1
        DEC G1Y
gd1:    LDY G2Y
        CPY #$CC
        BCC glf
        DEC G2Y
glf:    LSR A           ; left
        BCS grt
        LDY G1X
        CPY #$18
        BCS gl1
        DEC G1X
        DEC G2X
gl1:    LDY G1Y
        CPY #$D2
        BCS gl2
        INC G1Y
gl2:    LDY G2Y
        CPY #$CC
        BCC grt
        DEC G2Y
grt:    LSR A           ; right
        BCS gend
        LDY G1X
        CPY #$24
        BCS gr1
        INC G1X
        INC G2X
gr1:    LDY G1Y
        CPY #$CC
        BCC gr2
        DEC G1Y
gr2:    LDY G2Y
        CPY #$D2
        BCS gend
        INC G2Y
gend:   RTS
REST:   LDA G1X
        CMP #$20
        BCS rs1
        INC G1X
        INC G2X
        JMP rs2
rs1:    BEQ rs2
        DEC G1X
        DEC G2X
rs2:    LDA G1Y
        CMP #$CF
        BCS rs3
        INC G1Y
        JMP rs4
rs3:    BEQ rs4
        DEC G1Y
rs4:    LDA G2Y
        CMP #$CF
        BCS rs5
        INC G2Y
        JMP rsend
rs5:    BEQ rsend
        DEC G2Y
rsend:  RTS

; ---------------- the phasor shot ----------------
; Ported from the original, routine for routine (C64 addresses in brackets).
; Pressing fire sets the fire flag; FIREPH arms a shot, the next pass launches it
; (LAUNCH): the line routine stores the path from a gun to the crosshair, and the
; shot sprite walks along it, a step every few of 48 sub-ticks per frame, with the
; steps further apart each time (it slows down as it recedes) and a smaller shape
; every third step. The flag stays set until the shot reaches the end of its path,
; so one press fires a whole shot; holding fire fires the next one right after.
; js/test/run.js calls these routines and the original ones inside the C64 game
; with the same crosshair, guns and fire timing and compares the path and the
; shot sprite frame by frame.

FIREPH:                 ; per frame ($1424). The original first stops here when the
        LDA APPR        ; phasor cannons are destroyed ($39), a torpedo flies, the map
        BEQ phgo        ; is shown or approaching ($E3): then it clears the firing
        LDA SHOTON      ; state $D0-$D2 (a shot in flight is dropped, the guns stop
        ORA SHOTARM     ; firing)
        BEQ phret
        LDA #$00
        STA SHOTON
        STA SHOTARM
        STA FIREFLAG
        STA HITWIN
        STA SHOTVIS
        STA $D404
        RTS
phgo:   LDA FIREFLAG
        BEQ phret
        LDA SHOTON
        BEQ pharm
        JMP phfly
pharm:  LDA SHOTARM
        BNE phret
        LDA #$01
        STA SHOTARM
        JSR CHARGESND
phret:  RTS
phfly:  JSR SWEEPSND
        JSR LINEGEN     ; the next part of the path (port only, see LINE)
        LDA #$30
        STA SUBN
phsub:  JSR SHOTSTEP
        DEC SUBN
        BNE phsub
        RTS

LAUNCH: INC SHOTS       ; ($1467) shots fired, for the rating
        BNE la1
        INC SHOTS+1
la1:    LDA #$07        ; sprite 1: yellow, multicolor 6 / 2
        STA $D028
        LDA #$06
        STA $D025
        LDA #$02
        STA $D026
        LDA $D01C
        ORA #$02
        STA $D01C
        LDA $D017       ; (not expanded, in front of the bitmap)
        AND #$FD
        STA $D017
        LDA $D01D
        AND #$FD
        STA $D01D
        LDA $D01B
        AND #$FD
        STA $D01B
        LDA #$01
        STA SHIDX
        STA SHOTY
        LDA GUNSEL      ; the aim point moves 2 pixels every other shot
        EOR #$02
        STA GUNSEL
        LDA CURX
        LSR A
        CLC
        ADC #$18
        SEC
        SBC GUNSEL
        STA L4E
        LDA CURY
        CLC
        ADC #$02
        STA L4F
        LDA L4E         ; crosshair right of the middle: the left gun fires
        CMP #$56
        BCC la2
        LDX #$01
        LDA G1X
        LDY G1Y
        LSR A
        CLC
        ADC #$0A
        JMP la3
la2:    LDX #$FF
        LDA G2X
        LDY G2Y
        LSR A
        CLC
        ADC #$81
la3:    STA L36
        STY L37
        STX SHOTGUN
        JSR LINE        ; NPTS is known at once; the first points are made here
        JSR LINEGEN
        LDA NPTS        ; the step rate grows with the length of the path
        ASL A
        STA RATE
        LDA #$03
        STA SHPRATE
        STA SHPCNT
        LDA #$04
        STA STEPLEN
        STA STEPCNT
        LDA #$70        ; the biggest shape
        STA SHOTSHP
        STA SHOTON
        LDA #$00
        STA SHOTARM
        LDA #$01
        STA SHOTVIS
        JSR SWEEPSND
        JMP ENERGY10    ; a shot costs 10 energy ($F8B2)

SHOTSTEP:               ; one sub-tick ($1526)
        DEC STEPCNT
        BEQ ss1
        RTS
ss1:    LDA #$13        ; the original reads its colour as LDX $1520 / LDA $1520,X,
        STA $D028       ; which lands on $1527, a byte of its own code ($13): cyan
        CLC
        LDA STEPLEN
        ADC #$01
        STA STEPLEN
        STA STEPCNT
        DEC SHPCNT
        BNE ss2
        LDA SHPRATE
        STA SHPCNT
        LDA SHOTSHP
        CMP #$67        ; the smallest shape
        BEQ ss2
        DEC SHOTSHP
ss2:    LDY SHIDX
        LDA PATHX,Y     ; x / 2: bit 7 is the sprite's x bit 8
        PHA
        BPL ss3
        LDA #$01
        BNE ss4
ss3:    LDA #$00
ss4:    STA SHOTXH
        PLA
        ASL A
        STA SHOTX
        LDA PATHY,Y
        STA SHOTY
        INY
        CLC
        LDA FRAC        ; 1 point per step, 2 more when the fraction overflows
        ADC RATE
        STA FRAC
        BCC ss5
        INY
        INY
ss5:    CPY NPTS
        BCC ss7
        LDA #$00        ; the end of the path: the shot is gone
        STA SHOTON
        STA HITWIN
        STA FIREFLAG    ; (the next shot needs fire again)
        STA SHOTY
        STA SHOTVIS
        STA $D404
        STA $D406
        STA $D405
        LDA #$01
        STA $D404
        LDY #$00        ; the original loads Y from its sound flag $F8 here (LDY $F8),
ss7:    STY SHIDX       ; so the position it stores is that flag: 0 with no other sound
        LDA NPTS        ; the last 10 points: the hit test window ($3370, $1616)
        SEC
        SBC SHIDX
        CMP #$0A
        BCS ss8
        STA HITWIN
ss8:    RTS

CHARGESND:              ; ($15C7) voice 1 starts
        LDA #$00
        STA SF1
        STA SF2
        STA SF3
        STA $D404
        STA $D406
        LDA #$0B
        STA $D405
        LDA #$41
        STA $D404
        RTS

SWEEPSND:               ; ($15E0) voice 1 frequency and pulse sweep down
        LDA SHOTON
        ORA SHOTARM
        BNE sw0
        RTS
sw0:    LDY #$03
sw1:    LDA SF3
        SBC #$0D
        STA SF3
        STA $D403
        LDA SF1
        SBC #$3A
        STA SF1
        STA $D400
        BCS sw2
        LDA SF2
        SBC #$08
        STA SF2
        STA $D401
sw2:    DEY
        BNE sw1
        RTS

ENERGY10:               ; ($F8B2) the energy digits -10; at 0000 the original prints
        LDY HUDE+2      ; OUT OF ENERGY ($F8E0), here they just stay at 0000
        DEY
        CPY #$6F
        BEQ en1
        STY HUDE+2
        RTS
en1:    LDY #$79
        STY HUDE+2
        LDY HUDE+1
        DEY
        CPY #$6F
        BEQ en2
        STY HUDE+1
        RTS
en2:    LDY #$79
        STY HUDE+1
        LDY HUDE
        DEY
        CPY #$6F
        BEQ en3
        STY HUDE
        RTS
en3:    LDY #$70
        STY HUDE
        STY HUDE+1
        STY HUDE+2
        STY HUDE+3
        RTS

; The original's line routine ($3580) in its "store the points" mode: from
; (L36, L37) to (L4E, L4F), points into PATHX / PATHY. Same points, same order, but
; made in parts: the original makes the whole path at once (up to about 125 points,
; a full frame of processor time, which its main loop can afford); here LINE sets
; the line up and counts the points (the major delta + 1), and LINEGEN makes 24 more
; per call. The shot uses at most 18 points in its first frame and 12 later, so the
; path is always ready before the shot gets there.
LINE:   LDY #$01
        STY L59
        STY L5A
        DEY
        STY L52
        STY L53
        STY L51
        STY NGEN
        DEY
        LDX #$01
lnab:   LDA L4E,X       ; |delta| per axis, the step sign in L59 / L5A
        CMP L36,X
        BCS lnpos
        SEC
        LDA L36,X
        SBC L4E,X
        STA L4E,X
        PHA             ; (the original's STY $59,X has no absolute form)
        TYA
        STA L59,X
        PLA
        JMP lnnext
lnpos:  SBC L36,X
        STA L4E,X
lnnext: DEX
        BEQ lnab
        CMP L4F         ; y the major axis: swap
        BCS lnmaj
        LDX L4E
        LDA L4F
        STA L4E
        STX L4F
        INY
        LDA L59
        STA L52
        LDA L5A
        STA L53
        STY L59
        STY L5A
lnmaj:  LDY #$01
        STY LGY
        LDA L4E
        LSR A
        STA L50
        LDA L4E         ; the points: one per step of the major axis, both ends
        CLC
        ADC #$01
        STA NPTS
        RTS

LINEGEN:LDA NGEN
        CMP NPTS
        BCC lgmake
        RTS             ; all made
lgmake: LDA #24
        STA LGN
        LDY LGY
        LDA NGEN
        BEQ lnplot      ; the first point comes before any step
lnstep: CLC
        LDA L36
        ADC L59
        STA L36
        CLC
        LDA L37
        ADC L53
        STA L37
        CLC
        LDA L50
        ADC L4F
        STA L50
        LDA L51
        ADC #$00
        STA L51
        INY
        LDA L51
        BNE lnsub
        LDA L50
        CMP L4E
        BCC lnplot
        BEQ lnplot
lnsub:  SEC
        LDA L50
        SBC L4E
        STA L50
        LDA L51
        SBC #$00
        STA L51
        CLC
        LDA L36
        ADC L52
        STA L36
        CLC
        LDA L37
        ADC L5A
        STA L37
lnplot: LDX NGEN
        LDA L36
        STA PATHX,X
        LDA L37
        STA PATHY,X
        INC NGEN
        DEC LGN
        BEQ lgpause
        CPY L4E
        BCC lnmore
        BEQ lnmore
lgpause:STY LGY
        RTS
lnmore: JMP lnstep      ; (the loop is too long for a branch back)

; ---------------- data ----------------
CLEARM: .BYTE $3F,$CF,$F3,$FC
MASK3:  .BYTE $C0,$30,$0C,$03

; steering tables of the mouse patch (CEN PMSK YCEN PMSK2 NMSK DS NMSK2 DS2)
CEN:    .BYTE $7F
PMSK:   .BYTE $F7
YCEN:   .BYTE $81
        .BYTE $FE
NMSK:   .BYTE $FB
DS:     .BYTE $FF
        .BYTE $FD
DS2:    .BYTE $FF
BND:    .BYTE $00
BNDH:   .BYTE $FE       ; crosshair limits: X lo, X hi, Y lo, Y hi
        .BYTE $58,$AD

CURX:   .BYTE $7E
CURY:   .BYTE $81
XPOS:   .BYTE $AB
XMSB:   .BYTE 0
G1X:    .BYTE $20
G2X:    .BYTE $1F
G1Y:    .BYTE $CF
G2Y:    .BYTE $CF
JOY:    .BYTE $FF
JRAW:   .BYTE $FF
MPRES:  .BYTE 0
MDX:    .BYTE 0
MDY:    .BYTE 0
OLDX:   .BYTE 0
OLDY:   .BYTE 0
OLDV:   .BYTE 0
CD:     .BYTE 0
DTIMER: .BYTE DDLY
FCNT:   .BYTE 0
TRACK:  .BYTE 0
TON:    .BYTE 0         ; tracking asked for ($62)
TRUN:   .BYTE 0         ; the tracking loop runs ($64)
TSLIM:  .BYTE 0
HUDBRD: .BYTE $0E       ; the upper HUD's border ($0CCC)
SNDON:  .BYTE 0         ; a voice 1 sweep plays ($F8)
SNDCNT: .BYTE 0         ; ($08E5)
SNDRATE:.BYTE 0         ; ($08E6)
SNDRLD: .BYTE 0         ; ($08E7)
SNDSTP: .BYTE 0         ; ($08E8)
SNDDIR: .BYTE 0         ; ($08E9)
SNDLO:  .BYTE 0         ; ($08EA)
SNDHI:  .BYTE 0         ; ($08EB)
SNDHI0: .BYTE 0         ; ($08EC)
SNDPI:  .BYTE $16       ; ($0911)
ENGON:  .BYTE 1         ; the engine's noise ($C376)
ENGC:   .BYTE 1         ; ($C377)
RSPD:   .BYTE $41       ; the rush's speed ($F209)
STKX:   .BYTE 0
NT0:    .BYTE 1
RADPEND:.BYTE 0
TPRESS: .BYTE 0         ; A / T pressed ($8C06)
TKPREV: .BYTE 1
TTGT:   .BYTE 0         ; the tracked fighter ($8B48)
TACC:   .BYTE 0,0       ; passes owed (port)
TPC:    .BYTE 0         ; the loop's pass counter ($89)
TCAIM:  .BYTE 1         ; ($89C5)
TCST:   .BYTE 1         ; ($89C6)
TCDR:   .BYTE 1         ; ($89C7)
TCMV:   .BYTE 2         ; ($89C9)
TDX:    .BYTE 0         ; ($89C2-$89C4)
TDY:    .BYTE 0
TDZ:    .BYTE 0
TSX:    .BYTE 0         ; ($D5, $D6)
TSY:    .BYTE 0
TSPEND: .BYTE 0
TLOK:   .BYTE 0
MSGP:   .BYTE 0,0       ; ($9D34)
MSGCOL: .BYTE 0
MSGC1:  .BYTE 1         ; ($9BDF, $9BE0)
MSGC2:  .BYTE 7
MSGTG:  .BYTE 1         ; ($9BE4)
MSGRATE:.BYTE 8         ; ($9BDC)
MSGCD:  .BYTE 8         ; ($9BDD)
MSGN:   .BYTE 0         ; ($9BDE)
MSGON:  .BYTE 0         ; ($9BE3)
MSGMODE:.BYTE $80       ; ($9BE2)
MSGFINE:.BYTE 0         ; ($13D4)
FINEX:  .BYTE 5         ; ($13D3)
STRIPX: .BYTE 5         ; ($0A4A)
TRFRAME:.BYTE $31
TPREV:  .BYTE 1
SEED:   .BYTE $80
POSX:   .BYTE 0
POSY:   .BYTE 0
SAVEX:  .BYTE 0
WLN:    .BYTE 0
OVRUN:  .BYTE 0
JOYG:   .BYTE $FF
FRMC:   .BYTE 0
ADX:    .BYTE 0
ADY:    .BYTE 0
DIRX:   .BYTE 0
DIRY:   .BYTE 0
NTICK:  .BYTE 0
SHX:    .BYTE 0
SHY:    .BYTE 0
TMPS:   .BYTE 0
STARX:  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
STARY:  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
STARV:  .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
SAVMMU: .BYTE 0
SAVPTRL:.BYTE 0
SAVPTRH:.BYTE 0
SAVPA:  .BYTE 0
SAVC2:  .BYTE 0
SAV11:  .BYTE 0
SAV16:  .BYTE 0
SAV18:  .BYTE 0
SAVENA: .BYTE 0
SAVBOR: .BYTE 0
SAVBG:  .BYTE 0
SAVFAST:.BYTE 0
SAV1B:  .BYTE 0
SAV1D:  .BYTE 0
; the phasor shot (original addresses in brackets)
FIREFLAG:.BYTE 0        ; set by pressing fire, cleared at the end of a shot ($D0)
SHOTARM:.BYTE 0         ; armed, launch on the next pass ($D1)
SHOTON: .BYTE 0         ; a shot is in flight ($D2)
SHOTVIS:.BYTE 0         ; sprite 1 on ($98 bit 1)
SHOTSHP:.BYTE $70       ; shape, original numbering $70-$67 ($B1)
SHOTX:  .BYTE 0         ; sprite 1 x, low 8 bits ($E9)
SHOTXH: .BYTE 0         ; x bit 8 ($F7 bit 1)
SHOTY:  .BYTE 0         ; ($EA)
SHIDX:  .BYTE 0         ; position on the path ($1416)
NPTS:   .BYTE 0         ; points on the path ($1415)
NGEN:   .BYTE 0         ; points made so far (port only)
LGY:    .BYTE 0         ; line step counter between LINEGEN calls (port only)
LGN:    .BYTE 0
RATE:   .BYTE 0         ; ($141C)
FRAC:   .BYTE 0         ; ($141B, never reset)
SHPRATE:.BYTE 3         ; ($1412)
SHPCNT: .BYTE 3         ; ($1411)
STEPLEN:.BYTE 4         ; ($1414)
STEPCNT:.BYTE 4         ; ($1413)
SUBN:   .BYTE 0         ; ($1419)
GUNSEL: .BYTE 2         ; ($1417)
SHOTGUN:.BYTE 0         ; 1 = left gun, $FF = right ($1418)
HITWIN: .BYTE 0         ; points left when under 10 ($3370 / $1616)
SHOTS:  .BYTE 0,0       ; ($F43B)
SF1:    .BYTE 0         ; sound ($81-$83)
SF2:    .BYTE 0
SF3:    .BYTE 0
L36:    .BYTE 0         ; line routine ($36-$5A), pairs must stay together
L37:    .BYTE 0
L4E:    .BYTE 0
L4F:    .BYTE 0
L50:    .BYTE 0
L51:    .BYTE 0
L52:    .BYTE 0
L53:    .BYTE 0
L59:    .BYTE 0
L5A:    .BYTE 0


; =================== the fight, part 2 of the code ===================
        * = $8500

; ---------------- the fighters: one type-1 wave ----------------
; Ported from the original (C64 addresses in brackets); PLAN-C128-COCKPIT.md
; "How a fight runs". Three fighters, x ENX, y ENY, depth ENZ (16 bit each,
; indexed 0, 2, 4 like the original's $16 / $1C / $22,X). Each flies its movement
; stream (one step per frame; the original's main loop runs it every 16 passes,
; about once a frame), drifts back toward the middle every other frame, and is
; turned into sprite 4-6 every 4th frame. Steering turns them around the ship.
; Not yet: the hit test, enemy fire, the approach phase.

NEWWAVE:LDA #$01        ; type 1
        STA ETYPE
        JSR WAVEINIT
        LDA ETYPE       ; all three alive: the flags get the type ($C7B9), after
        STA ALIVE       ; WAVEINIT, which clears them
        STA ALIVE+1
        STA ALIVE+2
        STA EHITS       ; shots each one takes: the type ($C7B9)
        STA EHITS+1
        STA EHITS+2
nw1:    LDA #$01        ; a step on the next call
        STA SCNT
        STA SCNT+1
        STA SCNT+2
        LDA #$07        ; ($FFAF) colours: yellow, light green, white
        STA $D02B
        LDA #$0D
        STA $D02C
        LDA #$01
        STA $D02D
        LDA #$00
        STA EVIS
        RTS

WAVEINIT:               ; ($FF1B, the type-1 path)
        LDA #$00
        STA ALIVE
        STA ALIVE+1
        STA ALIVE+2
        LDX #$05
wi1:    STA ENX,X
        STA ENY,X
        STA ENZ,X
        STA SPX,X
        STA SPY,X
        STA SPZ,X
        DEX
        BPL wi1
        LDY #$02        ; pages left of each stream
        STY SPG
        STY SPG+1
        DEY
        STY SPG+2
        LDY #>STREAMS   ; x stream (original page $E8, table $FF15)
        STY SBASE
        STY SPX+1
        STY SPX+3
        INY
        STY SPX+5
        LDY #$82        ; y stream, STREAMS page + 2 ($EA, table $FF18)
        STY SBASE+1
        STY SPY+1
        STY SPY+3
        INY
        STY SPY+5
        LDY #$83        ; depth stream, STREAMS page + 3 ($EB)
        STY SBASE+2
        STY SPZ+1
        STY SPZ+3
        INY
        STY SPZ+5
        STA SIDX        ; A = 0
        STA ENZ+4
        LDA #$AA
        STA SIDX+1
        LDA #$54
        STA SIDX+2
        LDA #$88
        STA ENX+1
        STA ENX+3
        STA ENX+5
        STA ENY+1
        STA ENY+3
        STA ENY+5
        LDA #$8B
        STA ENZ+1
        STA ENZ+3
        STA ENZ+5
        LDA #$8C
        STA ENX
        LDA #$50
        STA ENX+2
        LDA #$AF
        STA ENX+4
        LDA #$80
        STA ENY
        LDA #$8C
        STA ENY+2
        LDA #$64
        STA ENY+4
        LDA #$14
        STA ENZ
        LDA #$28
        STA ENZ+2
        RTS

; One frame of the fight (vertical blank).
FIGHT:  JSR SNDTICK     ; ($09AC) the sweep sounds, the HUD's border
        JSR ENGTICK     ; ($C379) the engine
        JSR MSGFRAME    ; ($13D5) the message row
        INC EFRM
        LDA APPR        ; approaching a group: the long range scanner ($C6A9)
        BEQ fgdog
        JSR APFRAME
        JMP fgcom
fgdog:  LDA TRUN        ; (tracking: streams and drift run in its passes)
        BEQ fgd1
        JSR TRKSLOT
        JMP fg1
fgd1:
        LDX #$00
        JSR MOVEN
        LDX #$02
        JSR MOVEN
        LDX #$04
        JSR MOVEN
        LDA EFRM
        AND #$01
        BEQ fg1
        JSR EDRIFT
fg1:    LDA EFRM
        AND #$03
        BNE fg2
        LDX #$00
        JSR PLACE
        LDX #$02
        JSR PLACE
        LDX #$04
        JSR PLACE
fg2:    JSR SHOTHIT     ; the original tests the shot once a frame ($3244)
fgcom:  JSR EXPTICK
        JSR EXPTICK2
        LDA EFRM        ; the hit flash, every other frame ($0C90)
        AND #$01
        BNE fg3
        JSR FLASH
fg3:    LDA APPR        ; the number under the crosshair: every 4th frame in a
        BNE fg5         ; fight ($2D8F; every frame while approaching, APFRAME),
        LDA EFRM        ; when the slot has time for it (else the next frame)
        AND #$03
        BNE fg4
        INC NUMPEND
fg4:    LDA NUMPEND
        BEQ fg5
        LDA $D012
        CMP #214
        BCS fg5
        LDA #$00
        STA NUMPEND
        JMP NUMBER
fg5:    RTS

; A fighter takes a step of its stream ($2F6D, $2FB9, $3005: one copy per
; fighter in the original). X = fighter * 2.
MOVEN:  STX MX
        TXA
        LSR A
        TAY
        LDA ALIVE,Y
        BNE mv1
        RTS
mv1:    LDA SIDX,Y
        STA MIDX
        LDA SPX,X       ; x step
        STA PTR
        LDA SPX+1,X
        STA PTR+1
        LDY MIDX
        LDA (PTR),Y
        JSR ADDX
        LDA SPY,X       ; y step
        STA PTR
        LDA SPY+1,X
        STA PTR+1
        LDA (PTR),Y
        JSR ADDY
        LDA SPZ,X       ; depth step
        STA PTR
        LDA SPZ+1,X
        STA PTR+1
        LDA (PTR),Y
        JSR ADDZ
        LDA MX
        LSR A
        TAX
        DEC SCNT,X      ; type 1: a step every call ($2F8B)
        BEQ mv2
mvret:  RTS
mv2:    LDY ETYPE
        CPY #$01
        BEQ mv3
        DEY
mv3:    TYA
        STA SCNT,X
        INC SIDX,X
        BNE mvret
        LDX MX          ; the next page of the streams
        INC SPX+1,X
        INC SPY+1,X
        INC SPZ+1,X
        LDA MX
        LSR A
        TAX
        DEC SPG,X
        BNE mvret
        LDX MX          ; the end: back to the start of the streams
        LDA SBASE
        STA SPX+1,X
        LDA SBASE+1
        STA SPY+1,X
        LDA SBASE+2
        STA SPZ+1,X
        LDA MX
        LSR A
        TAX
        LDA #$02
        STA SPG,X
        RTS


; Steering ($39C1): the joystick byte (JOY, with the mouse patch's steering mask:
; directions held while the crosshair is off centre) rotates every fighter
; around the ship: up / down turn y and depth around y $8832, left / right turn
; x and depth around x $88A0, by shifts of the offsets (a rotation in small
; steps). Translated instruction for instruction from the original's
; disassembly (each line keeps its address); the original first returns when the
; ship's sector holds no squadron. Its checks of APPR, INFRONT and LRDIG ($E3:
; the approach phase, $C847: the chosen group is in front, $372C-$372F: the long
; range scanner's side and up digits) belong to the approach, not ported yet: 0.
STEER:
         LDA JOY    ; $39CE
         STA SJ1    ; $39D0
         STA SJ2    ; $39D3
         LDX #$00    ; $39D6
         LDY #$02    ; $39D8
st39DA:  LDA APPR    ; $39DA
         BEQ st39FA    ; $39DC
         LDA INFRONT    ; $39DE
         BEQ st39FA    ; $39E1
         LDA LRDIG+2    ; $39E3
         CMP #$70    ; $39E6
         BNE st39FA    ; $39E8
         LDA LRDIG+3    ; $39EA
         CMP #$70    ; $39ED
         BNE st39FA    ; $39EF
         LSR SJ1    ; $39F1
         LSR SJ1    ; $39F4
         JMP st3B25    ; $39F7
st39FA:  LSR SJ1    ; $39FA
         BCC st3A02    ; $39FD
         JMP st3A8E    ; $39FF
st3A02:  SEC    ; $3A02
         LDA #$32    ; $3A03
         SBC ENY,X    ; $3A05
         LDA #$88    ; $3A07
         SBC ENY+1,X    ; $3A09
         BCC st3A30    ; $3A0B
         SEC    ; $3A0D
         LDA #$32    ; $3A0E
         SBC ENY,X    ; $3A10
         STA T2B    ; $3A12
         LDA #$88    ; $3A14
         SBC ENY+1,X    ; $3A16
         ASL T2B    ; $3A18
         ROL A    ; $3A1A
         ASL T2B    ; $3A1B
         ROL A    ; $3A1D
         STA T2C    ; $3A1E
         SEC    ; $3A20
         LDA ENZ,X    ; $3A21
         SBC T2C    ; $3A23
         STA T2B    ; $3A25
         LDA ENZ+1,X    ; $3A27
         SBC #$00    ; $3A29
         STA T2C    ; $3A2B
         JMP st3A4B    ; $3A2D
st3A30:  SEC    ; $3A30
         LDA ENY,X    ; $3A31
         SBC #$32    ; $3A33
         STA T2B    ; $3A35
         LDA ENY+1,X    ; $3A37
         SBC #$88    ; $3A39
         ASL T2B    ; $3A3B
         ROL A    ; $3A3D
         ASL T2B    ; $3A3E
         ROL A    ; $3A40
         ADC ENZ,X    ; $3A41
         STA T2B    ; $3A43
         LDA ENZ+1,X    ; $3A45
         ADC #$00    ; $3A47
         STA T2C    ; $3A49
st3A4B:  LDA ENZ+1,X    ; $3A4B
         CMP #$86    ; $3A4D
         BCS st3A6E    ; $3A4F
         SEC    ; $3A51
         LDA #$00    ; $3A52
         SBC ENZ,X    ; $3A54
         STA T2D    ; $3A56
         LDA #$86    ; $3A58
         SBC ENZ+1,X    ; $3A5A
         ASL T2D    ; $3A5C
         ROL A    ; $3A5E
         ASL T2D    ; $3A5F
         ROL A    ; $3A61
         CLC    ; $3A62
         ADC ENY,X    ; $3A63
         STA ENY,X    ; $3A65
         BCC st3A6B    ; $3A67
         INC ENY+1,X    ; $3A69
st3A6B:  JMP st3A86    ; $3A6B
st3A6E:  SEC    ; $3A6E
         LDA ENZ,X    ; $3A6F
         SBC #$00    ; $3A71
         STA T2D    ; $3A73
         LDA ENZ+1,X    ; $3A75
         SBC #$86    ; $3A77
         STA T2E    ; $3A79
         SEC    ; $3A7B
         LDA ENY,X    ; $3A7C
         SBC T2E    ; $3A7E
         STA ENY,X    ; $3A80
         BCS st3A86    ; $3A82
         DEC ENY+1,X    ; $3A84
st3A86:  LDA T2B    ; $3A86
         STA ENZ,X    ; $3A88
         LDA T2C    ; $3A8A
         STA ENZ+1,X    ; $3A8C
st3A8E:  LSR SJ1    ; $3A8E
         BCC st3A96    ; $3A91
         JMP st3B25    ; $3A93
st3A96:  SEC    ; $3A96
         LDA #$32    ; $3A97
         SBC ENY,X    ; $3A99
         LDA #$88    ; $3A9B
         SBC ENY+1,X    ; $3A9D
         BCC st3AC0    ; $3A9F
         SEC    ; $3AA1
         LDA #$32    ; $3AA2
         SBC ENY,X    ; $3AA4
         STA T2B    ; $3AA6
         LDA #$88    ; $3AA8
         SBC ENY+1,X    ; $3AAA
         ASL T2B    ; $3AAC
         ROL A    ; $3AAE
         ASL T2B    ; $3AAF
         ROL A    ; $3AB1
         CLC    ; $3AB2
         ADC ENZ,X    ; $3AB3
         STA T2B    ; $3AB5
         LDA ENZ+1,X    ; $3AB7
         ADC #$00    ; $3AB9
         STA T2C    ; $3ABB
         JMP st3AE0    ; $3ABD
st3AC0:  SEC    ; $3AC0
         LDA ENY,X    ; $3AC1
         SBC #$32    ; $3AC3
         STA T2B    ; $3AC5
         LDA ENY+1,X    ; $3AC7
         SBC #$88    ; $3AC9
         ASL T2B    ; $3ACB
         ROL A    ; $3ACD
         ASL T2B    ; $3ACE
         ROL A    ; $3AD0
         STA T2C    ; $3AD1
         SEC    ; $3AD3
         LDA ENZ,X    ; $3AD4
         SBC T2C    ; $3AD6
         STA T2B    ; $3AD8
         LDA ENZ+1,X    ; $3ADA
         SBC #$00    ; $3ADC
         STA T2C    ; $3ADE
st3AE0:  LDA ENZ+1,X    ; $3AE0
         CMP #$86    ; $3AE2
         BCS st3B07    ; $3AE4
         SEC    ; $3AE6
         LDA #$00    ; $3AE7
         SBC ENZ,X    ; $3AE9
         STA T2D    ; $3AEB
         LDA #$86    ; $3AED
         SBC ENZ+1,X    ; $3AEF
         ASL T2D    ; $3AF1
         ROL A    ; $3AF3
         ASL T2D    ; $3AF4
         ROL A    ; $3AF6
         STA T2E    ; $3AF7
         SEC    ; $3AF9
         LDA ENY,X    ; $3AFA
         SBC T2E    ; $3AFC
         STA ENY,X    ; $3AFE
         BCS st3B04    ; $3B00
         DEC ENY+1,X    ; $3B02
st3B04:  JMP st3B1D    ; $3B04
st3B07:  SEC    ; $3B07
         LDA ENZ,X    ; $3B08
         SBC #$00    ; $3B0A
         STA T2D    ; $3B0C
         LDA ENZ+1,X    ; $3B0E
         SBC #$86    ; $3B10
         STA T2D    ; $3B12
         CLC    ; $3B14
         ADC ENY,X    ; $3B15
         STA ENY,X    ; $3B17
         BCC st3B1D    ; $3B19
         INC ENY+1,X    ; $3B1B
st3B1D:  LDA T2B    ; $3B1D
         STA ENZ,X    ; $3B1F
         LDA T2C    ; $3B21
         STA ENZ+1,X    ; $3B23
st3B25:  LDA APPR    ; $3B25
         BEQ st3B3F    ; $3B27
         LDA INFRONT    ; $3B29
         BEQ st3B3F    ; $3B2C
         LDA LRDIG    ; $3B2E
         CMP #$70    ; $3B31
         BNE st3B3F    ; $3B33
         LDA LRDIG+1    ; $3B35
         CMP #$70    ; $3B38
         BNE st3B3F    ; $3B3A
         JMP st3C75    ; $3B3C
st3B3F:  LSR SJ1    ; $3B3F
         BCC st3B47    ; $3B42
         JMP st3BDA    ; $3B44
st3B47:  SEC    ; $3B47
         LDA #$A0    ; $3B48
         SBC ENX,X    ; $3B4A
         LDA #$88    ; $3B4C
         SBC ENX+1,X    ; $3B4E
         BCC st3B71    ; $3B50
         SEC    ; $3B52
         LDA #$A0    ; $3B53
         SBC ENX,X    ; $3B55
         STA T2B    ; $3B57
         LDA #$88    ; $3B59
         SBC ENX+1,X    ; $3B5B
         ASL T2B    ; $3B5D
         ROL A    ; $3B5F
         ASL T2B    ; $3B60
         ROL A    ; $3B62
         CLC    ; $3B63
         ADC ENZ,X    ; $3B64
         STA T2B    ; $3B66
         LDA ENZ+1,X    ; $3B68
         ADC #$00    ; $3B6A
         STA T2C    ; $3B6C
         JMP st3B91    ; $3B6E
st3B71:  SEC    ; $3B71
         LDA ENX,X    ; $3B72
         SBC #$A0    ; $3B74
         STA T2B    ; $3B76
         LDA ENX+1,X    ; $3B78
         SBC #$88    ; $3B7A
         ASL T2B    ; $3B7C
         ROL A    ; $3B7E
         ASL T2B    ; $3B7F
         ROL A    ; $3B81
         STA T2C    ; $3B82
         SEC    ; $3B84
         LDA ENZ,X    ; $3B85
         SBC T2C    ; $3B87
         STA T2B    ; $3B89
         LDA ENZ+1,X    ; $3B8B
         SBC #$00    ; $3B8D
         STA T2C    ; $3B8F
st3B91:  LDA ENZ+1,X    ; $3B91
         CMP #$86    ; $3B93
         BCS st3BB8    ; $3B95
         SEC    ; $3B97
         LDA #$00    ; $3B98
         SBC ENZ,X    ; $3B9A
         STA T2D    ; $3B9C
         LDA #$86    ; $3B9E
         SBC ENZ+1,X    ; $3BA0
         ASL T2D    ; $3BA2
         ROL A    ; $3BA4
         ASL T2D    ; $3BA5
         ROL A    ; $3BA7
         STA T2E    ; $3BA8
         SEC    ; $3BAA
         LDA ENX,X    ; $3BAB
         SBC T2E    ; $3BAD
         STA ENX,X    ; $3BAF
         BCS st3BB5    ; $3BB1
         DEC ENX+1,X    ; $3BB3
st3BB5:  JMP st3BD2    ; $3BB5
st3BB8:  SEC    ; $3BB8
         LDA ENZ,X    ; $3BB9
         SBC #$00    ; $3BBB
         STA T2D    ; $3BBD
         LDA ENZ+1,X    ; $3BBF
         SBC #$86    ; $3BC1
         ASL T2D    ; $3BC3
         ROL A    ; $3BC5
         ASL T2D    ; $3BC6
         ROL A    ; $3BC8
         CLC    ; $3BC9
         ADC ENX,X    ; $3BCA
         STA ENX,X    ; $3BCC
         BCC st3BD2    ; $3BCE
         INC ENX+1,X    ; $3BD0
st3BD2:  LDA T2B    ; $3BD2
         STA ENZ,X    ; $3BD4
         LDA T2C    ; $3BD6
         STA ENZ+1,X    ; $3BD8
st3BDA:  LSR SJ1    ; $3BDA
         BCC st3BE2    ; $3BDD
         JMP st3C75    ; $3BDF
st3BE2:  SEC    ; $3BE2
         LDA #$A0    ; $3BE3
         SBC ENX,X    ; $3BE5
         LDA #$88    ; $3BE7
         SBC ENX+1,X    ; $3BE9
         BCC st3C10    ; $3BEB
         SEC    ; $3BED
         LDA #$A0    ; $3BEE
         SBC ENX,X    ; $3BF0
         STA T2B    ; $3BF2
         LDA #$88    ; $3BF4
         SBC ENX+1,X    ; $3BF6
         ASL T2B    ; $3BF8
         ROL A    ; $3BFA
         ASL T2B    ; $3BFB
         ROL A    ; $3BFD
         STA T2C    ; $3BFE
         SEC    ; $3C00
         LDA ENZ,X    ; $3C01
         SBC T2C    ; $3C03
         STA T2B    ; $3C05
         LDA ENZ+1,X    ; $3C07
         SBC #$00    ; $3C09
         STA T2C    ; $3C0B
         JMP st3C2C    ; $3C0D
st3C10:  SEC    ; $3C10
         LDA ENX,X    ; $3C11
         SBC #$A0    ; $3C13
         STA T2B    ; $3C15
         LDA ENX+1,X    ; $3C17
         SBC #$88    ; $3C19
         ASL T2B    ; $3C1B
         ROL A    ; $3C1D
         ASL T2B    ; $3C1E
         ROL A    ; $3C20
         CLC    ; $3C21
         ADC ENZ,X    ; $3C22
         STA T2B    ; $3C24
         LDA ENZ+1,X    ; $3C26
         ADC #$00    ; $3C28
         STA T2C    ; $3C2A
st3C2C:  LDA ENZ+1,X    ; $3C2C
         CMP #$86    ; $3C2E
         BCS st3C4F    ; $3C30
         SEC    ; $3C32
         LDA #$00    ; $3C33
         SBC ENZ,X    ; $3C35
         STA T2D    ; $3C37
         LDA #$86    ; $3C39
         SBC ENZ+1,X    ; $3C3B
         ASL T2D    ; $3C3D
         ROL A    ; $3C3F
         ASL T2D    ; $3C40
         ROL A    ; $3C42
         CLC    ; $3C43
         ADC ENX,X    ; $3C44
         STA ENX,X    ; $3C46
         BCC st3C4C    ; $3C48
         INC ENX+1,X    ; $3C4A
st3C4C:  JMP st3C6D    ; $3C4C
st3C4F:  SEC    ; $3C4F
         LDA ENZ,X    ; $3C50
         SBC #$00    ; $3C52
         STA T2D    ; $3C54
         LDA ENZ+1,X    ; $3C56
         SBC #$86    ; $3C58
         ASL T2D    ; $3C5A
         ROL A    ; $3C5C
         ASL T2D    ; $3C5D
         ROL A    ; $3C5F
         STA T2E    ; $3C60
         SEC    ; $3C62
         LDA ENX,X    ; $3C63
         SBC T2E    ; $3C65
         STA ENX,X    ; $3C67
         BCS st3C6D    ; $3C69
         DEC ENX+1,X    ; $3C6B
st3C6D:  LDA T2B    ; $3C6D
         STA ENZ,X    ; $3C6F
         LDA T2C    ; $3C71
         STA ENZ+1,X    ; $3C73
st3C75:  LDA SJ2    ; $3C75
         STA SJ1    ; $3C78
         INX    ; $3C7B
         INX    ; $3C7C
         DEY    ; $3C7D
         BMI st3C83    ; $3C7E
         JMP st39DA    ; $3C80
st3C83:  RTS    ; $3C83


; ---------------- enemy fire and the ship being hit ----------------
; Enemy fire ($C947). The original calls it once per main loop pass (about 16 a
; frame in a fight); every 3rd call (2nd from difficulty 3) it does something.
; The fighters take turns: when the delay runs out (by difficulty: 255, 176, 112,
; 64, 16 of those calls) the fighter whose turn it is fires if it is shown at
; x $44-$FF, y $6C-$B3; else the next one tries at once. The shot is sprite 2
; (single colour, doubled, its colour cycling), shapes $67 up to $70 (the phasor's
; shapes backwards), a new shape every 12, 11, ... 1 calls, moving away from the
; middle of the view. At $70 it has reached the ship: if it is still shown the
; ship is hit ($84D7), the view flashes and 12 points burst where it was.
EFRAME: LDA #EFPASS
        STA EFCNT
efr1:   JSR EFIRE
        DEC EFCNT
        BNE efr1
        RTS

EFIRE:  DEC EFTHR       ; ($C94D)
        BEQ ef0
        RTS
ef0:    LDX DIFF
        LDA EFTHRT,X    ; ($C918)
        STA EFTHR
        LDX EFI
        LDY EFY2
        LDA EFON
        BEQ ef2
        JMP efm
ef2:    DEC EFDLY       ; ($C973)
        BEQ ef3
        RTS
ef3:    LDX DIFF
        LDA EFDLYT,X    ; ($C913)
        STA EFDLY
        LDA EVIS        ; ($C981)
        AND EFBIT
        BEQ ef4
        LDA EMSB
        AND EFBIT
        BNE ef4
        LDA ESH,Y
        CMP #$44
        BCC ef4
        LDA ESH+1,Y
        CMP #$6C
        BCC ef4
        CMP #$B4
        BCC ef5
ef4:    LDA #$01        ; not now: the next fighter tries at the next call
        STA EFDLY
        JMP EFEND
ef5:    LDA #$01        ; ($C9A9) fire
        STA EFON
        LDA $D01C       ; sprite 2: single colour, doubled both ways
        AND #$FB
        STA $D01C
        LDA $D01D
        ORA #$04
        STA $D01D
        LDA $D017
        ORA #$04
        STA $D017
        LDA ESH,Y       ; at the fighter (type 1: 12 pixels left of it)
        LDX ETYPE
        CPX #$01
        BNE ef6
        SEC
        SBC #$0C
ef6:    STA EFX
        LDA ESH+1,Y
        STA EFY
        LDA #$00
        STA EFMSB
        STA EFVX        ; ($CA13, $CA35: steps are worked out from the fighter's
        STA EFVY        ; streams, then dropped: both start at 0)
        LDA #$04
        STA EFVIS
        LDA #$67
        STA EFSHP
        LDA #$0D
        STA EFE
        STA EFD
        JSR EFSND       ; ($C413)
efm:    DEC EFE         ; ($CA56)
        BNE efm3
        DEC EFD
        BNE efm1
        INC EFD
efm1:   LDA EFD
        STA EFE
        TAY
        LDA EFTAB,Y     ; ($C91D)
        CMP #$70
        BNE efm2
        LDA EFVIS       ; ($CA71) full size: it reaches the ship
        BEQ efm9
        STA HITFL       ; ($DD) the flash
        JSR SHIPHIT     ; ($84D7)
        LDA EXPL2       ; ($CA80) 12 points burst where it was
        BNE efm9
        LDA EFVX
        ASL A
        STA EVX02
        LDA EFVY
        ASL A
        STA EVY02
        LDA #$01
        STA EXPL2
        LDA #$00
        STA EXPB2
        CLC
        LDA EFMSB
        BEQ efm4
        SEC
efm4:   LDA EFX
        ROR A
        SEC
        SBC #$06
        STA EXPX2
        CMP #$0A
        BCC efm5
        CMP #$91
        BCC efm6
efm5:   LDA #$00
        STA EXPL2
efm6:   LDA EFY
        SEC
        SBC #$32
        STA EXPY2
        CMP #$0A
        BCC efm7
        CMP #$B4
        BCC efm9
efm7:   LDA #$00
        STA EXPL2
efm9:   JMP EFEND
efm2:   STA EFSHP       ; ($CAD6)
efm3:   INC $D029       ; ($CAD8) the colour cycles
        JSR EFSTEPX
        JSR EFSTEPY
        LDA EFVX        ; ($CAE1)
        BMI efx2
        CLC
        ADC EFX
        STA EFX
        BCS efx1
        LDA EFMSB
        BEQ efy
        LDA EFX
        CMP #$2F
        BCC efy
        JMP EFEND       ; off the right edge
efx1:   LDA #$04
        STA EFMSB
        JMP efy
efx2:   AND #$7F
        SEC
        STA ATMP2
        LDA EFX
        SBC ATMP2
        STA EFX
        BCS efy
        LDA EFMSB
        BNE efx3
        JMP EFEND       ; off the left edge
efx3:   LDA #$00
        STA EFMSB
efy:    LDA EFVY        ; ($CB21)
        BMI efy2
        CLC
        ADC EFY
        STA EFY
        CMP #$F0
        BCS efy3
        RTS
efy2:   AND #$7F
        STA ATMP2
        LDA EFY
        SEC
        SBC ATMP2
        STA EFY
        CMP #$59
        BCC efy3
        RTS
efy3:   JMP EFEND       ; off the top or the bottom

EFEND:  LDA #$00        ; ($CB45) the shot is gone, the next fighter's turn
        STA EFVIS
        STA EFON
        CLC
        ROL EFBIT
        INC EFY2
        INC EFY2
        INC EFI
        LDX EFI
        CPX #$03
        BNE efe1
        JSR EFRESET
efe1:   RTS

EFRESET:LDA #$10        ; ($C92F)
        STA EFBIT
        LDX #$00
        STX EFI
        STX EFY2
        LDA #$01
        STA EFTHR
        RTS

; A step of 1 away from the middle ($CB6C, $CBAA; bit 7 = minus, $80 = none).
; (The original first tests its MSB shadow against zero page $04 instead of #$04,
; a stream pointer's low byte, always 0: so the step is always worked out.)
EFSTEPX:LDA EFX
        CMP #$7C
        BCS esx1
        LDA #$81
        BNE esx9
esx1:   CMP #$98
        BCS esx2
        LDA #$80
        BNE esx9
esx2:   CMP #$D0
        BCS esx3
        LDA #$00
        BEQ esx9
esx3:   LDA #$01
esx9:   STA EFVX
        RTS
EFSTEPY:LDA EFY
        CMP #$61
        BCS esy1
        LDA #$81
        BNE esy9
esy1:   CMP #$71
        BCS esy2
        LDA #$80
        BNE esy9
esy2:   CMP #$A1
        BCS esy3
        LDA #$00
        BEQ esy9
esy3:   LDA #$01
esy9:   STA EFVY
        RTS

EFSND:  LDA #$00        ; ($C413) voice 2: the enemy shot
        STA $D40B
        STA $D40D
        LDA #$39
        STA $D40C
        LDA #$03
        STA $D408
        LDA #$81
        STA $D40B
        RTS

; The ship (SHIP-STATUS.md; the same model as the map program's SHIPINIT /
; SHIPHIT). A hit ($84D7, $85D9): a random working system loses a point, then
; one shield point; below 0 the ship is lost.
SHIPINIT:
        LDY DIFF
        LDX #$00
si1:    LDA HPTAB,Y
        STA SYSHP,X
        TYA
        CLC
        ADC #$05
        TAY
        INX
        CPX #$07
        BNE si1
        LDA #$FF        ; the communications module
        STA SYSHP+7
        LDX DIFF
        LDA SHTAB,X
        STA SHLD
        LDA #$00
        STA SHIPLOST
        STA HITS
        STA HITS+1
        JMP SHOWSH

SHIPHIT:LDY #$00        ; up to 256 tries, then no system is damaged
shp1:   JSR RANDOM
        AND #$07
        TAX
        DEY
        BEQ shp3
        LDA SYSHP,X
        BEQ shp1
        DEC SYSHP,X
        BNE shp3
        STX SYSLAST     ; destroyed (the original prints its message here, $84F2)
shp3:   INC HITS        ; ($85D9)
        BNE shp4
        INC HITS+1
shp4:   DEC SHLD
        LDA SHLD
        CMP #$FF
        BNE SHOWSH
        STA SHIPLOST    ; ($8300) the ship is lost
        INC SHLD
SHOWSH: LDA SHLD        ; ($8487) two digits on the HUD
        LDX #$70
ssh1:   CMP #10
        BCC ssh2
        SBC #10
        INX
        BNE ssh1
ssh2:   STX HUDS
        ORA #$70
        STA HUDS+1
        RTS

HPTAB:  .BYTE 255,10,5,5,5      ; ($8427-$8445) hit points by difficulty
        .BYTE 255,10,6,4,4
        .BYTE 4,3,2,2,2
        .BYTE 6,4,4,4,4
        .BYTE 3,3,3,3,3
        .BYTE 4,4,4,4,4
        .BYTE 2,2,2,2,2
SHTAB:  .BYTE 40,30,25,25,25    ; ($844A) shields
EFDLYT: .BYTE $FF,$B0,$70,$40,$10       ; ($C913) calls between shots
EFTHRT: .BYTE $03,$03,$03,$02,$02       ; ($C918) passes per call
EFTAB:  .BYTE $70,$70,$6F,$6F,$6E,$6D,$6D,$6C,$6B,$6B,$6A,$69,$68,$68 ; ($C91D)

; Our shot hits the enemy shot ($3287, X = 0): it bursts like a shot that
; reached the ship (12 points), the view flashes white / green ($1318), and the
; shot, still growing unseen, does no harm when it arrives (it is not shown).
HITSHOT:LDA EXPL2       ; ($3287) one such burst at a time
        BEQ ht0
        RTS
ht0:    LDA EFVX        ; ($328D-$3299: steps not doubled here)
        STA EVX02
        LDA EFVY
        STA EVY02
        LDA #$00
        STA EXPB2
        LDA #$01
        STA EXPL2
        STA TORPHIT     ; ($323D) the flash's colours
        LDA #$00        ; ($32F2)
        STA HITWIN
        LDA EFY         ; the burst's centre
        SEC
        SBC #$32
        STA EXPY2
        LDA EFX
        SEC
        SBC #$18
        LSR A
        STA EXPX2
        CMP #$06
        BCC ht1
        CMP #$99
        BCC ht2
ht1:    LDA #$00
        STA EXPL2
ht2:    LDA #$00        ; ($3341) the shot and our shot disappear
        STA EFVIS
        STA SHOTVIS
        JMP HITSND

; ---------------- the approach: groups far away, the long range scanner ----------------
; (traced in PLAN-C128-COCKPIT.md, "The approach phase and the long range scanner")
; A squadron of SQCOUNT ships is split into groups of up to 3 (GSIZE), placed far
; away at random (LAYOUT, $3D58). The long range scanner (row 23 of the text
; screen) shows the chosen group's side, up and depth readings (LRSCAN, $3776);
; fire chooses the next group; when it is in front and side and up are both 0-3,
; the ship rushes toward it (CLOSEIN, $C848). Closer than $0400 the group arrives
; (GROUPIN, $C749): up to 3 fighters around its place, the dogfight. When they are
; all down the next group is laid out and approached; the last kill empties the
; sector. The original runs the approach in its own loop ($C6A9), about 16 passes
; a frame; per frame the port steers 4 times, drifts twice, rushes the distance
; of 16 passes at once and checks the arrival every other frame.

ARRIVE: LDA #$00        ; ($FCE1) into a sector with SQCOUNT ships
        STA APPR        ; (no approach until there are ships: an empty sector
        STA GSIZE       ; must not keep the last one's, it blocks the phasor)
        STA GSIZE+1
        STA GSIZE+2
        STA LYACT
        STA EFON
        STA EFVIS
        STA EVIS
        STA BLIPON
        STA ALIVE
        STA ALIVE+1
        STA ALIVE+2
        STA APRUN
        STA LRMODE
        LDA #$01        ; the slots far away until the layout
        LDX #$05
arr1:   STA ENX,X
        STA ENY,X
        STA ENZ,X
        DEX
        DEX
        BPL arr1
        LDA SQCOUNT
        JSR SHOWTG
        LDA SQCOUNT
        BNE arr2
        LDY #39         ; empty: the scanner's row blank
arr3:   LDA #$60
        STA LRROW,Y
        DEY
        BPL arr3
        RTS
arr2:   JSR SECALERT    ; ($FD23) "ALERT  ENTERING GORGANITOR SECTOR", the sound
        LDA #$01
        STA APPR
        STA RELAYOUT    ; (the original keeps the slots where hyperspace left them)
        LDA #$1E        ; ($FCB8) 30 counts of 2 frames before the scanner
        STA APDLY
        JSR LRCLEAR
arr9:   RTS

APFRAME:LDA APRUN
        BNE af1
        LDA EFRM        ; ($C64C, every 32 passes) waiting for the scanner
        AND #$01
        BNE af0
        DEC APDLY
        BNE af0
        LDA #$01        ; ($C677) the long range scanner
        STA LRMODE
        LDA RELAYOUT
        BEQ afl
        LDA #$00
        STA RELAYOUT
        JSR LAYOUT      ; (the groups are placed in the next frames' vertical blank)
        INC APDLY       ; wait for it
        RTS
afl:    LDA LYACT
        BEQ afl2
        INC APDLY
        RTS
afl2:   LDA $D012       ; (the scanner's start takes ~20 lines: not after a
        CMP #206        ; long message step, the next frame then)
        BCC afl5
        INC APDLY
        RTS
afl5:   LDA MSGON       ; ($C6DE) the scanner waits for a standing message;
        BEQ afl3        ; a scrolling one goes
        LDA MSGMODE
        BEQ afl4
        INC APDLY
        RTS
afl4:   JSR MSGSTOP
afl3:   JSR APINIT
        JSR RADMODE     ; ($C67B) long range (LRMODE set above)
        LDA #$01
        STA APRUN
af0:    RTS
af1:    RTS

; The approach loop ($C6A9), pass by pass. Measured in the original (JS machine,
; approach.state): it makes 2.3 to 8, on average about 3.4 passes a frame (it
; draws the star field three times and more in every pass), against 16 in a fight. APACC counts them in 1/256ths;
; APCNT is its pass counter ($89, counted down): steering every 4 passes, the
; scanner's readings and the distance number every 16, enemy fire and closing in
; every pass, the drift every 8, everything 6 closer every 128, the arrival check
; every 32.
APPASSES:
        LDA APRUN
        BEQ app9
        CLC
        LDA APACC
        ADC #$66        ; + 3.4 passes ($0366 / 256)
        STA APACC
        LDA APACC+1
        ADC #$03
        STA APACC+1
app1:   LDA APACC+1
        BEQ app9
        LDA $D012       ; (a pass takes up to ~70 lines: the rest waits for the
        CMP #112        ; next frame)
        BCS app9
        DEC APACC+1
        JSR APPASS
        LDA APRUN       ; (a group arrived: the dogfight)
        BNE app1
app9:   RTS
APPASS: DEC APCNT
        LDA APCNT
        AND #$03
        BNE ap1
        JSR STEER       ; ($C6C6)
ap1:    LDA APCNT
        AND #$0F
        BNE ap2
        JSR LRSCAN      ; ($C6D2, $C6DB)
        JSR NUMBER
ap2:    JSR EFIRE       ; ($C6EB)
        LDA APCNT
        AND #$7F
        BNE ap3
        JSR ZSTEP       ; ($C6F7)
ap3:    LDA APCNT
        AND #$07
        BNE ap4
        SEC
        JSR EDRIFT      ; ($C706)
ap4:    JSR CLOSEIN     ; ($C721)
        LDA APCNT
        AND #$1F
        BNE ap5
        JMP ARRCHK      ; ($C72D-$C746)
ap5:    RTS

ZSTEP:  LDX #$04        ; ($C81E) every slot 6 closer
zs1:    SEC
        LDA ENZ,X
        SBC #$06
        STA ENZ,X
        LDA ENZ+1,X
        SBC #$00
        STA ENZ+1,X
        DEX
        DEX
        BPL zs1
        RTS

; The vertical blank's share (2 MHz, after the star field).
VBWORK: JSR RADSTEP     ; ($9F1C, twice a frame) the scan line and the colour band
        JSR RADSTEP
        JSR CIRCLES
        LDA EFRM        ; the radar: every other frame ($0C8A in the interrupt);
        AND #$01        ; when the star field took long (the rush), the next
        BNE vbr0        ; frame
        INC RADPEND
vbr0:   LDA RADPEND
        BEQ vbr
        LDA $D012
        CMP #251
        BCS vbr1
        CMP #6
        BCS vbr
vbr1:   LDA #$00
        STA RADPEND
        JSR RADAR
vbr:    LDA APPR
        BEQ vbdog
        LDA APRUN
        BEQ vbw1
        RTS
vbw1:   JMP STEER
vbdog:  LDA TRUN        ; the tracking computer's loop instead of the fight loop
        BEQ vbd1
        JMP TRKFRAME
vbd1:   LDA TPRESS      ; ($2D7A) A / T asks for tracking
        BEQ vbd2
        STA TON
        LDA #$00
        STA TPRESS
vbd2:   LDA EFRM        ; ($2D61) looked at every 32 passes (2 frames)
        AND #$01
        BNE vbd3
        JSR TRKCHK
vbd3:   JSR STEER       ; ($2D34) a fight: once a frame, and enemy fire
        JMP EFRAME

LAYOUT: JSR WAVEINIT    ; ($3D58) the groups: slots 0-2, far away
        LDA #$00
        STA GSIZE
        STA GSIZE+1
        STA GSIZE+2
        STA ENZ+1
        STA ENZ+3
        STA ENZ+5
        STA LYY
        LDA SQCOUNT
        BNE ly0
        RTS
ly0:    STA LYN
        LDA #$01        ; LYSTEP places one group a call (a placement can take
        STA LYACT       ; dozens of tries)
        RTS
LYSTEP: LDY LYY
        LDX DIFF
        LDA LYSPR,X
        JSR LYPLACE
        SEC
        LDA LYN
        SBC #$03
        STA LYN
        BMI ly3
        LDA #$03
        STA GSIZE,Y
        INY
        STY LYY
        CPY #$03
        BNE ly4
        JMP ly5
ly3:    CLC
        ADC #$03
        BEQ ly5
        STA GSIZE,Y
ly5:    LDA #$00
        STA LYACT
        LDA DIFF        ; ($C69B) the easy levels: all groups level with the ship
        CMP #$02
        BCS ly4
        LDA #$88
        STA ENY+1
        STA ENY+3
        STA ENY+5
ly4:    RTS

LYPLACE:STA LYMASK      ; ($3DA6) group Y at random, at least $4000 away
        STY LYG
lp1:    LDA LYG
        ASL A
        TAX
        LDY DIFF
        JSR RANDOM      ; (the carry RANDOM leaves goes into the sums, as the
        AND LYMASK      ; original's)
        ADC LYBASE,Y
        STA ENX+1,X
        JSR RANDOM
        AND LYMASK
        ADC LYBASE,Y
        STA ENY+1,X
        JSR RANDOM
        AND LYMASK
        ADC LYBASE,Y
        STA ENZ+1,X
        LDX LYG
        JSR DIST
        LDA DSTH
        CMP #$40
        BCC lp1
        LDY LYG
        RTS

; Distance of slot X ($2C43): |x - $88A0| + |y - $8890| + depth from $8690, in
; DSTL / DSTH; A (and N) = $01 in front, $FF behind (by the depth's high byte).
DIST:   STX DSX
        TXA
        ASL A
        TAX
        SEC
        LDA ENX,X
        SBC #$A0
        STA DSTL
        LDA ENX+1,X
        SBC #$88
        STA DSTH
        BCS ds1
        SEC
        LDA #$A0
        SBC ENX,X
        STA DSTL
        LDA #$88
        SBC ENX+1,X
        STA DSTH
ds1:    SEC
        LDA ENY,X
        SBC #$90
        STA DT0
        LDA ENY+1,X
        SBC #$88
        STA DT1
        BCS ds2
        SEC
        LDA #$90
        SBC ENY,X
        STA DT0
        LDA #$88
        SBC ENY+1,X
        STA DT1
ds2:    JSR DSADD
        LDA ENZ+1,X
        CMP #$86
        BCS ds3
        LDA #$FF
        STA DSIGN
        SEC
        LDA #$90
        SBC ENZ,X
        STA DT0
        LDA #$86
        SBC ENZ+1,X
        STA DT1
        JMP ds4
ds3:    LDA #$01
        STA DSIGN
        SEC
        LDA ENZ,X
        SBC #$90
        STA DT0
        LDA ENZ+1,X
        SBC #$86
        STA DT1
ds4:    JSR DSADD
        LDX DSX
        LDA DSIGN
        RTS
DSADD:  CLC
        LDA DSTL
        ADC DT0
        STA DSTL
        LDA DSTH
        ADC DT1
        STA DSTH
        RTS

APINIT: LDA #$4C        ; ($3736) the blip: shapes $4C-$4E, cyan
        STA BLSHP
        LDA #$03
        STA $D02B
        LDA #$00
        STA GSEL
        STA NUMT
        LDA #$01
        STA BLDIR
        STA BLIPON
        JSR BLIPPOS
        JSR LRCLEAR
        JMP LRSND

BLIPPOS:LDA EVIS        ; ($38E8) sprite 4 on the chosen group's radar mark
        ORA #$10
        STA EVIS
        LDA EMSB
        AND #$EF
        STA EMSB
        LDX GSEL
        LDA RBX,X
        ASL A
        CLC
        ADC #$0F
        STA ESH
        LDA RBY,X
        CLC
        ADC #$29
        STA ESH+1
        RTS

LRCLEAR:LDY #39         ; ($3918) the scanner's row: light green, empty
lc1:    LDA #$0D
        STA COLOR+920,Y
        LDA #$60
        STA LRROW,Y
        DEY
        BPL lc1
        LDA #$01        ; ($3927) X, Y, Z in white
        STA COLOR+929
        STA COLOR+937
        STA COLOR+945
        RTS

LRSND:  LDA #$00        ; ($38D0) voice 1: the scanner's beep
        STA $D404
        STA $D406
        LDA #$32
        STA $D401
        LDA #$09
        STA $D405
        LDA #$21
        STA $D404
        RTS

LRSCAN: LDY SQCOUNT     ; ($37BA) the last group: (ships - 1) / 3
        DEY
        LDX #$00
lr1:    DEY
        DEY
        DEY
        BMI lr2
        INX
        BPL lr1
lr2:    STX GLAST
        JSR BLIPPOS
        LDY BLDIR       ; ($37D6) the blip's shape: $4C, $4D, $4E, $4D, ...
        TYA
        BPL lr3
        CLC
        ADC BLSHP
        CMP #$4D
        BCS lr4
        LDY #$01
        JMP lr4
lr3:    CLC
        ADC BLSHP
        CMP #$4E
        BCC lr4
        LDY #$FF
lr4:    STY BLDIR
        STA BLSHP
        LDA JOY         ; ($3801) fire chooses the group before (needs the long
        AND #$10        ; range scan sequencer, system 6)
        BEQ lr5
        LDA #$00
        STA FLATCH
        JMP lr7
lr5:    LDA FLATCH
        BNE lr7
        INC FLATCH
        LDA SYSHP+6
        BEQ lr7
        LDY GSEL
        DEY
        BPL lr6
        LDY GLAST
lr6:    STY GSEL
        STY NUMT
        JSR LRSND
lr7:    LDA #$7B        ; ($3839) the readings: X (side), Y (up), Z (depth)
        STA LRROW+9
        LDA GSEL
        ASL A
        TAX
        LDA ENX+1,X
        JSR LRVAL
        STY LRROW+11
        LDY #11
        JSR LRDIGS
        STY LRROW+12
        STY LRDIG
        STX LRROW+13
        STX LRDIG+1
        LDA #$7C
        STA LRROW+17
        LDA GSEL
        ASL A
        TAX
        LDA ENY+1,X
        JSR LRVAL
        PHA
        TYA
        EOR #$06        ; (up is the other way round)
        TAY
        PLA
        STY LRROW+19
        LDY #19
        JSR LRDIGS
        STY LRROW+20
        STY LRDIG+2
        STX LRROW+21
        STX LRDIG+3
        LDA #$7D
        STA LRROW+25
        LDA GSEL
        ASL A
        TAX
        LDA ENZ+1,X
        JSR LRVAL
        STY LRROW+27
        LDY #27
        JSR LRDIGS
        STY LRROW+28
        STX LRROW+29
        RTS

LRVAL:  SEC             ; ($389C) A = high byte: size and sign glyph (Y)
        SBC #$08
        BMI lv1
        EOR #$7F
        CLC
        ADC #$01
        LDY #$6D
        RTS
lv1:    AND #$7F
        LDY #$6B
        RTS

LRDIGS: STY LRPOS       ; ($38AE) A = size: 0-99 (LRTAB), two digits Y / X;
        TAY             ; no sign when 0 (LRPOS = the sign's column)
        LDA LRTAB,Y
        JSR BCD
        LDA BCDT
        ORA BCDO
        BNE ld1
        LDY LRPOS
        LDA #$60
        STA LRROW,Y
ld1:    LDA BCDT
        CLC
        ADC #$70
        TAY
        LDA BCDO
        CLC
        ADC #$70
        TAX
        RTS

BCD:    LDX #$00        ; A -> hundreds BCDH, tens BCDT, ones BCDO ($9636)
bc1:    CMP #100
        BCC bc2
        SBC #100
        INX
        BNE bc1
bc2:    STX BCDH
        LDX #$00
bc3:    CMP #10
        BCC bc4
        SBC #10
        INX
        BNE bc3
bc4:    STX BCDT
        STA BCDO
        RTS

CLOSEIN:LDY #$05        ; ($C848) the chosen group in front, side and up 0-3:
        STY HUDBRD      ; the ship rushes toward it. The HUD's border: green,
        LDX GSEL        ; red with the side 0-3, yellow with both
        JSR DIST
        BPL ci1
        LDA #$00
        STA INFRONT
        RTS
ci1:    LDA #$01
        STA INFRONT
        LDA LRDIG
        CMP #$70
        BNE ci9
        LDA LRDIG+1
        CMP #$70
        BCC ci9
        CMP #$74
        BCS ci9
        LDA #$70
        STA LRROW+13
        LDY #$02
        STY HUDBRD
        LDA LRDIG+2
        CMP #$70
        BNE ci9
        LDA LRDIG+3
        CMP #$70
        BCC ci9
        CMP #$74
        BCS ci9
        LDA #$70
        STA LRROW+21
        LDY #$07
        STY HUDBRD
        LDA SNDON       ; ($C898) the rush's sound, unless one plays
        BNE ci3
        JSR SNDRUSH
ci3:    LDX #$04        ; 12 depth steps of 6 ($C89F, $C81E), then a drift ($C8AB)
ci2:    SEC
        LDA ENZ,X
        SBC #$48
        STA ENZ,X
        LDA ENZ+1,X
        SBC #$00
        STA ENZ+1,X
        DEX
        DEX
        BPL ci2
        SEC
        JSR EDRIFT
        LDA RSPD        ; ($C8AE) faster and faster: the engine's pitch and the
        CMP #$08        ; stars follow RSPD / 4
        BCC ci8
        SBC #$06
        STA RSPD
        LSR A
        LSR A
        STA $D40F
ci8:    RTS
ci9:    LDA #$41        ; ($C8CD)
        STA RSPD
        RTS

ARRCHK: LDX #$02        ; ($C730) a group closer than $0400 arrives
ac1:    LDA GSIZE,X
        BEQ ac2
        JSR DIST
        SEC             ; ($2CDE)
        LDA #$00
        SBC DSTL
        LDA #$04
        SBC DSTH
        BCS GROUPIN
ac2:    DEX
        BPL ac1
        RTS

GROUPIN:STX CURG        ; ($C749) the group becomes up to 3 fighters around its
        LDA #$00        ; place
        STA BLIPON
        LDA EVIS
        AND #$EF
        STA EVIS
        TXA
        ASL A
        TAX
        LDA ENX,X
        STA OFX
        SEC
        LDA ENX+1,X
        SBC #$88
        STA OFX+1
        LDA ENY,X
        STA OFY
        SEC
        LDA ENY+1,X
        SBC #$88
        STA OFY+1
        LDA ENZ,X
        STA OFZ
        SEC
        LDA ENZ+1,X
        SBC #$86
        STA OFZ+1
        JSR NEWWAVE     ; ($FF1B) the wave's start positions and streams
        LDA #$00        ; ($C7A6)
        STA ALIVE
        STA ALIVE+1
        STA ALIVE+2
        STA EHITS
        STA EHITS+1
        STA EHITS+2
        LDX #$04
gi1:    CLC
        LDA ENX,X
        ADC OFX
        STA ENX,X
        LDA ENX+1,X
        ADC OFX+1
        STA ENX+1,X
        CLC
        LDA ENY,X
        ADC OFY
        STA ENY,X
        LDA ENY+1,X
        ADC OFY+1
        STA ENY+1,X
        CLC
        LDA ENZ,X
        ADC OFZ
        STA ENZ,X
        LDA ENZ+1,X
        ADC OFZ+1
        STA ENZ+1,X
        DEX
        DEX
        BPL gi1
        LDX CURG        ; ($C7A6) as many fighters as the group has
        LDY GSIZE,X
gi2:    LDA ETYPE
        STA EHITS-1,Y
        STA ALIVE-1,Y
        DEY
        BNE gi2
        LDX #$00        ; ($C7C2) the others far away
gi3:    LDA ALIVE,X
        BNE gi4
        TXA
        ASL A
        TAY
        LDA #$00
        STA ENX+1,Y
gi4:    INX
        CPX #$03
        BNE gi3
        LDA #$00        ; ($C7DC) the dogfight
        STA APPR
        STA APRUN
        STA LRMODE
        JSR RADMODE     ; ($C7EA) close range
        LDA #$00
        STA FIREFLAG
        LDA #$FF        ; ($C807) the first enemy shot comes late
        STA EFTHR
        LDA #$41        ; ($C7D7) the rush's speed back to rest
        STA RSPD
        LDA #$01        ; ($C7F7) the tracking computer is asked for at once
        STA TON
        STA ENGON       ; ($C7F9) the engine
        JMP ALERT       ; ($C832) "WARNING THE GORGANITOR APPROACH" and the siren

; The number under the crosshair ($3935): the distance of the chosen group, or of
; the first live fighter, high byte / 2 in three digits drawn into the crosshair's
; shape ($5F70); white in front, light green behind. 000 with no ships left.
NUMBER: LDA APPR
        BNE nm0
        LDX #$00
nm1:    LDA ALIVE,X
        BNE nm2
        INX
        CPX #$03
        BNE nm1
nm0:    LDX GSEL
nm2:    STX NUMT
        JSR DIST
        BMI nm3
        LDA #$01
        BNE nm4
nm3:    LDA #$0D
nm4:    STA NUMCOL
        LDA DSTH
        LSR A
        JSR BCD
        LDA SQCOUNT
        BNE nm5
        STA BCDH
        STA BCDT
        STA BCDO
nm5:    LDX #$00
        LDY BCDH
        JSR DIGIT
        LDX #$01
        LDY BCDT
        JSR DIGIT
        LDX #$02
        LDY BCDO
DIGIT:  LDA DIGOFS,Y    ; ($39A2) 5 rows of digit Y into column X of the
        TAY             ; crosshair (sprite rows 16-20)
        LDA #$05
        STA DGN
dg1:    LDA DIGF,Y
        STA $4C30,X
        INY
        INY
        INY
        INX
        INX
        INX
        DEC DGN
        BNE dg1
        RTS
DIGOFS: .BYTE $00,$01,$02,$0F,$10,$11,$1E,$1F,$20,$2D

; The radar's mode ($3194): close range for the fight, long range for the
; approach. The original rewrites the radar's range constants (operands $307C,
; $3089, $30B7, $30C4 from $3233-$323A): close x $86A0-$8AA0, depth $8201-$8A01;
; long x $01A0-$FEA0, depth $0101-$FE01. Its ellipse in the box changes: long
; range a small one (radius 4), close range the big one (radius 8): the new one
; is plotted (value 2), the old one erased. A beep on voice 2; the box's colour
; band starts moving ($9EE5). LRMODE = the mode to switch to.
RADMODE:LDY LRMODE
        LDA RTAB,Y
        STA RXLO
        LDA RTAB+2,Y
        STA RXHI
        LDA RTAB+4,Y
        STA RZLO
        LDA RTAB+6,Y
        STA RZHI
        LDA #$04        ; long: plot 4, erase 8; close: plot 8, erase 4
        LDX #$08
        CPY #$00
        BNE rmd1
        LDA #$08
        LDX #$04
rmd1:   STA CRAD1
        STX CRAD2
        LDA #$02        ; (the two circles are drawn in the next two vertical
        STA CPEND       ; blanks, CIRCLES: each takes about 100 lines)
        LDA #$00        ; ($31EA) the beep
        STA $D40B
        STA $D407
        STA $D409
        STA $D40D
        LDA #$0A
        STA $D40A
        LDA #$2A
        STA $D40C
        LDA #$60
        STA $D408
        LDA #$41
        STA $D40B
        LDA #$01        ; ($C680) the colour band moves
        STA SHACT
        RTS
RTAB:   .BYTE $86,$01,$8A,$FE,$82,$01,$8A,$FE

CIRCLES:LDA CRUN        ; a circle under way: 2 more steps (vertical blank)
        BEQ ccs0
        JMP CIRCSTEP
ccs0:   LDA CPEND       ; a pending circle of RADMODE
        BEQ ccs9
        DEC CPEND
        BEQ ccs1
        LDA CRAD1       ; the new one, plotted
        LDX #$00
        JMP CIRCLE
ccs1:   LDA CRAD2       ; the old one, erased
        LDX #$01
        JMP CIRCLE
ccs9:   RTS

; A circle ($3635): centre x 79, y 163 (multicolour pixels: an ellipse), radius
; A, X = 0 plots value 2 ($EF45), 1 erases ($EF10). The original's midpoint
; steps, eight points a step.
CIRCLE: STA CR47
        STX CMODE
        LDA #$80
        STA CR44
        LDA #$00
        STA CR48
        STA CR45
        LDA #$01
        STA CRUN
CIRCSTEP:               ; (port: 2 steps a call, CRUN = 0 when the circle is done)
        LDA #$02
        STA CSN
cc1:    CLC             ; ($3660)
        LDA CR44
        ADC CR48
        ADC CR48
        ADC #$01
        STA CR45
        SEC
        LDA CR45
        SBC CR47
        SBC CR47
        CLC
        ADC #$01
        STA CR46
        CLC             ; (x + r, y + s), (x - r, y + s)
        LDA #79
        ADC CR47
        STA POSX
        CLC
        LDA #163
        ADC CR48
        STA POSY
        JSR CPLOT
        SEC
        LDA #79
        SBC CR47
        STA POSX
        JSR CPLOT
        SEC             ; (x - r, y - s), (x + r, y - s)
        LDA #79
        SBC CR47
        STA POSX
        SEC
        LDA #163
        SBC CR48
        STA POSY
        JSR CPLOT
        CLC
        LDA CR47
        ADC #79
        STA POSX
        JSR CPLOT
        CLC             ; (x + s, y + r), (x - s, y + r)
        LDA #79
        ADC CR48
        STA POSX
        CLC
        LDA #163
        ADC CR47
        STA POSY
        JSR CPLOT
        SEC
        LDA #79
        SBC CR48
        STA POSX
        JSR CPLOT
        CLC             ; (x + s, y - r), (x - s, y - r)
        LDA #79
        ADC CR48
        STA POSX
        SEC
        LDA #163
        SBC CR47
        STA POSY
        JSR CPLOT
        SEC
        LDA #79
        SBC CR48
        STA POSX
        JSR CPLOT
        LDA CR45        ; ($36E3)
        STA CR44
        INC CR48
        LDA CR46
        BMI cc2
        SEC
        LDA #$80
        SBC CR46
        STA CR49
        JMP cc3
cc2:    AND #$7F
        STA CR49
cc3:    LDA CR44
        BMI cc4
        SEC
        LDA #$80
        SBC CR44
        STA CR4A
        JMP cc5
cc4:    AND #$7F
        STA CR4A
cc5:    LDA CR49
        CMP CR4A
        BCS cc6
        LDA CR46
        STA CR44
        DEC CR47
cc6:    LDA CR47
        CMP CR48
        BCC cc7
        DEC CSN
        BEQ cc8
        JMP cc1
cc7:    LDA #$00
        STA CRUN
cc8:    RTS
CPLOT:  JSR PIXADDR     ; value 2 ($EF45) or cleared ($EF10)
        LDA (PTR),Y
        AND CLEARM,X
        LDY CMODE
        BNE cp9
        ORA MASK2,X
cp9:    LDY #$00
        STA (PTR),Y
        RTS

; The radar's scan line and colour band ($9F1C, twice a frame): the line moves a
; pixel while the short range scanner works; every 8 calls the next colour of the
; band (black, dark gray, gray, light gray, white: $9ED5) goes in at the left of
; the box's 4 colour RAM rows (row 18-21, columns 12-27) and the rest move right.
RADSTEP:LDA SYSHP+2
        BEQ rx1
        LDX SCANX
        INX
        CPX #$E0
        BNE rx0
        LDX #$60
rx0:    STX SCANX
rx1:    DEC SHD
        BEQ rx2
        RTS
rx2:    LDA #$08
        STA SHD
        LDX SHI
        LDA BANDTAB,X
        STA SHC
        DEX
        BPL rx3
        LDX #$0F
rx3:    STX SHI
        LDA SHACT
        BNE rx4
        RTS
rx4:    LDX #$00        ; 4 rows
rx5:    LDY BANDROW,X
        LDA #$0F
        STA SHN
rx6:    LDA $DADB,Y        ; (the cell to the left)
        STA $DADC,Y
        DEY
        DEC SHN
        BNE rx6
        LDA SHC
        STA $DADC,Y
        INX
        CPX #$04
        BNE rx5
        RTS
BANDROW:  .BYTE 15,55,95,135      ; row offset + 15 (the rightmost cell)
BANDTAB:  .BYTE $00,$00,$00,$BB,$BB,$BB,$CC,$CC,$CC,$FF,$FF,$FF,$11,$11,$11,$11

; The radar ($305F, once a frame, one slot each time): a small H in the scanner's
; box for each slot within range. Close (the fight): x $86A0-$8AA0 and depth
; $8201-$8A01, 1/16 scale, needs the short range scanner. Long range (the
; approach): 1/1024 scale, only groups that exist, needs the long range scanner.
RADAR:  LDY RSLOT
        DEY
        BPL rd1
        LDY #$02
rd1:    STY RSLOT
        TYA
        ASL A
        TAX
        SEC
        LDA ENX,X
        SBC #$A0
        STA DT0
        LDA ENX+1,X
        SBC RXLO        ; ($307C: $86 close, $01 long range, self-modified by $3194)
        STA DT1
        BCS rq1
        JMP rdout
rq1:    LDA #$A0
        SBC ENX,X
        LDA RXHI        ; ($3089: $8A / $FE)
        SBC ENX+1,X
        BCS rq2
        JMP rdout
rq2:    LDA LRMODE
        BNE rd2
        LDA DT0
        LSR DT1
        ROR A
        LSR DT1
        ROR A
        LSR DT1
        ROR A
        LSR DT1
        ROR A
        JMP rd3
rd2:    LDA DT1
        LSR A
        LSR A
rd3:    STA RBXN
        SEC
        LDA ENZ,X
        SBC #$01
        STA DT0
        LDA ENZ+1,X
        SBC RZLO        ; ($30B7: $82 / $01)
        STA DT1
        BCS rq3
        JMP rdout
rq3:    LDA #$01
        SBC ENZ,X
        LDA RZHI        ; ($30C4: $8A / $FE)
        SBC ENZ+1,X
        BCS rq4
        JMP rdout
rq4:    LDA LRMODE
        BNE rd4
        LDA DT1
        ASL DT0
        ROL A
        ASL DT0
        ROL A
        LDX SYSHP+2
        BNE rd5
        JMP rdout
rd4:    LDA DT1
        LSR A
        LSR A
        LSR A
        LDX GSIZE,Y
        BNE rq5
        JMP rdout
rq5:    LDX SYSHP+1
        BNE rq6
        JMP rdout
rq6:
rd5:    STA RBZN
        CLC             ; (port: nothing to do when the mark stays)
        LDA RBXN
        ADC #$2D
        STA RBXN
        SEC
        LDA #$B1
        SBC RBZN
        STA RBZN
        LDA RBON,Y
        BEQ rd6
        LDA RBXN
        CMP RBX,Y
        BNE rd6
        LDA RBZN
        CMP RBY,Y
        BEQ rd7
rd6:    LDA RBX,Y       ; the old mark goes, the new one comes
        STA POSX
        LDA RBY,Y
        STA POSY
        JSR MERASE
        LDA RBXN
        STA RBX,Y
        STA POSX
        LDA RBZN
        STA RBY,Y
        STA POSY
        LDA #$01
        STA RBON,Y
        JMP MARKER
rd7:    RTS
rdout:  LDA RBON,Y      ; (port: only a mark that is there)
        BEQ rd7
        LDA #$00
        STA RBON,Y
        LDA RBX,Y
        STA POSX
        LDA RBY,Y
        STA POSY
        JMP MERASE

; The radar's mark ($3166 / $3138): an H of 7 pixels, colour 3, leaving colour 2
; alone ($EF53 / $EEE6). Rows 0-2 hold sprite shapes in the port: not there.
MARKER: LDA #$00
        BEQ mk0
MERASE: LDA #$01
mk0:    STA MKE
        STY MKY
        LDY #$00
mk1:    LDA MKDX,Y
        CLC
        ADC POSX
        STA MKX0
        LDA MKDY,Y
        CLC
        ADC POSY
        CMP #24
        BCC mk3
        STA MKY0
        STY MKI
        LDA MKX0
        STA POSX
        LDA MKY0
        STA POSY
        JSR PIXADDR
        LDA (PTR),Y
        AND MASK3,X
        CMP MASK2,X
        BEQ mk2
        LDA (PTR),Y
        AND CLEARM,X
        LDY MKE
        BNE mk4
        ORA MASK3,X
mk4:    LDY #$00
        STA (PTR),Y
mk2:    LDY MKI
        LDA MKX0        ; (PIXADDR took POSX / POSY: back to the mark's corner)
        SEC
        SBC MKDX,Y
        STA POSX
        LDA MKY0
        SEC
        SBC MKDY,Y
        STA POSY
mk3:    INY
        CPY #$07
        BNE mk1
        LDY MKY
        RTS
MKDX:   .BYTE 0,0,0,2,2,2,1
MKDY:   .BYTE 0,1,2,2,1,0,1
MASK2:  .BYTE $80,$20,$08,$02

SHOWTG: LDX #$70        ; A = ships: TARGETS on the HUD, two digits ($FCE9)
stg1:   CMP #10
        BCC stg2
        SBC #10
        INX
        BNE stg1
stg2:   STX TARGETS-1
        ORA #$70
        STA TARGETS
        RTS

; Hooks for c128-game (the map over the 3D view). Standalone the map never opens.
INPUTV: LDA MAPSHOWN
        BEQ iv1
        LDA #$FF        ; no steering, no fire while the map is open
        STA JOY
        LDA #$00
        STA FIREFLAG
        JMP MAPINHK
iv1:    JMP INPUT
VIEWVB: LDA MAPSHOWN
        ORA WIPE
        BEQ vv1
        JMP MAPVBHK
vv1:    LDA LYACT       ; laying the groups out (a group a frame, up to ~100 lines):
        BEQ vv2         ; instead of the star field in those few frames
        JMP LYSTEP
vv2:    JMP STARS
MAPINHK:RTS             ; (c128-game: the map's mouse, cursor and choice)
MAPVBHK:RTS             ; (c128-game: the map's draw-in, blink, planet)
TICKHK: RTS             ; (c128-game: the map's TICKER)

; Sprite 7 ($1193, once a frame): three things in turn, one a frame: the left
; gun's barrel (shape $47), the right gun's ($48), both twice as wide, black, the
; firing gun's yellow while a shot flies (with the red gun: red and yellow); and
; the radar's scan line (shape $05, white, twice as tall), which sweeps the
; scanner box 2 pixels a frame ($9F1C, while the short range scanner works).
SPR7:   LDX S7I         ; (the scan line moves in VBWORK: RADSTEP)
        LDA S7PTR,X
        STA SPRPTR+7
        LDA $D010
        AND #$7F
        ORA S7MSB,X
        STA $D010
        LDA S7COL,X
        LDY SHOTON
        BEQ s7c
        CPX #$02
        BEQ s7c
        LDY SHOTGUN     ; ($11AE) the gun that fired: yellow
        CPY #$01
        BEQ s7d
        CPX #$01
        BNE s7c
        BEQ s7e
s7d:    CPX #$00
        BNE s7c
s7e:    LDA #$07
s7c:    STA $D02E
        LDA $D017
        AND #$7F
        ORA S7YX,X
        STA $D017
        LDA $D01D
        ORA #$80
        STA $D01D
        LDA $D01C
        AND #$7F
        STA $D01C
        LDA $D01B       ; behind the bitmap, like the guns (the original's $D01B
        ORA #$80        ; is $FD below the view)
        STA $D01B
        CPX #$02        ; ($11E2) place
        BNE s7f
        LDY #$C3
        LDA SCANX
        BNE s7g
s7f:    LDA G1X,X       ; (G1X, G2X: x; G1Y, G2Y: y)
        LDY G1Y,X
        INY
s7g:    STA $D00E
        STY $D00F
        DEX
        BPL s7h
        LDX #$02
s7h:    STX S7I
        RTS
S7PTR:  .BYTE $3D,$3E,$FE        ; shapes $47, $48, $05 (build.py)
S7MSB:  .BYTE $00,$80,$00
S7COL:  .BYTE $00,$00,$01
S7YX:   .BYTE $00,$00,$80

; ---------------- hits and explosions ----------------
; The shot against the fighters ($3244 / $324C), once a frame. During the last 10
; points of its path a shot hits a fighter shown within 12 pixels across and 10
; down of it (the original compares the low bytes of the sprite x only). A fighter
; takes ETYPE shots (type 1: one). A hit that does not destroy it ends the shot.
SHOTHIT:LDA HITWIN      ; ($1616)
        BNE hx0
        RTS
hx0:    LDA EFVIS       ; ($3271, X = 0) the enemy shot, sprite 2: it can be shot
        BEQ hxf         ; down
        LDA EFX         ; (HITBOX reads ESH,Y: the shot goes behind the fighters)
        STA ESH+6
        LDA EFY
        STA ESH+7
        LDY #$06
        JSR HITBOX
        BEQ hxf
        LDA EFY
        CMP #$C3
        BCS hxf
        JMP HITSHOT
hxf:    LDX #$00        ; fighter 0-2 = sprites 4-6 (the original's X = 2-4)
hx1:    LDA EVIS
        AND ENBIT,X
        BEQ hx9
        TXA
        ASL A
        TAY
        JSR HITBOX      ; ($3371)
        BEQ hx9
        LDA ESH+1,Y     ; ($327C) too low on the screen: no hit
        CMP #$C3
        BCC hx2
hx9:    INX
        CPX #$03
        BNE hx1
        RTS
hx2:    DEC EHITS,X     ; ($32A7)
        BEQ hxkill
        BMI hxkill
        LDA ENZ+1,Y     ; (closer than depth $8700 it goes down at once)
        CMP #$86
        BEQ hxkill
        LDA NPTS        ; ($32B5) the shot ends at its next step
        STA SHIDX
        JMP HITSND
hxkill: LDA EXPL        ; ($32BE) one explosion at a time (the fighter's count
        BEQ hk1         ; stays at 0: the next hit destroys it)
        RTS
hk1:    STY HTY
        LDA SPX,Y       ; the fighter's current x and y steps make the
        STA PTR         ; explosion drift ($32C6, stream pointers $04 / $0A)
        LDA SPX+1,Y
        STA PTR+1
        LDY SIDX,X
        LDA (PTR),Y
        STA EVX0
        LDY HTY
        LDA SPY,Y
        STA PTR
        LDA SPY+1,Y
        STA PTR+1
        LDY SIDX,X
        LDA (PTR),Y
        STA EVY0
        LDA #$00
        STA ALIVE,X
        LDY HTY
        LDA #$01        ; far away in every direction
        STA ENX+1,Y
        STA ENY+1,Y
        STA ENZ+1,Y
        STA EXPL
        LDA #$00        ; ($32F2)
        STA HITWIN
        STA EXPB
        LDA ESH,Y       ; the explosion's centre in bitmap pixels
        SEC
        SBC #$18
        LSR A
        PHA
        LDA ESH+1,Y
        SEC
        SBC #$32
        STA EXPY        ; ($3320)
        CMP #$0A
        BCC hk2
        CMP #$BE
        BCS hk2
        PLA
        STA EXPX
        CMP #$0A
        BCC hk3
        CMP #$91
        BCC hk4
        BCS hk3
hk2:    PLA             ; (the original leaves this byte on the stack, $3337)
hk3:    LDA #$00        ; off the view: no explosion
        STA EXPL
hk4:    JSR KILL
        LDA EVIS        ; the fighter and the shot disappear
        AND ENMASK,X
        STA EVIS
        LDA #$00
        STA SHOTVIS
        JMP HITSND

HITBOX: LDA ESH,Y       ; ($337D) A = 1: the shot is on the fighter (Y = 2 x fighter)
        CMP SHOTX
        BCS hb1
        LDA SHOTX
        SBC ESH,Y       ; (carry clear: one more, as the original)
        CMP #$0C
        BCS hbno
        BCC hb2
hb1:    SBC SHOTX
        CMP #$0C
        BCS hbno
hb2:    LDA ESH+1,Y
        CMP SHOTY
        BCS hb3
        LDA SHOTY
        SBC ESH+1,Y
        CMP #$0A
        BCS hbno
        BCC hbyes
hb3:    SBC SHOTY
        CMP #$0A
        BCS hbno
hbyes:  LDA #$01
        RTS
hbno:   LDA #$00
        RTS

KILL:   STX KLX         ; ($3CC4) one ship less in the sector, one more kill
        DEC SQCOUNT
        LDA SQCOUNT
        JSR SHOWTG
        INC KILLS
        BNE kl1
        INC KILLS+1
kl1:    JSR KILLHK
        LDA SQCOUNT
        BNE kl2
        LDA #$00        ; ($3CDE) the squadron is destroyed
        STA GSIZE
        STA GSIZE+1
        STA GSIZE+2
        STA APPR
        STA APRUN
        JSR EMPTYHK
        LDX KLX
        RTS
kl2:    LDX CURG        ; ($3D23) the group: when it is gone, the next one is
        DEC GSIZE,X     ; approached
        BNE kl3
        LDA #$01
        STA APPR
        STA RELAYOUT
        LDA #$00
        STA APRUN
        LDA #$0F
        STA APDLY
kl3:    LDX KLX
        RTS
KILLHK: RTS             ; (c128-game: the map's COUNT follows)
EMPTYHK:JMP SECSTART    ; standalone: the next squadron arrives (c128-game: none)
SECSTART:
        LDA #$09        ; (c128-game: from the map)
        STA SQCOUNT
        JMP ARRIVE

HITSND: LDA #$01        ; ($3349) voice 2 noise, and the flash starts
        STA HITFL
        STA OWNHIT
        LDA #$0F
        STA $D418
        LDA #$00
        STA $D40B
        STA $D40D
        STA $D407
        LDA #$6B
        STA $D40C
        LDA #$06
        STA $D408
        LDA #$81
        STA $D40B
        RTS

; The hit flash ($1321, every other frame): the 3D view's background and border
; go light blue, blue, light blue, white, blue, black, 6 frames each.
FLASH:  LDA HITFL
        BNE fl0
        RTS
fl0:    LDA FLC0
        BNE fl1
        LDA #$06
        STA FLN
        LDA #$03
        STA FLD
        STA FLC0
        JSR HITSND2
fl1:    DEC FLD
        BEQ fl2
        RTS
fl2:    LDA #$03
        STA FLD
        DEC FLN
        LDX FLN
        BPL fl3
        LDA #$00
        STA HITFL
        STA FLC0
        STA OWNHIT
        STA TORPHIT
        RTS
fl3:    LDA OWNHIT      ; ($137D) our shot hit: $130A, the ship was hit: $1303
        BEQ fl4
        LDA TORPHIT     ; (our shot hit the enemy shot: $1318)
        BNE fl5
        LDA FLTAB,X
        STA FLASHC
        RTS
fl5:    LDA FLTAB3,X
        STA FLASHC
        RTS
fl4:    LDA FLTAB2,X
        STA FLASHC
        RTS

HITSND2:LDA #$00        ; ($C3A8) the second noise of a hit
        STA $D407
        STA $D40B
        STA $D40D
        STA $D417
        LDA #$0F
        STA $D418
        LDA #$8F
        STA $D416
        LDA #$04
        STA $D408
        LDA #$0A
        STA $D40C
        LDA #$81
        STA $D40B
        RTS

; The explosion ($16B3): 26 points (the first 12 two pixels tall) fly apart from
; the fighter's place in white (colour 01) into empty pixels, drifting with the
; fighter's last step, in 20 steps that come faster and faster. The original
; counts its main loop passes between steps (15 down to 2, about 8 passes a
; frame in a fight); EXPTICK counts 8 a frame. A step plots and erases up to 76
; pixels, more than one slot of free time, so EXPLODE works through the points
; until the raster reaches EXLIM and goes on in the next free slot.
EXPTICK:LDA EXPL
        BEQ et9
        LDA EXPB
        BEQ et9
        LDA EXPEND
        ORA EXPRUN
        BNE et9
        SEC             ; ($1733)
        LDA EXPC
        SBC #PASSES
        BEQ et1
        BCC et1
        STA EXPC
et9:    RTS
et1:    SEC             ; ($1739)
        LDA EXPD
        SBC #$01
        CMP #$03
        BCS et2
        LDA #$02
et2:    STA EXPD
        STA EXPC
        LDA #$01
        STA EXPRUN
        LDA #$00
        STA EXPI
        RTS

EXPLODE:LDA EXPL
        BEQ ex9
        LDA MAPSHOWN    ; (none over the map)
        BEQ ex0
ex9:    RTS
ex0:    LDA EXPB
        BNE ex5
        LDA EXLIM       ; the start takes about 12 lines: only with time left
        SEC
        SBC #14
        CMP $D012
        BCS ex1
        RTS
ex1:    LDA #$14        ; ($16C1) 20 steps
        STA EXPN
        LDA EVX0        ; the drift: half the step, sign and size
        JSR HALFSTEP
        STA EDX
        LDA EVY0
        JSR HALFSTEP
        STA EDY
        LDA EXPX        ; (the original checks the same centre for each point)
        CMP #$91
        BCS ex2
        CMP #$05
        BCC ex2
        LDA EXPY
        CMP #$05
        BCC ex2
        CMP #$C3
        BCC ex3
ex2:    LDA #$00
        STA EXPL
        STA EXPB
        RTS
ex3:    LDX #25
        LDY EXPX
ex4:    TYA
        STA PNX,X
        STA POX,X
        LDA EXPY
        STA PNY,X
        STA POY,X
        DEX
        BPL ex4
        LDA #$0F
        STA EXPC
        STA EXPD
        STA EXPL
        STA EXPB
        LDA #$00
        STA EXPI
        STA EXPRUN
        STA EXPEND
        RTS
ex5:    LDA EXPEND
        BNE exclr
        LDA EXPRUN
        BNE exs0
        RTS
exs0:   LDX EXPI
exs1:   LDA $D012
        CMP EXLIM
        BCC exs2
        STX EXPI        ; out of time: on in the next slot
        RTS
exs2:   JSR PSTEP
        INX
        CPX #26
        BNE exs1
        LDA #$00
        STA EXPI
        STA EXPRUN
        DEC EXPN        ; ($17FF)
        BEQ exs3
        RTS
exs3:   LDA #$01        ; ($1805) the end: the points are erased
        STA EXPEND
exclr:  LDX EXPI
exc1:   LDA $D012
        CMP EXLIM
        BCC exc2
        STX EXPI
        RTS
exc2:   LDA PNX,X
        STA POSX
        LDA PNY,X
        STA POSY
        JSR EERASE
        CPX #12
        BCS exc3
        INC POSY
        JSR EERASE
exc3:   INX
        CPX #26
        BNE exc1
        LDA #$00
        STA EXPL
        STA EXPB
        STA EXPEND
        STA EXPI
        STA HITWIN      ; ($180D)
        RTS

HALFSTEP:               ; A = sign and size: half of it as a signed byte
        CMP #$80
        BCS hs1
        LSR A
        RTS
hs1:    AND #$7F
        LSR A
        EOR #$FF
        CLC
        ADC #$01
        RTS

PSTEP:  CLC             ; ($174D / $17AB) point X: move, plot, erase the old one
        LDA PNX,X
        STA POX,X
        ADC PVX,X
        CLC
        ADC EDX
        CMP #$9E
        BCC ps1
        LDA PNY,X       ; off the side: it stays where it was, erased
        STA POY,X
        JMP ps3
ps1:    STA POSX
        STA PNX,X
        CLC
        LDA PNY,X
        STA POY,X
        ADC PVY,X
        CLC
        ADC EDY
        CMP #$B5
        BCS ps3
        STA PNY,X
        STA POSY
        JSR EPLOT
        CPX #12
        BCS ps3
        INC POSY
        JSR EPLOT
ps3:    LDA POX,X
        STA POSX
        LDA POY,X
        STA POSY
        JSR EERASE
        CPX #12
        BCS ps4
        INC POSY
        JSR EERASE
ps4:    RTS

EPLOT:  LDA POSY        ; ($EF30) colour 01 into an empty pixel. Not in rows 0-2:
        CMP #24         ; in the port they hold sprite shapes (hidden by the HUD)
        BCC ep9
        STX EXSAV
        JSR PIXADDR
        LDA (PTR),Y
        AND MASK3,X
        BNE ep8
        LDA (PTR),Y
        ORA MASK1,X
        STA (PTR),Y
ep8:    LDX EXSAV
ep9:    RTS

EERASE: LDA POSY        ; ($EF1B) clears a pixel only if it has colour 01
        CMP #24
        BCC ee9
        STX EXSAV
        JSR PIXADDR
        LDA (PTR),Y
        AND MASK3,X
        CMP MASK1,X
        BNE ee8
        LDA (PTR),Y
        AND CLEARM,X
        STA (PTR),Y
ee8:    LDX EXSAV
ee9:    RTS

; The second explosion ($9DAA): the same, with 12 points, all two pixels tall:
; where an enemy shot reaches the ship. Generated from the first (labels and
; variables with a 2 / q).
EXPTICK2:LDA EXPL2
        BEQ qet9
        LDA EXPB2
        BEQ qet9
        LDA EXPEND2
        ORA EXPRUN2
        BNE qet9
        SEC             ; ($9E2A)
        LDA EXPC2
        SBC #PASSES
        BEQ qet1
        BCC qet1
        STA EXPC2
qet9:    RTS
qet1:    SEC             ; ($1739)
        LDA EXPD2
        SBC #$01
        CMP #$03
        BCS qet2
        LDA #$02
qet2:    STA EXPD2
        STA EXPC2
        LDA #$01
        STA EXPRUN2
        LDA #$00
        STA EXPI2
        RTS

EXPLODE2:LDA EXPL2
        BEQ qex9
        LDA MAPSHOWN
        BEQ qex0
qex9:   RTS
qex0:    LDA EXPB2
        BNE qex5
        LDA EXLIM       ; the start takes about 12 lines: only with time left
        SEC
        SBC #14
        CMP $D012
        BCS qex1
        RTS
qex1:    LDA #$14        ; ($9DB8) 20 steps
        STA EXPN2
        LDA EVX02        ; the drift: half the step, sign and size
        JSR HALFSTEP
        STA EDX2
        LDA EVY02
        JSR HALFSTEP
        STA EDY2
        LDA EXPX2        ; (the original checks the same centre for each point)
        CMP #$91
        BCS qex2
        CMP #$05
        BCC qex2
        JMP qex3        ; (the original checks x twice here, never y)
qex2:    LDA #$00
        STA EXPL2
        STA EXPB2
        RTS
qex3:    LDX #11
        LDY EXPX2
qex4:    TYA
        STA PNX2,X
        STA POX2,X
        LDA EXPY2
        STA PNY2,X
        STA POY2,X
        DEX
        BPL qex4
        LDA #$0F
        STA EXPC2
        STA EXPD2
        STA EXPL2
        STA EXPB2
        LDA #$00
        STA EXPI2
        STA EXPRUN2
        STA EXPEND2
        RTS
qex5:    LDA EXPEND2
        BNE qexclr
        LDA EXPRUN2
        BNE qexs0
        RTS
qexs0:   LDX EXPI2
qexs1:   LDA $D012
        CMP EXLIM
        BCC qexs2
        STX EXPI2        ; out of time: on in the next slot
        RTS
qexs2:   JSR PSTEP2
        INX
        CPX #12
        BNE qexs1
        LDA #$00
        STA EXPI2
        STA EXPRUN2
        DEC EXPN2        ; ($9EA2)
        BEQ qexs3
        RTS
qexs3:   LDA #$01        ; ($9EA8) the end
        STA EXPEND2
qexclr:  LDX EXPI2
qexc1:   LDA $D012
        CMP EXLIM
        BCC qexc2
        STX EXPI2
        RTS
qexc2:   LDA PNX2,X
        STA POSX
        LDA PNY2,X
        STA POSY
        JSR EERASE
        CPX #12
        BCS qexc3
        INC POSY
        JSR EERASE
qexc3:   INX
        CPX #12
        BNE qexc1
        LDA #$00
        STA EXPL2
        STA EXPB2
        STA EXPEND2
        STA EXPI2
        RTS


PSTEP2:  CLC             ; ($9E44) point X
        LDA PNX2,X
        STA POX2,X
        ADC PVX,X
        CLC
        ADC EDX2
        CMP #$9E
        BCC qps1
        LDA PNY2,X       ; off the side: it stays where it was, erased
        STA POY2,X
        JMP qps3
qps1:    STA POSX
        STA PNX2,X
        CLC
        LDA PNY2,X
        STA POY2,X
        ADC PVY,X
        CLC
        ADC EDY2
        CMP #$B5
        BCS qps3
        STA PNY2,X
        STA POSY
        JSR EPLOT
        CPX #12
        BCS qps3
        INC POSY
        JSR EPLOT
qps3:    LDA POX2,X
        STA POSX
        LDA POY2,X
        STA POSY
        JSR EERASE
        CPX #12
        BCS qps4
        INC POSY
        JSR EERASE
qps4:    RTS

MASK1:  .BYTE $40,$10,$04,$01
FLTAB:  .BYTE $00,$06,$01,$0E,$06,$0E
FLTAB3: .BYTE $00,$01,$05,$01,$05,$01  ; ($1318) the enemy shot shot down: white, green
FLTAB2: .BYTE $00,$02,$01,$08,$0A,$01  ; ($1303) the ship hit: white, light red, orange, white, red
PVX:    .BYTE $FE,$FC,$FE,$03,$02,$04,$FC,$FD,$FE,$03,$02,$04,$FC,$FC,$FD,$FC,$00,$03,$04,$04,$FC,$FD,$00,$03,$04,$05
PVY:    .BYTE $FC,$FE,$FD,$FC,$FD,$FE,$03,$02,$04,$03,$03,$02,$FD,$FD,$FB,$00,$FC,$FC,$FD,$00,$03,$04,$04,$04,$03,$03

; A signed step (bit 7 = minus) added to x, y or depth ($2BEF, $2C0B, $2C27).
ADDX:   BMI ax1
        CLC
        ADC ENX,X
        STA ENX,X
        BCC ax0
        INC ENX+1,X
ax0:    RTS
ax1:    AND #$7F
        STA ATMP
        SEC
        LDA ENX,X
        SBC ATMP
        STA ENX,X
        BCS ax0
        DEC ENX+1,X
        RTS
ADDY:   BMI ay1
        CLC
        ADC ENY,X
        STA ENY,X
        BCC ay0
        INC ENY+1,X
ay0:    RTS
ay1:    AND #$7F
        STA ATMP
        SEC
        LDA ENY,X
        SBC ATMP
        STA ENY,X
        BCS ay0
        DEC ENY+1,X
        RTS
ADDZ:   BMI az1
        CLC
        ADC ENZ,X
        STA ENZ,X
        BCC az0
        INC ENZ+1,X
az0:    RTS
az1:    AND #$7F
        STA ATMP
        SEC
        LDA ENZ,X
        SBC ATMP
        STA ENZ,X
        BCS az0
        DEC ENZ+1,X
        RTS

; ---------------- the automatic tracking computer ($89E6-$8C22) ----------------
; A (or T) asks for it in a fight ($8C07, read by the fight loop, $2D7A). The fight
; loop looks every 32 passes ($2D61 -> $89E6): with the computer working (SYSHP+4,
; $3D) it starts its own main loop ($8A34) instead of the fight loop. That loop:
; no steering ($39C1 is not called), the view turns by itself toward the first
; live fighter (TAIM, $8B49, every 4 passes) and that fighter is pulled into the
; box x $8847-$88F9, y $8869-$88A3, depth $8650-$87CF (TMOVE, $8BED: 1, 2, 3
; units every 3 passes); enemy fire every pass, the fighters' streams and the
; drift at rates of their own (tables), a shot launches only every 64 passes.
; Every 32 passes it ends on A again, when no fighter is left, when the approach
; starts or thrust is used ($63), or when the computer is destroyed. It makes
; about 6.2 passes a frame (measured), against ~16 of the fight loop.
TRKCHK: LDA TON         ; ($89E6) every other frame of a fight
        BNE tk1
        RTS
tk1:    LDA SYSHP+4
        BNE tk2
        STA TON         ; ($89EF) destroyed: off
        STA TRUN
        STA TRACK
        STA TTGT
        RTS
tk2:    LDA TRUN
        BNE tk9
        LDA #$00        ; ($89FD) start
        STA TTGT
        STA TACC
        LDA #$01
        STA TRUN
        STA TRACK
        STA TCAIM
        STA TCST
        LDA #$31        ; ($8A2F) the crosshair: $49
        STA TRFRAME
        JMP TRKMSG
tk9:    RTS

TRKEND: LDA #$00        ; ($8A4E)
        STA TON
        STA TRUN
        STA TRACK
        STA TPRESS
        RTS

TRKFRAME:               ; a frame of the tracking loop: owed in the vertical blank
        CLC             ; (2 MHz), run until line 30; the rest in the fight's slot
        LDA TACC        ; (TRKSLOT, lines 194-222)
        ADC #$2C        ; + 6.17 passes ($062C / 256)
        STA TACC
        LDA TACC+1
        ADC #$06
        STA TACC+1
tf1:    LDA TACC+1
        BEQ tf9
        LDA $D012
        CMP #30
        BCC tf2
        CMP #251
        BCC tf9
tf2:    DEC TACC+1
        JSR TPASS
        LDA TRUN
        BNE tf1
        STA TACC+1
tf9:    RTS

TRKSLOT:LDA #222        ; the fight's slot: until line 222
TRKSL2: STA TSLIM       ; (the 3D view's: until line 112)
ts1:    LDA TACC+1
        BEQ ts9
        LDA $D012
        CMP TSLIM
        BCS ts9
        DEC TACC+1
        JSR TPASS
        LDA TRUN
        BNE ts1
        STA TACC+1
ts9:    RTS

TPASS:  LDA TPC         ; ($8A34)
        AND #$1F
        BNE tp2
        LDA TPRESS      ; A again ($8C07)
        BNE tpx
        LDA ALIVE
        ORA ALIVE+1
        ORA ALIVE+2
        BEQ tpx
        LDA APPR        ; ($63: the approach began, or thrust)
        BNE tpx
tp2:    LDA SYSHP+4
        BNE tp3
tpx:    JMP TRKEND
tp3:    DEC TPC
        JSR EFIRE       ; ($C947)
        DEC TCAIM       ; ($89C5) every 4 passes: aim
        BNE tp4
        LDA #$04
        STA TCAIM
        JSR TAIM
tp4:    DEC TCST        ; ($89C6) the streams: every 8,7,7,6,6 / 4,4,4,3,3 /
        BNE tp5         ; 7,7,7,6,5 passes by type and difficulty
        LDX ETYPE
        LDA TSTRB-1,X
        CLC
        ADC DIFF
        TAX
        LDA TSTRT,X
        STA TCST
        LDX #$00
        JSR MOVEN
        LDX #$02
        JSR MOVEN
        LDX #$04
        JSR MOVEN
tp5:    DEC TCDR        ; ($89C7) the drift: every 4,3,3 + 2 * difficulty passes
        BNE tp6
        LDX ETYPE
        LDA DIFF
        ASL A
        ADC TDRT-1,X
        STA TCDR
        SEC
        JSR EDRIFT
tp6:    LDA TPC         ; ($8AA9) a shot launches only now
        AND #$3F
        BNE tp7
        LDA #$01
        STA TLOK
tp7:    LDA TPC         ; ($8B08) every 16: the lost fighters' depth to 0
        AND #$0F
        BNE tp8
        LDX #$04
        LDY #$02
td1:    LDA ALIVE,Y
        BNE td2
        STA ENZ+1,X
td2:    DEX
        DEX
        DEY
        BPL td1
tp8:    DEC TCMV        ; ($89C9) every 3 passes: pull the target
        BNE tp9
        LDA #$03
        STA TCMV
        JMP TMOVE
tp9:    RTS

; Aim ($8B49): the first live fighter; for each axis below / above the box: the
; step that pulls it in (sign and size) and the star field's turn (+-2, as the
; stick would: $D5 x, $D6 y; one step of the stars with it, $EE25). The
; comparisons use the carry as it comes, as in the original. The original also
; moves the planet ($89CA -> $B846, with masks read from zero page $FB, $F7, $FE,
; $FD instead of immediates); there is no planet in the cockpit.
TAIM:   LDX #$FF
ta0:    INX
        CPX #$03
        BCC ta00
        RTS
ta00:   LDA ALIVE,X
        BEQ ta0
        TXA
        STX TTGT
        ASL A
        TAX
        LDA ENX,X
        SBC #$46
        LDA ENX+1,X
        SBC #$88
        BCC ta2
        LDA ENX,X
        SBC #$FA
        LDA ENX+1,X
        SBC #$88
        BCS ta1
        LDA #$00
        TAY
        BEQ ta3
ta1:    LDA #$FE
        LDY #$81
        BMI ta3
ta2:    LDA #$02
        LDY #$01
ta3:    STA TSX
        STY TDX
        LDA ENY,X
        SBC #$68
        LDA ENY+1,X
        SBC #$88
        BCC ta5
        LDA ENY,X
        SBC #$A4
        LDA ENY+1,X
        SBC #$88
        BCS ta4
        LDA #$00
        TAY
        BEQ ta6
ta4:    LDA #$FE
        LDY #$82
        BMI ta6
ta5:    LDA #$02
        LDY #$02
ta6:    STA TSY
        STY TDY
        LDA ENZ,X
        SBC #$50
        LDA ENZ+1,X
        SBC #$86
        BCC ta8
        LDA ENZ,X
        SBC #$D0
        LDA ENZ+1,X
        SBC #$87
        BCS ta7
        LDY #$00
        BEQ ta9
ta7:    LDY #$83
        BMI ta9
ta8:    LDY #$03
ta9:    STY TDZ
        LDA #$01        ; the stars take the turn in the next frame
        STA TSPEND
        RTS

TMOVE:  LDA TTGT        ; ($8BED)
        ASL A
        TAX
        LDA TDX
        JSR ADDX
        LDA TDY
        JSR ADDY
        LDA TDZ
        JMP ADDZ

TRKMSG: LDA #<TMTEXT    ; ($8A1D -> $9BE5) "AUTO TRACKING ENGAGED", scrolled in,
        LDX #>TMTEXT    ; white / yellow, every 8th step, 18 times
        LDY #$71
        STY MSGCOL
        LDY #$08
        STY MSGRATE
        LDY #18
        JMP MSGSCR

; ---------------- system messages in row 23 ($9BE5, $9CD3, $13D5) ----------------
; A message scrolls in from the right, 2 pixels a frame (the strip's fine scroll,
; $13D3: 5, 3, 1, 7, ...), a character every 4 frames; every MSGRATE characters
; the row's colour flips between the two colours of MSGCOL (low nibble first,
; with a beep), MSGN times; then the row turns light green and stays.
MSGSCR: STA MSGP        ; A/X = text ($FF ends it), Y = colour flips
        STA PTR
        STX MSGP+1
        STX PTR+1
        STY MSGN
        LDA MSGRATE
        STA MSGCD
        LDA MSGCOL
        AND #$0F
        STA MSGC1
        LDA MSGCOL
        LSR A
        LSR A
        LSR A
        LSR A
        STA MSGC2
        LDA #$00
        STA MSGMODE
        LDY #39
ms1:    LDA #$60
        STA LRROW,Y
        LDA #$00
        STA COLROW,Y
        DEY
        BPL ms1
        LDA #$01
        STA MSGON
        STA MSGFINE
        RTS

MSGSTAT:JSR MSGSCR      ; ($9BE5 with $80: the text stands in the row at once)
        LDA #$80
        STA MSGMODE
        LDA #$00
        STA MSGFINE
        LDA #$05
        STA STRIPX
        STA FINEX
        LDY #$00
mss1:   LDA (PTR),Y
        CMP #$FF
        BEQ mss2
        STA LRROW,Y
        INY
        BNE mss1
mss2:   RTS

MSGFRAME:               ; ($13D5) once a frame
        LDA MSGFINE
        BEQ mf9
        LDY FINEX
        STY STRIPX
        DEY
        DEY
        BPL mf1
        LDY #$07
mf1:    STY FINEX
        CPY #$05
        BNE mf9
        JMP MSGTICK
mf9:    LDA MSGON       ; (a standing message ticks every frame)
        BEQ mf8
        LDA MSGFINE
        BNE mf8
        JMP MSGTICK
mf8:    RTS

MSGTICK:LDA MSGON       ; ($9CD3)
        BEQ mt5
        DEC MSGCD
        BNE mt5
        LDA MSGRATE
        STA MSGCD
        LDA MSGTG
        EOR #$01
        STA MSGTG
        TAX
        LDA MSGC1,X
        LDY #39
mt1:    STA COLROW,Y
        DEY
        BPL mt1
        JSR MSGBEEP
        DEC MSGN
        BNE mt5
        LDA #$00        ; done: light green, and it stays
        STA MSGON
        LDY #39
mt2:    LDA #$0D
        STA COLROW,Y
        LDA MSGMODE     ; a standing message goes
        CMP #$80
        BNE mt3
        LDA #$60
        STA LRROW,Y
mt3:    DEY
        BPL mt2
        LDA #$80
        STA MSGMODE
        RTS
mt5:    LDA MSGMODE
        BPL mt6
        LDA #$00        ; (port: the fine scroll stops at 5 once the message is
        STA MSGFINE     ; over, for the scanner's digits; the original keeps
        LDA #$05        ; cycling it under the empty row)
        STA STRIPX
        STA FINEX
        RTS
mt6:    LDY #$00
mt7:    LDA LRROW+1,Y
        STA LRROW,Y
        INY
        CPY #39
        BNE mt7
        LDA MSGP
        STA PTR
        LDA MSGP+1
        STA PTR+1
        LDY #$00
        LDA (PTR),Y
        CMP #$FF
        BNE mt8
        LDA #$60
        BNE mt9
mt8:    INC MSGP
        BNE mt9
        INC MSGP+1
mt9:    STA LRROW+39
        RTS

MSGSTOP:LDA #$00        ; (port) the approach takes the row over
        STA MSGON
        STA MSGFINE
        LDA #$80
        STA MSGMODE
        LDA #$05
        STA STRIPX
        STA FINEX
        RTS

MSGBEEP:LDA #$00        ; ($9D4A) voice 2
        STA $D40B
        STA $D407
        STA $D40D
        STA $D409
        LDA #$03
        STA $D40A
        LDA #$02
        STA $D40C
        LDA #$3F
        STA $D408
        LDA #$41
        STA $D40B
        RTS

TMTEXT: .BYTE $40,$40,$40,$40,$40,$40,$40,$40,$40,$41,$55,$54,$4F,$40,$54,$52
        .BYTE $41,$43,$4B,$49,$4E,$47,$40,$45,$4E,$47,$41,$47,$45,$44,$FF
TSTRB:  .BYTE 0,5,10
TSTRT:  .BYTE 8,7,7,6,6, 4,4,4,3,3, 7,7,7,6,5
TDRT:   .BYTE 4,3,3

TKEYS:
        LDA #$FD        ; A (column 1, row 2, as in the original: $FDE7) or T
        STA CIA1PA      ; (column 2, row 6): the tracking computer
        LDA CIA1PB
        AND #$04
        BEQ tkd
        LDA #$FB
        STA CIA1PA
        LDA CIA1PB
        AND #$40
        BEQ tkd
        LDA #$00        ; released: the press is forgotten ($8C07)
        STA TKPREV
        STA TPRESS
        BEQ tdone
tkd:    LDA TKPREV
        BNE tdone
        LDA #$01
        STA TKPREV
        STA TPRESS
tdone:  LDA TRACK       ; ($12AE) tracking: the crosshair $49, $4A, $4B every 16th
        BEQ tno9        ; frame (type 1, or the target is close: depth $86xx),
        INC FCNT        ; else $49 (now $31-$33)
        LDA FCNT
        AND #$0F
        BNE tno9
        LDY #$31
        LDA ETYPE
        CMP #$01
        BEQ tan
        LDA TTGT
        ASL A
        TAX
        LDA ENZ+1,X
        CMP #$86
        BNE tst
tan:    LDY TRFRAME
        INY
        CPY #$34
        BNE tst
        LDY #$31
tst:    STY TRFRAME
tno9:   RTS

TSTARS: LDA TRUN        ; ($8B49 -> $EE25, every 4 passes, about 1.5 a frame);
        BEQ tss0        ; C = 1: done
        LDA TSPEND
        BEQ tss1
        LDA #$00
        STA TSPEND
        LDA TSX
        STA SHX
        LDA TSY
        STA SHY
tss1:   SEC
        RTS
tss0:   CLC
        RTS

; ---------------- the voice 1 sound effects and the HUD's border ($0969, $09AC) ----------------
; A sweep of voice 1 (pulse, AD $72, SR $6F): SNDCNT times SNDRLD frames, each frame
; 5 steps of SNDSTP up (SNDDIR <> 0) or down, from the high byte SNDHI0. While one
; plays (SNDON, $F8) the upper HUD's border pulses through grays ($08EE), the engine
; ("representing the engine"); else it is light blue. In the approach the scanner
; sets it (CLOSEIN).
SNDRUSH:LDA #$01        ; ($094E) the rush: once, 48 frames, up from $01xx by $1E
        STA SNDDIR
        STA SNDHI0
        LDA #$1E
        LDX #$01
        LDY #$30
        JMP SNDGO
SNDSIREN:               ; ($0930) the siren: 8 times 40 frames, up from $1Exx by $FF
        LDA #$01
        STA SNDDIR
        LDA #$1E
        STA SNDHI0
        LDA #$FF
        LDX #$08
        LDY #$28
SNDGO:  STA SNDSTP      ; ($0969)
        STX SNDCNT
        STY SNDRATE
        STY SNDRLD
        LDA #$00
        STA SNDON
        STA $D404
        STA $D400
        STA SNDLO
        LDA #$08
        STA $D403
        LDA #$6F
        STA $D406
        LDA #$72
        STA $D405
        LDA SNDHI0
        STA SNDHI
        STA $D401
        LDA #$0F
        STA $D418
        STA SNDON
        LDA #$41
        STA $D404
        RTS

SNDTICK:LDA SNDON       ; ($09AC) once a frame
        BNE sd1
        LDA APPR
        BNE sd0
        LDA #$0E
        STA HUDBRD
sd0:    RTS
sd1:    LDX SNDPI       ; the border's pulse
        LDA APPR
        BNE sd2
        LDA PULSE,X
        STA HUDBRD
sd2:    DEC SNDPI
        BPL sd3
        LDA #$22
        STA SNDPI
sd3:    DEC SNDRATE
        BNE sd5
        LDA SNDRLD
        STA SNDRATE
        DEC SNDCNT
        BNE sd4
        LDA #$00        ; over
        STA SNDON
        STA $D404
        LDA APPR
        BNE sd0
        LDA #$0E
        STA HUDBRD
        RTS
sd4:    LDA SNDHI0      ; again from the start
        STA $D401
        STA SNDHI
sd5:    LDY #$04
        LDA SNDDIR
        BNE sd7
sd6:    SEC
        LDA SNDLO
        SBC SNDSTP
        STA SNDLO
        STA $D400
        LDA SNDHI
        SBC #$00
        STA SNDHI
        STA $D401
        DEY
        BPL sd6
        RTS
sd7:    CLC
        LDA SNDLO
        ADC SNDSTP
        STA SNDLO
        STA $D400
        LDA SNDHI
        ADC #$00
        STA SNDHI
        STA $D401
        DEY
        BPL sd7
        RTS

; The engine ($C379, once a frame while ENGON, $C376): a burst of noise on voice 3
; every 6th frame. The rush lowers its pitch between bursts (CLOSEIN).
ENGTICK:LDA ENGON
        BEQ en9
        DEC ENGC
        BNE en9
        LDA #$06
        STA ENGC
        LDA #$00
        STA $D412
        LDA #$08
        STA $D40F
        LDA #$68
        STA $D40E
        LDA #$A0
        STA $D414
        LDA #$22
        STA $D413
        LDA #$81
        STA $D412
en9:    RTS

; Star steps this frame: one, two every fourth frame; while rushing the original
; lowers every star's delay to RSPD / 4 ($C8C1): here up to 7 more steps.
STARTK: LDY #1
        LDA FRMC
        AND #3
        BNE stk1
        INY
stk1:   LDA APPR
        BEQ stk2
        LDA RSPD
        LSR A
        LSR A
        LSR A
        CMP #$07        ; $41-$38 -> none more, ... $05 -> 3 more (what the
        BCS stk2        ; vertical blank has time for: each step of 12 stars)
        EOR #$07
        LSR A
        STA STKX
        TYA
        CLC
        ADC STKX
        TAY
stk2:   STY NT0
        RTS

; The arrival ($C832): "WARNING  THE GORGANITOR APPROACH" in yellow / orange,
; flashing every 15th frame, 30 times (as it stands, not scrolled), and the siren.
ALERT:  LDA #<WARNTX
        LDX #>WARNTX
        LDY #$87
        STY MSGCOL
        LDY #$0F
        STY MSGRATE
        LDY #30
        JSR MSGSTAT
        JMP SNDSIREN

PULSE:  .BYTE $0F,$0F,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0B,$0B,$00,$00,$00
        .BYTE $00,$00,$0B,$0B,$0B,$0B,$0B,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0F,$0F,$0F
WARNTX: .BYTE $40,$40,$40,$40,$57,$41,$52,$4E,$49,$4E,$47,$40,$40,$54,$48,$45,$40,$47
        .BYTE $4F,$52,$47,$41,$4E,$49,$54,$4F,$52,$40,$41,$50,$50,$52,$4F,$41,$43,$48,$FF

RANDOM: LDA SEED
        ASL A
        BCC randok
        EOR #$1D
randok: STA SEED
        RTS

; Into a sector with a squadron ($FD23): "ALERT  ENTERING GORGANITOR SECTOR",
; yellow / orange, 10 flips every 10th frame, standing; and voice 1 sweeping down
; from $50xx by $40, 8 times 30 frames ($0921).
SECALERT:
        LDA #<SECTX
        LDX #>SECTX
        LDY #$87
        STY MSGCOL
        LDY #$0A
        STY MSGRATE
        LDY #$0A
        JSR MSGSTAT
        LDA #$00
        STA SNDDIR
        LDA #$50
        STA SNDHI0
        LDA #$40
        LDX #$08
        LDY #$1E
        JMP SNDGO

SECTX:  .BYTE $40,$40,$40,$40,$41,$4C,$45,$52,$54,$40,$40,$45,$4E,$54,$45,$52,$49,$4E
        .BYTE $47,$40,$47,$4F,$52,$47,$41,$4E,$49,$54,$4F,$52,$40,$53,$45,$43,$54,$4F,$52,$FF

; The attackers drift back toward the middle of the view, 4 units per call:
; x $8832-$890E, y $885E-$88AE, depth $8640-$87E0 ($33B6; the original first
; returns while $BA or $FB is set). The carry going into the comparisons is
; whatever the previous instruction left, as in the original.
EDRIFT:  LDX #$04
        LDA #$40
        STA DM1
        LDA #$BF
        STA DM2
edr1:    LDA ENX,X
        SBC #$32
        LDA ENX+1,X
        SBC #$88
        BCS edr2
        LDA ENX,X
        ADC #$04
        STA ENX,X
        BCC edr1b
        INC ENX+1,X
edr1b:   JMP edr3
edr2:    LDA ENX,X
        SBC #$0E
        LDA ENX+1,X
        SBC #$89
        BCC edr3
        LDA ENX,X
        SBC #$04
        STA ENX,X
        BCS edr3
        DEC ENX+1,X
edr3:    LDA ENY,X
        SBC #$5E
        LDA ENY+1,X
        SBC #$88
        BCS edr4
        LDA ENY,X
        ADC #$04
        STA ENY,X
        BCC edr3b
        INC ENY+1,X
edr3b:   JMP edr5
edr4:    LDA ENY,X
        SBC #$AE
        LDA ENY+1,X
        SBC #$88
        BCC edr5
        LDA ENY,X
        SBC #$04
        STA ENY,X
        BCS edr5
        DEC ENY+1,X
edr5:    LDA ENZ,X
        SBC #$40
        LDA ENZ+1,X
        SBC #$86
        BCS edr6
        LDA ENZ,X
        ADC #$04
        STA ENZ,X
        BCC edr5b
        INC ENZ+1,X
edr5b:   JMP edr7
edr6:    LDA ENZ,X
        SBC #$E0
        LDA ENZ+1,X
        SBC #$87
        BCC edr7
        LDA ENZ,X
        SBC #$04
        STA ENZ,X
        BCS edr7
        DEC ENZ+1,X
edr7:    SEC
        ROR DM2
        CLC
        ROR DM1
        DEX
        DEX
        BMI edrret
        JMP edr1
edrret:  RTS

; A fighter -> its sprite ($2E36): hidden outside x $8751-$894F, y high byte $88
; and depth $86xx-$87xx; x bit 8 from bit 0 of the high byte; the shape from the
; depth ($2E86, type 1: $2F - depth/32, $20-$2F). X = fighter * 2.
PLACE:  TXA
        LSR A
        TAY
        SEC
        LDA #$50
        SBC ENX,X
        LDA #$87
        SBC ENX+1,X
        BCS plhide
        SEC
        LDA #$4F
        SBC ENX,X
        LDA #$89
        SBC ENX+1,X
        BCC plhide
        LDA ENX+1,X
        LSR A
        BCS pl1
        LDA EMSB
        AND ENMASK,Y
        JMP pl2
pl1:    LDA EMSB
        ORA ENBIT,Y
pl2:    STA EMSB
        LDA ENX,X
        STA ESH,X
        LDA ENY+1,X
        CMP #$88
        BNE plhide
        LDA ENY,X
        STA ESH+1,X
        LDA ENZ+1,X
        CMP #$86
        BCC plhide
        CMP #$88
        BCS plhide
        SEC             ; ($2E86) the shape from the depth
        LDA ENZ,X
        SBC #$00
        STA ZT
        LDA ENZ+1,X
        SBC #$86
        STA ZT+1
        LDA ZT
        LSR ZT+1
        ROR A
        LSR A
        LSR A
        LSR A
        LSR A
        STA ZT
        SEC
        LDA #$2F
        SBC ZT
        STA ESHP,Y
        LDA EVIS
        ORA ENBIT,Y
        STA EVIS
        RTS
plhide: LDA EVIS
        AND ENMASK,Y
        STA EVIS
        RTS

; Sprites 4-6 from the fighters' shadows (in the view, line 78).
SPRENEMY:
        LDA ESH
        STA $D008
        LDA ESH+1
        STA $D009
        LDA ESH+2
        STA $D00A
        LDA ESH+3
        STA $D00B
        LDA ESH+4
        STA $D00C
        LDA ESH+5
        STA $D00D
        LDA $D010
        AND #$8F
        ORA EMSB
        STA $D010
        LDA $D01C       ; type 1: single colour, not expanded, in front
        AND #$8F
        STA $D01C
        LDA $D01D
        AND #$8F
        STA $D01D
        LDA $D017
        AND #$8F
        STA $D017
        LDA $D01B       ; (behind the map's lines and icons while it is open)
        AND #$8F
        ORA MAPPRIO
        STA $D01B
        LDX #$02        ; pointers from the shapes ($20-$2F -> ENPTR)
spe1:   LDA ESHP,X
        SEC
        SBC #$20
        TAY
        LDA ENPTR,Y
        STA SPRPTR+4,X
        DEX
        BPL spe1
        LDA BLIPON      ; approaching: sprite 4 is the chosen group's blip
        BEQ spe2
        LDA BLSHP
        CLC
        ADC #BLPTR-76
        STA SPRPTR+4
spe2:   RTS

ENBIT:  .BYTE $10,$20,$40
ENMASK: .BYTE $EF,$DF,$BF
; sprite pointers of the fighter shapes $20-$2F: bitmap rows 0-2 ($6000-$63BF,
; behind the HUD text) hold 15, row 23 the last one (build.py places them)
ENPTR:  .BYTE $80,$81,$82,$83,$84,$85,$86,$87,$88,$89,$8A,$8B,$8C,$8D,$8E,$FD

; the fighters (original addresses in brackets)
ETYPE:  .BYTE 1         ; squadron type ($A5)
ALIVE:  .BYTE 0,0,0     ; ($5F-$61)
ENX:    .BYTE 0,0,0,0,0,0   ; x lo/hi per fighter ($16-$1B)
ENY:    .BYTE 0,0,0,0,0,0   ; y ($1C-$21)
ENZ:    .BYTE 0,0,0,0,0,0   ; depth ($22-$27)
SPX:    .BYTE 0,0,0,0,0,0   ; stream pointers: x ($04-$09)
SPY:    .BYTE 0,0,0,0,0,0   ; y ($0A-$0F)
SPZ:    .BYTE 0,0,0,0,0,0   ; depth ($10-$15)
SIDX:   .BYTE 0,0,0     ; position in the streams ($A6-$A8)
SCNT:   .BYTE 1,1,1     ; calls until the next step ($2F6A-$2F6C)
SPG:    .BYTE 0,0,0     ; stream pages left ($2F62-$2F64)
SBASE:  .BYTE 0,0,0     ; first page of the x, y, depth streams ($2F65-$2F67)
ESH:    .BYTE 0,0,0,0,0,0   ; sprite x / y of fighters 1-3 ($EF-$F4)
        .BYTE 0,0           ; (the enemy shot's, for HITBOX)
EMSB:   .BYTE 0         ; their x bit 8, bits 4-6 ($F7)
EVIS:   .BYTE 0         ; which are shown, bits 4-6 ($98)
ESHP:   .BYTE $20,$20,$20   ; their shapes, original numbering ($B4-$B6)
DM1:    .BYTE 0         ; ($33B3)
DM2:    .BYTE 0         ; ($33B4)
EFRM:   .BYTE 0
MX:     .BYTE 0
MIDX:   .BYTE 0
ATMP:   .BYTE 0         ; ($2B)
ZT:     .BYTE 0,0       ; ($67, $68)
T2B:    .BYTE 0         ; steering temporaries ($2B-$2E)
T2C:    .BYTE 0
T2D:    .BYTE 0
T2E:    .BYTE 0
SJ1:    .BYTE 0         ; the joystick byte, shifted per direction ($39BF)
SJ2:    .BYTE 0         ; and its copy for the next fighter ($39C0)
APPR: .BYTE 0           ; the approach phase ($E3)
INFRONT:.BYTE 0
LRDIG:  .BYTE 0,0,0,0
EHITS:  .BYTE 0,0,0     ; shots each fighter can still take ($C59A)
KILLS:  .BYTE 0,0       ; fighters destroyed ($F434)
HTY:    .BYTE 0
HITFL:  .BYTE 0         ; a hit flash runs ($DD, $1320)
FLC0:   .BYTE 0         ; ($1300)
FLN:    .BYTE 0         ; colour index ($1301)
FLD:    .BYTE 0         ; calls per colour ($1302)
FLASHC: .BYTE 0         ; the 3D view's background and border
EXPL:   .BYTE 0         ; an explosion runs ($160A)
EXPB:   .BYTE 0         ; it has started ($160B)
EXPX:   .BYTE 0         ; centre ($160C, $160D)
EXPY:   .BYTE 0
EXPN:   .BYTE 0         ; steps left ($160E)
EXPD:   .BYTE 0         ; passes between steps ($160F)
EXPC:   .BYTE 0         ; passes to the next step ($1610)
EDX:    .BYTE 0         ; drift per step ($1612, $1613)
EDY:    .BYTE 0
EVX0:   .BYTE 0         ; the fighter's last step ($1614, $1615)
EVY0:   .BYTE 0
EXPRUN: .BYTE 0         ; a step is under way (port)
EXPEND: .BYTE 0         ; the final erase is under way (port)
EXPI:   .BYTE 0         ; next point of the step (port)
EXLIM:  .BYTE 0         ; raster line where the slot's time ends (port)
EXSAV:  .BYTE 0
POX:    .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0         ; old points ($164B, $1665)
POY:    .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
PNX:    .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0         ; new points ($167F, $1699)
PNY:    .BYTE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
EXPL2:  .BYTE 0
EXPB2:  .BYTE 0
EXPX2:  .BYTE 0
EXPY2:  .BYTE 0
EXPN2:  .BYTE 0
EXPD2:  .BYTE 0
EXPC2:  .BYTE 0
EDX2:   .BYTE 0
EDY2:   .BYTE 0
EVX02:  .BYTE 0
EVY02:  .BYTE 0
EXPRUN2:.BYTE 0
EXPEND2:.BYTE 0
EXPI2:  .BYTE 0
POX2:   .BYTE 0,0,0,0,0,0,0,0,0,0,0,0
POY2:   .BYTE 0,0,0,0,0,0,0,0,0,0,0,0
PNX2:   .BYTE 0,0,0,0,0,0,0,0,0,0,0,0
PNY2:   .BYTE 0,0,0,0,0,0,0,0,0,0,0,0
OWNHIT: .BYTE 0         ; the flash is for our hit on a fighter ($1320)
DIFF:   .BYTE 0         ; difficulty 0-4 ($E0): 0 = skirmish (fire every 255 calls)
SYSHP:  .BYTE 0,0,0,0,0,0,0,0   ; the systems' hit points ($39-$40)
SHLD:   .BYTE 0         ; shields ($844F)
HITS:   .BYTE 0,0       ; hits taken ($F432)
SHIPLOST:.BYTE 0        ; the ship is lost ($8300)
SYSLAST:.BYTE $FF       ; the last system destroyed
EFCNT:  .BYTE 0
EFTHR:  .BYTE 1         ; ($C92E)
EFDLY:  .BYTE 1         ; ($C90A)
EFON:   .BYTE 0         ; ($C90C) an enemy shot is under way
EFD:    .BYTE 0         ; ($C90D)
EFE:    .BYTE 0         ; ($C90E)
EFVX:   .BYTE 0         ; ($C90F, $C910)
EFVY:   .BYTE 0
EFI:    .BYTE 0         ; ($C911) whose turn
EFY2:   .BYTE 0         ; ($C912)
EFBIT:  .BYTE $10       ; ($C92B)
EFX:    .BYTE 0         ; sprite 2 ($EB, $EC, $F7 bit 2, $B2, $98 bit 2)
EFY:    .BYTE 0
EFMSB:  .BYTE 0
EFSHP:  .BYTE $67
EFVIS:  .BYTE 0
ATMP2:  .BYTE 0
GFRM:   .BYTE 0         ; frame counter for the guns ($A0)
SQCOUNT:.BYTE 0         ; ships left in the sector ($0378,X)
GSIZE:  .BYTE 0,0,0     ; ships in each group ($C593)
GSEL:   .BYTE 0         ; the chosen group ($3731)
GLAST:  .BYTE 0         ; the last group ($381E)
CURG:   .BYTE 0         ; the group being fought ($C596)
APRUN:  .BYTE 0         ; the approach loop runs (port)
APDLY:  .BYTE 0         ; ($C598)
RELAYOUT:.BYTE 0        ; lay the groups out again ($C597)
LRMODE: .BYTE 0         ; the radar at long range ($D3 bit 7)
BLIPON: .BYTE 0         ; sprite 4 is the blip
BLSHP:  .BYTE $4C       ; ($3733)
BLDIR:  .BYTE 1         ; ($3732)
FLATCH: .BYTE 0         ; ($3735)
NUMT:   .BYTE 0         ; ($5B)
NUMCOL: .BYTE 1         ; ($3934)
TORPHIT:.BYTE 0         ; ($323D)
KLX:    .BYTE 0
LYN:    .BYTE 0
LYMASK: .BYTE 0
LYG:    .BYTE 0
LYSPR:  .BYTE 63,63,63,79,79    ; ($3D4C) spread by difficulty
LYBASE: .BYTE 102,102,102,85,85 ; ($3D52) base
DSX:    .BYTE 0
DSTL:   .BYTE 0         ; ($2B, $2C)
DSTH:   .BYTE 0
DT0:    .BYTE 0
DT1:    .BYTE 0
DSIGN:  .BYTE 0
LRPOS:  .BYTE 0
BCDH:   .BYTE 0         ; ($9C-$9E)
BCDT:   .BYTE 0
BCDO:   .BYTE 0
OFX:    .BYTE 0,0
OFY:    .BYTE 0,0
OFZ:    .BYTE 0,0
DGN:    .BYTE 0
RSLOT:  .BYTE 0         ; ($3051)
RBXN:   .BYTE 0         ; ($3052, $3055)
RBZN:   .BYTE 0
RBX:    .BYTE $30,$30,$30       ; the marks' places ($3058, $305B)
RBY:    .BYTE $A8,$A8,$A8
MKE:    .BYTE 0
MKY:    .BYTE 0
MKI:    .BYTE 0
MKX0:   .BYTE 0
MKY0:   .BYTE 0
RBON:   .BYTE 0,0,0     ; a mark is drawn (port)
LYACT:  .BYTE 0         ; laying out (port)
LYY:    .BYTE 0
NUMPEND:.BYTE 0         ; the number is due (port)
MAPSHOWN:.BYTE 0        ; the map is open over the 3D view (c128-game)
MAPPRIO:.BYTE 0         ; $70 while it is: the fighters behind it
VIEWBG: .BYTE 0         ; the 3D view's background: black, white with the map
WIPE:   .BYTE 0         ; rows of the 3D view still to wipe (c128-game: map open / close)
PTSX:   .BYTE 0         ; the map's mouse pointer, sprite 0 (c128-game: set by the map)
PTSXH:  .BYTE 0
PTSY:   .BYTE 0
PTON:   .BYTE 0
CURYS:  .BYTE 0
S7I:    .BYTE 2         ; ($118E)
SCANX:  .BYTE $60       ; the scan line's x ($9ECF)
APACC:  .BYTE 0,0       ; approach passes, 1/256ths (port)
APCNT:  .BYTE 0         ; ($89)
RXLO:   .BYTE $86       ; the radar's range ($307C, $3089, $30B7, $30C4)
RXHI:   .BYTE $8A
RZLO:   .BYTE $82
RZHI:   .BYTE $8A
CRAD2:  .BYTE 0
CMODE:  .BYTE 0
CR44:   .BYTE 0         ; the circle's working bytes ($44-$4A)
CR45:   .BYTE 0
CR46:   .BYTE 0
CR47:   .BYTE 0
CR48:   .BYTE 0
CR49:   .BYTE 0
CR4A:   .BYTE 0
SHD:    .BYTE 8         ; ($9ED2)
SHI:    .BYTE $0F       ; ($9ED4)
SHC:    .BYTE 0         ; ($9ED3)
SHN:    .BYTE 0
SHACT:  .BYTE 0         ; ($9EE5)
CRAD1:  .BYTE 0
CPEND:  .BYTE 0         ; circles of RADMODE still to draw (port)
CRUN:   .BYTE 0
CSN:    .BYTE 0
