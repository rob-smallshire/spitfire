; SPItFIRE Turbo 256-byte test
; Uses VIA shift register mode for MISO capture
; Minimal test - just 256 transfers, print elapsed time

ORG &1900

; VIA registers
VIA_BASE = &FE60
IORB = VIA_BASE + &00
DDRB = VIA_BASE + &02
SR   = VIA_BASE + &0A
ACR  = VIA_BASE + &0B
PCR  = VIA_BASE + &0C
IER  = VIA_BASE + &0E

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

; ACR shift register mode
SR_IN_CB1 = %00001100       ; Mode 3: Shift in under CB1 control

; OS
OSWRCH = &FFEE
OSNEWL = &FFE7
OSWORD = &FFF1

; Zero page
spi_temp   = &70
count      = &71
start_time = &72    ; 5 bytes
end_time   = &77    ; 5 bytes

.start
    JSR init_via

    ; Print intro
    LDX #0
.print_intro
    LDA intro_msg, X
    BEQ begin_test
    JSR OSWRCH
    INX
    BNE print_intro

.begin_test
    ; Read start time
    LDA #1
    LDX #<start_time
    LDY #>start_time
    JSR OSWORD

    ; Select SPItFIRE (device 1)
    LDA IORB
    AND #NOT_SEL
    ORA #DEV_SPITFIRE
    STA IORB

    ; Do 256 transfers
    LDA #0
    STA count
.transfer_loop
    JSR spi_read_byte   ; Optimized read (clock-only, SR captures)
    INC count
    BNE transfer_loop

    ; Deselect (device 0)
    LDA IORB
    AND #NOT_SEL
    STA IORB

    ; Read end time
    LDA #1
    LDX #<end_time
    LDY #>end_time
    JSR OSWORD

    ; Print elapsed
    LDX #0
.print_done
    LDA done_msg, X
    BEQ print_time
    JSR OSWRCH
    INX
    BNE print_done

.print_time
    ; 16-bit subtraction
    SEC
    LDA end_time
    SBC start_time
    PHA
    LDA end_time + 1
    SBC start_time + 1
    JSR print_hex_byte
    PLA
    JSR print_hex_byte
    LDX #0
.print_cs
    LDA cs_msg, X
    BEQ finished
    JSR OSWRCH
    INX
    BNE print_cs

.finished
    JSR OSNEWL
    RTS

.init_via
    ; Disable CB1/CB2 interrupts (bit 7=0 means clear, bits 3-4 = CB2/CB1)
    LDA #%00011000
    STA IER

    ; Set PCR: CB2 input, CB1 negative edge
    LDA #%00000000
    STA PCR

    ; Set ACR: SR mode 3 (shift in under CB1)
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

; Fast read-only transfer using shift register
; Sends 0xFF (MOSI stays high), returns received byte in A
; Much faster than full spi_transfer - no per-bit MOSI handling
.spi_read_byte
    LDA SR              ; Clear shift register

    ; MOSI high (sending 0xFF) - set once, not per-bit
    LDA IORB
    ORA #MOSI
    AND #NOT_SCK        ; Ensure SCK low
    STA IORB

    ; Just toggle SCK 8 times - SR captures MISO on falling edges
    LDX #8
.read_clock
    LDA IORB
    ORA #SCK            ; Rising edge
    STA IORB
    AND #NOT_SCK        ; Falling edge - SR captures
    STA IORB
    DEX
    BNE read_clock

    LDA SR              ; Read received byte
    RTS

; Full SPI transfer (for reference, not used in timing test)
.spi_transfer
    STA spi_temp

    ; Clear shift register
    LDA SR

    LDX #8
.spi_bit
    LDA spi_temp
    ASL A
    STA spi_temp

    LDA IORB
    AND #%11111110
    BCC mosi_low
    ORA #MOSI
.mosi_low
    STA IORB

    ; Rising edge - AVR outputs MISO
    ORA #SCK
    STA IORB

    NOP
    NOP

    ; Falling edge - SR captures MISO via CB1
    AND #NOT_SCK
    STA IORB

    DEX
    BNE spi_bit

    ; Read received byte from shift register
    LDA SR

    RTS

.print_hex_byte
    PHA
    LSR A
    LSR A
    LSR A
    LSR A
    JSR print_nybble
    PLA
    AND #&0F
.print_nybble
    CMP #10
    BCC digit
    ADC #6
.digit
    ADC #&30
    JMP OSWRCH

.intro_msg
    EQUS "256-byte turbo test v3", 13, 10, 0

.done_msg
    EQUS "Elapsed: &", 0

.cs_msg
    EQUS " cs", 0

.end

SAVE "SPIT256", start, end
