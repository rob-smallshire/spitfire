; SPItFIRE Joystick Allocation Test
; Needs the spijoy firmware. Reads the JOY_ALL burst ten times a second
; and shows it in MODE 7: the header, the raw bytes in hex, and the ADVAL
; channels they carry. The A and B keys cycle each port through the
; eight port types without saving (JOY_PORT_); S saves the types shown
; (CFG_PORT_). See docs/protocol.md, "Joystick allocation".

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
CMD_JOY_ALL    = &55        ; The allocation burst
CMD_JOY_CONFIG = &58        ; Saved configuration
CMD_CFG_PORT   = &D0        ; +port*8+type: set and save
CMD_JOY_PORT   = &E0        ; +port*8+type: set until reset, not saved

MAX_BURST = 20

; OS calls
OSWRCH = &FFEE
OSBYTE = &FFF4

; Zero page variables
spi_temp = &70              ; SPI transfer temp
spi_x    = &71              ; X saved across spi_cmd
type_a   = &72              ; Port types shown, 0-7
type_b   = &73
count    = &74              ; Burst length
n        = &75              ; Joysticks in the burst
k        = &76              ; Keypad mask
ptr      = &77              ; Index into burst
row      = &78              ; Screen row
tmp      = &79
config   = &7A              ; Last JOY_CONFIG
tmp_ptr  = &7C              ; String pointer (2 bytes)


.start
    LDA #22 : JSR OSWRCH : LDA #7 : JSR OSWRCH
    LDA #23 : JSR OSWRCH : LDA #1 : JSR OSWRCH  ; Cursor off
    LDX #8
    LDA #0
.cursor_off
    JSR OSWRCH
    DEX
    BNE cursor_off

    JSR init_via

    ; Start from the saved configuration
    LDA #CMD_JOY_CONFIG
    JSR spi_cmd
    STA config
    AND #7
    STA type_a
    LDA config
    LSR A : LSR A : LSR A
    AND #7
    STA type_b

    LDX #0 : LDY #0 : JSR tab
    LDX #LO(title) : LDY #HI(title) : JSR print
    LDX #0 : LDY #24 : JSR tab
    LDX #LO(txt_help) : LDY #HI(txt_help) : JSR print

.main_loop
    JSR wait_tenth
    JSR check_keys
    JSR read_config
    JSR read_burst
    JSR show
    LDA #&81 : LDX #&8F : LDY #&FF : JSR OSBYTE  ; INKEY-113: Escape?
    CPX #&FF
    BNE main_loop
    LDA #&7E : JSR OSBYTE
    LDA #22 : JSR OSWRCH : LDA #7 : JMP OSWRCH

; Wait 0.1 s
.wait_tenth
    LDA #5
    STA tmp
.wait_loop
    LDA #19 : JSR OSBYTE    ; Wait for vertical sync
    DEC tmp
    BNE wait_loop
    RTS

; ------ Keys ------

.check_keys
    LDA #&81 : LDX #0 : LDY #0 : JSR OSBYTE    ; INKEY(0)
    BCS keys_done
    TXA
    AND #&DF                ; Upper case
    CMP #'A' : BEQ key_a
    CMP #'B' : BEQ key_b
    CMP #'S' : BEQ key_s
.keys_done
    RTS

.key_a
    LDA type_a : CLC : ADC #1 : AND #7 : STA type_a
    ORA #CMD_JOY_PORT
    JMP spi_cmd

.key_b
    LDA type_b : CLC : ADC #1 : AND #7 : STA type_b
    ORA #CMD_JOY_PORT + 8
    JMP spi_cmd

.key_s
    LDA type_a : ORA #CMD_CFG_PORT : JSR spi_cmd
    LDA type_b : ORA #CMD_CFG_PORT + 8 : JMP spi_cmd

; ------ Reading ------

.read_config
    LDA #CMD_JOY_CONFIG
    JSR spi_cmd
    STA config
    RTS

; Read the burst. Its length follows from the header: 7 bytes, plus 4,
; 9 or 13 for joysticks 2-4, plus 2 per keypad.
.read_burst
    JSR select_device
    LDA #CMD_JOY_ALL
    JSR spi_transfer        ; Command; ignore the stale response
    LDA #0
    JSR spi_transfer
    STA burst
    LDA #0
    JSR spi_transfer
    STA burst+1
    LDA #0
    STA count
    LDA burst
    AND #&F0
    CMP #&A0
    BNE read_bad
    LDA burst+1
    AND #&F0
    CMP #&50
    BNE read_bad
    LDA burst
    AND #&0F
    STA n
    CMP #5
    BCS read_bad
    LDA burst+1
    AND #&0F
    STA k
    LDY n
    LDA len_by_n, Y
    LDX #4
.len_keys
    LSR k
    BCC len_next
    ADC #1                  ; C=1, so +2
.len_next
    DEX
    BNE len_keys
    STA count
    LDA burst+1
    AND #&0F
    STA k
    LDY #2
.read_loop
    CPY count
    BCS read_done
    LDA #0
    STY ptr
    JSR spi_transfer
    LDY ptr
    STA burst, Y
    INY
    BNE read_loop
.read_done
    JMP deselect_device
.read_bad
    JMP deselect_device

.len_by_n
    EQUB 7, 7, 11, 16, 20

; ------ Display ------

.show
    ; Types shown and saved
    LDX #0 : LDY #2 : JSR tab
    LDX #LO(txt_port_a) : LDY #HI(txt_port_a) : JSR print
    LDA type_a : JSR print_type
    LDX #0 : LDY #3 : JSR tab
    LDX #LO(txt_port_b) : LDY #HI(txt_port_b) : JSR print
    LDA type_b : JSR print_type
    LDX #0 : LDY #4 : JSR tab
    LDX #LO(txt_config) : LDY #HI(txt_config) : JSR print
    LDA config : JSR print_hex

    ; Header
    LDX #0 : LDY #6 : JSR tab
    LDX #LO(txt_header) : LDY #HI(txt_header) : JSR print
    LDA burst : JSR print_hex
    LDA #' ' : JSR OSWRCH
    LDA burst+1 : JSR print_hex
    LDA count
    BNE show_ok
    LDX #LO(txt_bad) : LDY #HI(txt_bad) : JSR print
    RTS
.show_ok
    LDX #LO(txt_n) : LDY #HI(txt_n) : JSR print
    LDA n : JSR print_digit
    LDX #LO(txt_k) : LDY #HI(txt_k) : JSR print
    LDA k : JSR print_digit
    LDX #LO(txt_len) : LDY #HI(txt_len) : JSR print
    LDA count : JSR print_hex

    ; Raw bytes, ten to a line, on rows 8 and 9
    LDX #0 : LDY #8 : JSR tab
    LDY #2
.raw_loop
    CPY count
    BCS raw_pad
    STY ptr
    LDA burst, Y : JSR print_hex
    LDA #' ' : JSR OSWRCH
    LDY ptr
    INY
    CPY #12
    BNE raw_loop
    STY ptr
    LDX #0 : LDY #9 : JSR tab
    LDY ptr
    JMP raw_loop
.raw_pad
    LDX #12                 ; Clear what is left of the two lines
    LDA #' '
.raw_pad_loop
    JSR OSWRCH : JSR OSWRCH : JSR OSWRCH
    DEX
    BNE raw_pad_loop

    ; Decoded channels, rows 11-20
    LDA #11 : STA row
    LDA #2 : STA ptr        ; Burst index
    ; J1: ADVAL(0), (1), (2)
    LDA #0 : JSR show_switch
    LDA #1 : JSR show_value
    LDA #2 : JSR show_value
    LDA n : CMP #2 : BCC no_j2
    LDA #3 : JSR show_value
    LDA #4 : JSR show_value
    JMP j3
.no_j2
    LDA #3 : JSR show_unused
    LDA #4 : JSR show_unused
.j3
    LDA n : CMP #3 : BCC no_j3
    LDA #16 : JSR show_switch
    LDA #17 : JSR show_value
    LDA #18 : JSR show_value
    JMP j4
.no_j3
    LDA #16 : JSR show_unused
    LDA #17 : JSR show_unused
    LDA #18 : JSR show_unused
.j4
    LDA n : CMP #4 : BCC no_j4
    LDA #19 : JSR show_value
    LDA #20 : JSR show_value
    JMP keypads
.no_j4
    LDA #19 : JSR show_unused
    LDA #20 : JSR show_unused
.keypads
    ; Keypads, in joystick order, on row 22
    LDX #0 : LDY #22 : JSR tab
    LDX #LO(txt_keys) : LDY #HI(txt_keys) : JSR print
    LDA #0 : STA tmp        ; Joystick index
.key_loop
    LDA k
    LDX tmp
.key_shift
    BEQ key_test
    LSR A
    DEX
    JMP key_shift
.key_test
    AND #1
    BEQ key_next
    LDA #'J' : JSR OSWRCH
    LDA tmp : CLC : ADC #1 : JSR print_digit
    LDA #'=' : JSR OSWRCH
    LDY ptr
    LDA burst+1, Y : JSR print_hex
    LDY ptr
    LDA burst, Y : JSR print_hex
    LDA #' ' : JSR OSWRCH
    INC ptr : INC ptr
.key_next
    INC tmp
    LDA tmp
    CMP #4
    BNE key_loop
    LDX #10
    LDA #' '
.key_pad
    JSR OSWRCH
    DEX
    BNE key_pad
    RTS

; "ADVAL(c)" at the start of the row, then a tab to the value column
.row_label
    PHA
    LDX #2 : LDY row : JSR tab
    LDX #LO(txt_adval) : LDY #HI(txt_adval) : JSR print
    PLA
    JSR print_dec2
    LDA #')' : JSR OSWRCH
    LDX #14 : LDY row : JMP tab

; Channel A: a switch byte at the burst pointer
.show_switch
    JSR row_label
    LDA #'&' : JSR OSWRCH
    LDY ptr
    LDA burst, Y : JSR print_hex
    INC ptr
    LDX #LO(txt_blank) : LDY #HI(txt_blank) : JSR print
    INC row
    RTS

; Channel A: a 16-bit value at the burst pointer
.show_value
    JSR row_label
    LDA #'&' : JSR OSWRCH
    LDY ptr
    LDA burst+1, Y : JSR print_hex
    LDY ptr
    LDA burst, Y : JSR print_hex
    INC ptr : INC ptr
    INC row
    RTS

.show_unused
    JSR row_label
    LDX #LO(txt_unused) : LDY #HI(txt_unused) : JSR print
    INC row
    RTS

; Print port type A (0-7) by name, padded to 15 characters
.print_type
    ASL A : ASL A : ASL A : ASL A
    TAX
    LDY #16
.type_loop
    LDA type_names, X : JSR OSWRCH
    INX
    DEY
    BNE type_loop
    RTS

; ------ Printing ------

.print_hex
    PHA
    LSR A : LSR A : LSR A : LSR A
    JSR print_nibble
    PLA
    AND #&0F
.print_nibble
    CMP #10
    BCC print_digit
    ADC #'A' - 10 - 1       ; C=1
    JMP OSWRCH
.print_digit
    CLC
    ADC #'0'
    JMP OSWRCH

; Print A (0-99) as two characters, space-padded
.print_dec2
    LDX #0
.dec_tens
    CMP #10
    BCC dec_units
    SBC #10
    INX
    BNE dec_tens
.dec_units
    PHA
    TXA
    BEQ dec_space
    JSR print_digit
    JMP dec_last
.dec_space
    LDA #' ' : JSR OSWRCH
.dec_last
    PLA
    JMP print_digit

; Move the cursor to X, Y
.tab
    LDA #31 : JSR OSWRCH
    TXA : JSR OSWRCH
    TYA : JMP OSWRCH

; Print the string at YX, terminated by 0
.print
    STX tmp_ptr
    STY tmp_ptr+1
    LDY #0
.print_loop
    LDA (tmp_ptr), Y
    BEQ print_done
    JSR OSWRCH
    INY
    BNE print_loop
.print_done
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

.title
    EQUS "SPItFIRE JOY_ALL test", 0
.txt_help
    EQUS "A, B: next type   S: save   Esc: quit", 0

.txt_port_a  EQUS "Port A ", 0
.txt_port_b  EQUS "Port B ", 0
.txt_config  EQUS "Saved config &", 0
.txt_header  EQUS "Header ", 0
.txt_bad     EQUS "  bad header        ", 0
.txt_n       EQUS "  n=", 0
.txt_k       EQUS " k=", 0
.txt_len     EQUS " len &", 0
.txt_adval   EQUS "ADVAL(", 0
.txt_blank   EQUS "  ", 0
.txt_unused  EQUS "-    ", 0
.txt_keys    EQUS "Keypads ", 0

.type_names                 ; 16 bytes each, as the protocol numbers them
    EQUS "None           ", 0
    EQUS "Single         ", 0
    EQUS "Dual           ", 0
    EQUS "Delta 3B Single", 0
    EQUS "Delta 3B Twin  ", 0
    EQUS "Delta 14B      ", 0
    EQUS "Bitstik        ", 0
    EQUS "Quinkey        ", 0

.burst                      ; Received bytes
    SKIP MAX_BURST

.end
    PRINT "SPIALL: ", ~start, "-", ~end
    SAVE "SPIALL", start, end
