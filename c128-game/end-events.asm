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
        JSR SECKILL
        JMP ENDTRYWIN
ENDMSOFF:
        JSR MSOFF
ENDTRYWIN:
        PHP
        PHA
        TXA
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
        TAX
        PLA
        PLP
        RTS
ENDRETURN:
        PLA             ; discard the frame's abandoned JSR VIEWWORK/ENDVIEW return
        PLA
        JMP frame
ENDBASETALLY:
        JSR ENDONE      ; original recharge tally includes one full-meter overflow
        JMP MRGLYPHBACK
ENDEVENTEND:
