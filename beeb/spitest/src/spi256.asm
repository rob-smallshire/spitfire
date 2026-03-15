; SPItFIRE SPI 256-byte test
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

; Port B bits
MOSI = %00000001
SCK  = %00000010
SS   = %00000100
NOT_SS  = %11111011
NOT_SCK = %11111101

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

    ; Assert SS for entire transfer block
    LDA IORB
    AND #NOT_SS
    STA IORB

    ; Do 256 transfers
    LDA #0
    STA count
.transfer_loop
    LDA count
    JSR spi_transfer
    INC count
    BNE transfer_loop

    ; Deassert SS
    LDA IORB
    ORA #SS
    STA IORB

    ; Read end time
    LDA #1
    LDX #<end_time
    LDY #>end_time
    JSR OSWORD

    ; Print elapsed (just low byte in hex)
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
    ; This prevents IRQs on every SCK edge!
    LDA #%00011000
    STA IER

    ; Set PCR to known state: CB2 input, CB1 neg edge
    LDA #%00000000
    STA PCR

    ; Set ACR to known state: SR disabled
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

.spi_transfer
    ; Real SPI code preserved here for later
    STA spi_temp
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

    ORA #SCK
    STA IORB

    NOP
    NOP

    AND #NOT_SCK
    STA IORB

    DEX
    BNE spi_bit

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
    EQUS "256-byte SPI test v13", 13, 10, 0

.done_msg
    EQUS "Elapsed: &", 0

.cs_msg
    EQUS " cs", 0

.end

SAVE "SPI256", start, end
