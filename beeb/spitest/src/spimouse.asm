; SPItFIRE Mouse Test
; Polls mouse data from AVR at 100 Hz, displays at 10 Hz
; Shows delta X/Y, accumulated totals, and button states

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

; Device numbers (via 74HC138)
DEV_NONE     = %00000000    ; Y0 - no device
DEV_SPITFIRE = %00000100    ; Y1 - SPItFIRE (A0=1)

; Inverted masks for AND operations
NOT_SEL  = %11100011        ; Clear decoder bits
NOT_SCK  = %11111101

; SPI mouse commands (match protocol.md)
CMD_MOUSE_X   = &30
CMD_MOUSE_Y   = &31
CMD_MOUSE_BTN = &32

; SPI config commands
CMD_MODE_AMX   = &F1
CMD_MODE_AMIGA = &F2
CMD_MODE_ATARI = &F3

; OS calls
OSWRCH = &FFEE
OSNEWL = &FFE7
OSBYTE = &FFF4
OSWORD = &FFF1

; Zero page variables
spi_temp    = &70           ; SPI transfer temp
mouse_dx    = &71           ; Last delta X (signed)
mouse_dy    = &72           ; Last delta Y (signed)
mouse_btn   = &73           ; Button state
total_x_lo  = &74           ; 16-bit accumulated X (signed)
total_x_hi  = &75
total_y_lo  = &76           ; 16-bit accumulated Y (signed)
total_y_hi  = &77
display_cnt = &78           ; Down-counter for display update
last_time   = &79           ; Last centisecond tick (low byte)
mouse_mode  = &7A           ; Current mode (1=AMX, 2=Amiga, 3=Atari)

.start
    JSR init_via
    JSR init_vars
    JSR init_display

.main_loop
    ; Wait for centisecond tick (100 Hz)
    JSR wait_tick

    ; Poll mouse over SPI: X, Y, buttons
    JSR poll_mouse

    ; Accumulate deltas into totals
    JSR accumulate

    ; Check for mode switch keys (1/2/3)
    JSR check_keys

    ; Display update every 10th poll (10 Hz)
    DEC display_cnt
    BNE check_escape
    LDA #10
    STA display_cnt
    JSR update_display

.check_escape
    BIT &FF
    BMI done

    JMP main_loop

.done
    ; Clear Escape condition
    LDA #&7E
    JSR OSBYTE

    ; Move cursor below display area
    LDA #31 : JSR OSWRCH
    LDA #0  : JSR OSWRCH
    LDA #12 : JSR OSWRCH
    JSR OSNEWL
    RTS

; ------ Initialisation ------

.init_vars
    LDA #0
    STA mouse_dx
    STA mouse_dy
    STA mouse_btn
    STA total_x_lo
    STA total_x_hi
    STA total_y_lo
    STA total_y_hi
    LDA #10
    STA display_cnt
    LDA #0
    STA last_time
    LDA #1
    STA mouse_mode          ; Default: AMX
    RTS

.init_display
    ; MODE 7 (teletext, low CPU cost)
    LDA #22 : JSR OSWRCH
    LDA #7  : JSR OSWRCH

    ; Hide cursor
    LDA #23 : JSR OSWRCH
    LDA #1  : JSR OSWRCH
    LDA #0
    JSR OSWRCH : JSR OSWRCH : JSR OSWRCH
    JSR OSWRCH : JSR OSWRCH : JSR OSWRCH
    JSR OSWRCH : JSR OSWRCH

    ; Print header
    LDX #0
.print_header
    LDA header_msg, X
    BEQ init_display_done
    JSR OSWRCH
    INX
    BNE print_header
.init_display_done
    RTS

; ------ Timing ------

; Wait for centisecond tick to change (100 Hz)
.wait_tick
    LDA #1
    LDX #LO(time_buf)
    LDY #HI(time_buf)
    JSR OSWORD
    LDA time_buf
    CMP last_time
    BEQ wait_tick
    STA last_time
    RTS

.time_buf
    EQUD 0
    EQUB 0

; ------ SPI Communication ------

; Poll mouse: sends 3 commands, stores dx, dy, buttons
.poll_mouse
    ; --- MOUSE_X ---
    JSR select_device
    LDA #CMD_MOUSE_X
    JSR spi_transfer        ; Send command (ignore stale response)
    LDA #&00
    JSR spi_transfer        ; Send dummy, receive dx
    STA mouse_dx
    JSR deselect_device

    ; --- MOUSE_Y ---
    JSR select_device
    LDA #CMD_MOUSE_Y
    JSR spi_transfer
    LDA #&00
    JSR spi_transfer
    STA mouse_dy
    JSR deselect_device

    ; --- MOUSE_BTN ---
    JSR select_device
    LDA #CMD_MOUSE_BTN
    JSR spi_transfer
    LDA #&00
    JSR spi_transfer
    STA mouse_btn
    JSR deselect_device

    RTS

.select_device
    LDA IORB
    AND #NOT_SEL
    ORA #DEV_SPITFIRE
    STA IORB
    NOP : NOP : NOP : NOP
    RTS

.deselect_device
    LDA IORB
    AND #NOT_SEL
    STA IORB
    RTS

; ------ Accumulation ------

; total_x += sign_extend(mouse_dx)
; total_y += sign_extend(mouse_dy)
.accumulate
    ; X axis
    CLC
    LDA mouse_dx
    BPL acc_x_pos
    ; Negative: sign-extend high byte = &FF
    ADC total_x_lo
    STA total_x_lo
    LDA #&FF
    ADC total_x_hi
    STA total_x_hi
    JMP acc_y
.acc_x_pos
    ADC total_x_lo
    STA total_x_lo
    LDA #0
    ADC total_x_hi
    STA total_x_hi

.acc_y
    ; Y axis
    CLC
    LDA mouse_dy
    BPL acc_y_pos
    ADC total_y_lo
    STA total_y_lo
    LDA #&FF
    ADC total_y_hi
    STA total_y_hi
    RTS
.acc_y_pos
    ADC total_y_lo
    STA total_y_lo
    LDA #0
    ADC total_y_hi
    STA total_y_hi
    RTS

; ------ Key Handling ------

; Check for mode switch keys 1/2/3
.check_keys
    LDA #&81                ; OSBYTE 129 = INKEY
    LDX #0                  ; Timeout low = 0
    LDY #0                  ; Timeout high = 0 (non-blocking)
    JSR OSBYTE
    BCS no_key              ; Carry set = no key available
    CPX #'1'
    BEQ set_mode_amx
    CPX #'2'
    BEQ set_mode_amiga
    CPX #'3'
    BEQ set_mode_atari
.no_key
    RTS

.set_mode_amx
    LDA #CMD_MODE_AMX
    LDX #1
    BNE send_mode           ; Always branches
.set_mode_amiga
    LDA #CMD_MODE_AMIGA
    LDX #2
    BNE send_mode
.set_mode_atari
    LDA #CMD_MODE_ATARI
    LDX #3

.send_mode
    STX mouse_mode
    PHA                     ; Save command
    ; Reset totals on mode switch
    LDX #0
    STX total_x_lo
    STX total_x_hi
    STX total_y_lo
    STX total_y_hi
    ; Send mode command to AVR
    JSR select_device
    PLA                     ; Restore command
    JSR spi_transfer        ; Send command
    LDA #&00
    JSR spi_transfer        ; Send dummy, receive confirmation
    JSR deselect_device
    ; Force display update
    LDA #1
    STA display_cnt
    RTS

; ------ Display ------

.update_display
    ; Row 3: Delta values
    LDA #31 : JSR OSWRCH
    LDA #0  : JSR OSWRCH
    LDA #3  : JSR OSWRCH

    LDX #0
.print_dx_label
    LDA dx_label, X
    BEQ print_dx_val
    JSR OSWRCH
    INX
    BNE print_dx_label
.print_dx_val
    LDA mouse_dx
    JSR print_signed_hex
    LDA #' '
    JSR OSWRCH
    JSR OSWRCH

    ; dY on same line
    LDX #0
.print_dy_label
    LDA dy_label, X
    BEQ print_dy_val
    JSR OSWRCH
    INX
    BNE print_dy_label
.print_dy_val
    LDA mouse_dy
    JSR print_signed_hex
    LDA #' '
    JSR OSWRCH
    JSR OSWRCH

    ; Row 5: Accumulated totals
    LDA #31 : JSR OSWRCH
    LDA #0  : JSR OSWRCH
    LDA #5  : JSR OSWRCH

    LDX #0
.print_tx_label
    LDA tx_label, X
    BEQ print_tx_val
    JSR OSWRCH
    INX
    BNE print_tx_label
.print_tx_val
    LDA total_x_hi
    JSR print_hex_byte
    LDA total_x_lo
    JSR print_hex_byte

    LDA #' '
    JSR OSWRCH
    JSR OSWRCH

    LDX #0
.print_ty_label
    LDA ty_label, X
    BEQ print_ty_val
    JSR OSWRCH
    INX
    BNE print_ty_label
.print_ty_val
    LDA total_y_hi
    JSR print_hex_byte
    LDA total_y_lo
    JSR print_hex_byte

    ; Row 6: Mode
    LDA #31 : JSR OSWRCH
    LDA #0  : JSR OSWRCH
    LDA #6  : JSR OSWRCH

    LDX #0
.print_mode_label
    LDA mode_label, X
    BEQ print_mode_val
    JSR OSWRCH
    INX
    BNE print_mode_label
.print_mode_val
    LDA mouse_mode
    CMP #1 : BNE not_mode_1
    LDX #0 : BEQ print_mode_name   ; Always branches
.not_mode_1
    CMP #2 : BNE not_mode_2
    LDX #4 : BNE print_mode_name
.not_mode_2
    LDX #10
.print_mode_name
    LDA mode_names, X
    BEQ mode_name_done
    JSR OSWRCH
    INX
    BNE print_mode_name
.mode_name_done
    ; Pad with spaces
    LDA #' '
    JSR OSWRCH
    JSR OSWRCH
    JSR OSWRCH

    ; Row 8: Buttons
    LDA #31 : JSR OSWRCH
    LDA #0  : JSR OSWRCH
    LDA #8  : JSR OSWRCH

    LDX #0
.print_btn_label
    LDA btn_label, X
    BEQ show_buttons
    JSR OSWRCH
    INX
    BNE print_btn_label

.show_buttons
    ; Left button (bit 0)
    LDA mouse_btn
    AND #&01
    BEQ btn_l_off
    LDA #'L'
    JMP btn_l_done
.btn_l_off
    LDA #'-'
.btn_l_done
    JSR OSWRCH
    LDA #' '
    JSR OSWRCH

    ; Middle button (bit 2)
    LDA mouse_btn
    AND #&04
    BEQ btn_m_off
    LDA #'M'
    JMP btn_m_done
.btn_m_off
    LDA #'-'
.btn_m_done
    JSR OSWRCH
    LDA #' '
    JSR OSWRCH

    ; Right button (bit 1)
    LDA mouse_btn
    AND #&02
    BEQ btn_r_off
    LDA #'R'
    JMP btn_r_done
.btn_r_off
    LDA #'-'
.btn_r_done
    JSR OSWRCH
    LDA #' '
    JSR OSWRCH

    RTS

; Print A as signed hex: +XX or -XX
.print_signed_hex
    BPL pos_val
    ; Negative
    PHA
    LDA #'-'
    JSR OSWRCH
    PLA
    ; Negate: NOT + 1
    EOR #&FF
    CLC
    ADC #1
    JMP print_hex_byte
.pos_val
    PHA
    LDA #'+'
    JSR OSWRCH
    PLA
    ; Fall through to print_hex_byte

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
    BCC hex_digit
    ADC #6
.hex_digit
    ADC #&30
    JMP OSWRCH

; ------ VIA Initialisation ------

.init_via
    ; Disable CB1/CB2 interrupts
    LDA #%00011000
    STA IER

    ; Set PCR to known state
    LDA #%00000000
    STA PCR

    ; Set ACR to known state: SR disabled
    LDA #%00000000
    STA ACR

    ; Set PB0 (MOSI), PB1 (SCK), PB2-4 (decoder) as outputs
    LDA DDRB
    ORA #MOSI OR SCK OR SEL_MASK
    STA DDRB

    ; Set idle state: device 0 (none), SCK low, MOSI high
    LDA IORB
    AND #NOT_SEL AND NOT_SCK
    ORA #MOSI
    STA IORB

    RTS

; SPI transfer: send byte in A, return received byte in A
.spi_transfer
    STA spi_temp

    ; Ensure SR disabled
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
    LDA spi_temp
    ASL A
    STA spi_temp

    LDA IORB
    AND #%11111110          ; Clear MOSI
    BCC spi_mosi_low
    ORA #MOSI
.spi_mosi_low
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

; ------ String Data ------

.header_msg
    EQUS "SPItFIRE Mouse Test", 13, 10
    EQUS "1=AMX  2=Amiga  3=Atari", 13, 10, 0

.dx_label
    EQUS "dX=", 0

.dy_label
    EQUS "dY=", 0

.tx_label
    EQUS "X=", 0

.ty_label
    EQUS "Y=", 0

.mode_label
    EQUS "Mode: ", 0

.mode_names
    EQUS "AMX", 0           ; offset 0 (mode 1)
    EQUS "Amiga", 0         ; offset 4 (mode 2)
    EQUS "Atari", 0         ; offset 10 (mode 3)

.btn_label
    EQUS "Buttons: ", 0

.end

SAVE "SPIMOUSE", start, end
