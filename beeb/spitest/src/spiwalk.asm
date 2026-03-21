; SPItFIRE Decoder Walk Test
; Cycles through all 8 decoder addresses slowly
; Use with LED board to verify 74HC138 wiring

ORG &1900

; VIA registers
VIA_BASE = &FE60
IORB = VIA_BASE + &00
DDRB = VIA_BASE + &02

; Port B bit assignments
SEL_A0   = %00000100        ; PB2 - decoder A0
SEL_A1   = %00001000        ; PB3 - decoder A1
SEL_A2   = %00010000        ; PB4 - decoder A2
SEL_MASK = %00011100        ; All decoder bits (PB2-PB4)

; Inverted mask
NOT_SEL  = %11100011        ; Clear decoder bits

; OS calls
OSWRCH = &FFEE
OSNEWL = &FFE7
OSBYTE = &FFF4

; Zero page
current  = &70              ; Current device number (0-7)
delay_lo = &71
delay_mid = &72
delay_hi = &73

.start
    JSR init_via

    ; Print intro
    LDX #0
.print_intro
    LDA intro_msg, X
    BEQ main_loop
    JSR OSWRCH
    INX
    BNE print_intro

.main_loop
    LDA #0
    STA current

.device_loop
    ; Print current device number
    LDA current
    ORA #'0'
    JSR OSWRCH
    LDA #' '
    JSR OSWRCH

    ; Set decoder address
    ; Device number in 'current' needs to be shifted left 2 bits
    ; to align with PB2-PB4
    LDA current
    ASL A
    ASL A                   ; Now in bits 2-4 position
    STA delay_lo            ; Temp storage

    LDA IORB
    AND #NOT_SEL            ; Clear PB2-PB4
    ORA delay_lo            ; Set new address
    STA IORB

    ; Delay ~0.5 second (adjust as needed)
    JSR long_delay

    ; Next device
    INC current
    LDA current
    CMP #8
    BNE device_loop

    ; Newline after 0-7 cycle
    JSR OSNEWL

    ; Check for Escape
    BIT &FF
    BMI done

    JMP main_loop

.done
    ; Clear Escape condition
    LDA #&7E
    JSR OSBYTE

    ; Deselect all (device 0)
    LDA IORB
    AND #NOT_SEL
    STA IORB

    JSR OSNEWL
    RTS

; Initialize VIA
.init_via
    ; Set PB2-4 (decoder) as outputs
    ; Don't touch other bits
    LDA DDRB
    ORA #SEL_MASK
    STA DDRB

    ; Start with device 0 (all decoder bits low)
    LDA IORB
    AND #NOT_SEL
    STA IORB

    RTS

; Long delay - approximately 0.5 seconds at 2MHz
; Nested loop: outer * middle * inner * cycles
.long_delay
    LDA #4                  ; Outer loop
    STA delay_hi
.delay_outer
    LDA #0                  ; Middle loop (256 iterations)
    STA delay_mid
.delay_middle
    LDA #0                  ; Inner loop (256 iterations)
    STA delay_lo
.delay_inner
    NOP
    NOP
    NOP
    NOP
    DEC delay_lo
    BNE delay_inner
    DEC delay_mid
    BNE delay_middle
    DEC delay_hi
    BNE delay_outer
    RTS

.intro_msg
    EQUS "74HC138 Decoder Walk Test", 13, 10
    EQUS "Cycling 0-7, Escape to stop", 13, 10, 10
    EQUS "A2 A1 A0 (PB4 PB3 PB2)", 13, 10, 0

.end

SAVE "SPIWALK", start, end
