# SPI Interface Design Document

## Overview

SPItFIRE uses SPI to communicate between the BBC Master Compact and an ATmega1284p microcontroller. The BBC acts as SPI master, bit-banging the protocol on its User VIA. The AVR acts as SPI slave using its hardware SPI peripheral.

The design follows the proven MMFS approach, wiring CB1 to PB1 externally to enable both bit-banged and shift-register-accelerated transfers.

## BBC Master Compact DE-9 Pinout

The DE-9 Mouse/Joystick port exposes User VIA pins:

| DE-9 Pin | VIA Signal | SPI Function | Direction |
|----------|------------|--------------|-----------|
| 1 | PB3 | SS (device 2) | Output |
| 2 | PB2 | SS (SPItFIRE) | Output |
| 3 | PB1 | SCK | Output |
| 4 | PB4 | SS (device 3) | Output |
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
| PB2 | AVR_SS | SPItFIRE chip select (active low) |
| PB3 | (spare SS) | Available for SD card |
| PB4 | (spare SS) | Available for third device |
| CB1 | SCK | Wired to PB1 for shift register clock |
| CB2 | MISO | Data from slave (same as MMFS) |

## Multi-Device SPI Bus

The DE-9 port provides three independent slave select lines, supporting up to three SPI devices without any external decoder:

1. **PB2** - SPItFIRE (joystick/mouse)
2. **PB3** - SD Card (mass storage, MMFS compatible)
3. **PB4** - Future expansion

```
DE-9 Connector                           Devices
──────────────                           ───────
Pin 6 (PB0) ─────────────────────┬─[1kΩ]──→ AVR PB5 (MOSI)
                                 ├─────────→ SD MOSI
                                 └─────────→ Dev3 MOSI

Pin 3 (PB1) ──┬──────────────────┬─[1kΩ]──→ AVR PB7 (SCK)
Pin 5 (CB1) ──┘ (wire together)  ├─────────→ SD SCK
                                 └─────────→ Dev3 SCK

Pin 9 (CB2) ←────────────────────┬─[1kΩ]─── AVR PB6 (MISO)
                                 ├─────────── SD MISO
                                 └─────────── Dev3 MISO

Pin 2 (PB2) ─────────────────────────────────→ AVR PB4 (SS)
Pin 1 (PB3) ─────────────────────────────────→ SD SS
Pin 4 (PB4) ─────────────────────────────────→ Dev3 SS
Pin 8 (0V)  ─────────────────────────────────── GND (common)
```

### Device Selection

directly select one device at a time by driving its SS line low:

| PB4 | PB3 | PB2 | Selected Device |
|-----|-----|-----|-----------------|
| 1 | 1 | 1 | None (all deselected) |
| 1 | 1 | 0 | SPItFIRE |
| 1 | 0 | 1 | SD Card |
| 0 | 1 | 1 | Device 3 |

## SPItFIRE As-Built Wiring

Connection from female DE-9 breakout board to ATmega1284p, using a straight-through
DE-9 cable from the Master Compact:

```
Female DE-9 Breakout        ATmega1284p
────────────────────        ───────────
Pin 2 (PB2/SS)   ─────────────────────→ PB4 (SS)
Pin 3 (PB1/SCK)  ──┬───────[1kΩ]──────→ PB7 (SCK)
Pin 5 (CB1)      ──┘ (wire together)
Pin 6 (PB0/MOSI) ──────────[1kΩ]──────→ PB5 (MOSI)
Pin 9 (CB2/MISO) ←─────────[1kΩ]─────── PB6 (MISO)
Pin 8 (GND)      ─────────────────────── GND
```

| DE-9 Pin | Signal | Resistor | AVR Pin |
|----------|--------|----------|---------|
| 2 | SS | direct | PB4 |
| 3 | SCK | 1kΩ | PB7 |
| 5 | CB1 | wire to pin 3 | - |
| 6 | MOSI | 1kΩ | PB5 |
| 8 | GND | direct | GND |
| 9 | MISO | 1kΩ | PB6 |

Pins 1, 4, 7 unused (spare SS lines and +5V).

## Series Resistors

1kΩ series resistors serve two purposes:

**ISP programming compatibility (MOSI, SCK):** The BBC VIA and ISP programmer both
drive these lines to the AVR. The resistors allow the programmer to override the
BBC's signals during programming. SS does not need a resistor because the ISP
programmer uses RESET, not SS, to enter programming mode.

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

SD card connections do not need resistors as they don't conflict with the AVR
programmer (different device on shared bus).

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

    ; 4. Set port direction (PB0=MOSI, PB1=SCK, PB2=SS as outputs)
    LDA DDRB
    ORA #%00000111
    STA DDRB

    ; 5. Set idle state: SS high, SCK low (CPOL=0), MOSI high
    LDA IORB
    ORA #%00000101      ; SS and MOSI high
    AND #%11111101      ; SCK low
    STA IORB

    RTS
```

## Transfer Modes

### Bit-Bang Mode (Simple)

Write to PB0/PB1 to toggle MOSI and SCK. Read CB2 for MISO.
Suitable for initial bring-up and low-speed operation.

### Shift Register Mode (Fast Reads)

Leverages VIA shift register mode 2:
- CB1 (wired to PB1) provides clock to shift register
- CB2 receives serial data into shift register
- Write to PB1 to generate clock pulses
- Read shift register for received byte

This matches MMFS "turbo read" mode for high-speed data transfer.

## Clock Speed Considerations

- BBC Micro runs at 2 MHz
- AVR runs at 18.432 MHz
- Bit-bang: ~10-50 kHz practical
- Shift register: potentially faster (limited by VIA timing)
- Joystick updates at 25 Hz need only ~2-4 bytes per frame
- Plenty of bandwidth for joystick, SD card, and additional devices

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
