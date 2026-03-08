; SPItFIRE SPI Test Program
; Minimal test: clock 8 bits, receive response, print it
;
; Uses VIA shift register mode 2 for receive (same as MMFS)

ORG &1900

; VIA registers (User VIA on Master Compact)
VIA_BASE = &FE60
IORB = VIA_BASE + &00       ; Port B I/O
DDRB = VIA_BASE + &02       ; Port B data direction
SR   = VIA_BASE + &0A       ; Shift register
ACR  = VIA_BASE + &0B       ; Auxiliary control register
IFR  = VIA_BASE + &0D       ; Interrupt flag register

; Port B bit assignments
MOSI = %00000001            ; PB0
SCK  = %00000010            ; PB1
SS   = %00000100            ; PB2

; Inverted masks for AND operations
NOT_SS   = %11111011
NOT_SCK  = %11111101
NOT_MOSI = %11111110

; OS calls
OSWRCH = &FFEE
OSNEWL = &FFE7

.start
    JSR init_via

    ; Print intro
    LDX #0
.print_intro
    LDA intro_msg, X
    BEQ do_test
    JSR OSWRCH
    INX
    BNE print_intro

.do_test
    ; Assert SS (drive low)
    LDA IORB
    AND #NOT_SS
    STA IORB

    ; Do SPI transfer - sends &FF, receives response
    JSR spi_read_byte
    STA result

    ; Deassert SS (drive high)
    LDA IORB
    ORA #SS
    STA IORB

    ; Print result
    LDX #0
.print_result_msg
    LDA result_msg, X
    BEQ print_hex
    JSR OSWRCH
    INX
    BNE print_result_msg

.print_hex
    LDA result
    JSR print_hex_byte
    JSR OSNEWL

    RTS

; Initialise VIA for SPI
.init_via
    ; Set PB0 (MOSI), PB1 (SCK), PB2 (SS) as outputs
    LDA DDRB
    ORA #MOSI OR SCK OR SS
    STA DDRB

    ; Set idle state: SS high, SCK high, MOSI high
    LDA IORB
    ORA #MOSI OR SCK OR SS
    STA IORB

    ; Start in shift register mode 0 (disabled)
    LDA ACR
    AND #%11100011          ; Clear SR mode bits
    STA ACR

    RTS

; Read a byte via SPI using shift register mode 2
; MOSI is held high (&FF sent), returns received byte in A
; Based on MMFS approach
.spi_read_byte
    ; Ensure MOSI and SCK high before entering SR mode
    LDA IORB
    ORA #MOSI OR SCK
    STA IORB

    ; Enter shift register mode 2 (shift in under phi2)
    ; PB1 becomes input (floats, but CB1 wire keeps it connected)
    LDA DDRB
    AND #NOT_SCK           ; PB1 as input
    STA DDRB

    LDA ACR
    AND #%11100011          ; Clear SR mode bits
    ORA #%00001000          ; Mode 2: shift in under phi2/CB1
    STA ACR

    ; Start the shift by reading SR
    LDA SR

    ; Wait for shift complete (IFR bit 2)
    LDA #%00000100
.wait_sr
    BIT IFR
    BEQ wait_sr

    ; Return to mode 0 before reading (avoids extra byte)
    LDA ACR
    AND #%11100011
    STA ACR

    ; PB1 back to output
    LDA DDRB
    ORA #SCK
    STA DDRB

    ; Read the received byte
    LDA SR

    RTS

; Print A as two hex digits
.print_hex_byte
    PHA
    LSR A
    LSR A
    LSR A
    LSR A
    JSR print_hex_nybble
    PLA
    AND #&0F
    ; Fall through

.print_hex_nybble
    CMP #10
    BCC digit
    ADC #6                  ; Adjust for A-F (carry is set)
.digit
    ADC #&30                ; Convert to ASCII
    JMP OSWRCH

.intro_msg
    EQUS "SPItFIRE SPI Test", 13, 10
    EQUS "Expecting &AA from AVR", 13, 10, 0

.result_msg
    EQUS "Received: &", 0

.result
    EQUB 0

.end

SAVE "SPITEST", start, end
