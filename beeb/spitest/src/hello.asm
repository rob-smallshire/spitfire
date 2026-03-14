; Simple Hello World test
; Verifies build/transfer/execution pipeline

ORG &1900

OSWRCH = &FFEE
OSNEWL = &FFE7

.start
    LDX #0
.loop
    LDA message, X
    BEQ done
    JSR OSWRCH
    INX
    BNE loop
.done
    JSR OSNEWL
    RTS

.message
    EQUS "Hello from SPItFIRE!"
    EQUB 0

.end

SAVE "HELLO", start, end
