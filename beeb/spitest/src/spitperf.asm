; SPItFIRE Turbo Performance Test
; Uses VIA shift register mode for MISO capture
; Runs 65536 transfers, measures elapsed time in centiseconds
; Reports transfer rate

ORG &1900

; VIA registers (User VIA on Master Compact)
VIA_BASE = &FE60
IORB = VIA_BASE + &00       ; Port B I/O
DDRB = VIA_BASE + &02       ; Port B data direction
SR   = VIA_BASE + &0A       ; Shift register
ACR  = VIA_BASE + &0B       ; Auxiliary control register
PCR  = VIA_BASE + &0C       ; Peripheral control register
IER  = VIA_BASE + &0E       ; Interrupt enable register

; Port B bit assignments
MOSI = %00000001            ; PB0
SCK  = %00000010            ; PB1
SS   = %00000100            ; PB2

; Inverted masks for AND operations
NOT_SS   = %11111011
NOT_SCK  = %11111101

; ACR shift register mode
SR_IN_CB1 = %00001100       ; Mode 3: Shift in under CB1 control

; OS calls
OSWRCH = &FFEE
OSNEWL = &FFE7
OSWORD = &FFF1

; Zero page variables
spi_temp   = &70
count_lo   = &71            ; 16-bit transfer counter
count_hi   = &72
start_time = &73            ; 5-byte start time (73-77)
end_time   = &78            ; 5-byte end time (78-7C)
elapsed_lo = &7D            ; 16-bit elapsed centiseconds
elapsed_hi = &7E
rate_lo    = &7F            ; bytes per second result
rate_mid   = &80
rate_hi    = &81
div_tmp    = &82            ; division workspace (5 bytes: 3 dividend + 2 remainder)

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
    ; Read start time (OSWORD 1, X/Y point to 5-byte buffer)
    LDA #1
    LDX #<start_time
    LDY #>start_time
    JSR OSWORD

    ; Initialise counter to 0
    LDA #0
    STA count_lo
    STA count_hi

    ; Assert SS
    LDA IORB
    AND #NOT_SS
    STA IORB

.transfer_loop
    ; Fast read using shift register
    JSR spi_read_byte

    ; Increment 16-bit counter
    INC count_lo
    BNE transfer_loop

    ; Every 256 transfers, toggle SS to let AVR resync
    LDA IORB
    ORA #SS
    STA IORB            ; Deassert SS
    NOP
    NOP
    AND #NOT_SS
    STA IORB            ; Reassert SS

    INC count_hi
    BNE transfer_loop

    ; Counter wrapped to 0 = 65536 transfers done

    ; Deassert SS
    LDA IORB
    ORA #SS
    STA IORB

    ; Read end time
    LDA #1
    LDX #<end_time
    LDY #>end_time
    JSR OSWORD

    ; Calculate elapsed time (16-bit, ignore upper bytes)
    SEC
    LDA end_time
    SBC start_time
    STA elapsed_lo
    LDA end_time + 1
    SBC start_time + 1
    STA elapsed_hi

    ; Print results
    LDX #0
.print_done
    LDA done_msg, X
    BEQ print_elapsed
    JSR OSWRCH
    INX
    BNE print_done

.print_elapsed
    LDA elapsed_hi
    JSR print_hex_byte
    LDA elapsed_lo
    JSR print_hex_byte

    LDX #0
.print_cs
    LDA cs_msg, X
    BEQ calculate_rate
    JSR OSWRCH
    INX
    BNE print_cs

.calculate_rate
    ; Rate = 6553600 / elapsed_cs bytes per second
    ; 6553600 = &640000
    ; Do 24-bit / 16-bit division

    JSR divide_rate

    ; Print rate
    LDX #0
.print_rate_msg
    LDA rate_msg, X
    BEQ print_rate_value
    JSR OSWRCH
    INX
    BNE print_rate_msg

.print_rate_value
    ; Print 24-bit result as decimal
    JSR print_rate_decimal

    LDX #0
.print_bps
    LDA bps_msg, X
    BEQ perf_done
    JSR OSWRCH
    INX
    BNE print_bps

.perf_done
    JSR OSNEWL
    RTS

; Divide 6553600 (&640000) by elapsed_lo/hi
; Result in rate_lo/mid/hi
; Uses 5-byte workspace: div_tmp+0:+1:+2 = dividend, div_tmp+3:+4 = remainder
.divide_rate
    ; Initialise dividend = &640000 (little-endian in +0:+1:+2)
    LDA #&00
    STA div_tmp
    STA div_tmp + 1
    LDA #&64
    STA div_tmp + 2
    ; Initialise remainder = 0 (in +3:+4)
    LDA #&00
    STA div_tmp + 3
    STA div_tmp + 4

    ; Clear result
    STA rate_lo
    STA rate_mid
    STA rate_hi

    ; 24-bit / 16-bit division
    LDX #24                 ; 24 bits to process
.div_loop
    ; Shift dividend left, MSB into remainder
    ASL div_tmp
    ROL div_tmp + 1
    ROL div_tmp + 2
    ROL div_tmp + 3
    ROL div_tmp + 4

    ; Shift result left (0 into bit 0, will set if subtraction succeeds)
    ASL rate_lo
    ROL rate_mid
    ROL rate_hi

    ; Try to subtract divisor from remainder (div_tmp+3:+4)
    SEC
    LDA div_tmp + 3
    SBC elapsed_lo
    PHA
    LDA div_tmp + 4
    SBC elapsed_hi

    ; If borrow, don't subtract (result bit stays 0)
    BCC div_no_sub

    ; Subtraction succeeded, store result and set bit
    STA div_tmp + 4
    PLA
    STA div_tmp + 3
    INC rate_lo             ; Set LSB of result
    JMP div_next

.div_no_sub
    PLA                     ; Discard tentative result

.div_next
    DEX
    BNE div_loop
    RTS

; Print 24-bit number in rate_lo/mid/hi as decimal
.print_rate_decimal
    ; Convert to decimal by repeated subtraction
    ; Max value ~655360 (if elapsed=10), so 6 digits max

    ; We'll print leading zeros suppressed
    ; Divisors: 100000, 10000, 1000, 100, 10, 1

    LDA #0
    STA spi_temp            ; Leading zero flag

    ; 100000 = &186A0
    LDA #<100000
    STA div_tmp
    LDA #>100000
    STA div_tmp + 1
    LDA #&01                ; High byte of 100000
    STA div_tmp + 2
    JSR print_decimal_digit

    ; 10000 = &2710
    LDA #<10000
    STA div_tmp
    LDA #>10000
    STA div_tmp + 1
    LDA #0
    STA div_tmp + 2
    JSR print_decimal_digit

    ; 1000 = &3E8
    LDA #<1000
    STA div_tmp
    LDA #>1000
    STA div_tmp + 1
    LDA #0
    STA div_tmp + 2
    JSR print_decimal_digit

    ; 100 = &64
    LDA #100
    STA div_tmp
    LDA #0
    STA div_tmp + 1
    STA div_tmp + 2
    JSR print_decimal_digit

    ; 10
    LDA #10
    STA div_tmp
    LDA #0
    STA div_tmp + 1
    STA div_tmp + 2
    JSR print_decimal_digit

    ; 1 - always print
    LDA rate_lo
    ORA #&30
    JMP OSWRCH

; Subtract divisor from rate, count times, print digit
.print_decimal_digit
    LDX #0
.sub_loop
    ; Try subtract div_tmp from rate
    SEC
    LDA rate_lo
    SBC div_tmp
    PHA
    LDA rate_mid
    SBC div_tmp + 1
    PHA
    LDA rate_hi
    SBC div_tmp + 2

    ; If borrow, we're done
    BCC sub_done

    ; Store result
    STA rate_hi
    PLA
    STA rate_mid
    PLA
    STA rate_lo
    INX
    JMP sub_loop

.sub_done
    PLA
    PLA                     ; Clean up stack

    ; X = digit value
    TXA
    BNE print_nonzero

    ; Check if we've printed a digit yet
    LDA spi_temp
    BEQ skip_zero           ; Still leading zeros

.print_nonzero
    LDA #1
    STA spi_temp            ; Mark that we've printed
    TXA
    ORA #&30
    JMP OSWRCH

.skip_zero
    RTS

; Initialise VIA for SPI with shift register mode
.init_via
    ; Disable CB1/CB2 interrupts (bit 7=0 means clear, bits 3-4 = CB2/CB1)
    ; This prevents IRQs on every SCK edge!
    LDA #%00011000
    STA IER

    ; Set PCR to known state: CB2 input, CB1 neg edge
    LDA #%00000000
    STA PCR

    ; Set ACR: SR mode 3 (shift in under CB1)
    LDA #SR_IN_CB1
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

.print_hex_nybble
    CMP #10
    BCC digit
    ADC #6
.digit
    ADC #&30
    JMP OSWRCH

.intro_msg
    EQUS "SPItFIRE Turbo Performance Test v1", 13, 10
    EQUS "Running 65536 transfers...", 13, 10, 0

.done_msg
    EQUS "Elapsed: &", 0

.cs_msg
    EQUS " centiseconds", 13, 10, 0

.rate_msg
    EQUS "Rate: ", 0

.bps_msg
    EQUS " bytes/sec", 0

.end

SAVE "SPITPERF", start, end
