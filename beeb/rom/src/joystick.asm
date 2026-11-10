; Joystick module
; Makes the joysticks on SPItFIRE's two ports the BBC's, under MOS 5.x.
; See "Module: Joystick" in docs/rom-design.md and "Joystick allocation"
; in docs/protocol.md.
;
; Each port has a type, saved in the AVR's EEPROM. The AVR allocates the
; ports' joysticks to ADVAL slot pairs, Port A's first: joysticks 1-4 are
; ADVAL(1)/(2), (3)/(4), (17)/(18) and (19)/(20), with fire bits in
; ADVAL(0) and (16) and keypads in ADVAL(10), (11), (26) and (27).
;
; On reset (service &27) the module sets bit 7 of the MOS's joystick
; byte (*FX190,128,127), so every centisecond the MOS hands its whole
; joystick handling to service call &2C instead of reading the User VIA
; itself. Y is the offset in page 2 of the five bytes that OSBYTE &80
; returns for ADVAL(0)-(2).
;
; Every second call (50 Hz) reads the AVR's JOY_ALL burst
; (firmware/src/spijoy.cpp): a header, then the five bytes for
; ADVAL(0)-(2), ready to store in the MOS's workspace, then whatever else
; is allocated. That goes to this ROM's private workspace, where a BYTEV
; hook answers OSBYTE &80 for channels 3, 4, 10, 11, 16-20, 26 and 27.
; Channels that nothing is allocated to read 0. Every other OSBYTE, and
; every other channel, goes on to the previous BYTEV handler.
;
; The private workspace is one page of HAZEL, claimed at a hard reset
; through service calls &24 and &22. Both service calls and extended
; vectors run with HAZEL paged in. The page starts with a signature;
; without it (after *SRLOAD ... I, which issues no reset service calls)
; the module stores ADVAL(0)-(2) only and installs no hook.
;
; The call arrives in the 100 Hz interrupt, so it may interrupt a
; foreground SPI transaction (MMFS keeps the SD card selected for a
; whole card operation; the RTC module keeps the DS3234 selected). The
; poll therefore runs only when the decoder rests on Y7 (no device), and
; restores DDRB, the ACR and port B's outputs afterwards.
;
; Temporaries in page 2: the MOS's proportional-mode temporaries at
; &0200+Y+5 and &0200+Y+6, unused once the call is delegated. (&0200+Y+7
; is not free: *FX190,64 keeps its key repeat count there.)

CMD_JOY_ALL    = &55        ; The allocation burst
CMD_JOY_CONFIG = &58        ; The saved configuration
CMD_CFG_PORT   = &D0        ; + 8 * port + type: set and save a port's type
HEADER_N       = &A0        ; JOY_ALL header byte 0: &A0 | joysticks
HEADER_K       = &50        ; JOY_ALL header byte 1: &50 | keypad mask
CONFIG_VALID   = &40        ; JOY_CONFIG: b6 set, b7 clear

JOY_TICK  = &0205           ; + Y: bit 0 alternates, to poll at 50 Hz
JOY_SHIFT = &0206           ; + Y: byte being sent; then header byte 0

ROM_WS    = &0DF0           ; + ROM number: private workspace page
BYTEV     = &020A
E_BYTEV   = &FF0F           ; BYTEV's extended vector entry point
XV_BYTEV  = 3 * 5           ; BYTEV's entry in the extended vector table

; Private workspace page layout
WS_SIG    = 0               ; "SF" and the ROM number: the page is ours
WS_N      = 3               ; Joysticks allocated (0-4)
WS_K      = 4               ; Keypad mask: bit j-1 for joystick j
WS_J2     = 5               ; ADVAL(3), (4), low byte first
WS_SW16   = 9               ; ADVAL(16): fire bits for joysticks 3 and 4
WS_J3     = 10              ; ADVAL(17), (18)
WS_J4     = 14              ; ADVAL(19), (20)
WS_KEYS   = 18              ; Keypads of joysticks 1-4, 2 bytes each
WS_OLD_BYTEV = 26           ; The BYTEV handler to pass other calls to

wsp = ws + 4                ; Pointer to the private workspace (2 bytes).
                            ; Saved and restored wherever it is used
                            ; outside a *command.

OSBYTE = &FFF4

; ------ Workspace ------

; Service &24: count private HAZEL workspace. One page.
.joy_count_ws
    DEY
    RTS

; Service &22: claim private HAZEL workspace. Y = our page; record it,
; mark it as ours, and step past it. X = ROM number.
.joy_claim_ws
    TYA
    STA ROM_WS, X
    LDA wsp
    PHA
    LDA wsp+1
    PHA
    STY wsp+1
    LDA #0
    STA wsp
    TYA
    PHA
    LDY #WS_SIG
    LDA #'S'
    STA (wsp), Y
    INY
    LDA #'F'
    STA (wsp), Y
    INY
    TXA
    STA (wsp), Y
    PLA
    TAY
    INY
    PLA
    STA wsp+1
    PLA
    STA wsp
    RTS

; Point wsp at the private workspace of ROM X, or set wsp+1 = 0 if it
; has none: its entry in ROM_WS is not a HAZEL page or the page does not
; carry the signature. Preserves X and Y.
.joy_find_ws
    LDA #0
    STA wsp
    LDA ROM_WS, X
    STA wsp+1
    CMP #&C0
    BCC joy_find_ws_none
    CMP #&DC
    BCS joy_find_ws_none
    TYA
    PHA
    LDY #WS_SIG
    LDA (wsp), Y
    CMP #'S'
    BNE joy_find_ws_wrong
    INY
    LDA (wsp), Y
    CMP #'F'
    BNE joy_find_ws_wrong
    INY
    TXA
    CMP (wsp), Y
    BNE joy_find_ws_wrong
    PLA
    TAY
    RTS
.joy_find_ws_wrong
    PLA
    TAY
.joy_find_ws_none
    LDA #0
    STA wsp+1
    RTS

; ------ Reset ------

; Service &27: reset. Hand the MOS's joystick handling to service call
; &2C, keeping the other bits of the joystick byte; clear the values;
; and install the BYTEV hook. X = ROM number. Preserves X and Y.
.joy_reset
    TXA
    PHA
    TYA
    PHA
    LDA wsp
    PHA
    LDA wsp+1
    PHA
    JSR joy_find_ws
    LDA wsp+1
    BEQ joy_reset_mos
    LDA #0
    LDY #WS_N
.joy_reset_clear
    STA (wsp), Y
    INY
    CPY #WS_OLD_BYTEV
    BNE joy_reset_clear
    JSR joy_install
.joy_reset_mos
    LDA #&BE
    LDX #&80
    LDY #&7F
    JSR OSBYTE
    PLA
    STA wsp+1
    PLA
    STA wsp
    PLA
    TAY
    PLA
    TAX
    RTS

; Install the BYTEV hook through the extended vector, keeping the
; previous handler in the workspace. If the hook is already installed
; (BYTEV is the extended entry and the entry is ours), leave it, so the
; previous handler is never our own. X = ROM number, wsp = workspace.
xv = ws + 6                 ; Extended vector table (2 bytes)
.joy_install
    LDA xv
    PHA
    LDA xv+1
    PHA
    TXA
    PHA
    LDA #&A8                ; Read the extended vector table's address
    LDX #0
    LDY #&FF
    JSR OSBYTE
    STX xv
    STY xv+1
    PLA
    TAX
    PHP
    SEI
    LDA BYTEV
    CMP #LO(E_BYTEV)
    BNE joy_install_hook
    LDA BYTEV+1
    CMP #HI(E_BYTEV)
    BNE joy_install_hook
    LDY #XV_BYTEV + 2
    TXA
    CMP (xv), Y
    BEQ joy_install_done    ; Already ours
.joy_install_hook
    LDY #WS_OLD_BYTEV
    LDA BYTEV
    STA (wsp), Y
    INY
    LDA BYTEV+1
    STA (wsp), Y
    LDY #XV_BYTEV
    LDA #LO(joy_bytev)
    STA (xv), Y
    INY
    LDA #HI(joy_bytev)
    STA (xv), Y
    INY
    TXA
    STA (xv), Y
    LDA #LO(E_BYTEV)
    STA BYTEV
    LDA #HI(E_BYTEV)
    STA BYTEV+1
.joy_install_done
    PLP
    PLA
    STA xv+1
    PLA
    STA xv
    RTS

; ------ The poll ------

; Service &2C: centisecond joystick poll, in the interrupt. Y = offset in
; page 2 of the ADVAL workspace, X = ROM number. Preserves X and Y.
.joy_poll
    TXA
    PHA
    TYA
    PHA
    LDA JOY_TICK, Y
    EOR #1
    STA JOY_TICK, Y
    AND #1
    BEQ joy_poll_done       ; Every second centisecond
    LDA IORB
    AND #SEL_MASK
    CMP #DEV_NONE
    BNE joy_poll_done       ; A foreground transaction is in progress

    LDA wsp
    PHA
    LDA wsp+1
    PHA
    JSR joy_find_ws
    LDA DDRB
    PHA
    LDA ACR
    PHA
    LDA IORB
    PHA
    JSR joy_bus_take
    JSR joy_read
    JSR joy_bus_release
    PLA
    STA IORB
    PLA
    STA ACR
    PLA
    STA DDRB
    PLA
    STA wsp+1
    PLA
    STA wsp
.joy_poll_done
    PLA
    TAY
    PLA
    TAX
    RTS

; Port B outputs with no device, SCK and MOSI low, then the AVR
; selected. Leaves X = port B value with the AVR selected and SCK low.
.joy_bus_take
    LDA #%00011100          ; No SR, CB1 or CB2 interrupts
    STA IER
    LDA ACR
    AND #%11100011          ; Shift register mode 0
    STA ACR
    LDA IORB
    AND #NOT_SEL AND NOT_SCK AND NOT_MOSI
    ORA #DEV_NONE
    STA IORB                ; SCK low (the AVR's idle) before selecting
    LDA DDRB
    ORA #MOSI OR SCK OR SEL_MASK
    STA DDRB
    LDA IORB
    AND #NOT_SEL
    ORA #DEV_SPITFIRE
    STA IORB
    TAX
    RTS

.joy_bus_release
    TXA
    ORA #DEV_NONE
    STA IORB
    RTS

; Read the JOY_ALL burst and store it. X = selected port B value (from
; joy_bus_take), Y = ADVAL workspace offset, wsp = private workspace or
; wsp+1 = 0. Nothing is stored if the header is wrong: no AVR answered,
; or not this firmware. Corrupts Y.
.joy_read
    LDA #CMD_JOY_ALL
    JSR joy_send
    JSR joy_receive         ; Header: &A0 | n
    STA JOY_SHIFT, Y
    AND #&F0
    CMP #HEADER_N
    BNE joy_read_exit
    LDA JOY_SHIFT, Y
    AND #&0F
    CMP #5
    BCC joy_read_header_k
.joy_read_exit
    RTS
.joy_read_header_k
    JSR joy_receive         ; Header: &50 | k
    PHA
    AND #&F0
    CMP #HEADER_K
    BNE joy_read_bad
    JSR joy_receive
    STA &0200, Y            ; Switches
    JSR joy_receive
    STA &0201, Y            ; ADVAL(1)
    JSR joy_receive
    STA &0202, Y
    JSR joy_receive
    STA &0203, Y            ; ADVAL(2)
    JSR joy_receive
    STA &0204, Y
    LDA wsp+1
    BEQ joy_read_bad        ; No workspace: ADVAL(0)-(2) only

    LDA JOY_SHIFT, Y        ; Record n and k
    AND #&0F
    LDY #WS_N
    STA (wsp), Y
    PLA
    AND #&0F
    INY
    STA (wsp), Y
    LDA #0                  ; Clear everything after them
    LDY #WS_OLD_BYTEV - 1
.joy_read_clear
    STA (wsp), Y
    DEY
    CPY #WS_J2
    BCS joy_read_clear

    LDY #WS_N               ; Joysticks 2-4, as many as are allocated
    LDA (wsp), Y
    CMP #2
    BCC joy_read_keys
    PHA
    LDY #WS_J2
    JSR joy_store4          ; ADVAL(3), (4)
    PLA
    CMP #3
    BCC joy_read_keys
    PHA
    JSR joy_store1          ; ADVAL(16)
    JSR joy_store4          ; ADVAL(17), (18)
    PLA
    CMP #4
    BCC joy_read_keys
    JSR joy_store4          ; ADVAL(19), (20)

.joy_read_keys
    LDY #WS_K               ; A keypad for each bit of k
    LDA (wsp), Y
    BEQ joy_read_done
    LDY #WS_KEYS
.joy_read_key
    LSR A
    PHA
    BCC joy_read_key_skip
    JSR joy_store1
    JSR joy_store1
    JMP joy_read_key_next
.joy_read_key_skip
    INY
    INY
.joy_read_key_next
    PLA
    BNE joy_read_key
    RTS

.joy_read_bad
    PLA
.joy_read_done
    RTS

; Receive 4 bytes, or 1, into the workspace at Y, stepping Y
.joy_store4
    JSR joy_store1
    JSR joy_store1
    JSR joy_store1
.joy_store1
    JSR joy_receive
    STA (wsp), Y
    INY
    RTS

; ------ The BYTEV hook ------

; Entered through the extended vector with HAZEL and this ROM paged in,
; and A, X, Y as the OSBYTE call made them. Answers OSBYTE &80 for the
; channels in joy_channels from the workspace; passes everything else
; on to the previous handler.
.joy_bytev
    CMP #&80
    BNE joy_bytev_pass
    CPX #joy_channels_end - joy_channels
    BCS joy_bytev_pass
    PHA
    LDA joy_channels, X
    BMI joy_bytev_pass_pla  ; Not ours
    TXA
    PHA                     ; The channel
    LDA wsp
    PHA
    LDA wsp+1
    PHA
    LDX &F4                 ; This ROM
    JSR joy_find_ws
    TSX
    LDA &0103, X
    TAX                     ; The channel again
    LDA wsp+1
    BEQ joy_bytev_none
    LDA joy_channels, X
    TAY
    PHP
    SEI                     ; The poll writes these in the interrupt
    LDA (wsp), Y
    PHA                     ; Low byte
    INY
    LDA (wsp), Y
    CPX #16
    BNE joy_bytev_high
    LDA #0                  ; ADVAL(16) is a single byte
.joy_bytev_high
    TAY
    PLA
    TAX
    PLP
    PLA
    STA wsp+1
    PLA
    STA wsp
    PLA                     ; The channel
    PLA                     ; A
    RTS

.joy_bytev_none             ; No workspace: let the MOS answer
    PLA
    STA wsp+1
    PLA
    STA wsp
    PLA
    TAX
.joy_bytev_pass_pla
    PLA
    ; Fall through

; Pass the call on to the previous handler, with A, X and Y unchanged,
; by pushing its address (less one) and returning to it.
.joy_bytev_pass
    PHA                     ; Room for the address
    PHA
    PHA                     ; A
    TXA
    PHA
    TYA
    PHA
    LDA wsp
    PHA
    LDA wsp+1
    PHA
    LDX &F4
    LDA #0
    STA wsp
    LDA ROM_WS, X
    STA wsp+1
    TSX
    LDY #WS_OLD_BYTEV
    LDA (wsp), Y
    SEC
    SBC #1
    STA &0106, X
    INY
    LDA (wsp), Y
    SBC #0
    STA &0107, X
    PLA
    STA wsp+1
    PLA
    STA wsp
    PLA
    TAY
    PLA
    TAX
    PLA
    RTS

; Workspace offset for each channel the hook answers, by channel number;
; &FF for channels left to the MOS or other drivers
.joy_channels
    EQUB &FF, &FF, &FF                  ; 0-2: the MOS's workspace
    EQUB WS_J2, WS_J2 + 2               ; 3, 4
    EQUB &FF, &FF, &FF, &FF, &FF        ; 5-9: mouse drivers
    EQUB WS_KEYS, WS_KEYS + 2           ; 10, 11
    EQUB &FF, &FF, &FF, &FF             ; 12-15
    EQUB WS_SW16                        ; 16
    EQUB WS_J3, WS_J3 + 2               ; 17, 18
    EQUB WS_J4, WS_J4 + 2               ; 19, 20
    EQUB &FF, &FF, &FF, &FF, &FF        ; 21-25
    EQUB WS_KEYS + 4, WS_KEYS + 6       ; 26, 27
.joy_channels_end

; ------ SPI ------

; Foreground (for *SPITFIRE commands): send command A to the AVR and
; return its reply in A. Preserves Y; corrupts X.
.joy_command
    PHA
    JSR spi_init
    LDA #DEV_SPITFIRE
    JSR spi_select0
    PLA
    JSR spi_xfer0
    LDA #0
    JSR spi_xfer0           ; Clock out the reply
    PHA
    JSR spi_deselect0
    PLA
    RTS

; Send A, MSB first, in SPI mode 0. X = selected port B value with SCK
; and MOSI low. Uses JOY_SHIFT + Y. Leaves SCK and MOSI low.
.joy_send
    SEC
    ROL A                   ; C = bit 7; a 1 follows the data as a marker
    STA JOY_SHIFT, Y
.joy_send_bit
    TXA
    BCC joy_send_low
    ORA #MOSI
.joy_send_low
    STA IORB                ; MOSI valid, SCK low
    ORA #SCK
    STA IORB                ; Rising edge: the AVR samples MOSI
    LDA JOY_SHIFT, Y
    ASL A
    STA JOY_SHIFT, Y
    BNE joy_send_bit        ; Until the marker has shifted out
    STX IORB
    RTS

; Clock in one byte with MOSI low. X = selected port B value with SCK
; low. The User VIA's shift register captures MISO on each rising edge.
; The JSR and the store between bytes give the AVR's interrupt time to
; load the next byte. Preserves X and Y.
.joy_receive
    LDA SR                  ; Clear the shift register
    TXA
    ORA #SCK
    STA IORB : STX IORB
    STA IORB : STX IORB
    STA IORB : STX IORB
    STA IORB : STX IORB
    STA IORB : STX IORB
    STA IORB : STX IORB
    STA IORB : STX IORB
    STA IORB : STX IORB
    LDA SR
    RTS
