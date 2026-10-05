; SPItFIRE DS3234 RTC Test
; Tests the SparkFun DeadOn RTC (DS3234) on header J5, selected by ~SS_3
; (74HC138 output Y3).
;
; 1. Writes a pattern to the DS3234's user SRAM and reads it back
; 2. Displays the time, date, control/status registers and temperature,
;    refreshing continuously until Escape is pressed
;
; SPI mode: the DS3234 chooses its clock polarity from the state of SCLK
; when CS goes low. The 6522 shift register samples MISO (CB2) on the
; rising edge of CB1, so SCK must idle HIGH when the RTC is selected.
; The DS3234 then shifts DOUT on falling edges and latches DIN on rising
; edges (CPOL=1, CPHA=1), the same scheme MMFS uses for SD cards.

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
MOSI     = %00000001        ; PB0
SCK      = %00000010        ; PB1
SEL_MASK = %00011100        ; Decoder bits (PB2-PB4)

; Device numbers (via 74HC138)
DEV_RTC  = %00001100        ; Y3 (A0=1, A1=1) -> ~SS_3 -> J5 DeadOn RTC

; Inverted masks for AND operations
NOT_SEL  = %11100011
NOT_SCK  = %11111101
NOT_MOSI = %11111110

; DS3234 register addresses (read; OR with &80 to write)
RTC_SECONDS = &00           ; 00-06: time and date (BCD)
RTC_CONTROL = &0E           ; 0E control, 0F status, 10 aging, 11-12 temp
RTC_SRAM_ADDR = &18
RTC_SRAM_DATA = &19
RTC_WRITE = &80

; OS calls
OSWRCH = &FFEE
OSNEWL = &FFE7
OSBYTE = &FFF4

; Zero page
spi_temp = &70
ptr      = &72              ; 2 bytes, string pointer
sram_ok  = &74              ; 0 = fail, 1 = pass

.start
    JSR init_via
    JSR init_display
    JSR sram_test
    JSR show_sram

.main_loop
    JSR read_time
    JSR read_status
    JSR show_time

    ; Wait up to 20 cs (INKEY), then check Escape
    LDA #&81
    LDX #20
    LDY #0
    JSR OSBYTE
    BIT &FF
    BPL main_loop

    ; Acknowledge Escape and leave the cursor below the display
    LDA #&7E
    JSR OSBYTE
    LDX #0
    LDY #14
    JSR tab
    RTS

; ------ VIA and device selection ------

.init_via
    ; Disable CB1/CB2 interrupts (CB1 is wired to SCK)
    LDA #%00011000
    STA IER
    LDA #0
    STA PCR
    STA ACR                 ; Shift register mode 0

    ; PB0 (MOSI), PB1 (SCK), PB2-4 (decoder) as outputs
    LDA DDRB
    ORA #MOSI OR SCK OR SEL_MASK
    STA DDRB

    ; Idle: no device selected, SCK HIGH, MOSI high
    LDA IORB
    AND #NOT_SEL
    ORA #MOSI OR SCK
    STA IORB
    RTS

; Select the RTC with SCK high, so the DS3234 uses CPOL=1
.rtc_select
    LDA IORB
    ORA #SCK
    AND #NOT_SEL
    ORA #DEV_RTC
    STA IORB
    RTS

.rtc_deselect
    LDA IORB
    AND #NOT_SEL
    STA IORB
    RTS

; SPI transfer, SCK idling high: send A, return received byte in A.
; Each bit: SCK falls with MOSI set (DS3234 shifts out its next bit),
; then SCK rises (DS3234 latches MOSI, VIA shift register latches MISO).
; Preserves Y. Leaves SCK high.
.spi_xfer
    STA spi_temp
    LDA SR                  ; Clear shift register
    LDX #8
.spi_bit
    LDA IORB
    AND #NOT_SCK AND NOT_MOSI
    ASL spi_temp
    BCC spi_mosi_low
    ORA #MOSI
.spi_mosi_low
    STA IORB                ; Falling edge, MOSI valid
    ORA #SCK
    STA IORB                ; Rising edge: both ends sample
    DEX
    BNE spi_bit
    LDA SR
    RTS

; ------ SRAM test ------

; Write the pattern to SRAM 00-07, read it back and compare
.sram_test
    JSR set_sram_addr_zero

    JSR rtc_select
    LDA #RTC_SRAM_DATA OR RTC_WRITE
    JSR spi_xfer
    LDY #0
.sram_write
    LDA pattern, Y
    JSR spi_xfer
    INY
    CPY #8
    BNE sram_write
    JSR rtc_deselect

    JSR set_sram_addr_zero

    JSR rtc_select
    LDA #RTC_SRAM_DATA
    JSR spi_xfer
    LDY #0
.sram_read
    LDA #&FF
    JSR spi_xfer
    STA sram_buf, Y
    INY
    CPY #8
    BNE sram_read
    JSR rtc_deselect

    LDA #1
    STA sram_ok
    LDY #7
.sram_compare
    LDA sram_buf, Y
    CMP pattern, Y
    BEQ sram_match
    LDA #0
    STA sram_ok
.sram_match
    DEY
    BPL sram_compare
    RTS

.set_sram_addr_zero
    JSR rtc_select
    LDA #RTC_SRAM_ADDR OR RTC_WRITE
    JSR spi_xfer
    LDA #0
    JSR spi_xfer
    JMP rtc_deselect

; ------ Register reads ------

; Burst read 00-06 (seconds .. year) into time_buf
.read_time
    JSR rtc_select
    LDA #RTC_SECONDS
    JSR spi_xfer
    LDY #0
.read_time_loop
    LDA #&FF
    JSR spi_xfer
    STA time_buf, Y
    INY
    CPY #7
    BNE read_time_loop
    JMP rtc_deselect

; Burst read 0E-12 (control, status, aging, temp MSB, temp LSB)
.read_status
    JSR rtc_select
    LDA #RTC_CONTROL
    JSR spi_xfer
    LDY #0
.read_status_loop
    LDA #&FF
    JSR spi_xfer
    STA ext_buf, Y
    INY
    CPY #5
    BNE read_status_loop
    JMP rtc_deselect

; ------ Display ------

.init_display
    LDA #22 : JSR OSWRCH
    LDA #7  : JSR OSWRCH
    ; Hide the cursor: VDU 23,1,0;0;0;0;
    LDA #23 : JSR OSWRCH
    LDA #1  : JSR OSWRCH
    LDA #0
    LDX #8
.hide_cursor
    JSR OSWRCH
    DEX
    BNE hide_cursor
    LDX #LO(s_title)
    LDY #HI(s_title)
    JMP print_str

.show_sram
    LDX #0
    LDY #2
    JSR tab
    LDX #LO(s_sram)
    LDY #HI(s_sram)
    JSR print_str
    LDY #0
.show_sram_loop
    LDA sram_buf, Y
    JSR print_hex_byte
    LDA #' '
    JSR OSWRCH
    INY
    CPY #8
    BNE show_sram_loop
    LDA sram_ok
    BEQ show_sram_fail
    LDX #LO(s_ok)
    LDY #HI(s_ok)
    JMP print_str
.show_sram_fail
    LDX #LO(s_fail)
    LDY #HI(s_fail)
    JMP print_str

.show_time
    ; Row 4: time (24-hour mode assumed; hours bits 0-5)
    LDX #0
    LDY #4
    JSR tab
    LDX #LO(s_time)
    LDY #HI(s_time)
    JSR print_str
    LDA time_buf+2
    AND #&3F
    JSR print_hex_byte
    LDA #':' : JSR OSWRCH
    LDA time_buf+1
    AND #&7F
    JSR print_hex_byte
    LDA #':' : JSR OSWRCH
    LDA time_buf+0
    AND #&7F
    JSR print_hex_byte

    ; Row 5: date dd/mm/yyyy (century bit is month bit 7) and day of week
    LDX #0
    LDY #5
    JSR tab
    LDX #LO(s_date)
    LDY #HI(s_date)
    JSR print_str
    LDA time_buf+4
    AND #&3F
    JSR print_hex_byte
    LDA #'/' : JSR OSWRCH
    LDA time_buf+5
    AND #&1F
    JSR print_hex_byte
    LDA #'/' : JSR OSWRCH
    LDA #'2' : JSR OSWRCH
    LDA time_buf+5
    ASL A                   ; Century bit into carry
    LDA #'0'
    ADC #0
    JSR OSWRCH
    LDA time_buf+6
    JSR print_hex_byte
    LDX #LO(s_day)
    LDY #HI(s_day)
    JSR print_str
    LDA time_buf+3
    AND #&07
    ORA #'0'
    JSR OSWRCH

    ; Row 7: control and status registers
    LDX #0
    LDY #7
    JSR tab
    LDX #LO(s_ctrl)
    LDY #HI(s_ctrl)
    JSR print_str
    LDA ext_buf+0
    JSR print_hex_byte
    LDX #LO(s_stat)
    LDY #HI(s_stat)
    JSR print_str
    LDA ext_buf+1
    JSR print_hex_byte
    LDA ext_buf+1
    BPL no_osf
    LDX #LO(s_osf)
    LDY #HI(s_osf)
    JSR print_str
    JMP row8
.no_osf
    LDX #LO(s_blank)
    LDY #HI(s_blank)
    JSR print_str

    ; Row 8: temperature, MSB = integer degrees (two's complement),
    ; LSB bits 7-6 = quarter degrees
.row8
    LDX #0
    LDY #8
    JSR tab
    LDX #LO(s_temp)
    LDY #HI(s_temp)
    JSR print_str
    LDA ext_buf+3
    BPL temp_positive
    PHA
    LDA #'-' : JSR OSWRCH
    PLA
    EOR #&FF
    CLC
    ADC #1
.temp_positive
    JSR print_dec
    LDA #'.' : JSR OSWRCH
    LDA ext_buf+4
    LSR A : LSR A : LSR A : LSR A : LSR A
    AND #%00000110          ; Quarter index * 2
    TAX
    LDA quarters, X   : JSR OSWRCH
    LDA quarters+1, X : JSR OSWRCH
    LDX #LO(s_degc)
    LDY #HI(s_degc)
    JSR print_str

    ; Row 10: raw registers 00-06
    LDX #0
    LDY #10
    JSR tab
    LDX #LO(s_raw)
    LDY #HI(s_raw)
    JSR print_str
    LDY #0
.raw_loop
    LDA time_buf, Y
    JSR print_hex_byte
    LDA #' '
    JSR OSWRCH
    INY
    CPY #7
    BNE raw_loop
    RTS

; ------ Output helpers ------

; Move the text cursor to column X, row Y
.tab
    LDA #31
    JSR OSWRCH
    TXA
    JSR OSWRCH
    TYA
    JMP OSWRCH

; Print the zero-terminated string at X (low), Y (high). Clobbers Y.
.print_str
    STX ptr
    STY ptr+1
    LDY #0
.print_str_loop
    LDA (ptr), Y
    BEQ print_str_done
    JSR OSWRCH
    INY
    BNE print_str_loop
.print_str_done
    RTS

; Print A (0-255) in decimal without leading zeros. Clobbers X, Y.
.print_dec
    LDY #0                  ; Nothing printed yet
    LDX #0
.dec_100
    CMP #100
    BCC dec_100_done
    SBC #100
    INX
    BNE dec_100
.dec_100_done
    JSR print_digit
    LDX #0
.dec_10
    CMP #10
    BCC dec_10_done
    SBC #10
    INX
    BNE dec_10
.dec_10_done
    JSR print_digit
    TAX
    LDY #1                  ; Always print the units digit
    ; Fall through

; Print digit X unless it is a leading zero (Y=0). Preserves A.
.print_digit
    PHA
    TXA
    BNE print_digit_now
    CPY #0
    BEQ print_digit_skip
.print_digit_now
    TXA
    ORA #'0'
    JSR OSWRCH
    LDY #1
.print_digit_skip
    PLA
    RTS

; Print A as two hex digits (also prints BCD values as decimal)
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
    BCC hex_digit
    ADC #6
.hex_digit
    ADC #&30
    JMP OSWRCH

; ------ Data ------

.pattern
    EQUB &55, &AA, &00, &FF, &01, &80, &5A, &A5

.quarters
    EQUS "00255075"

.s_title
    EQUS "SPItFIRE DS3234 RTC Test (J5, Y3)", 0
.s_sram
    EQUS "SRAM ", 0
.s_ok
    EQUS "OK", 0
.s_fail
    EQUS "FAIL", 0
.s_time
    EQUS "Time ", 0
.s_date
    EQUS "Date ", 0
.s_day
    EQUS "  Day ", 0
.s_ctrl
    EQUS "Ctrl ", 0
.s_stat
    EQUS "  Stat ", 0
.s_osf
    EQUS " OSF", 0
.s_blank
    EQUS "    ", 0
.s_temp
    EQUS "Temp ", 0
.s_degc
    EQUS " C  ", 0
.s_raw
    EQUS "Raw ", 0

.time_buf
    SKIP 7
.ext_buf
    SKIP 5
.sram_buf
    SKIP 8

.end

SAVE "SPIRTC", start, end
