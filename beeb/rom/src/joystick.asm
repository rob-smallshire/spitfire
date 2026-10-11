; Joystick module
; Makes a joystick on SPItFIRE Port A the BBC's first joystick under MOS
; 5.x, through the Master Compact's joystick service call &2C. See
; "Module: Joystick" in docs/rom-design.md.
;
; On reset (service &27) the module sets bit 7 of the MOS's joystick
; byte (*FX190,128,127), so every centisecond the MOS hands its whole
; joystick handling to service call &2C instead of reading the User VIA
; itself. Y is the offset in page 2 of the five bytes that OSBYTE &80
; returns: ADVAL(0) low byte (switches), then ADVAL(1) and ADVAL(2) as
; 16-bit values. Odd channels return ADVAL(1) and even ones ADVAL(2).
;
; Every second call (50 Hz) reads the AVR's JOY_ADVAL burst for the
; handset (firmware/src/spijoy.cpp): a status byte, then those five
; bytes, ready to store. The AVR scales the readings and derives the
; direction bits, so the 6502 only copies.
;
; The call arrives in the 100 Hz interrupt, so it may interrupt a
; foreground SPI transaction (MMFS keeps the SD card selected for a
; whole card operation; the RTC module keeps the DS3234 selected). The
; poll therefore runs only when the decoder rests on Y7 (no device), and
; restores DDRB, the ACR and port B's outputs afterwards.
;
; Workspace: the MOS's proportional-mode temporaries at &0200+Y+5 and
; &0200+Y+6, unused once the call is delegated. (&0200+Y+7 is not free:
; *FX190,64 keeps its key repeat count there.) Y stays the same
; throughout.

CMD_JOY_ADVAL  = &50        ; + handset: 0 = Port A CH0/CH1
CMD_JOY_TYPE_A = &E0        ; + firmware type for Port A
ADVAL_STATUS   = &A0        ; JOY_ADVAL status byte: &A0 | port type
JOY_HANDSET    = 0          ; Port A left handset (CH0, CH1)
JOY_TYPE       = 1          ; Firmware 3B Twin: the Acorn port's grounds

DEV_SPITFIRE = %00000100    ; Y1 -> SPItFIRE AVR

JOY_TICK  = &0205           ; + Y: bit 0 alternates, to poll at 50 Hz
JOY_SHIFT = &0206           ; + Y: byte being sent

OSBYTE = &FFF4

; Service &27: reset. Hand the MOS's joystick handling to service call
; &2C, keeping the other bits of the joystick byte. Preserves X and Y.
.joy_reset
    TXA
    PHA
    TYA
    PHA
    LDA #&BE
    LDX #&80
    LDY #&7F
    JSR OSBYTE
    PLA
    TAY
    PLA
    TAX
    RTS

; Service &2C: centisecond joystick poll, in the interrupt. Y = offset in
; page 2 of the ADVAL workspace. Preserves X and Y.
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

; Read the handset's burst and store it, or fix the port type if the AVR
; reports another. X = selected port B value (from joy_bus_take).
.joy_read
    LDA #CMD_JOY_ADVAL + JOY_HANDSET
    JSR joy_send
    JSR joy_receive         ; Status
    PHA
    AND #&F8
    CMP #ADVAL_STATUS
    BEQ joy_read_status
    PLA                     ; No AVR (or not this firmware): keep values
    RTS
.joy_read_status
    PLA
    AND #&07
    CMP #JOY_TYPE
    BNE joy_set_type
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
    RTS

; The AVR's port is not yet the type we need (it may have reset): end
; this transaction and set it.
.joy_set_type
    TXA
    ORA #DEV_NONE
    STA IORB
    STX IORB                ; Select again
    LDA #CMD_JOY_TYPE_A + JOY_TYPE
    JSR joy_send
    JMP joy_receive         ; Clock out the echo

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
; load the next byte.
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
