; Sentinel cockpit for the native C128 (VIC-IIe, 40 columns).
;
; The picture is built the way the original does it: the raster is polled and the
; video mode, border and background colours are switched at fixed lines (see
; c128-gui/README.md, "Raster schedule"): a text strip with the HUD on top, the
; multicolor bitmap for the 3D view and the cockpit art, a text strip at the bottom.
; The 3D view is a star field. The crosshair (sprite 0, shape $7D) follows the
; 1351 mouse or the joystick in port 2 with the logic of the original mouse patch;
; the two guns (sprites 0 and 3, shapes $7E / $7F, shown below the 3D view) follow it
; with the original's gun routine ($9568).
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
        AND #$FE
        ORA XMSB
        STA $D010
        LDA CURY
        STA $D001
        LDA #1
        STA $D027
        LDA #1
        STA VICENA
        RTS

; Below the 3D view the same two slots show the gun shapes (original $120B-$126F):
; sprite 0 = left gun $7E, sprite 3 = right gun $7F, both twice as wide, behind the
; bitmap, gray, and one of them red while firing.
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
        LDY FIRING
        BEQ sg3
        LDY FLIP
        BNE sg2
        LDA #2
        JMP sg3
sg2:    LDX #2
sg3:    STA $D027
        STX $D02A
        LDA $D01D
        ORA #$09
        STA $D01D
        LDA #$09
        STA VICENA
        RTS

; ---------------- the star field ----------------
; The stars drift away from the vanishing point, which follows the crosshair
; (the point the ship is heading for), faster the farther out they are.
STARS:  LDA CURX        ; vanishing point in bitmap pixels
        CLC
        ADC #33
        ROR A
        STA VPX
        LDA CURY
        SEC
        SBC #43
        STA VPY
        LDX #NSTARS-1
stl:    JSR ERASESTAR
        JSR MOVESTAR
        JSR PLOTSTAR
        DEX
        BPL stl
        RTS

NEWSTAR:JSR RANDOM      ; X = star: anywhere in the 3D view (x 2-157, y 26-141)
        AND #$7F
        STA TMPS
        JSR RANDOM
        AND #$1F
        CLC
        ADC TMPS
        ADC #2
        CMP #158
        BCC nsx
        SBC #40
nsx:    STA STARX,X
        JSR RANDOM
        AND #$7F
        CLC
        ADC #26
        CMP #142
        BCC nsy
        SBC #64
nsy:    STA STARY,X
        RTS

MOVESTAR:
        LDA STARX,X     ; x: step away from VPX, 1 + distance/16 pixels
        SEC
        SBC VPX
        BCS mxp
        EOR #$FF
        CLC
        ADC #1
        LSR A
        LSR A
        LSR A
        LSR A
        CLC
        ADC #1
        STA TMPS
        LDA STARX,X
        SEC
        SBC TMPS
        BCC msnew
        CMP #2
        BCC msnew
        JMP mxs
mxp:    LSR A
        LSR A
        LSR A
        LSR A
        CLC
        ADC #1
        CLC
        ADC STARX,X
        CMP #158
        BCS msnew
mxs:    STA STARX,X
        LDA STARY,X     ; y: the same, away from VPY
        SEC
        SBC VPY
        BCS myp
        EOR #$FF
        CLC
        ADC #1
        LSR A
        LSR A
        LSR A
        LSR A
        CLC
        ADC #1
        STA TMPS
        LDA STARY,X
        SEC
        SBC TMPS
        BCC msnew
        CMP #26
        BCC msnew
        JMP mys
myp:    LSR A
        LSR A
        LSR A
        LSR A
        CLC
        ADC #1
        CLC
        ADC STARY,X
        CMP #142
        BCS msnew
mys:    STA STARY,X
        RTS
msnew:  JMP NEWSTAR

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
        LDA JOY         ; fire flag for the guns
        AND #$10
        EOR #$10
        STA FIRING
        BEQ ifx
        INC FCNT2
        LDA FCNT2
        AND #$03
        BNE ifx
        LDA FLIP
        EOR #1
        STA FLIP
ifx:    JSR CURSOR
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
FIRING: .BYTE 0
FLIP:   .BYTE 0
FCNT:   .BYTE 0
FCNT2:  .BYTE 0
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
VPX:    .BYTE 80
VPY:    .BYTE 84
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
