; SPItFIRE Joystick Test
; Needs the spijoy firmware. Shows both joystick ports in MODE 1: stick
; positions as crosses in boxes, raw 10-bit values, and buttons. The A
; and B keys cycle each port through None, Delta 3B Single, Delta 3B
; Twin, Delta 14B and Acorn Bitstik.

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
SEL_MASK = %00011100        ; All decoder bits (PB2-PB4)

; Device numbers (via 74HC138)
DEV_SPITFIRE = %00000100    ; Y1 - SPItFIRE (A0=1)

NOT_SEL  = %11100011        ; Clear decoder bits
NOT_SCK  = %11111101

; SPI joystick commands (see firmware/src/spijoy.cpp)
CMD_JOY_A0   = &40          ; +port*4+channel: channel low byte
CMD_JOY_HI   = &48          ; latched high byte
CMD_JOY_BTN  = &49          ; fire inputs
CMD_JOY_KEY  = &4A          ; +port: 14B keypad buttons 0-7
CMD_JOY_TYPE = &E0          ; +port*4+firmware type

; Joystick types, in the order the A and B keys cycle through them
T_NONE    = 0
T_3BS     = 1
T_3BT     = 2
T_14B     = 3
T_BITSTIK = 4
NUM_TYPES = 5

; OS calls
OSWRCH = &FFEE
OSBYTE = &FFF4

; Zero page variables
spi_temp = &70              ; SPI transfer temp
spi_x    = &71              ; X saved across spi_cmd
port     = &72              ; Port being processed (0=A, 1=B)
chbase   = &73              ; port*4: index of the port's channel 0
cur_type = &74              ; Type of the port being processed
stick    = &75              ; Marker index: port*2 + stick
frame    = &76              ; Frame counter
ptr      = &77              ; 2 bytes: inline data pointer
base     = &79              ; 2 bytes: panel's graphics X origin
tmp      = &7B              ; 2 bytes
val      = &7D              ; 2 bytes
cx       = &7F              ; 2 bytes: cross centre
cy       = &81              ; 2 bytes
px       = &83              ; 2 bytes: plot point
py       = &85              ; 2 bytes
nx       = &87              ; 2 bytes: new marker position
ny       = &89              ; 2 bytes

.start
    JSR init_via
    LDA #T_NONE
    STA type
    STA type+1
    LDA #0
    STA frame
    LDX #LO(vdu_init)
    LDY #HI(vdu_init)
    JSR vdu_list
    LDX #0
    JSR set_port_type
    LDX #1
    JSR set_port_type

.main_loop
    LDA #19                 ; Wait for vsync
    JSR OSBYTE
    LDA #CMD_JOY_BTN
    JSR spi_cmd
    STA buttons
    LDX #0
    JSR do_port
    LDX #1
    JSR do_port
    INC frame
    JSR check_keys
    BIT &FF
    BPL main_loop

    LDA #&7E                ; Acknowledge Escape
    JSR OSBYTE
    LDX #LO(vdu_exit)
    LDY #HI(vdu_exit)
    JMP vdu_list

; ------ Ports ------

; Set up port, chbase and base for port X
.port_setup
    STX port
    TXA
    ASL A
    ASL A
    STA chbase
    LDA #0
    STA base
    STA base+1
    CPX #0
    BEQ port_setup_done
    LDA #LO(640)
    STA base
    LDA #HI(640)
    STA base+1
.port_setup_done
    RTS

; Tell the firmware port X's type and redraw its panel
.set_port_type
    JSR port_setup
    LDY type, X
    LDA fw_type, Y
    ORA chbase
    ORA #CMD_JOY_TYPE
    JSR spi_cmd
    JMP draw_panel

; Read and display port X
.do_port
    JSR port_setup
    LDA type, X
    BEQ do_port_done
    STA cur_type
    JSR read_port
    LDA #0
    JSR update_marker
    LDA cur_type
    CMP #T_3BT
    BNE do_port_text
    LDA #1
    JSR update_marker
.do_port_text
    LDA frame
    AND #3
    BNE do_port_done
    JSR update_text
.do_port_done
    RTS

; Read the channels (and keypad) the port's type uses
.read_port
    LDY #2
    LDA cur_type
    CMP #T_3BT
    BEQ read_port_4
    CMP #T_BITSTIK
    BNE read_port_n
.read_port_4
    LDY #4
.read_port_n
    STY nch
    LDY #0
.read_port_channel
    TYA
    CLC
    ADC chbase
    TAX
    ORA #CMD_JOY_A0
    JSR spi_cmd
    STA raw_lo, X
    LDA #CMD_JOY_HI
    JSR spi_cmd
    STA raw_hi, X
    INY
    CPY nch
    BNE read_port_channel

    LDA cur_type
    CMP #T_14B
    BNE read_port_done
    LDX port
    TXA
    ORA #CMD_JOY_KEY
    JSR spi_cmd
    STA keys_lo, X
    LDA #CMD_JOY_HI
    JSR spi_cmd
    STA keys_hi, X
.read_port_done
    RTS

.check_keys
    LDA #&81                ; INKEY(0)
    LDX #0
    LDY #0
    JSR OSBYTE
    BCS check_keys_done
    TXA
    AND #&DF                ; Upper case
    LDX #0
    CMP #'A'
    BEQ check_keys_port
    INX
    CMP #'B'
    BNE check_keys_done
.check_keys_port
    INC type, X
    LDA type, X
    CMP #NUM_TYPES
    BCC check_keys_set
    LDA #T_NONE
    STA type, X
.check_keys_set
    JMP set_port_type
.check_keys_done
    RTS

; ------ Panels ------

; Clear the port's panel, print its title and draw its boxes
.draw_panel
    LDA port
    ASL A
    TAX
    LDA #0
    STA drawn, X
    STA drawn+1, X

    LDA #0                  ; GCOL 0,0
    JSR gcol0
    JSR plot_inline
    EQUB 4 : EQUW 0, 64
    JSR plot_inline
    EQUB 101 : EQUW 639, 895    ; Rectangle fill

    LDA #3
    LDY #0
    JSR tab_row
    LDA port
    CLC
    ADC #'A'
    JSR OSWRCH
    LDA #':'
    JSR OSWRCH
    LDA #' '
    JSR OSWRCH
    LDX port
    LDA type, X
    ASL A
    ASL A
    ASL A
    ASL A
    TAX
.draw_panel_name
    LDA type_names, X
    BEQ draw_panel_boxes
    JSR OSWRCH
    INX
    BNE draw_panel_name

.draw_panel_boxes
    LDA #3                  ; GCOL 0,3
    JSR gcol0
    LDX port
    LDA type, X
    BEQ draw_panel_done
    CMP #T_3BT
    BEQ draw_panel_twin
    JSR plot_inline
    EQUB 4 : EQUW 60, 364
    JSR plot_inline
    EQUB 5 : EQUW 576, 364
    JSR plot_inline
    EQUB 5 : EQUW 576, 880
    JSR plot_inline
    EQUB 5 : EQUW 60, 880
    JSR plot_inline
    EQUB 5 : EQUW 60, 364
.draw_panel_done
    RTS

.draw_panel_twin
    JSR plot_inline
    EQUB 4 : EQUW 44, 492
    JSR plot_inline
    EQUB 5 : EQUW 304, 492
    JSR plot_inline
    EQUB 5 : EQUW 304, 752
    JSR plot_inline
    EQUB 5 : EQUW 44, 752
    JSR plot_inline
    EQUB 5 : EQUW 44, 492
    JSR plot_inline
    EQUB 4 : EQUW 332, 492
    JSR plot_inline
    EQUB 5 : EQUW 592, 492
    JSR plot_inline
    EQUB 5 : EQUW 592, 752
    JSR plot_inline
    EQUB 5 : EQUW 332, 752
    JSR plot_inline
    EQUB 5 : EQUW 332, 492
    LDA #7
    LDY #2
    JSR tab_row
    JSR print_inline
    EQUS "Left", 0
    LDA #7
    LDY #11
    JSR tab_row
    JSR print_inline
    EQUS "Right", 0
    RTS

; ------ Markers ------

; Move stick A's cross to its current reading
.update_marker
    STA k_cur
    LDA port
    ASL A
    ORA k_cur
    STA stick
    LDY #0                  ; Box: 0 = single, 1/2 = 3BT left/right
    LDA cur_type
    CMP #T_3BT
    BNE update_marker_box
    LDY k_cur
    INY
.update_marker_box
    STY geom

    LDA k_cur               ; X axis: channel 2k
    ASL A
    CLC
    ADC chbase
    STA rawi
    TAX
    LDA raw_lo, X
    STA tmp
    LDA raw_hi, X
    STA tmp+1
    JSR scale
    LDY cur_type
    LDA invert_x, Y
    BEQ update_marker_x
    JSR invert
.update_marker_x
    LDY geom
    CLC
    LDA tmp
    ADC box_left_lo, Y
    STA nx
    LDA tmp+1
    ADC box_left_hi, Y
    STA nx+1
    CLC
    LDA nx
    ADC base
    STA nx
    LDA nx+1
    ADC base+1
    STA nx+1

    LDX rawi                ; Y axis: channel 2k+1
    LDA raw_lo+1, X
    STA tmp
    LDA raw_hi+1, X
    STA tmp+1
    JSR scale
    LDY cur_type
    LDA invert_y, Y
    BEQ update_marker_y
    JSR invert
.update_marker_y
    LDY geom
    CLC
    LDA tmp
    ADC box_bottom_lo, Y
    STA ny
    LDA tmp+1
    ADC box_bottom_hi, Y
    STA ny+1

    LDX stick
    LDA drawn, X
    BEQ update_marker_draw
    LDA nx
    CMP drawn_xl, X
    BNE update_marker_erase
    LDA nx+1
    CMP drawn_xh, X
    BNE update_marker_erase
    LDA ny
    CMP drawn_yl, X
    BNE update_marker_erase
    LDA ny+1
    CMP drawn_yh, X
    BNE update_marker_erase
    RTS

.update_marker_erase
    LDA drawn_xl, X
    STA cx
    LDA drawn_xh, X
    STA cx+1
    LDA drawn_yl, X
    STA cy
    LDA drawn_yh, X
    STA cy+1
    JSR cross

.update_marker_draw
    LDX stick
    LDA nx
    STA cx
    STA drawn_xl, X
    LDA nx+1
    STA cx+1
    STA drawn_xh, X
    LDA ny
    STA cy
    STA drawn_yl, X
    LDA ny+1
    STA cy+1
    STA drawn_yh, X
    LDA #1
    STA drawn, X
    JMP cross

; Flip the scaled reading in tmp across its box: 255 - tmp for a 3BT
; half box, 511 - tmp otherwise
.invert
    LDX #LO(511)
    LDY #HI(511)
    LDA cur_type
    CMP #T_3BT
    BNE invert_sub
    LDX #LO(255)
    LDY #HI(255)
.invert_sub
    TXA
    SEC
    SBC tmp
    STA tmp
    TYA
    SBC tmp+1
    STA tmp+1
    RTS

; Scale the reading in tmp to box units for cur_type
.scale
    LDA cur_type
    CMP #T_3BT
    BEQ scale_quarter
    CMP #T_BITSTIK
    BEQ scale_bitstik
    LSR tmp+1               ; 0-1023 -> 0-511
    ROR tmp
    RTS
.scale_quarter
    LSR tmp+1               ; 0-1023 -> 0-255
    ROR tmp
    LSR tmp+1
    ROR tmp
    RTS
.scale_bitstik
    ; The Bitstik spans about 0-640: scale by 1/2 + 1/4 + 1/32 and clamp
    LSR tmp+1
    ROR tmp
    LDA tmp
    STA val
    LDA tmp+1
    STA val+1
    LSR tmp+1
    ROR tmp
    CLC
    LDA val
    ADC tmp
    STA val
    LDA val+1
    ADC tmp+1
    STA val+1
    LSR tmp+1
    ROR tmp
    LSR tmp+1
    ROR tmp
    LSR tmp+1
    ROR tmp
    CLC
    LDA val
    ADC tmp
    STA tmp
    LDA val+1
    ADC tmp+1
    STA tmp+1
    CMP #2
    BCC scale_done
    LDA #LO(511)
    STA tmp
    LDA #HI(511)
    STA tmp+1
.scale_done
    RTS

; Draw a cross, exclusive-ORed in yellow, centred on (cx, cy). Drawing
; it twice removes it.
.cross
    LDA #18
    JSR OSWRCH
    LDA #3
    JSR OSWRCH
    LDA #2
    JSR OSWRCH
    LDA #&F0
    LDY #0
    JSR set_p
    LDA #4
    JSR plot_p
    LDA #16
    LDY #0
    JSR set_p
    LDA #5
    JSR plot_p
    LDA #0
    LDY #&F0
    JSR set_p
    LDA #4
    JSR plot_p
    LDA #0
    LDY #16
    JSR set_p
    LDA #5
    JMP plot_p

; px = cx + A, py = cy + Y (signed offsets)
.set_p
    STY tmp
    LDX #0
    CMP #&80
    BCC set_p_x
    DEX
.set_p_x
    CLC
    ADC cx
    STA px
    TXA
    ADC cx+1
    STA px+1
    LDA tmp
    LDX #0
    CMP #&80
    BCC set_p_y
    DEX
.set_p_y
    CLC
    ADC cy
    STA py
    TXA
    ADC cy+1
    STA py+1
    RTS

; ------ Text ------

.update_text
    LDA #22
    LDY #0
    JSR tab_row
    LDA cur_type
    CMP #T_3BT
    BNE update_text_left
    JSR print_inline
    EQUS "L ", 0
.update_text_left
    LDA #0
    JSR print_axes

    LDA cur_type
    CMP #T_3BT
    BNE update_text_twist
    LDA #23
    LDY #0
    JSR tab_row
    JSR print_inline
    EQUS "R ", 0
    LDA #2
    JSR print_axes
    JMP update_text_buttons

.update_text_twist
    CMP #T_BITSTIK
    BNE update_text_buttons
    LDA #23
    LDY #0
    JSR tab_row
    JSR print_inline
    EQUS "Twist ", 0
    LDX chbase
    LDA raw_lo+2, X
    STA val
    LDA raw_hi+2, X
    STA val+1
    JSR print_dec4

.update_text_buttons
    LDA buttons             ; This port's fire inputs in bits 0-1
    LDX port
    BEQ update_text_fire
    LSR A
    LSR A
.update_text_fire
    STA pbtn
    LDA #25
    LDY #0
    JSR tab_row
    LDA cur_type
    CMP #T_14B
    BEQ update_text_keypad
    CMP #T_BITSTIK
    BEQ update_text_bitstik

    JSR print_inline
    EQUS "Fire ", 0
    LDA pbtn
    AND #1
    LDX #'L'
    JSR show_flag
    LDA #' '
    JSR OSWRCH
    LDA pbtn
    AND #2
    LDX #'R'
    JMP show_flag

.update_text_bitstik
    ; T and L are the fire inputs; R pulls CH3 below half scale
    JSR print_inline
    EQUS "Buttons ", 0
    LDA pbtn
    AND #1
    LDX #'T'
    JSR show_flag
    LDA #' '
    JSR OSWRCH
    LDA pbtn
    AND #2
    LDX #'L'
    JSR show_flag
    LDA #' '
    JSR OSWRCH
    LDX chbase
    LDA raw_hi+3, X
    CMP #2
    LDA #0
    BCS update_text_r
    LDA #1
.update_text_r
    LDX #'R'
    JMP show_flag

.update_text_keypad
    ; Buttons 9-11 on the top row down to 0-2 on the bottom row
    LDA #9
    STA keyn
    LDA #25
    STA keyrow
.keypad_row
    LDA keyrow
    LDY #0
    JSR tab_row
    JSR print_inline
    EQUS "Keys", 0
    LDA #3
    STA keycol
.keypad_key
    LDA #' '
    JSR OSWRCH
    LDX port
    LDA keyn
    CMP #8
    BCS keypad_high
    TAY
    LDA keys_lo, X
    AND bit_mask, Y
    JMP keypad_show
.keypad_high
    SBC #8
    TAY
    LDA keys_hi, X
    AND bit_mask, Y
.keypad_show
    JSR flag_colour
    LDA keyn
    CMP #10
    BCC keypad_units
    SBC #10
    PHA
    LDA #'1'
    BNE keypad_tens
.keypad_units
    PHA
    LDA #' '
.keypad_tens
    JSR OSWRCH
    PLA
    ORA #'0'
    JSR OSWRCH
    JSR white
    INC keyn
    DEC keycol
    BNE keypad_key
    LDA keyn
    SEC
    SBC #6
    STA keyn
    INC keyrow
    LDA keyrow
    CMP #29
    BNE keypad_row
    RTS

; Print "X nnnn Y nnnn" for channels A and A+1 of the port
.print_axes
    CLC
    ADC chbase
    STA rawi
    JSR print_inline
    EQUS "X ", 0
    LDX rawi
    LDA raw_lo, X
    STA val
    LDA raw_hi, X
    STA val+1
    JSR print_dec4
    JSR print_inline
    EQUS " Y ", 0
    LDX rawi
    LDA raw_lo+1, X
    STA val
    LDA raw_hi+1, X
    STA val+1
    JMP print_dec4

; Print character X in yellow if A is non-zero (pressed), red otherwise
.show_flag
    JSR flag_colour
    TXA
    JSR OSWRCH
.white
    LDA #17
    JSR OSWRCH
    LDA #3
    JMP OSWRCH

; Text colour yellow if A is non-zero, red if zero. Preserves X and Y.
.flag_colour
    CMP #0
    BEQ flag_colour_off
    LDA #2
    BNE flag_colour_set
.flag_colour_off
    LDA #1
.flag_colour_set
    PHA
    LDA #17
    JSR OSWRCH
    PLA
    JMP OSWRCH

; Move the text cursor to row A, column port*20 + Y
.tab_row
    PHA
    LDA #31
    JSR OSWRCH
    TYA
    LDX port
    BEQ tab_row_col
    CLC
    ADC #20
.tab_row_col
    JSR OSWRCH
    PLA
    JMP OSWRCH

; Print val (0-9999) as four decimal digits
.print_dec4
    LDX #0
.print_dec4_digit
    LDY #'0'
.print_dec4_sub
    SEC
    LDA val
    SBC pow_lo, X
    STA tmp
    LDA val+1
    SBC pow_hi, X
    BCC print_dec4_out
    STA val+1
    LDA tmp
    STA val
    INY
    BNE print_dec4_sub
.print_dec4_out
    TYA
    JSR OSWRCH
    INX
    CPX #4
    BNE print_dec4_digit
    RTS

; Print the zero-terminated string that follows the JSR
.print_inline
    PLA
    STA ptr
    PLA
    STA ptr+1
    LDY #0
.print_inline_next
    INC ptr
    BNE print_inline_char
    INC ptr+1
.print_inline_char
    LDA (ptr), Y
    BEQ print_inline_done
    JSR OSWRCH
    JMP print_inline_next
.print_inline_done
    LDA ptr+1
    PHA
    LDA ptr
    PHA
    RTS

; ------ Graphics ------

; GCOL 0, A
.gcol0
    PHA
    LDA #18
    JSR OSWRCH
    LDA #0
    JSR OSWRCH
    PLA
    JMP OSWRCH

; PLOT A, px, py
.plot_p
    PHA
    LDA #25
    JSR OSWRCH
    PLA
    JSR OSWRCH
    LDA px
    JSR OSWRCH
    LDA px+1
    JSR OSWRCH
    LDA py
    JSR OSWRCH
    LDA py+1
    JMP OSWRCH

; PLOT with the 5 bytes that follow the JSR: code, X (from the panel's
; origin), Y
.plot_inline
    PLA
    STA ptr
    PLA
    STA ptr+1
    LDY #2
    LDA (ptr), Y
    CLC
    ADC base
    STA px
    INY
    LDA (ptr), Y
    ADC base+1
    STA px+1
    INY
    LDA (ptr), Y
    STA py
    INY
    LDA (ptr), Y
    STA py+1
    LDY #1
    LDA (ptr), Y
    JSR plot_p
    CLC
    LDA ptr
    ADC #5
    STA ptr
    LDA ptr+1
    ADC #0
    PHA
    LDA ptr
    PHA
    RTS

; Send the VDU bytes in the length-prefixed list at YX
.vdu_list
    STX ptr
    STY ptr+1
    LDY #0
    LDA (ptr), Y
    TAX
.vdu_list_next
    INY
    LDA (ptr), Y
    JSR OSWRCH
    DEX
    BNE vdu_list_next
    RTS

; ------ SPI ------

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

    ; Set idle state: no device (Y7), SCK low, MOSI high
    LDA IORB
    AND #NOT_SCK              ; SCK low
    ORA #MOSI OR SEL_MASK     ; MOSI high, no device (Y7)
    STA IORB
    RTS

; Send command A to the AVR and return its response. Preserves X and Y.
.spi_cmd
    STX spi_x
    PHA
    JSR select_device
    PLA
    JSR spi_transfer        ; Send command (ignore stale response)
    LDA #&00
    JSR spi_transfer        ; Send dummy, receive response
    PHA
    JSR deselect_device
    PLA
    LDX spi_x
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
    ORA #SEL_MASK            ; No device (Y7)
    STA IORB
    RTS

; SPI transfer: send byte in A, return received byte in A. Corrupts X.
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

; ------ Data ------

; Firmware type for each of our types: None, 3BT, 3BS, 14B = 0-3. The
; Bitstik is wired as an Acorn port, which is the firmware's 3BT.
.fw_type
    EQUB 0, 2, 1, 3, 1

; Axes whose readings run opposite to the screen, by type. Acorn-standard
; joysticks (the Deltas) read high at the left and at the top; the Bitstik
; reads low at the left and at the front.
.invert_x
    EQUB 0, 1, 1, 1, 0
.invert_y
    EQUB 0, 0, 0, 0, 1

.type_names                 ; 16 bytes each
    EQUS "None           ", 0
    EQUS "Delta 3B Single", 0
    EQUS "Delta 3B Twin  ", 0
    EQUS "Delta 14B      ", 0
    EQUS "Acorn Bitstik  ", 0
ASSERT P% - type_names = 16 * NUM_TYPES

; Boxes: single, 3BT left, 3BT right (inside the outlines)
.box_left_lo
    EQUB LO(64), LO(48), LO(336)
.box_left_hi
    EQUB HI(64), HI(48), HI(336)
.box_bottom_lo
    EQUB LO(368), LO(496), LO(496)
.box_bottom_hi
    EQUB HI(368), HI(496), HI(496)

.pow_lo
    EQUB LO(1000), LO(100), LO(10), LO(1)
.pow_hi
    EQUB HI(1000), HI(100), HI(10), HI(1)

.bit_mask
    EQUB 1, 2, 4, 8, 16, 32, 64, 128

; MODE 1, cursor off, title
.vdu_init
    EQUB vdu_init_end - vdu_init - 1
    EQUB 22, 1
    EQUB 23, 1, 0, 0, 0, 0, 0, 0, 0, 0
    EQUS "SPItFIRE Joystick Test", 13, 10
    EQUS "A, B: change port type  Escape: quit"
.vdu_init_end

; Cursor on, bottom of screen
.vdu_exit
    EQUB vdu_exit_end - vdu_exit - 1
    EQUB 23, 1, 1, 0, 0, 0, 0, 0, 0, 0
    EQUB 31, 0, 31
.vdu_exit_end

; ------ Variables ------

.type       EQUB 0, 0       ; Per port
.buttons    EQUB 0          ; Fire inputs, both ports
.pbtn       EQUB 0          ; Fire inputs, this port
.raw_lo     SKIP 8          ; Channels, port*4 + channel
.raw_hi     SKIP 8
.keys_lo    EQUB 0, 0       ; 14B keypads, per port
.keys_hi    EQUB 0, 0
.drawn      SKIP 4          ; Markers, port*2 + stick
.drawn_xl   SKIP 4
.drawn_xh   SKIP 4
.drawn_yl   SKIP 4
.drawn_yh   SKIP 4
.k_cur      EQUB 0
.geom       EQUB 0
.rawi       EQUB 0
.nch        EQUB 0
.keyn       EQUB 0
.keyrow     EQUB 0
.keycol     EQUB 0

.end

SAVE "SPIJOY", start, end
