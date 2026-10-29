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
        JSR NEWWAVE     ; a type-1 squadron wave
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
        LDA FLASHC      ; black, or the colour of a hit flash ($0B26, $0A4D)
        STA BG
        LDA #77
        JSR WAITLN
        LDA FLASHC
        STA BORDER
        LDA #78
        JSR WAITLN
        JSR SPRCROSS    ; the crosshair
        JSR FIREPH      ; the phasors, while the 3D view is drawn (the original runs
        LDA SHOTARM     ; $1424 in its interrupt and launches from its main loop,
        BEQ nolaunch    ; $2DFC; here the time until line 194 is free)
        JSR LAUNCH
nolaunch:
        JSR SWEEPSND    ; the phasor sound is swept 6 times a frame while a shot
        JSR SWEEPSND    ; flies: once in $1424, 3 times after it ($0C3B-$0C41),
        JSR SWEEPSND    ; at line 194 ($0C60) and at line 233 ($0CBA)
        LDA #182        ; the explosions use what is left of the 3D view's time
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
        LDA #$05
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

        JSR INPUT       ; vertical blank: mouse, cursor, guns (at 1 MHz: lines
        LDA #251        ; 242-250 are still in the display window)
        JSR WAITLN
        LDA FAST        ; 2 MHz in the border, lines 251-47: the VIC-IIe fetches
        ORA #$01        ; nothing there (sprites are off, no bad lines), so the
        STA FAST        ; processor gets twice the time (I/O accesses stay 1 MHz)
        JSR STARS       ; the star field
        JSR STEER       ; steering ($39C1; the original's comes after the movers)
        JSR EFRAME      ; enemy fire ($C947)
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
        LDA SHOTSHP     ; shapes $67-$70 are pointers $F3-$FC here
        CLC
        ADC #$8C        ; SHOTPTR - $67
        STA SPRPTR+1
        JSR SPRENEMY    ; sprites 4-6: the fighters
        LDA SHOTX
        STA $D002
        LDA SHOTY
        STA $D003
        LDA EFX         ; sprite 2: the enemy shot
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
        LDA SHOTVIS
        ASL A
        ORA #1
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
        ORA #$09
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
        LDA FIREFLAG    ; phasor cannons are destroyed ($39), a torpedo flies, the map
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
        * = $8C00

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
        LDA TARGETS     ; the HUD's TARGETS count: refilled when it runs low (no
        CMP #$73        ; squadrons yet)
        BCS nw1
        LDA #$79
        STA TARGETS
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
FIGHT:  INC EFRM
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
        JSR EXPTICK
        JSR EXPTICK2
        LDA EFRM        ; the hit flash, every other frame ($0C90)
        AND #$01
        BNE fg3
        JSR FLASH
fg3:    LDA ALIVE       ; a wave wiped out: once its explosion is over, the next
        ORA ALIVE+1     ; one comes (the squadron and wave bookkeeping of the
        ORA ALIVE+2     ; original, $3CD6-$3D4B, comes with the approach phase)
        ORA EXPL
        BNE fg4
        JSR NEWWAVE
fg4:    RTS

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

; ---------------- hits and explosions ----------------
; The shot against the fighters ($3244 / $324C), once a frame. During the last 10
; points of its path a shot hits a fighter shown within 12 pixels across and 10
; down of it (the original compares the low bytes of the sprite x only). A fighter
; takes ETYPE shots (type 1: one). A hit that does not destroy it ends the shot.
SHOTHIT:LDA HITWIN      ; ($1616)
        BNE hx0
        RTS
hx0:    LDX #$00        ; fighter 0-2 = sprites 4-6 (the original's X = 2-4)
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

KILL:   DEC TARGETS     ; ($3CC4) one target less on the HUD, one more kill
        INC KILLS
        BNE kl1
        INC KILLS+1
kl1:    RTS

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
        RTS
fl3:    LDA OWNHIT      ; ($137D) our shot hit: $130A, the ship was hit: $1303
        BEQ fl4
        LDA FLTAB,X
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
        BNE ex0
        RTS
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
        BNE qex0
        RTS
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
        LDA $D01B
        AND #$8F
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
        RTS

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
DIFF:   .BYTE 1         ; difficulty 0-4 ($E0): 1 = assault
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
