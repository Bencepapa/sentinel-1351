; Sentinel (Synapse, 1984) - Commodore 1351 mouse patch
;
; Mouse goes in control port 2 (same port as the joystick).
; - Mouse moves the crosshair directly.
; - While flying, a crosshair away from the center acts like a joystick
;   held in that direction, so the ship keeps turning without having to
;   keep moving the mouse (small dead zone around the center).
; - Left button  = fire.
; - Right button = C= key (open the map).
; - Both buttons = SPACE (proton torpedo); the laser is held back meanwhile.
; - Mouse untouched for a while -> crosshair glides back to center, like the
;   original joystick behaviour.
; - On the sector map the mouse moves a pointer (the crosshair) over the
;   grid; the map's cursor box jumps to the sector under it, fire selects it
;   (enhancement: the original only steps the box a sector at a time).
; - Outside the crosshair view (other screens) mouse motion is turned into
;   joystick directions, so every screen stays usable.
; - No mouse (X pot stays $FF) -> original joystick behaviour.
;
; Hooks into the original game:
;   $0B43  JSR POTRD          (raster IRQ, every frame, before keyboard scan)
;   $0BB0  JSR JOYIN          (per-frame port read, replaces $B2D8)
;   $0D19  JSR CURSOR         (crosshair update, replaces $B30C)
;   $FE30/$FE68/$FEA0  keyboard scan leaves $DC00=$BF (port 2 pots -> SID)
;   $864A  difficulty menu reads JOY instead of $DC00 (sees mouse motion)
;   $FBCE  JSR MSEL           (map loop: mouse pointer, replaces JSR $21C8)
;   $129B  JSR MPY            (crosshair routine: its Y on the map screen)
;   $0D12  JSR MPY0 / JMP $0D1C  (the line-59 split's sprite 0 Y off the cockpit)
;   $0100-$01D7  extra code (dead loader leftovers in the stack page; the game's
;                stack stays above $01E6, measured over title, menus and play)
;   $FC9D  JSR JUMPCLR        (after a jump: the map's boxes off the bitmap)
;   $53C0  the map pointer's shape (+), sprite shape $4F, unused by the game
;   old routine area $B2D8-$B399 is reused for the new code; its
;   self-modified operands live in YMAX/YMIN/YCEN/DDLY now

; ---- game variables ----
JOY     = $96           ; joystick bits (active low) used all over the game
FIREFL  = $97
ATTRACT = $88
VIEW    = $B8           ; 0 = cockpit view with crosshair
CURX    = $B2D7         ; crosshair X (sprite X - $2D)
CURY    = $120A         ; crosshair Y (sprite Y)
JTIMER  = $B2D6
DTIMER  = $B2D5         ; idle-drift countdown
XLOCK   = $8420

DZ      = 12            ; steering dead zone around the center (pixels)
MAPDLY  = 5             ; frames the right button must be held alone for the map
NDZ     = 244           ; -DZ

; ---- patch tables/variables ($0334-$033B and $03F6-$03FF, unused) ----
; per axis (X index 0 = horizontal, 2 = vertical)
CEN     = $0334         ; center:            $7F, YCEN
PMSK    = $0335         ; dir if right/below: RIGHT, UP (joystick up = crosshair down)
YCEN    = $0336
NMSK    = $0338         ; dir if left/above:  LEFT, DOWN
DS      = $0339         ; current steering mask per axis
BND     = $03F6         ; clamp bounds: X lo, X hi, Y lo, Y hi
YMIN    = $03F8
YMAX    = $03F9
OPOTX   = $03FC
OPOTY   = $03FD
MDX     = $03FE         ; signed motion this frame, +right
MDY     = $03FF         ; signed motion this frame, +back
; zero page bytes never referenced by the game
MFLAG   = $4B           ; bit7 set = no mouse
CD      = $6F
DDLY    = $ED
OLDV    = $AB
PX      = $8A           ; map pointer: x - 17 (0-119, multicolour pixels), never
PY      = $8B           ; referenced by the game; y - 35 (0-95)
MFRM    = $8D           ; frame of the last pointer move
PSY     = $8E           ; pointer sprite Y for the crosshair routine

; =====================================================================
        * = $02A2
; per-frame port read (called from the IRQ at $0BB0)
; the keyboard scan just before this left $DC00=$BF (port 2 selected)
JOYIN:  DEC JTIMER
        BNE jfret
        INC JTIMER
        LDA #$FF
        LDY ATTRACT
        BNE jset
        LDA $DC00
        BIT MFLAG
        BMI jset
        JSR MBTN        ; mouse buttons -> keys
        LDY VIEW
        BNE jmot
        AND DS          ; cockpit: steer by crosshair offset
        AND DS+2
        BNE jset        ; A always has bit 7 set
jmot:   JSR MSYN        ; elsewhere: mouse motion -> joystick directions
jset:   STA JOY
        LDY #0
        AND #$10
        BNE jfire
        INY
        LDA $B8
        BNE jfire
        STY $D0
jfire:  STY FIREFL
jfret:  RTS
; called from the raster IRQ instead of LDA $A0 / AND #$03 (flags kept)
POTRD:  LDX #1
potl:   LDA $D419,X
        EOR PINV,X      ; Y pot inverted: MDY comes out +back
        LDY OPOTX,X
        JSR MOVCHK
        STA MDX,X
        TYA
        STA OPOTX,X
        DEX
        BPL potl
        CPY #$FF        ; X pot stuck at $FF -> nothing plugged in
        ROR MFLAG
        LDA $A0
        AND #$03
        RTS
PINV:   .BYTE $00,$FF
ENDA2:

; =====================================================================
        * = $B2D8
; crosshair update (only called while the crosshair is shown)
CURSOR: BIT MFLAG
        BMI cjoy
        JMP MCUR
cjoy:   LDA JOY
        AND #$1F
        CMP #$1F
        BNE cjact
IDLE:   LDA XLOCK
        BNE cret
        DEC DTIMER
        BEQ DRIFT
cret:   RTS
; idle: glide toward center one step per frame (original behaviour)
DRIFT:  LDA #1
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
; joystick: X +-3, Y +-2 per frame (up moves the crosshair down)
cjact:  LDY DDLY
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
        BNE CAPPLY
; X = dx, Y = dy (signed); also refreshes the steering mask DS
CAPPLY: STY CD
        LDA XLOCK
        BNE capy
        STX OLDV
        LDA CURX
        LDX #0
        JSR CLAMP
        STA CURX
capy:   LDA CD
        STA OLDV
        LDA CURY
        LDX #2
        JSR CLAMP
        STA CURY
        RTS

; CBM 1351 delta: A=new pot, Y=old -> A=signed delta, Y=value to keep
; (same result as the Commodore driver: 7-bit difference / 2, +-1 jitter ignored)
MOVCHK: STY OLDV
        TAY
        SEC
        SBC OLDV
        ASL A           ; 7-bit difference -> signed, x2
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
; A = joystick bits; clears the directions the mouse moved in this frame
MSYN:   LDY MDY
        BEQ jsx
        BMI jsu
        AND #$FD        ; back = DOWN
        .BYTE $2C
jsu:    AND #$FE        ; forward = UP
jsx:    LDY MDX
        BEQ jsr
        BMI jsl
        AND #$F7
        .BYTE $2C
jsl:    AND #$FB
jsr:    RTS
; the interrupt's line-59 split hides sprite 0 off the cockpit ($0D12): with the
; map pointer it shows it at the pointer's Y instead (enhancement)
MPY0:   LDA #0
        JSR MPY
        STA $D001
        RTS
ENDB3:

; =====================================================================
        * = $03B4
; A = A + OLDV (signed), clamped to BND+X .. BND+1+X, then falls into SIDE
CLAMP:  LDY OLDV
        BMI clneg
        CLC
        ADC OLDV
        BCS clhi
        CMP BND+1,X
        BCC SIDE
clhi:   LDA BND+1,X
        BCS SIDE
clneg:  CLC
        ADC OLDV
        BCC cllo
        CMP BND,X
        BCS SIDE
cllo:   LDA BND,X
; A = position on axis X: set DS,X to the joystick direction it stands for
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
MHI:    .BYTE 119,95    ; (here: JUMPCLR needs the room at the end of $0100)
RCNT:   .BYTE $00

ENDC3:

; =====================================================================
        * = $0100
; mouse crosshair: follow the mouse; when it is left alone (no motion, no
; fire) run the original idle countdown and glide back to center
MCUR:   LDA JOY
        AND #$10
        EOR #$10        ; nonzero while firing
        ORA MDX
        ORA MDY
        BNE mmove
        JMP IDLE
mmove:  LDY DDLY
        STY DTIMER
        LDX MDX
        LDY MDY         ; +back: forward moves the crosshair up
        JMP CAPPLY

; A = port 2 bits -> returns them with the right button masked off
;   right alone (held MAPDLY frames) -> C= key, opens the map
;   both buttons                     -> SPACE, proton torpedo (no laser)
MBTN:   TAX
        AND #$11
        BEQ mboth
        CMP #$10        ; right only?
        BNE mrel
        BIT RCNT
        BMI mdone       ; both were pressed: wait for release
        INC RCNT
        LDA RCNT
        CMP #MAPDLY
        BCC mdone
        LDA #$DF        ; C= as the keyboard scan reports it
        STA $FDEC
        BNE mdone
mboth:  LDA #$EF        ; SPACE as the keyboard scan reports it
        STA $FDE5
        STA RCNT        ; negative: no map until the right button is released
        TXA
        ORA #$10        ; hold the laser back
        TAX
        BNE mdone
mrel:   LDA #0
        STA RCNT
mdone:  TXA
        ORA #$01        ; right mouse button is wired to UP
        RTS

; ---- map pointer (enhancement) ----
; map loop, every pass (replaces JSR $21C8): with a mouse the pointer moves once a
; frame by the mouse motion; the box goes to the sector under it ($2213 draws it)
MSEL:   BIT MFLAG
        BMI msj
        LDA $B077       ; the map is drawn ($21C8's own test)
        ORA $B078
        BEQ msr
        LDA $A0
        CMP MFRM
        BEQ mscell
        STA MFRM
        LDX #1
msl:    LDA PX,X
        CLC
        ADC MDX,X
        CMP #$C0        ; below 0
        BCS mslo
        CMP MHI,X
        BCC msst
        LDA MHI,X
        .BYTE $2C
mslo:   LDA #0
msst:   STA PX,X
        DEX
        BPL msl
        LDA PX          ; the crosshair is the pointer: X = 2 * (PX + 17) - 33
        ASL A
        ORA #1
        STA CURX
        LDA PY
        ADC #78         ; sprite Y = PY + 35 + 50 - 7 (C clear)
        STA PSY         ; (sprite 0 stays on in $98 on the map: only its Y hides it)
mscell: LDA PX          ; column (PX / 12), row (PY / 16)
        LDX #$FF
        SEC
msc:    INX
        SBC #12
        BCS msc
        LDA PY
        LSR A
        LSR A
        LSR A
        LSR A
        TAY
        CPX $20E2
        BNE msm
        CPY $20E1
        BEQ msr
msm:    JMP $2213
msj:    JMP $21C8
msr:    RTS
; crosshair routine: A = its Y; on another screen the pointer's Y while the map
; loop has moved it in the last 32 frames (it does not run every frame), else 0
; While shown, the pointer's shape is a + (sprite shape $4F at $53C0, unused by
; the game): the line-59 call (MPY0) sets the pointer shadow $B0 just before the
; interrupt copies it to the sprite pointers (line 76).
MPY:    LDY VIEW
        BEQ mpr
        LDA $A0
        SEC
        SBC MFRM
        CMP #32
        LDA PSY
        BCC mpp
        LDA $A0         ; hidden: keep MFRM 64 frames ahead, so the 8-bit frame
        ADC #63         ; difference never comes back under 32 (C set)
        STA MFRM
        LDA #0
        RTS
mpp:    LDY #$4F
        STY $B0
mpr:    RTS
; a jump from the map (fix of a bug in the original): the hyperspace erases the grid
; with $EEE6, which keeps pixel value 2, and only the map's other exit clears the
; bitmap ($FC4E). The cursor boxes stayed: black, unseen until a white flash, and
; stars cannot cross them. Clear the same area here.
JUMPCLR:JSR $BAB0
        JMP $0D81
END01:
