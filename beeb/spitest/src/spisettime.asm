; SPItFIRE DS3234 RTC: Set Time
; Prompts for the date and time, computes the day of the week, waits for a
; key press (so the clock can be started on an exact second), writes the
; DS3234 time registers, clears the oscillator stop flag, and reads back.
;
; The RTC is the SparkFun DeadOn (DS3234) on J5, selected by ~SS_3
; (74HC138 output Y3). SCK idles HIGH when the RTC is selected (CPOL=1,
; CPHA=1) because the 6522 shift register samples MISO on the rising edge
; of CB1. See spirtc.asm.
;
; Years 2000-2099 are supported (DS3234 century bit left at 0).
; Day-of-week register convention: 1 = Sunday ... 7 = Saturday.

ORG &1900

; VIA registers (User VIA on Master Compact)
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
SEL_MASK = %00011100        ; Decoder bits (PB2-PB4)

DEV_RTC  = %00001100        ; Y3 -> ~SS_3 -> J5 DeadOn RTC

NOT_SEL  = %11100011
NOT_SCK  = %11111101
NOT_MOSI = %11111110

; DS3234 registers
RTC_SECONDS = &00
RTC_STATUS  = &0F
RTC_WRITE   = &80

; OS calls
OSRDCH = &FFE0
OSWRCH = &FFEE
OSNEWL = &FFE7
OSWORD = &FFF1
OSBYTE = &FFF4

; Zero page
spi_temp = &70
ptr      = &72              ; 2 bytes
num_lo   = &74              ; Parsed number (16-bit)
num_hi   = &75
idx      = &76              ; Parse position in line_buf
digits   = &77              ; Digit count for current number
t_lo     = &78              ; 16-bit scratch
t_hi     = &79
s_lo     = &7A              ; 16-bit day-of-week sum
s_hi     = &7B
tmp      = &7C
f_day    = &7D              ; Entered fields, binary
f_mon    = &7E
f_yr     = &7F              ; Year - 2000 (0-99)
f_hour   = &80
f_min    = &81
f_sec    = &82
dow      = &83              ; 1 = Sunday .. 7 = Saturday

.start
    JSR init_via
    LDX #LO(s_title)
    LDY #HI(s_title)
    JSR print_str

; ------ Date ------

.ask_date
    LDX #LO(s_ask_date)
    LDY #HI(s_ask_date)
    JSR print_str
    JSR read_line
    BCS escaped
    LDA #0
    STA idx

    JSR parse_num           ; Day
    BCS bad_date
    LDA num_hi
    BNE bad_date
    LDA num_lo
    STA f_day

    JSR parse_num           ; Month
    BCS bad_date
    LDA num_hi
    BNE bad_date
    LDA num_lo
    BEQ bad_date
    CMP #13
    BCS bad_date
    STA f_mon

    JSR parse_num           ; Year: must be 2000-2099 (&07D0-&0833)
    BCS bad_date
    LDA num_lo
    SEC
    SBC #LO(2000)
    STA f_yr
    LDA num_hi
    SBC #HI(2000)
    BNE bad_date            ; < 2000 (borrow) or >= 2256
    LDA f_yr
    CMP #100
    BCS bad_date

    ; Day must be 1 .. days in month (29 in February of a leap year)
    LDA f_day
    BEQ bad_date
    LDX f_mon
    LDA days_in_month-1, X
    STA tmp
    CPX #2
    BNE check_day
    LDA f_yr
    AND #3                  ; 2000-2099: leap if divisible by 4
    BNE check_day
    INC tmp
.check_day
    LDA tmp
    CMP f_day               ; Carry clear if days_in_month < f_day
    BCS ask_time

.bad_date
    LDX #LO(s_bad)
    LDY #HI(s_bad)
    JSR print_str
    JMP ask_date

.escaped
    LDA #&7E                ; Acknowledge Escape
    JSR OSBYTE
    LDX #LO(s_cancel)
    LDY #HI(s_cancel)
    JMP print_str

; ------ Time ------

.ask_time
    LDX #LO(s_ask_time)
    LDY #HI(s_ask_time)
    JSR print_str
    JSR read_line
    BCS escaped
    LDA #0
    STA idx

    JSR parse_num           ; Hours 0-23
    BCS bad_time
    LDA num_hi
    BNE bad_time
    LDA num_lo
    CMP #24
    BCS bad_time
    STA f_hour

    JSR parse_num           ; Minutes 0-59
    BCS bad_time
    LDA num_hi
    BNE bad_time
    LDA num_lo
    CMP #60
    BCS bad_time
    STA f_min

    JSR parse_num           ; Seconds 0-59
    BCS bad_time
    LDA num_hi
    BNE bad_time
    LDA num_lo
    CMP #60
    BCS bad_time
    STA f_sec
    JMP time_ok

.bad_time
    LDX #LO(s_bad)
    LDY #HI(s_bad)
    JSR print_str
    JMP ask_time

; ------ Confirm and set ------

.time_ok
    JSR compute_dow

    LDX #LO(s_press)
    LDY #HI(s_press)
    JSR print_str
    JSR OSRDCH              ; Wait for a key; carry set on Escape
    BCS escaped

    JSR write_time
    JSR clear_osf

    LDX #LO(s_set)
    LDY #HI(s_set)
    JSR print_str
    JSR read_time
    JSR print_time
    JMP OSNEWL

; ------ Day of week (Sakamoto's method) ------
; For full year Y (month < 3 uses Y-1):
;   dow = (Y + Y/4 - Y/100 + Y/400 + t[m-1] + d) mod 7, 0 = Sunday
; With Y = 2000 + k, the 2000 terms contribute 2485 = 0 (mod 7), so only
; k + k/4 - k/100 matters. Jan/Feb 2000 needs k = -1; using k = 399
; instead is equivalent because 400 years is a whole number of weeks.
.compute_dow
    LDA f_yr
    STA t_lo
    LDA #0
    STA t_hi
    LDA f_mon
    CMP #3
    BCS dow_k_ready
    LDA t_lo
    BNE dow_k_dec
    LDA #LO(399)
    STA t_lo
    LDA #HI(399)
    STA t_hi
    JMP dow_k_ready
.dow_k_dec
    DEC t_lo
.dow_k_ready
    ; s = k
    LDA t_lo
    STA s_lo
    LDA t_hi
    STA s_hi
    ; s += k / 4
    LDA t_hi
    STA tmp
    LDA t_lo
    LSR tmp
    ROR A
    LSR tmp
    ROR A
    CLC
    ADC s_lo
    STA s_lo
    LDA s_hi
    ADC tmp
    STA s_hi
    ; X = k / 100 (k < 400, so at most 3)
    LDX #0
.dow_div100
    LDA t_lo
    SEC
    SBC #100
    TAY
    LDA t_hi
    SBC #0
    BCC dow_div100_done
    STA t_hi
    STY t_lo
    INX
    JMP dow_div100
.dow_div100_done
    ; s -= k / 100
    STX tmp
    LDA s_lo
    SEC
    SBC tmp
    STA s_lo
    LDA s_hi
    SBC #0
    STA s_hi
    ; s += t[m-1] + d
    LDX f_mon
    LDA sakamoto-1, X
    CLC
    ADC f_day
    CLC
    ADC s_lo
    STA s_lo
    LDA s_hi
    ADC #0
    STA s_hi
    ; s mod 7
.dow_mod7
    LDA s_lo
    SEC
    SBC #7
    TAY
    LDA s_hi
    SBC #0
    BCC dow_mod7_done
    STA s_hi
    STY s_lo
    JMP dow_mod7
.dow_mod7_done
    LDA s_lo
    CLC
    ADC #1                  ; 1 = Sunday
    STA dow
    RTS

; ------ RTC access ------

.init_via
    LDA #%00011000          ; Disable CB1/CB2 interrupts
    STA IER
    LDA #0
    STA PCR
    STA ACR
    LDA DDRB
    ORA #MOSI OR SCK OR SEL_MASK
    STA DDRB
    LDA IORB                ; No device, SCK high, MOSI high
    ORA #MOSI OR SCK OR SEL_MASK ; No device (Y7), SCK and MOSI high
    STA IORB
    RTS

.rtc_select
    LDA IORB
    ORA #SCK
    AND #NOT_SEL
    ORA #DEV_RTC
    STA IORB
    RTS

.rtc_deselect
    LDA IORB
    ORA #SEL_MASK            ; No device (Y7)
    STA IORB
    RTS

; SPI transfer with SCK idling high. Send A, return received byte in A.
; Preserves Y.
.spi_xfer
    STA spi_temp
    LDA SR
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

; Convert the fields to BCD and burst-write registers 00-06.
; Writing the seconds register resets the DS3234's sub-second countdown.
.write_time
    LDA f_sec  : JSR to_bcd : STA reg_buf+0
    LDA f_min  : JSR to_bcd : STA reg_buf+1
    LDA f_hour : JSR to_bcd : STA reg_buf+2   ; Bit 6 = 0: 24-hour mode
    LDA dow                 : STA reg_buf+3
    LDA f_day  : JSR to_bcd : STA reg_buf+4
    LDA f_mon  : JSR to_bcd : STA reg_buf+5   ; Bit 7 (century) = 0
    LDA f_yr   : JSR to_bcd : STA reg_buf+6

    JSR rtc_select
    LDA #RTC_SECONDS OR RTC_WRITE
    JSR spi_xfer
    LDY #0
.write_loop
    LDA reg_buf, Y
    JSR spi_xfer
    INY
    CPY #7
    BNE write_loop
    JMP rtc_deselect

; Clear the oscillator stop flag (status bit 7), leaving the other
; writable bits unchanged. A1F/A2F can only be written to 0, so writing
; back their current values leaves them as they are.
.clear_osf
    JSR rtc_select
    LDA #RTC_STATUS
    JSR spi_xfer
    LDA #&FF
    JSR spi_xfer
    STA tmp
    JSR rtc_deselect
    JSR rtc_select
    LDA #RTC_STATUS OR RTC_WRITE
    JSR spi_xfer
    LDA tmp
    AND #&7F
    JSR spi_xfer
    JMP rtc_deselect

; Burst read registers 00-06 into reg_buf
.read_time
    JSR rtc_select
    LDA #RTC_SECONDS
    JSR spi_xfer
    LDY #0
.read_loop
    LDA #&FF
    JSR spi_xfer
    STA reg_buf, Y
    INY
    CPY #7
    BNE read_loop
    JMP rtc_deselect

; ------ Input ------

; Read a line into line_buf with OSWORD 0. Carry set on Escape.
.read_line
    LDA #0
    LDX #LO(osword0_block)
    LDY #HI(osword0_block)
    JMP OSWORD

; Parse the next decimal number (up to 4 digits) from line_buf at idx,
; skipping any separators. Result in num_lo/num_hi.
; Carry clear on success, set if there is no number or it is too long.
.parse_num
    LDY idx
.parse_skip
    LDA line_buf, Y
    CMP #13
    BEQ parse_fail
    JSR is_digit
    BCC parse_start
    INY
    JMP parse_skip
.parse_start
    LDA #0
    STA num_lo
    STA num_hi
    STA digits
.parse_digit
    LDA line_buf, Y
    JSR is_digit
    BCS parse_done
    INC digits
    LDX digits
    CPX #5
    BCS parse_fail
    PHA
    ; num = num * 10 = (num * 4 + num) * 2
    LDA num_lo
    STA t_lo
    LDA num_hi
    STA t_hi
    ASL num_lo
    ROL num_hi
    ASL num_lo
    ROL num_hi
    LDA num_lo
    CLC
    ADC t_lo
    STA num_lo
    LDA num_hi
    ADC t_hi
    STA num_hi
    ASL num_lo
    ROL num_hi
    ; num += digit
    PLA
    CLC
    ADC num_lo
    STA num_lo
    LDA num_hi
    ADC #0
    STA num_hi
    INY
    JMP parse_digit
.parse_done
    STY idx
    CLC
    RTS
.parse_fail
    SEC
    RTS

; If A is an ASCII digit, return its value in A with carry clear;
; otherwise return with carry set.
.is_digit
    CMP #'0'
    BCC not_digit
    CMP #'9'+1
    BCS not_digit
    SEC
    SBC #'0'
    CLC
    RTS
.not_digit
    SEC
    RTS

; ------ Output ------

; Convert A (0-99) to BCD. Clobbers X.
.to_bcd
    LDX #0
.to_bcd_loop
    CMP #10
    BCC to_bcd_done
    SBC #10
    INX
    BNE to_bcd_loop
.to_bcd_done
    STA tmp
    TXA
    ASL A
    ASL A
    ASL A
    ASL A
    ORA tmp
    RTS

; Print the registers in reg_buf as "Ddd dd/mm/20yy hh:mm:ss"
.print_time
    LDA reg_buf+3           ; Day of week name
    AND #7
    BEQ print_date          ; 0 is invalid: skip the name
    SEC
    SBC #1
    ASL A                   ; * 4 (names are 4 bytes)
    ASL A
    TAX
    LDY #4
.print_day_loop
    LDA day_names, X
    JSR OSWRCH
    INX
    DEY
    BNE print_day_loop
.print_date
    LDA reg_buf+4
    AND #&3F
    JSR print_hex_byte
    LDA #'/' : JSR OSWRCH
    LDA reg_buf+5
    AND #&1F
    JSR print_hex_byte
    LDA #'/' : JSR OSWRCH
    LDA #'2' : JSR OSWRCH
    LDA #'0' : JSR OSWRCH
    LDA reg_buf+6
    JSR print_hex_byte
    LDA #' ' : JSR OSWRCH
    LDA reg_buf+2
    AND #&3F
    JSR print_hex_byte
    LDA #':' : JSR OSWRCH
    LDA reg_buf+1
    AND #&7F
    JSR print_hex_byte
    LDA #':' : JSR OSWRCH
    LDA reg_buf+0
    AND #&7F
    JMP print_hex_byte

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

; Print A as two hex digits (prints BCD values as decimal)
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

.osword0_block
    EQUW line_buf
    EQUB 19                 ; Maximum line length
    EQUB 32                 ; Lowest accepted character
    EQUB 126                ; Highest accepted character

.days_in_month
    EQUB 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

.sakamoto
    EQUB 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4

.day_names
    EQUS "Sun Mon Tue Wed Thu Fri Sat "

.s_title
    EQUS "SPItFIRE DS3234 RTC Set Time", 13, 10
    EQUS "Escape to cancel", 13, 10, 10, 0
.s_ask_date
    EQUS "Date (DD/MM/YYYY): ", 0
.s_ask_time
    EQUS "Time (HH:MM:SS): ", 0
.s_bad
    EQUS "Invalid, please try again", 13, 10, 0
.s_press
    EQUS "Press a key to start the clock", 13, 10, 0
.s_set
    EQUS "Clock set: ", 0
.s_cancel
    EQUS 13, 10, "Cancelled - clock not changed", 13, 10, 0

.line_buf
    SKIP 20
.reg_buf
    SKIP 7

.end

SAVE "SPISETTIME", start, end
