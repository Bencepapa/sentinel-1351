; Reuse only the retired decoder's 76 bytes. Existing labels do not move.
        * = MSUNPACK
ENDSHIPFLAG:
        STA SHIPLOST
ENDARM:
        PHA
        LDA #<ENDVIEW
        STA nov3+1
        LDA #>ENDVIEW
        STA nov3+2
        PLA
        RTS
ENDPLANETFLAG:
        STA M_DEAD,X
        CPX #4
        BEQ ENDARM
        RTS
ENDKILL:
        JSR SECKILL     ; any kill arms the poll for good (the original polls $F5B9
        PHP             ; every 64 loops): the last squadron may vanish later by an
        JSR ENDARM      ; attack, with no kill
        PLP
        RTS
ENDMSOFF:
        JSR MSOFF
ENDTRYWIN:
        PHP
        PHA
        TYA
        PHA
        LDY #59
ee_scan:LDA M_STATE,Y
        BEQ ee_next
        CMP #$FF
        BNE ee_done
ee_next:DEY
        BPL ee_scan
        JSR ENDARM
ee_done:PLA
        TAY
        PLA
        PLP
        RTS
ENDRETURN:
        PLA             ; discard the frame's abandoned JSR VIEWWORK/ENDVIEW return
        PLA
        JMP TITLERESET
ENDBASETALLY:
        JSR ENDONE      ; original recharge tally includes one full-meter overflow
        JMP MRGLYPHBACK
ENDEVENTEND:
