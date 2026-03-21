; SPItFIRE SPI Turbo Soak Test
; Uses VIA shift register mode for faster MISO capture
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
IER  = VIA_BASE + &0E       ; Interrupt enable register

; Port B bit assignments
MOSI     = %00000001        ; PB0
SCK      = %00000010        ; PB1
SEL_A0   = %00000100        ; PB2 - decoder A0
SEL_A1   = %00001000        ; PB3 - decoder A1
SEL_A2   = %00010000        ; PB4 - decoder A2
SEL_MASK = %00011100        ; All decoder bits (PB2-PB4)

; Device numbers (accent directly via 74HC138)
DEV_NONE     = %00000000    ; Y0 - no device
DEV_SPITFIRE = %00000100    ; Y1 - SPItFIRE (A0=1)

; Inverted masks for AND operations
NOT_SEL  = %11100011        ; Clear decoder bits
NOT_SCK  = %11111101

; ACR shift register modes (bits 4-2)
SR_DISABLED = %00000000     ; Mode 0: SR disabled
SR_IN_CB1   = %00001100     ; Mode 3: Shift in under CB1 control

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

    ; Select SPItFIRE (device 1)
    LDA IORB
    AND #NOT_SEL
    ORA #DEV_SPITFIRE
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

    ; Deselect (device 0)
    LDA IORB
    AND #NOT_SEL
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

; Initialise VIA for SPI with shift register
.init_via
    ; Disable CB1/CB2 interrupts (bit 7=0 means clear, bits 3-4 = CB2/CB1)
    ; This prevents IRQs on every SCK edge!
    LDA #%00011000
    STA IER

    ; Set PCR: CB2 input, CB1 negative edge (captures on falling SCK)
    ; CB1 neg edge means SR shifts when SCK goes low
    LDA #%00000000
    STA PCR

    ; Set ACR: SR mode 3 (shift in under CB1), T1/T2 defaults, no latching
    ; Mode 3 = bits 4-2 = 011
    LDA #SR_IN_CB1
    STA ACR

    ; Set PB0 (MOSI), PB1 (SCK), PB2-4 (decoder) as outputs
    LDA DDRB
    ORA #MOSI OR SCK OR SEL_MASK
    STA DDRB

    ; Set idle state: device 0 (none), SCK low (CPOL=0), MOSI high
    LDA IORB
    AND #NOT_SEL AND NOT_SCK
    ORA #MOSI
    STA IORB

    RTS

; SPI transfer using shift register for receive
; Send byte in A, return received byte in A
; MOSI is bit-banged, MISO captured by SR on CB1 (falling edge)
.spi_transfer
    STA spi_temp            ; Save byte to send

    ; Clear shift register by reading it
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

    ; Rising edge - AVR outputs new MISO bit, MISO now valid
    ORA #SCK
    STA IORB

    NOP                     ; Let it settle
    NOP

    ; Falling edge - SR captures MISO via CB1, AVR samples MOSI
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
    EQUS "SPItFIRE Turbo Soak Test v2", 13, 10
    EQUS "SR mode 3: shift in under CB1", 13, 10
    EQUS "Press Escape to stop", 13, 10, 10, 0

.good_msg
    EQUS "Good: &", 0

.bad_msg
    EQUS "  Bad: &", 0

.end

SAVE "SPITTEST", start, end
