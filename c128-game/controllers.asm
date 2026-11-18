; Shared port-2 mode and POT history for the cockpit and Stellar Grid.
; A disconnected mouse reads $FF. With valid pots, a new press on Down, Left
; or Right is unambiguously a joystick. Mouse motion takes control again.
; Up and Fire share the 1351 button lines, so with valid stationary pots
; those two lines follow the selected device.
GPOTS:  LDA POTX
        CMP #$FF
        BEQ gp_absent
        LDX GPOTCONNECTED
        BMI gp_present
        BNE gp_external
        STA OLDX        ; first native sample: seed both axes without moving
        LDA POTY
        EOR #$FF
        STA OLDY
gp_external:
        LDA #$80
        STA GPOTCONNECTED
        JSR POTS
        LDA CIA1PA
        EOR #$FF
        AND #$0E
        STA GJOYDIR
        BNE gp_joy
        JMP gp_mouse
gp_present:
        JSR POTS
        LDA CIA1PA
        EOR #$FF
        AND #$0E
        CMP GJOYDIR
        BEQ gp_motion
        TAX
        EOR GJOYDIR
        STX GJOYDIR
        AND GJOYDIR
        BNE gp_joy
gp_motion:
        LDA MDX
        ORA MDY
        BNE gp_mouse
        LDX M_MPRES     ; stationary pots: keep the last active device
        BEQ gp_mode
gp_mouse:
        LDX #1
        BNE gp_mode
gp_absent:
        LDX #0
        STX GPOTCONNECTED
        STX GJOYDIR
        BEQ gp_zero
gp_joy: LDX #0
gp_zero:STX MDX
        STX MDY
gp_mode:STX MPRES
        CPX M_MPRES
        BEQ gp_done
        STX M_MPRES
        LDA #0          ; clear button history when the inputs change meaning
        STA RCNT
        STA PTON
        STA M_FIREPREV
        STA M_DELAY
        CPX #0
        BEQ gp_done
        LDA MAPSHOWN
        BEQ gp_done
GMAPCENTER:
        LDX M_CURX      ; pick up the mouse pointer at the joystick's last sector
        LDA M_VX,X
        CLC
        ADC #6
        STA M_MPX
        LDX M_CURY
        LDA M_YS,X
        CLC
        ADC #8
        STA M_MPY
gp_done:RTS

GMAPPOTS:
        JSR GPOTS
        LDA MDX
        STA M_MDX
        LDA MDY
        STA M_MDY
        RTS

; MAPKEY can run before that frame's POT sample. An unshared joystick line
; taking over must suppress the aliased mouse buttons immediately.
GMAPBUTTONS:
        LDA CIA1PA
        PHA
        ORA GJOYDIR     ; a new press has both its current and previous bits clear
        AND #$0E
        CMP #$0E
        BEQ gmb_current
        PLA
        ORA #$11
        RTS
gmb_current:
        PLA
        RTS

; The old BASIC exit saved CIA selections here. Both bytes reset with the
; cockpit's state. 1 means the browser seeded the axes, $80 regular sampling.
GPOTCONNECTED = SAVC2
GJOYDIR = SAVPA
