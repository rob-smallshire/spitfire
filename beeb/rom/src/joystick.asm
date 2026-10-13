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
; Every second call (50 Hz) reads the AVR's JOY_MOS burst
; (firmware/src/spijoy.cpp): a status byte, then those five bytes for
; the handset configured in the AVR's EEPROM, ready to store. The AVR
; scales the readings and derives the direction bits, so the 6502 only
; copies. The port types and the handset are set with *SPITFIRE
; JOYSTICK (commands.asm) and the AVR applies them at power-up, so the
; poll needs no set-up.
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

CMD_JOY_MOS    = &54        ; Burst for the configured handset
CMD_JOY_CONFIG = &58        ; The saved configuration
CMD_CFG_TYPE_A = &D0        ; + type: set and save Port A's type
CMD_CFG_HANDSET = &D8       ; + handset: set and save the MOS handset
ADVAL_STATUS   = &A0        ; JOY_MOS status byte: &A0 | port type
CONFIG_VALID   = &40        ; JOY_CONFIG: b6 set, b7 clear

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

; Read the configured handset's burst and store it. X = selected port B
; value (from joy_bus_take). The values are kept if no AVR answers (or
; not this firmware) or the handset's port is set to None.
.joy_read
    LDA #CMD_JOY_MOS
    JSR joy_send
    JSR joy_receive         ; Status: &A1-&A3
    CMP #ADVAL_STATUS + 1
    BCC joy_read_done
    CMP #ADVAL_STATUS + 4
    BCS joy_read_done
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
.joy_read_done
    RTS

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
