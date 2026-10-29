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
        LDA #$0E        ; upper HUD: light blue border, dark gray background
        STA BORDER
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
        LDA #0
        STA BG
        LDA #77
        JSR WAITLN
        LDA #0
        STA BORDER
        LDA #78
        JSR WAITLN
        JSR SPRCROSS    ; the crosshair
        JSR FIREPH      ; the phasors, while the 3D view is drawn (the original runs
        LDA SHOTARM     ; $1424 in its interrupt and launches from its main loop,
        BEQ nolaunch    ; $2DFC; here the time until line 194 is free)
        JSR LAUNCH
nolaunch:
        LDA #194
        JSR WAITLN
        JSR SPRGUNS     ; sprites 0 and 3 become the two guns
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
        LDA #$05
        STA $D016
        LDA #$20
        STA $D018
        LDX #0          ; black below it: written as early as possible in line 242
        LDY #$08
w242:   LDA $D012
        CMP #242
        BCC w242
        STX BORDER
        STX BG
        STY $D016

        JSR INPUT       ; vertical blank: mouse, cursor, guns, then the star field
        JSR STARS       ; (the processor has all its time here, no tearing)
        LDA $D012       ; count frames whose work ran past line 56 (should stay 0)
        CMP #56
        BCC vbok
        CMP #251
        BCS vbok
        INC OVRUN
vbok:
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
        LDA $D010
        AND #$FC
        ORA XMSB
        LDX SHOTXH      ; sprite 1: the phasor shot
        BEQ sc2
        ORA #$02
sc2:    STA $D010
        LDA CURY
        STA $D001
        LDA #1
        STA $D027
        LDA SHOTSHP     ; shapes $67-$70 of the original are $36-$3F here
        SEC
        SBC #$31
        STA SPRPTR+1
        LDA SHOTX
        STA $D002
        LDA SHOTY
        STA $D003
        LDA SHOTVIS
        ASL A
        ORA #1
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
        ORA #$09
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
        LDA FRMC
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
nosh:   LDX #NSTARS-1
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
        LDY #1          ; one step per frame, two every fourth frame
        LDA FRMC
        AND #3
        BNE mtk
        INY
mtk:    STY NTICK
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

RANDOM: LDA SEED
        ASL A
        BCC randok
        EOR #$1D
randok: STA SEED
        RTS

; ---------------- input, cursor, guns ----------------
; Once per frame in the vertical blank. The 1351 (port 2) moves the crosshair, its
; left button fires; without a mouse the joystick moves it, as in the original.
INPUT:  JSR POTS
        LDA #$FF        ; port 2 lines (the keyboard columns are all off)
        STA CIA1PA
        LDA CIA1PA
        STA JRAW
        LDA #$FB        ; T (column 2, row 6) toggles target tracking (the animated crosshair)
        STA CIA1PA
        LDA CIA1PB
        AND #$40
        BNE tup
        LDA TPREV
        BNE tdone
        LDA #1
        STA TPREV
        LDA TRACK
        EOR #1
        STA TRACK
        JMP tdone
tup:    LDA #0
        STA TPREV
tdone:  LDA TRACK       ; tracking animation: $49, $4A, $4B every 16th frame
        BEQ tno
        INC FCNT
        LDA FCNT
        AND #$0F
        BNE tno
        LDA TRFRAME
        CLC
        ADC #1
        CMP #$34        ; the tracking frames $49-$4B of the original, now $31-$33
        BCC tfok
        LDA #$31
tfok:   STA TRFRAME
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
        LDA JOY         ; fire held (original $D0)
        AND #$10
        EOR #$10
        STA FIREHELD
        JSR CURSOR
        LDA CURX        ; crosshair sprite position
        CLC
        ADC #$2D
        STA XPOS
        LDA #0
        ROL A
        STA XMSB
        JSR GUNS
        RTS

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
; Holding fire arms a shot (FIREPH); the next pass launches it (LAUNCH): the line
; routine stores the path from a gun to the crosshair, and while fire is held the
; shot sprite walks along it, a step every few of 48 sub-ticks per frame, with the
; steps further apart each time (it slows down as it recedes) and a smaller shape
; every third step. Releasing fire stops the shot where it is, as in the original.
; js/test/run.js calls these routines and the original ones inside the C64 game
; with the same crosshair, guns and fire timing and compares the path and the
; shot sprite frame by frame.

FIREPH:                 ; per frame ($1424). The original first stops here when the
        LDA FIREHELD    ; phasor cannons are destroyed ($39), a torpedo flies, the map
        BEQ phret       ; is shown or ($E3); none of those exist in this program yet.
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
        STA FIREHELD
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
FIREHELD:.BYTE 0        ; fire button held ($D0)
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
