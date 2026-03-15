; SPItFIRE SPI Performance Test
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

; Port B bit assignments
MOSI = %00000001            ; PB0
SCK  = %00000010            ; PB1
SS   = %00000100            ; PB2

; Inverted masks for AND operations
NOT_SS   = %11111011
NOT_SCK  = %11111101

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
div_tmp    = &82            ; division workspace (4 bytes)

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
    ; Send a byte (value doesn't matter for perf test)
    LDA count_lo
    JSR spi_transfer

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
.divide_rate
    ; Initialise dividend = &640000
    LDA #&00
    STA div_tmp
    LDA #&00
    STA div_tmp + 1
    LDA #&64
    STA div_tmp + 2
    LDA #&00
    STA div_tmp + 3         ; 32-bit workspace

    ; Clear result
    LDA #0
    STA rate_lo
    STA rate_mid
    STA rate_hi

    ; 24-bit / 16-bit division
    LDX #24                 ; 24 bits to process
.div_loop
    ; Shift dividend left, MSB into carry
    ASL div_tmp
    ROL div_tmp + 1
    ROL div_tmp + 2
    ROL div_tmp + 3

    ; Shift carry into result
    ROL rate_lo
    ROL rate_mid
    ROL rate_hi

    ; Try to subtract divisor from upper 16 bits of workspace
    SEC
    LDA div_tmp + 2
    SBC elapsed_lo
    PHA
    LDA div_tmp + 3
    SBC elapsed_hi

    ; If borrow, don't subtract (result bit stays 0)
    BCC div_no_sub

    ; Subtraction succeeded, store result and set bit
    STA div_tmp + 3
    PLA
    STA div_tmp + 2
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
.spi_transfer
    STA spi_temp

    ; Set ACR to known state: SR disabled, no latching
    LDA #%00000000
    STA ACR

    ; Clear shift register
    LDA SR

    ; Start with SCK low
    LDA IORB
    AND #NOT_SCK
    STA IORB

    LDX #8
.spi_bit
    LDA spi_temp
    ASL A
    STA spi_temp

    LDA IORB
    AND #%11111110          ; Clear MOSI
    BCC mosi_low
    ORA #MOSI
.mosi_low
    STA IORB                ; MOSI set, SCK still low

    ; Rising edge
    ORA #SCK
    STA IORB

    NOP
    NOP

    ; Falling edge
    AND #NOT_SCK
    STA IORB

    DEX
    BNE spi_bit

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

.print_hex_nybble
    CMP #10
    BCC digit
    ADC #6
.digit
    ADC #&30
    JMP OSWRCH

.intro_msg
    EQUS "SPItFIRE SPI Performance Test", 13, 10
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

SAVE "SPIPERF", start, end
