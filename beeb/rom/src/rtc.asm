; RTC module
; Answers OSWORD &0E (read clock) from the DS3234 on J5, so *TIME and
; TIME$ see real time. See "Module: RTC" in docs/rom-design.md.
;
; Subcalls handled:
;   0  Return "Ddd,dd Mon yyyy.hh:mm:ss" + CR (25 bytes), real century
;   1  Return 7 BCD bytes: year, month, date, weekday (1 = Sunday),
;      hours, minutes, seconds
;   2  Convert the 7 BCD bytes at XY+1 into a string (year &00-&79 is
;      20xx). Experimental: on MOS 5.10 this only takes effect if the MOS
;      offers subcall 2 to ROMs before converting it itself.
; Everything else is passed on, including subcalls 3 and 4 (ANFS's file
; server time). If the DS3234's oscillator stop flag is set, or no RTC
; answers, subcalls 0 and 1 are passed on too, so ANFS or the MOS
; default answer instead. OSWORD calls never raise errors.

; DS3234 registers
RTC_SECONDS = &00
RTC_STATUS  = &0F
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

; Service &08 handler. Return C=0 if claimed, C=1 to pass on.
; May corrupt A, X, Y (the dispatcher saves them).
.rtc_osword
    LDA OSWORD_A
    CMP #&0E
    BNE rtc_pass
    LDY #0
    LDA (OSWORD_BLK), Y
    CMP #3
    BCS rtc_pass            ; Only subcalls 0-2

    LDX #7                  ; Save &A8-&AF
.rtc_save_ws
    LDA ws, X
    PHA
    DEX
    BPL rtc_save_ws

    JSR rtc_osword0e

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

.rtc_name_offset
    EQUB 0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36
.rtc_day_names
    EQUS "   SunMonTueWedThuFriSat"
.rtc_month_names
    EQUS "???JanFebMarAprMayJunJulAugSepOctNovDec"
