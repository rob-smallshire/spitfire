; SPI core
; Bit-banged SPI on the User VIA port B, with MISO captured by the shift
; register (CB2) clocked from SCK (PB1 wired to CB1). PB2-PB4 drive the
; 74HC138 that selects the device. See docs/spi-interface.md.
;
; Only SPI mode 3 (SCK idling high) is provided so far: the DS3234 RTC
; and SD cards. The AVR (mode 0, SCK idling low) will need its own
; select and transfer routines.

VIA_BASE = &FE60            ; User VIA
IORB = VIA_BASE + &00
DDRB = VIA_BASE + &02
SR   = VIA_BASE + &0A
ACR  = VIA_BASE + &0B
PCR  = VIA_BASE + &0C
IER  = VIA_BASE + &0E

; Port B bit assignments
MOSI     = %00000001        ; PB0
SCK      = %00000010        ; PB1
SEL_MASK = %00011100        ; Decoder inputs (PB2-PB4)

NOT_SEL  = %11100011
NOT_SCK  = %11111101
NOT_MOSI = %11111110

; Devices (74HC138 outputs). "No device" is Y7: the Compact pulls
; PB2-PB4 high whenever port B is not driving them, so all ones is the
; resting state (see Rev 2 erratum 3 in docs/rev1-bringup.md).
DEV_NONE = %00011100        ; Y7
DEV_RTC  = %00001100        ; Y3 -> ~SS_3 -> J5 DeadOn DS3234

spi_temp = ws + 7           ; Byte being shifted out

; Set up port B and the shift register for SPI, with no device
; selected and SCK high. Touches only the CB side of the VIA: the CA
; side (printer port) and the timers are left alone.
.spi_init
    LDA #%00011100          ; Disable SR, CB1 and CB2 interrupts
    STA IER
    LDA ACR
    AND #%11100011          ; Shift register mode 0
    STA ACR
    LDA PCR
    AND #%00001111          ; CB1, CB2 inputs
    STA PCR
    LDA IORB
    ORA #MOSI OR SCK OR DEV_NONE   ; No device, SCK and MOSI high
    STA IORB
    LDA DDRB
    ORA #MOSI OR SCK OR SEL_MASK
    STA DDRB
    RTS

; Select device A (a DEV_ constant) in SPI mode 3: SCK is high before
; the chip select falls.
.spi_select3
    STA spi_temp
    LDA IORB
    ORA #SCK OR DEV_NONE
    STA IORB                ; No device, SCK high
    AND #NOT_SEL
    ORA spi_temp
    STA IORB
    RTS

.spi_deselect
    LDA IORB
    ORA #SCK OR DEV_NONE
    STA IORB
    RTS

; Mode 3 transfer: send A, return the received byte in A.
; Preserves Y; corrupts X.
.spi_xfer3
    STA spi_temp
    LDA SR                  ; Clear the shift register
    LDX #8
.spi_xfer3_bit
    LDA IORB
    AND #NOT_SCK AND NOT_MOSI
    ASL spi_temp
    BCC spi_xfer3_mosi_low
    ORA #MOSI
.spi_xfer3_mosi_low
    STA IORB                ; Falling edge, MOSI valid
    ORA #SCK
    STA IORB                ; Rising edge: both ends sample
    DEX
    BNE spi_xfer3_bit
    LDA SR
    RTS
