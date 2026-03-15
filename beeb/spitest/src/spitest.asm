; SPItFIRE SPI Soak Test
; Sends incrementing bytes, verifies AVR returns byte XOR &55
; Displays running count of good/bad transfers

ORG &1900

; VIA registers (User VIA on Master Compact)
VIA_BASE = &FE60
IORB = VIA_BASE + &00       ; Port B I/O
DDRB = VIA_BASE + &02       ; Port B data direction
SR   = VIA_BASE + &0A       ; Shift register
ACR  = VIA_BASE + &0B       ; Auxiliary control register
PCR  = VIA_BASE + &0C       ; Peripheral control register
IFR  = VIA_BASE + &0D       ; Interrupt flag register

; Port B bit assignments
MOSI = %00000001            ; PB0
SCK  = %00000010            ; PB1
SS   = %00000100            ; PB2

; Inverted masks for AND operations
NOT_SS   = %11111011
NOT_SCK  = %11111101

; XOR pattern (must match AVR)
XOR_PATTERN = &55

; OS calls
OSWRCH = &FFEE
OSNEWL = &FFE7
OSBYTE = &FFF4

; Zero page variables
send_byte = &70
expected  = &71
received  = &72
good_lo   = &73             ; 24-bit good counter
good_mid  = &74
good_hi   = &75
bad_lo    = &76             ; 24-bit bad counter
bad_mid   = &77
bad_hi    = &78
spi_temp  = &79             ; Temp for spi_transfer

.start
    JSR init_via
    JSR init_counters

    ; Print intro
    LDX #0
.print_intro
    LDA intro_msg, X
    BEQ main_loop
    JSR OSWRCH
    INX
    BNE print_intro

.main_loop
    ; Calculate expected response
    LDA send_byte
    EOR #XOR_PATTERN
    STA expected

    ; Assert SS
    LDA IORB
    AND #NOT_SS
    STA IORB

    ; Small delay for AVR
    NOP
    NOP
    NOP
    NOP

    ; First transfer: send the test byte (ignore response - it's stale)
    LDA send_byte
    JSR spi_transfer

    ; Second transfer: send dummy, receive actual response
    LDA #&FF
    JSR spi_transfer
    STA received

    ; Deassert SS
    LDA IORB
    ORA #SS
    STA IORB

    ; Compare and update counters
    LDA received
    CMP expected
    BNE bad_transfer

    ; Good transfer - increment 16-bit good counter
    INC good_lo
    BNE print_result
    INC good_hi
    JMP print_result

.bad_transfer
    ; Bad transfer - increment 16-bit bad counter
    INC bad_lo
    BNE print_result
    INC bad_hi

.print_result
    ; Print: sent expected received good bad
    LDA send_byte
    JSR print_hex_byte
    LDA #' '
    JSR OSWRCH
    LDA expected
    JSR print_hex_byte
    LDA #' '
    JSR OSWRCH
    LDA received
    JSR print_hex_byte
    LDA #' '
    JSR OSWRCH
    LDA good_hi
    JSR print_hex_byte
    LDA good_lo
    JSR print_hex_byte
    LDA #' '
    JSR OSWRCH
    LDA bad_hi
    JSR print_hex_byte
    LDA bad_lo
    JSR print_hex_byte
    JSR OSNEWL

    ; Next byte
    INC send_byte

    ; Check Escape flag at &FF (bit 7 set = Escape pressed)
    BIT &FF
    BMI done

    JMP main_loop

.done
    ; Clear Escape condition
    LDA #&7E
    JSR OSBYTE

    JSR OSNEWL
    RTS

; Initialise counters
.init_counters
    LDA #0
    STA send_byte
    STA good_lo
    STA good_mid
    STA good_hi
    STA bad_lo
    STA bad_mid
    STA bad_hi
    RTS

; Update display with current counts
.update_display
    ; Cursor to start of line
    LDA #13
    JSR OSWRCH

    ; Print good count
    LDX #0
.print_good_msg
    LDA good_msg, X
    BEQ print_good_count
    JSR OSWRCH
    INX
    BNE print_good_msg

.print_good_count
    LDA good_hi
    JSR print_hex_byte
    LDA good_mid
    JSR print_hex_byte
    LDA good_lo
    JSR print_hex_byte

    ; Print bad count
    LDX #0
.print_bad_msg
    LDA bad_msg, X
    BEQ print_bad_count
    JSR OSWRCH
    INX
    BNE print_bad_msg

.print_bad_count
    LDA bad_hi
    JSR print_hex_byte
    LDA bad_mid
    JSR print_hex_byte
    LDA bad_lo
    JSR print_hex_byte

    RTS

; Initialise VIA for SPI
.init_via
    ; Set PCR to known state: CB2 input, CB1 neg edge, CA2 input, CA1 neg edge
    LDA #%00000000
    STA PCR

    ; Set ACR to known state: SR disabled, T1/T2 defaults, no latching
    LDA #%00000000
    STA ACR

    ; Set PB0 (MOSI), PB1 (SCK), PB2 (SS) as outputs
    LDA DDRB
    ORA #MOSI OR SCK OR SS
    STA DDRB

    ; Set idle state: SS high, SCK low (CPOL=0), MOSI high
    LDA IORB
    ORA #MOSI OR SS
    AND #NOT_SCK
    STA IORB

    RTS

; SPI transfer: send byte in A, return received byte in A
; Bit-bang MOSI/SCK, SR captures MISO on falling CB1 edge
; AVR Mode 1: outputs MISO on rising edge, samples MOSI on falling edge
; So we: set MOSI, go HIGH (AVR outputs MISO), go LOW (we sample, AVR samples)
.spi_transfer
    STA spi_temp            ; Save byte to send

    ; Ensure mode 0
    LDA ACR
    AND #%11100011
    STA ACR

    ; Clear shift register
    LDA SR

    ; Start with SCK low
    LDA IORB
    AND #NOT_SCK
    STA IORB

    LDX #8
.spi_bit
    ; Set MOSI based on MSB of spi_temp
    LDA spi_temp
    ASL A
    STA spi_temp            ; Shift for next iteration

    LDA IORB
    AND #%11111110          ; Clear MOSI
    BCC mosi_low
    ORA #MOSI
.mosi_low
    STA IORB                ; MOSI set, SCK still low

    ; Rising edge - AVR outputs new MISO bit
    ORA #SCK
    STA IORB

    NOP                     ; Let it settle
    NOP

    ; Falling edge - 6522 captures MISO, AVR samples MOSI
    AND #NOT_SCK
    STA IORB

    DEX
    BNE spi_bit

    ; Read received byte from shift register
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
    ADC #6
.digit
    ADC #&30
    JMP OSWRCH

.intro_msg
    EQUS "SPItFIRE SPI Soak Test", 13, 10
    EQUS "Press Escape to stop", 13, 10, 10, 0

.good_msg
    EQUS "Good: &", 0

.bad_msg
    EQUS "  Bad: &", 0

.final_msg
    EQUS "Final - Good: &", 0

.end

SAVE "SPITEST", start, end
