# SPI Interface Design Document

## Overview

SPItFIRE uses SPI to communicate between the BBC Master Compact and an ATmega1284p microcontroller. The BBC acts as SPI master, bit-banging the protocol on its User VIA. The AVR acts as SPI slave using its hardware SPI peripheral.

The design uses CB1 wired to PB1 externally to enable both bit-banged and shift-register-accelerated transfers (following the MMFS approach). A 74HC138 3-to-8 decoder expands three VIA output pins into seven independent chip select lines, allowing up to seven SPI devices on the bus.

## Connector Terminology

SPItFIRE has two DE-9 connectors with distinct roles:

| Connector | Description |
|-----------|-------------|
| **Host DE-9** | Connects to the BBC Master Compact Mouse/Joystick port. Carries SPI signals (MOSI, MISO, SCK) and device selection via the 74HC138 decoder. The BBC is the SPI master. |
| **Peripheral DE-9** | Directly connects input devices to SPItFIRE. Directly accepts quadrature mice, switched joysticks, or other peripherals. Connected to AVR Port D. |

This naming convention is used consistently throughout the documentation:
- "Host" = toward the BBC Master Compact (SPI master side)
- "Peripheral" = toward input devices (directly connected to AVR)

## Host DE-9 Pinout

The Host DE-9 connects to the BBC Master Compact's Mouse/Joystick port, which exposes User VIA pins:

| DE-9 Pin | VIA Signal | SPI Function | Direction |
|----------|------------|--------------|-----------|
| 1 | PB3 | Decoder A1 | Output |
| 2 | PB2 | Decoder A0 | Output |
| 3 | PB1 | SCK | Output |
| 4 | PB4 | Decoder A2 | Output |
| 5 | CB1 | SCK | Input (wire to pin 3) |
| 6 | PB0 | MOSI | Output |
| 7 | +5V | Power | - |
| 8 | 0V | GND | - |
| 9 | CB2 | MISO | Input |

## SPI Signal Assignment

Following MMFS conventions for MOSI, SCK, and MISO:

| VIA Pin | SPI Function | Notes |
|---------|--------------|-------|
| PB0 | MOSI | Data to slave (same as MMFS) |
| PB1 | SCK | Clock, wired to CB1 (same as MMFS) |
| PB2 | Decoder A0 | Device select bit 0 |
| PB3 | Decoder A1 | Device select bit 1 |
| PB4 | Decoder A2 | Device select bit 2 |
| CB1 | SCK | Wired to PB1 for shift register clock |
| CB2 | MISO | Data from slave (same as MMFS) |

## Multi-Device SPI Bus

A 74HC138 3-to-8 decoder expands three VIA pins into seven chip select lines. The decoder outputs are active-low, directly compatible with SPI SS requirements.

### 74HC138 Connections

```
                              74HC138
                            ┌────┴────┐
                        A0 ─┤1      16├─ VCC
                        A1 ─┤2      15├─ Y0 (unconnected - no device)
                        A2 ─┤3      14├─ Y1 → [1kΩ] → AVR PB4 (SS)
                       ~G2A─┤4      13├─ Y2 (unassigned)
                       ~G2B─┤5      12├─ Y3 (unassigned)
                        G1 ─┤6      11├─ Y4 (unassigned)
                        Y7 ─┤7      10├─ Y5 (unassigned)
                       GND ─┤8       9├─ Y6 (unassigned)
                            └─────────┘
```

### Decoder Enable Configuration

The enable pins are hard-wired so one output is always active:
- G1 = VCC (active high enable)
- ~G2A = GND (active low enable)
- ~G2B = GND (active low enable)

### Full System Wiring

```
Host DE-9                   74HC138                 Devices
─────────                   ───────                 ───────
Pin 2 (PB2) ─────────────────→ A0
Pin 1 (PB3) ─────────────────→ A1
Pin 4 (PB4) ─────────────────→ A2
                               Y0 ─── (no connection)
                               Y1 ───[1kΩ]──→ AVR PB4 (SS)
                               Y2 ─── (unassigned)
                               Y3 ─── (unassigned)
                               Y4 ─── (unassigned)
                               Y5 ─── (unassigned)
                               Y6 ─── (unassigned)
                               Y7 ─── (unassigned)

Pin 6 (PB0) ─────────[1kΩ]───────────────→ AVR PB5 (MOSI)
Pin 3 (PB1) ──┬──────[1kΩ]───────────────→ AVR PB7 (SCK)
Pin 5 (CB1) ──┘ (wire together)
Pin 9 (CB2) ←────────[1kΩ]─────────────── AVR PB6 (MISO)
Pin 8 (0V)  ───────────────────────────── GND (common)
```

### Device Selection

Write a 3-bit device number to PB4:PB3:PB2 to select a device:

| A2 (PB4) | A1 (PB3) | A0 (PB2) | Value | Active Output | Device |
|----------|----------|----------|-------|---------------|--------|
| 0 | 0 | 0 | 0 | Y0 | None (idle) |
| 0 | 0 | 1 | 1 | Y1 | SPItFIRE |
| 0 | 1 | 0 | 2 | Y2 | (unassigned) |
| 0 | 1 | 1 | 3 | Y3 | (unassigned) |
| 1 | 0 | 0 | 4 | Y4 | (unassigned) |
| 1 | 0 | 1 | 5 | Y5 | (unassigned) |
| 1 | 1 | 0 | 6 | Y6 | (unassigned) |
| 1 | 1 | 1 | 7 | Y7 | (unassigned) |

### Software Interface

Device selection uses pre-shifted constants for efficiency (no runtime shifting):

```asm
; Port B bit assignments
SEL_A0   = %00000100        ; PB2 - decoder A0
SEL_A1   = %00001000        ; PB3 - decoder A1
SEL_A2   = %00010000        ; PB4 - decoder A2
SEL_MASK = %00011100        ; All decoder bits (PB2-PB4)

; Device constants (pre-shifted to PB2-4 position)
DEV_NONE     = %00000000    ; Y0 - no device selected
DEV_SPITFIRE = %00000100    ; Y1 - SPItFIRE (A0=1)
DEV_2        = %00001000    ; Y2 - unassigned (A1=1)
DEV_3        = %00001100    ; Y3 - unassigned (A1=1, A0=1)
DEV_4        = %00010000    ; Y4 - unassigned (A2=1)
DEV_5        = %00010100    ; Y5 - unassigned (A2=1, A0=1)
DEV_6        = %00011000    ; Y6 - unassigned (A2=1, A1=1)
DEV_7        = %00011100    ; Y7 - unassigned (A2=1, A1=1, A0=1)

; Mask for clearing decoder bits
NOT_SEL  = %11100011        ; Clear PB2, PB3, PB4

; Select SPItFIRE
    LDA IORB
    AND #NOT_SEL            ; Clear decoder bits
    ORA #DEV_SPITFIRE       ; Set device 1
    STA IORB

; Deselect (idle)
    LDA IORB
    AND #NOT_SEL            ; Clear decoder bits (device 0)
    STA IORB
```

**Note:** This interface differs from MMFS which ties SS to ground (always selected). SD card support would require a custom MMC driver that controls device selection via the decoder.

## SPItFIRE As-Built Wiring

Connection from Host DE-9 (directly via female breakout board) through 74HC138 decoder
to ATmega1284p. A straight-through DE-9 cable connects to the Master Compact.

```
Host DE-9                   74HC138             ATmega1284p
─────────                   ───────             ───────────
Pin 2 (PB2) ─────────────────→ A0
Pin 1 (PB3) ─────────────────→ A1
Pin 4 (PB4) ─────────────────→ A2
                               Y1 ────[1kΩ]────→ PB4 (SS)
Pin 3 (PB1/SCK)  ──┬─────────[1kΩ]─────────────→ PB7 (SCK)
Pin 5 (CB1)      ──┘ (wire together)
Pin 6 (PB0/MOSI) ────────────[1kΩ]─────────────→ PB5 (MOSI)
Pin 9 (CB2/MISO) ←───────────[1kΩ]───────────── PB6 (MISO)
Pin 8 (GND)      ──────────────────────────────── GND

74HC138 power and enable:
  Pin 16 (VCC) ── +5V
  Pin 8 (GND)  ── GND
  Pin 6 (G1)   ── +5V (enable)
  Pin 4 (~G2A) ── GND (enable)
  Pin 5 (~G2B) ── GND (enable)
```

| Connection | From | To | Notes |
|------------|------|-----|-------|
| Decoder A0 | Host DE-9 pin 2 (PB2) | 74HC138 pin 1 | Device select bit 0 |
| Decoder A1 | Host DE-9 pin 1 (PB3) | 74HC138 pin 2 | Device select bit 1 |
| Decoder A2 | Host DE-9 pin 4 (PB4) | 74HC138 pin 3 | Device select bit 2 |
| SS | 74HC138 Y1 (pin 14) | AVR PB4 | Via 1kΩ resistor |
| SCK | Host DE-9 pin 3 (PB1) | AVR PB7 | Via 1kΩ resistor |
| CB1 | Host DE-9 pin 5 | Host DE-9 pin 3 | Wire together |
| MOSI | Host DE-9 pin 6 (PB0) | AVR PB5 | Via 1kΩ resistor |
| MISO | AVR PB6 | Host DE-9 pin 9 (CB2) | Via 1kΩ resistor |
| GND | Host DE-9 pin 8 | Common | All grounds connected |

Host DE-9 pin 7 (+5V) is currently unused.

## Series Resistors

1kΩ series resistors serve two purposes:

**ISP programming compatibility (MOSI, SCK, SS):** The BBC VIA (via the decoder)
and ISP programmer both drive these lines to the AVR. The resistors allow the
programmer to override the BBC's signals during programming.

**Protection (MISO):** Although only the AVR drives MISO, a series resistor is
included for general protection.

```
ISP Programmer               ATmega1284p
──────────────               ───────────
MOSI ──────────────────────→ PB5 (direct, overrides BBC via 1kΩ)
MISO ←──────────────────────── PB6 (direct)
SCK  ──────────────────────→ PB7 (direct, overrides BBC via 1kΩ)
RESET ─────────────────────→ RESET
```

Future SPI devices on other decoder outputs (Y2-Y7) would also benefit from
series resistors if they share pins with an ISP header.

## SPI Protocol Parameters

| Parameter | Value |
|-----------|-------|
| Mode | SPI Mode 0 (CPOL=0, CPHA=0) |
| Bit Order | MSB first |
| Clock Speed | ~10-50 kHz (bit-bang) or faster (shift register) |
| SS Polarity | Active low |

### Mode 0 Timing

```
        ┌───┐   ┌───┐   ┌───┐   ┌───┐
SCK  ───┘   └───┘   └───┘   └───┘   └───
        ↑       ↑       ↑       ↑
      sample  sample  sample  sample

Data changes on falling edge, sampled on rising edge.
```

## VIA Initialization Requirements

Correct VIA initialization is critical for reliable SPI operation. The following
registers must be explicitly set to known values before any SPI transfers.

### CB1/CB2 Interrupts Must Be Disabled

**This is the most critical step.** Because CB1 is wired to PB1 (SCK), every
falling edge of the SPI clock triggers CB1. If the OS has left CB1 interrupts
enabled in the IER, this causes an IRQ on every clock pulse.

With 8 clock pulses per byte, a 256-byte transfer generates 2048 interrupts.
Each interrupt handler invocation takes thousands of cycles, resulting in
transfer speeds of ~6 bytes/second instead of the expected ~4000 bytes/second.

```asm
IER = &FE6E         ; User VIA Interrupt Enable Register

; Disable CB1 and CB2 interrupts
; Bit 7 = 0 means "clear the specified bits"
; Bits 4,3 = CB1, CB2
LDA #%00011000
STA IER
```

### ACR and PCR Must Be Set to Known Values

Previous code may have left the Auxiliary Control Register (ACR) or Peripheral
Control Register (PCR) in unexpected states. Do not use AND/OR to modify these
registers; set them to absolute values.

```asm
ACR = &FE6B         ; Auxiliary Control Register
PCR = &FE6C         ; Peripheral Control Register

; Set PCR: CB2 input, CB1 negative edge
LDA #%00000000
STA PCR

; Set ACR: Shift register disabled
LDA #%00000000
STA ACR
```

### Complete VIA Initialization Sequence

```asm
; Port B bit assignments
MOSI     = %00000001    ; PB0
SCK      = %00000010    ; PB1
SEL_A0   = %00000100    ; PB2 - decoder A0
SEL_A1   = %00001000    ; PB3 - decoder A1
SEL_A2   = %00010000    ; PB4 - decoder A2
SEL_MASK = %00011100    ; All decoder bits

.init_via
    ; 1. Disable CB1/CB2 interrupts FIRST
    LDA #%00011000
    STA IER

    ; 2. Set PCR to known state
    LDA #%00000000
    STA PCR

    ; 3. Set ACR to known state (SR disabled)
    LDA #%00000000
    STA ACR

    ; 4. Set port direction (PB0=MOSI, PB1=SCK, PB2-4=decoder as outputs)
    LDA DDRB
    ORA #MOSI OR SCK OR SEL_MASK
    STA DDRB

    ; 5. Set idle state: device 0 (none), SCK low (CPOL=0), MOSI high
    LDA IORB
    AND #%11100001      ; Clear SCK and decoder bits
    ORA #MOSI           ; MOSI high
    STA IORB

    RTS
```

## Transfer Modes

### Bit-Bang Mode (Simple)

The simplest approach: toggle PB0 (MOSI) and PB1 (SCK) directly, shifting out
one bit at a time. Read CB2 for MISO if needed (or use shift register to
capture incoming data).

```asm
; Full bit-bang SPI transfer
; Send byte in A, returns received byte in A
.spi_transfer
    STA spi_temp

    ; Clear shift register
    LDA SR

    ; Start with SCK low
    LDA IORB
    AND #NOT_SCK
    STA IORB

    LDX #8
.spi_bit
    ; Shift out next bit
    LDA spi_temp
    ASL A
    STA spi_temp

    ; Set MOSI based on carry
    LDA IORB
    AND #%11111110      ; Clear MOSI
    BCC mosi_low
    ORA #MOSI
.mosi_low
    STA IORB            ; MOSI set, SCK still low

    ; Rising edge - slave samples MOSI, outputs MISO
    ORA #SCK
    STA IORB

    NOP                 ; Setup time
    NOP

    ; Falling edge - shift register captures MISO via CB1
    AND #NOT_SCK
    STA IORB

    DEX
    BNE spi_bit

    LDA SR              ; Read received byte
    RTS
```

Measured performance: **~4,100 bytes/second** (65536 transfers in 15.9 seconds).

### Shift Register Mode (Turbo Reads)

For read-heavy operations (like polling joystick/mouse), the shift register
provides significant acceleration. This leverages VIA shift register **mode 3**
(shift in under external CB1 control).

Because CB1 is wired to PB1, toggling SCK automatically clocks data into the
shift register. MISO (on CB2) is captured on each falling edge of CB1/SCK.

**Key insight:** When reading (sending 0xFF), MOSI stays high for all 8 bits.
We can set MOSI once and then just toggle SCK, eliminating per-bit branching.

#### VIA Configuration for Turbo Mode

```asm
SR_IN_CB1 = %00001100   ; ACR mode 3: Shift in under CB1 control

.init_via_turbo
    ; Disable CB1/CB2 interrupts
    LDA #%00011000
    STA IER

    ; CB2 input, CB1 negative edge
    LDA #%00000000
    STA PCR

    ; Enable shift register mode 3
    LDA #SR_IN_CB1
    STA ACR

    ; Set port direction
    LDA DDRB
    ORA #MOSI OR SCK OR SS
    STA DDRB

    ; Idle state: SS high, SCK low, MOSI high
    LDA IORB
    ORA #MOSI OR SS
    AND #NOT_SCK
    STA IORB

    RTS
```

#### Optimized Turbo Read Routine

```asm
; Fast read-only transfer using shift register
; Sends 0xFF (MOSI stays high), returns received byte in A
; Much faster than full spi_transfer - no per-bit MOSI handling
.spi_read_byte
    LDA SR              ; Clear shift register

    ; MOSI high (sending 0xFF) - set once, not per-bit
    LDA IORB
    ORA #MOSI
    AND #NOT_SCK        ; Ensure SCK low
    STA IORB

    ; Just toggle SCK 8 times - SR captures MISO on falling edges
    LDX #8
.read_clock
    LDA IORB
    ORA #SCK            ; Rising edge
    STA IORB
    AND #NOT_SCK        ; Falling edge - SR captures
    STA IORB
    DEX
    BNE read_clock

    LDA SR              ; Read received byte
    RTS
```

Measured performance: **~7,400 bytes/second** (65536 transfers in 8.9 seconds).

### Performance Comparison

| Mode | Technique | Rate | Relative |
|------|-----------|------|----------|
| Bit-bang | Full spi_transfer | 4,124 bytes/sec | 1.0x |
| Turbo | spi_read_byte (SR mode 3) | 7,371 bytes/sec | 1.79x |

The turbo mode is **79% faster** for read operations. The gains come from:
1. No per-bit MOSI handling (just 8 clock toggles)
2. No conditional branching in the inner loop
3. Shift register captures data automatically

For the joystick/mouse interface, which is read-biased, turbo mode is the
clear choice. Writes (if needed) can fall back to bit-bang mode.

## Clock Speed Considerations

- BBC Micro runs at 2 MHz
- AVR runs at 18.432 MHz
- Measured bit-bang throughput: ~4,100 bytes/sec (~33 kHz bit rate)
- Measured turbo read throughput: ~7,400 bytes/sec (~59 kHz bit rate)
- Joystick updates at 50 Hz need only ~4-6 bytes per frame (~300 bytes/sec)
- Plenty of bandwidth for joystick, mouse, and SD card access

## ATmega1284p SPI Slave

| AVR Pin | Function | Direction |
|---------|----------|-----------|
| PB4 | SS | Input (active low) |
| PB5 | MOSI | Input |
| PB6 | MISO | Output |
| PB7 | SCK | Input |

Hardware SPI configured as slave, mode 0, MSB first.

## Alternative Approach: Time&Config

The Time&Config project (RTC and FRAM interface) also uses the User VIA for serial
communication but takes a different approach:

| VIA Pin | Time&Config Function |
|---------|---------------------|
| PB1 | Clock line (input with pullup, pulsed during cleanup) |
| PB5 | RTC chip select (active low) |
| PB6 | RTC alarm signal (input) |
| PB7 | FRAM chip select (active low) |
| CB1 | Shift register clock (external from RTC) |
| CB2 | Shift register data (bidirectional) |

Key differences from MMFS/SPItFIRE:

1. **External clock source**: The RTC chip provides clock pulses at 4096 Hz to CB1,
   rather than the BBC generating clock via PB1.

2. **No PB1-CB1 wiring**: Since the clock comes from the RTC, no external wire
   between PB1 and CB1 is needed.

3. **Different chip selects**: Uses PB5/PB7 instead of PB2/PB3/PB4.

4. **VIA shift register modes**: Uses Timer 2-controlled output (mode 6) and
   external clock input (mode 2), rather than the MMFS approach of software-
   clocked shifts.

The designs use non-overlapping chip select lines, so they could potentially
coexist. However, the PB1-CB1 wire required for MMFS/SPItFIRE would conflict
with Time&Config's expectation of external clock input on CB1.

## References

- [MMFS GitHub - Hardware Wiki](https://github.com/hoglet67/MMFS/wiki/Hardware)
- [MMFS Stardot Forum](https://www.stardot.org.uk/forums/viewtopic.php?t=30037)
- MMFS uses identical CB1/PB1 wiring for shift register acceleration
- [Time&Config - Codeberg](https://codeberg.org/Barneyntd/Time-Config.)
