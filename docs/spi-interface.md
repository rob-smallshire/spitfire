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

Pin 9 (CB2) ←────────────────────┬─────────── AVR PB6 (MISO)
                                 ├─────────── SD MISO
                                 └─────────── Dev3 MISO

Pin 2 (PB2) ─────────[1kΩ]───────────────────→ AVR PB4 (SS)
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

## SPItFIRE Minimal Wiring

For SPItFIRE only (no SD card):

```
DE-9 Connector              ATmega1284p
──────────────              ───────────
Pin 6 (PB0) ────[1kΩ]─────→ PB5 (MOSI)
Pin 3 (PB1) ──┬─[1kΩ]─────→ PB7 (SCK)
Pin 5 (CB1) ──┘ (wire together)
Pin 2 (PB2) ────[1kΩ]─────→ PB4 (SS)
Pin 9 (CB2) ←───────────────PB6 (MISO)
Pin 8 (0V)  ──────────────── GND
```

## Series Resistors

1kΩ resistors between BBC VIA outputs and AVR inputs (MOSI, SCK, SS) allow ISP programmer to override during programming:

```
ISP Programmer               ATmega1284p
──────────────               ───────────
MOSI ──────────────────────→ PB5 (direct)
MISO ←──────────────────────── PB6 (direct)
SCK  ──────────────────────→ PB7 (direct)
RESET ─────────────────────→ RESET
```

No resistor needed on MISO (AVR output, BBC input).

SD card connections do not need resistors as they don't conflict with the AVR programmer (directly directly directly directly different device on shared bus).

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

## References

- [MMFS GitHub - Hardware Wiki](https://github.com/hoglet67/MMFS/wiki/Hardware)
- [MMFS Stardot Forum](https://www.stardot.org.uk/forums/viewtopic.php?t=30037)
- MMFS uses identical CB1/PB1 wiring for shift register acceleration
