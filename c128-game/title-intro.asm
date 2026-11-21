; The welcome ribbon (RIBTICK, started in the confirm), then the Starfleet briefing
; ($96AA-$99F2): the bar opens a line a frame (48 steps), the message types a glyph
; every second frame, holds, and closes. The raster handlers are in intro-core.asm.
INTROHOLDTIME = 239
INTROHOLDFLASH = 40

; The briefing's six rows are hidden text rows until the bar opens; they are made up
; in the confirm (BRIEFPREP), so that the title loop hands over to the raster
; handlers within the frame.
BRIEFPREP:             ; A = 0-5: the row's cells (and, for 0, the font)
        TAY
        BNE intro_prep
        JSR TITLEFONTRESTORE
        INY             ; (it leaves Y = $FF)
intro_prep:
        LDX INTROROWEND,Y
        LDY #39
intro_fill:
        LDA #$60
        STA INTROROW,X
        LDA #1
        STA $D878,X
        DEX
        DEY
        BPL intro_fill
        INX
        LDA #$61
        STA INTROROW,X
        LDA #$62
        STA INTROROW+39,X
        RTS
INTROROWEND: .BYTE 39,79,119,159,199,239

BRIEFRUN:
        LDA #0
        STA INTROARM    ; (INTROINDEX and INTROPHASE are the package image's)
        LDA #INTROBASE
        STA INTROSPLIT
        LDA #1
        STA INTROACTIVE
        JSR INTROIRQON
intro_frame:           ; twice a frame. At line 125 (below the bar, above the strip) the ribbon's row and
        LDA $D012      ; fine scroll, the bar and the message change, so the strip and the matrix fetch
        CMP #125       ; (also the page's, at the frame's end) see this frame's final row, as the
        BCS intro_frame ; original's IRQ at line 74 did. At line 243 the sprites and stars follow.
intro_vblank:
        LDA $D012
        CMP #125
        BCC intro_vblank
intro_work:
        LDA #$7F
        STA CIA1PA
        LDA CIA1PB
        TAY
        LDA #$BF
        STA CIA1PA
        TYA
        AND CIA1PA
        AND #$10
        BEQ intro_pressed
        STA INTROARM     ; release the selector's Fire before allowing a skip
        BNE intro_phase
intro_pressed:
        LDA INTROARM
        BEQ intro_phase
intro_finish:
        TYA              ; consume a held Space through the normal torpedo latch
        AND #$10
        BNE intro_quiet
        LDA #2
        STA TSPP
        JSR GSPACE
intro_quiet:
        JSR GVIEWCLEAR  ; (the briefing's raster handlers keep the picture up while the view clears)
        JSR TITLEMATBACK
        JSR INTRORESTORE
intro_sync:             ; the long clearing is over: the screen blanks at a frame's top
        BIT $D011
        BPL intro_sync
intro_syncwrap:
        BIT $D011
        BMI intro_syncwrap
        JSR INTROIRQOFF ; for the load and the map's first frame only
        LDA #0
        STA INTROACTIVE
        RTS
intro_phase:
        LDX INTROPHASE
        BEQ intro_welcome
        DEX
        BEQ intro_open
        DEX
        BEQ intro_type
        DEX
        BNE intro_close
        JMP intro_hold
intro_close:
        DEC INTROSPLIT
        JSR intro_blip
        LDA INTROSPLIT
        CMP #INTROBASE
        BNE intro_again
        LDA #0
        STA $D404
        BEQ intro_finish

intro_welcome:
        JSR RIBTICK
        LDA RIBON
        BNE intro_again
        INC INTROPHASE  ; the bar's first step comes with the ribbon's last
        JMP intro_open
intro_again:
        JSR ENGTICK     ; (the original's hum comes after the frame's other sounds)
intro_late:
        LDA $D012
        CMP #243
        BCC intro_late
        JSR title_sprites
        JSR title_stars
        JMP intro_frame

intro_open:
        INC INTROSPLIT
        JSR intro_blip
        LDA INTROSPLIT
        CMP #INTROEND
        BNE intro_again
        INC INTROPHASE  ; the first glyph comes with the bar's last step
        LDA #0
        STA $D404
        STA INTROINDEX
        LDA #1
        STA INTROCOUNT

intro_type:
        DEC INTROCOUNT
        BNE intro_again
        LDA #2
        STA INTROCOUNT
        LDX INTROINDEX
        LDA BRIEFTEXT,X
        CMP #$FF
        BEQ intro_typed
        STA INTROROW,X
        INC INTROINDEX
        CMP #$40
        BEQ intro_again
        LDA #$62
        LDX #2
        LDY #0
        JSR intro_tone
        JMP intro_again
intro_typed:
        INC INTROPHASE
        LDA #INTROHOLDTIME
        STA INTROCOUNT
        BNE intro_again

intro_hold:
        DEC INTROFLASH
        BNE intro_held
        LDA #INTROHOLDFLASH
        STA INTROFLASH
        LDA INTROFLASHINK    ; the last row flashes white and 15, the first time
        EOR #14              ; one frame after the message ended
        STA INTROFLASHINK
        LDX #38         ; (the side rules stay white)
intro_flash:
        STA $D878+200,X
        DEX
        BNE intro_flash
intro_held:
        DEC INTROCOUNT
        BEQ intro_holdend
        JMP intro_again
intro_holdend:
        INC INTROPHASE
        JMP intro_again

; The bar's step and a typed glyph: voice 1's triangle, in the original's order
; ($97BE and $9978): gate off, release, frequency low / high, pulse width, attack.
intro_blip:
        LDA #$82
        LDX #3
        LDY #1
intro_tone:
        PHA
        LDA #0
        STA $D404
        STA $D406
        STA $D400
        PLA
        STA $D401
        TYA
        BEQ intro_nopulse
        STY $D403
intro_nopulse:
        STX $D405
        LDA #$11
        STA $D404
        RTS

INTROPHASE: .BYTE 0
INTROCOUNT: .BYTE 0
INTROINDEX: .BYTE 0
INTROFLASH: .BYTE 1
INTROFLASHINK: .BYTE 1
BRIEFTEXT:
; BRIEFTEXTDATA
