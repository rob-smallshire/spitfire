; RTC module
; Answers OSWORD &0E (read clock) and &0F (write clock) from the DS3234
; on J5, so *TIME and TIME$ see and set real time. See "Module: RTC" in
; docs/rom-design.md.
;
; OSWORD &0E subcalls handled:
;   0  Return "Ddd,dd Mon yyyy.hh:mm:ss" + CR (25 bytes), real century
;   1  Return 7 BCD bytes: year, month, date, weekday (1 = Sunday),
;      hours, minutes, seconds
;   2  Convert the 7 BCD bytes at XY+1 into a string (year &00-&79 is
;      20xx). MOS 5.10 offers subcall 2 to ROMs before converting it
;      itself (with century 19), so this fixes the century for everyone.
; Everything else is passed on, including subcalls 3 and 4 (ANFS's file
; server time). If the DS3234's oscillator stop flag is set, or no RTC
; answers, subcalls 0 and 1 are passed on too, so ANFS or the MOS
; default answer instead.
;
; OSWORD &0F lengths handled (data from XY+1):
;   8  "hh:mm:ss"                  Set the time, leave the date
;   15 "Ddd,dd Mon yyyy"           Set the date, leave the time
;   24 "Ddd,dd Mon yyyy.hh:mm:ss"  Set both
; Fields are at fixed positions and punctuation is not checked. The
; weekday name is ignored: the weekday is computed from the date. Years
; 2000-2199 only (the DS3234's century bit). Month names match in either
; case. Anything invalid is passed on. A successful write clears the
; oscillator stop flag.
;
; OSWORD calls never raise errors.

; DS3234 registers
RTC_SECONDS = &00
RTC_WEEKDAY = &03
RTC_STATUS  = &0F
RTC_WRITE   = &80           ; OR with a register number to write it
RTC_OSF     = %10000000     ; Status: oscillator stop flag
RTC_CENTURY = %10000000     ; Month register: century bit

; The clock in OSWORD &0E,1 order, plus the century, all BCD
rtc_year    = ws + 0
rtc_month   = ws + 1
rtc_date    = ws + 2
rtc_weekday = ws + 3
rtc_hours   = ws + 4
rtc_minutes = ws + 5
rtc_seconds = ws + 6
rtc_century = ws + 7        ; Shares with spi_temp; set after SPI is done

; OSWORD &0F fields, binary until converted to BCD for writing
set_seconds = ws + 0
set_minutes = ws + 1
set_hours   = ws + 2
set_date    = ws + 3
set_month   = ws + 4
set_year    = ws + 5        ; 0-99 within the century
set_century = ws + 6        ; 0 = 20xx, 1 = 21xx; later the weekday
set_temp    = ws + 7        ; Shares with spi_temp; free before SPI

; Service &08 handler. Return C=0 if claimed, C=1 to pass on.
; May corrupt A, X, Y (the dispatcher saves them).
.rtc_osword
    LDA OSWORD_A
    CMP #&0F
    BEQ rtc_osword_ours
    CMP #&0E
    BNE rtc_pass
    LDY #0
    LDA (OSWORD_BLK), Y
    CMP #3
    BCS rtc_pass            ; Only subcalls 0-2

.rtc_osword_ours
    LDX #7                  ; Save &A8-&AF
.rtc_save_ws
    LDA ws, X
    PHA
    DEX
    BPL rtc_save_ws

    JSR rtc_osword_dispatch

    LDX #&F8                ; Restore &A8-&AF. Counts up to zero, as
.rtc_restore_ws             ; PLA, STA, INX and BNE all leave C alone;
    PLA                     ; the zero page index wraps &B0+&F8 to &A8
    STA ws + 8, X
    INX
    BNE rtc_restore_ws
    RTS

.rtc_pass
    SEC
    RTS

.rtc_osword_dispatch
    LDA OSWORD_A
    CMP #&0F
    BNE rtc_osword0e
    JMP rtc_osword0f

; OSWORD &0E subcalls 0-2, with &A8-&AF free. C=0 if claimed.
.rtc_osword0e
    LDY #0
    LDA (OSWORD_BLK), Y
    CMP #2
    BEQ rtc_convert
    JSR rtc_read
    BCS rtc_osword0e_done   ; Clock not valid: pass on
    LDY #0
    LDA (OSWORD_BLK), Y
    BEQ rtc_string

    LDY #6                  ; Subcall 1: the 7 BCD bytes
.rtc_copy_bcd
    LDA ws, Y
    STA (OSWORD_BLK), Y
    DEY
    BPL rtc_copy_bcd
    CLC
.rtc_osword0e_done
    RTS

.rtc_string
    JSR rtc_format
    CLC
    RTS

; Subcall 2: convert the caller's BCD block
.rtc_convert
    LDY #1
.rtc_convert_copy
    LDA (OSWORD_BLK), Y
    STA ws - 1, Y
    INY
    CPY #8
    BNE rtc_convert_copy
    LDX #&20
    LDA rtc_year
    CMP #&80
    BCC rtc_convert_century
    LDX #&19
.rtc_convert_century
    STX rtc_century
    JSR rtc_format
    CLC
    RTS

; Read the DS3234 into ws. C=1 if the clock is not valid.
.rtc_read
    JSR spi_init
    LDA #DEV_RTC
    JSR spi_select3
    LDA #RTC_STATUS
    JSR spi_xfer3
    JSR spi_xfer3
    PHA
    JSR spi_deselect
    PLA
    BMI rtc_invalid         ; Oscillator stopped, or no RTC (reads &FF)

    LDA #DEV_RTC
    JSR spi_select3
    LDA #RTC_SECONDS        ; Burst read registers 00-06
    JSR spi_xfer3
    LDY #0
.rtc_read_loop
    JSR spi_xfer3
    LDX rtc_reg_to_ws, Y
    STA ws, X
    INY
    CPY #7
    BNE rtc_read_loop
    JSR spi_deselect

    LDA rtc_hours
    AND #%00111111          ; 24-hour mode (as SPISETTIME sets it)
    STA rtc_hours
    LDX #&20
    LDA rtc_month
    BPL rtc_read_century
    LDX #&21
.rtc_read_century
    STX rtc_century
    AND #%00011111
    STA rtc_month
    BEQ rtc_invalid         ; Month 0: nothing sensible answered
    CLC
    RTS
.rtc_invalid
    SEC
    RTS

; DS3234 registers 00-06 (seconds, minutes, hours, weekday, date, month,
; year) to their offsets in the OSWORD &0E,1 block
.rtc_reg_to_ws
    EQUB 6, 5, 4, 3, 2, 1, 0

; Write "Ddd,dd Mon yyyy.hh:mm:ss" + CR to the OSWORD block from ws.
; An unknown weekday prints as spaces and an unknown month as "???".
.rtc_format
    LDA rtc_weekday
    CMP #8
    BCC rtc_weekday_ok
    LDA #0
.rtc_weekday_ok
    TAX
    LDA rtc_name_offset, X
    TAX
    LDY #0
.rtc_day_name
    LDA rtc_day_names, X
    JSR rtc_put
    INX
    CPY #3
    BNE rtc_day_name
    LDA #','
    JSR rtc_put
    LDA rtc_date
    JSR rtc_put_bcd
    LDA #' '
    JSR rtc_put

    LDA rtc_month           ; BCD &01-&12 to binary 1-12
    CMP #&10
    BCC rtc_month_bin
    SBC #6
.rtc_month_bin
    CMP #13
    BCC rtc_month_ok
    LDA #0
.rtc_month_ok
    TAX
    LDA rtc_name_offset, X
    TAX
.rtc_month_name
    LDA rtc_month_names, X
    JSR rtc_put
    INX
    CPY #10
    BNE rtc_month_name
    LDA #' '
    JSR rtc_put

    LDA rtc_century
    JSR rtc_put_bcd
    LDA rtc_year
    JSR rtc_put_bcd
    LDA #'.'
    JSR rtc_put
    LDA rtc_hours
    JSR rtc_put_bcd
    LDA #':'
    JSR rtc_put
    LDA rtc_minutes
    JSR rtc_put_bcd
    LDA #':'
    JSR rtc_put
    LDA rtc_seconds
    JSR rtc_put_bcd
    LDA #13
    ; Fall through

; Store A at block offset Y and advance Y. Preserves X.
.rtc_put
    STA (OSWORD_BLK), Y
    INY
    RTS

; Store BCD A as two digits. Preserves X.
.rtc_put_bcd
    PHA
    LSR A
    LSR A
    LSR A
    LSR A
    ORA #'0'
    JSR rtc_put
    PLA
    AND #&0F
    ORA #'0'
    JMP rtc_put

; ------ OSWORD &0F ------

; With &A8-&AF free. C=0 if claimed.
.rtc_osword0f
    LDY #0
    LDA (OSWORD_BLK), Y
    CMP #8
    BEQ rtc_set_time
    CMP #15
    BEQ rtc_set_date
    CMP #24
    BEQ rtc_set_both
.rtc_set_invalid
    SEC
    RTS

.rtc_set_time
    LDY #1
    JSR rtc_parse_time
    BCS rtc_set_invalid
    JSR rtc_write_time
    JMP rtc_set_done

.rtc_set_date
    JSR rtc_parse_date
    BCS rtc_set_invalid
    JSR rtc_write_date
    JMP rtc_set_done

.rtc_set_both
    JSR rtc_parse_date
    BCS rtc_set_invalid
    LDY #17
    JSR rtc_parse_time
    BCS rtc_set_invalid
    JSR rtc_write_date
    JSR rtc_write_time
.rtc_set_done
    JSR rtc_clear_osf
    CLC
    RTS

; Parse "hh:mm:ss" at block offset Y into set_hours/minutes/seconds.
; C=1 if invalid.
.rtc_parse_time
    JSR rtc_parse2
    BCS rtc_parse_fail
    CMP #24
    BCS rtc_parse_fail
    STA set_hours
    INY
    JSR rtc_parse2
    BCS rtc_parse_fail
    CMP #60
    BCS rtc_parse_fail
    STA set_minutes
    INY
    JSR rtc_parse2
    BCS rtc_parse_fail
    CMP #60
    BCS rtc_parse_fail
    STA set_seconds
    RTS                     ; C=0

.rtc_parse_fail
    SEC
    RTS

; Parse "Ddd,dd Mon yyyy" at block offset 1 into set_date, set_month,
; set_year and set_century. The weekday name is not looked at.
; C=1 if invalid.
.rtc_parse_date
    LDY #12                 ; Century
    JSR rtc_parse2
    BCS rtc_parse_fail
    SEC
    SBC #20
    CMP #2
    BCS rtc_parse_fail      ; Not 20 or 21
    STA set_century
    JSR rtc_parse2          ; Year within the century
    BCS rtc_parse_fail
    STA set_year

    LDA #1                  ; Month: match the name at offset 8
    STA set_month
    LDX #0
.rtc_month_try
    LDY #8
.rtc_month_char
    LDA (OSWORD_BLK), Y
    EOR rtc_month_names + 3, X
    AND #%11011111          ; Ignore case
    BNE rtc_month_next
    INX
    INY
    CPY #11
    BNE rtc_month_char
    BEQ rtc_month_found     ; Always
.rtc_month_next
    INC set_month
    LDX set_month
    CPX #13
    BCS rtc_parse_fail
    LDA rtc_name_offset - 1, X
    TAX
    JMP rtc_month_try
.rtc_month_found

    LDY #5                  ; Date: 1 to the length of the month
    JSR rtc_parse2
    BCS rtc_parse_fail
    STA set_date
    CMP #1
    BCC rtc_parse_fail
    LDX set_month
    LDA rtc_month_days - 1, X
    CPX #2
    BNE rtc_check_date
    JSR rtc_leap_year       ; February: add 1 in a leap year
    ADC #28
.rtc_check_date
    CMP set_date
    BCC rtc_parse_fail      ; Days in month < date
    CLC
    RTS

; C=1 if set_year/set_century is a leap year: every 4 years, but not
; 2100 (2000 is, being divisible by 400)
.rtc_leap_year
    LDA set_year
    AND #3
    BNE rtc_not_leap
    LDA set_year
    ORA set_century
    BNE rtc_leap_not_2100
    SEC                     ; 2000
    RTS
.rtc_leap_not_2100
    LDA set_year
    BEQ rtc_not_leap        ; 2100
    SEC
    RTS
.rtc_not_leap
    LDA #0
    CLC
    RTS

; Parse two decimal digits at block offset Y into A (binary), Y += 2.
; C=1 if either is not a digit.
.rtc_parse2
    LDA (OSWORD_BLK), Y
    JSR rtc_digit
    BCS rtc_parse2_done
    ASL A                   ; Tens * 10 = tens * 2 + tens * 8
    STA set_temp
    ASL A
    ASL A
    ADC set_temp
    STA set_temp
    INY
    LDA (OSWORD_BLK), Y
    JSR rtc_digit
    BCS rtc_parse2_done
    ADC set_temp            ; C=0 from rtc_digit
    INY
.rtc_parse2_done
    RTS

; ASCII digit in A to 0-9; C=1 if not a digit
.rtc_digit
    SEC
    SBC #'0'
    CMP #10
    RTS

; Weekday, 1 = Sunday ... 7 = Saturday, from the set_ date fields.
; Sakamoto's method: for year Y (less 1 in January and February),
;   (Y + Y/4 - Y/100 + Y/400 + t[month] + date) mod 7, 0 = Sunday.
; With Y = 2000 + k, the 2000 parts sum to 2485 = 0 (mod 7), leaving
; k + k/4 - k/100 for k = 0-199, which fits in 8 bits. Y = 1999 (k = -1)
; contributes 2483 = 5 (mod 7).
.rtc_weekday_of
    LDA set_year
    LDX set_century
    BEQ rtc_weekday_k
    CLC
    ADC #100
.rtc_weekday_k              ; A = k
    LDX set_month
    CPX #3
    BCS rtc_weekday_sum
    SEC                     ; January or February: k - 1
    SBC #1
    BCS rtc_weekday_sum
    LDA #5                  ; 1999
    BNE rtc_weekday_month   ; Always
.rtc_weekday_sum
    STA set_temp
    LSR A
    LSR A
    CLC
    ADC set_temp            ; k + k/4 <= 248
    LDX set_temp
    CPX #100
    BCC rtc_weekday_month
    SBC #1                  ; - k/100 (C=1 from CPX)
.rtc_weekday_month
    JSR rtc_mod7
    LDX set_month
    CLC
    ADC rtc_weekday_t - 1, X
    ADC set_date
    JSR rtc_mod7
    CLC
    ADC #1
    RTS

.rtc_mod7
    CMP #7
    BCC rtc_mod7_done
    SBC #7
    BCS rtc_mod7            ; Always
.rtc_mod7_done
    RTS

; Binary 0-99 in A to BCD. Corrupts X.
.rtc_to_bcd
    LDX #0
.rtc_to_bcd_tens
    CMP #10
    BCC rtc_to_bcd_done
    SBC #10
    INX
    BNE rtc_to_bcd_tens     ; Always
.rtc_to_bcd_done
    STA set_temp
    TXA
    ASL A
    ASL A
    ASL A
    ASL A
    ORA set_temp
    RTS

; Write set_hours/minutes/seconds to registers 00-02. Writing the
; seconds restarts the DS3234's sub-second countdown.
.rtc_write_time
    LDA set_seconds
    JSR rtc_to_bcd
    STA set_seconds
    LDA set_minutes
    JSR rtc_to_bcd
    STA set_minutes
    LDA set_hours
    JSR rtc_to_bcd          ; Bit 6 = 0: 24-hour mode
    STA set_hours
    JSR spi_init
    LDA #DEV_RTC
    JSR spi_select3
    LDA #RTC_SECONDS OR RTC_WRITE
    JSR spi_xfer3
    LDY #0
.rtc_write_time_loop
    LDA set_seconds, Y
    JSR spi_xfer3
    INY
    CPY #3
    BNE rtc_write_time_loop
    JMP spi_deselect

; Write the weekday and set_date/month/year/century to registers 03-06
.rtc_write_date
    JSR rtc_weekday_of
    PHA
    LDA set_month
    JSR rtc_to_bcd
    LDX set_century
    BEQ rtc_write_date_month
    ORA #RTC_CENTURY
.rtc_write_date_month
    STA set_month
    PLA
    STA set_century         ; Now the weekday, in register order
    LDA set_date
    JSR rtc_to_bcd
    STA set_date
    LDA set_year
    JSR rtc_to_bcd
    STA set_year
    JSR spi_init
    LDA #DEV_RTC
    JSR spi_select3
    LDA #RTC_WEEKDAY OR RTC_WRITE
    JSR spi_xfer3
    LDA set_century         ; Weekday
    JSR spi_xfer3
    LDA set_date
    JSR spi_xfer3
    LDA set_month
    JSR spi_xfer3
    LDA set_year
    JSR spi_xfer3
    JMP spi_deselect

; Clear the oscillator stop flag (status bit 7). Writing back the alarm
; flags as read leaves them as they are (they can only be written to 0).
.rtc_clear_osf
    JSR spi_init
    LDA #DEV_RTC
    JSR spi_select3
    LDA #RTC_STATUS
    JSR spi_xfer3
    JSR spi_xfer3
    PHA
    JSR spi_deselect
    LDA #DEV_RTC
    JSR spi_select3
    LDA #RTC_STATUS OR RTC_WRITE
    JSR spi_xfer3
    PLA
    AND #&FF EOR RTC_OSF
    JSR spi_xfer3
    JMP spi_deselect

; Sakamoto's month offsets, January first
.rtc_weekday_t
    EQUB 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4
.rtc_month_days
    EQUB 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

.rtc_name_offset
    EQUB 0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36
.rtc_day_names
    EQUS "   SunMonTueWedThuFriSat"
.rtc_month_names
    EQUS "???JanFebMarAprMayJunJulAugSepOctNovDec"
