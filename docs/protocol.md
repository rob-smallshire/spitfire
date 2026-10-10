# SPItFIRE SPI Protocol Specification

This document describes the SPI communication protocol between the BBC Master Compact and the SPItFIRE adapter.

## Overview

The BBC Master Compact connects to SPItFIRE via the **Host DE-9** connector, which exposes the 6522 VIA. The host software bit-bangs an SPI protocol on the VIA output lines to communicate with the ATMega1284p, which operates as an SPI slave.

See [spi-interface.md](spi-interface.md) for connector terminology and physical layer details.

## Physical Layer

### Pin Assignments

| VIA Pin | Signal | Direction | Description |
|---------|--------|-----------|-------------|
| PBx     | SCLK   | Host→Device | SPI Clock |
| PBx     | MOSI   | Host→Device | Master Out, Slave In |
| PBx     | MISO   | Device→Host | Master In, Slave Out |
| PBx     | CS     | Host→Device | Chip Select (active low) |

*TODO: Define exact VIA pin assignments based on hardware design*

### SPI Configuration

- **Mode**: SPI Mode 0 (CPOL=0, CPHA=0)
- **Bit Order**: MSB first
- **Clock Speed**: Limited by VIA bit-banging (typically < 100 kHz)

## Protocol Layer

### Command Format

Each transaction begins with a command byte sent by the host:

```
┌─────────────────────────────────────────┐
│ Bit 7-4: Command   │ Bit 3-0: Params   │
└─────────────────────────────────────────┘
```

### Commands

We need much more than the following, but this gives a flavour.


| Command | Code | Description | Response Bytes |
|---------|------|-------------|----------------|
| NOP     | 0x00 | No operation | 0 |
| STATUS  | 0x10 | Get device status | 1 |
| JOY_X   | 0x20 | Get joystick X position | 1 |
| JOY_Y   | 0x21 | Get joystick Y position | 1 |
| JOY_BTN | 0x22 | Get joystick buttons | 1 |
| MOUSE_X | 0x30 | Get mouse X velocity | 1 (signed) |
| MOUSE_Y | 0x31 | Get mouse Y velocity | 1 (signed) |
| MOUSE_BTN | 0x32 | Get mouse buttons | 1 |
| CONFIG  | 0xF0 | Configuration command | varies |

### Analogue Joystick Commands (`spijoy` firmware)

The `spijoy` firmware reports both DA-15 ports at full 10-bit resolution.
Channels follow the Acorn port: CH0-CH3 are DA-15 pins 15, 7, 12 and 4.
Each response is answered from cached values (the ADC converts all eight
inputs continuously), so it is ready for the host's dummy byte.

| Command | Code | Response |
|---------|------|----------|
| JOY_A0-JOY_A3 | 0x40-0x43 | Low byte of Port A CH0-CH3; latches the high byte |
| JOY_B0-JOY_B3 | 0x44-0x47 | The same for Port B |
| JOY_HI | 0x48 | High byte latched by the last channel or keypad read |
| JOY_BTN | 0x49 | Fire inputs, 1 = pressed: b0 A pin 13, b1 A pin 10, b2 B pin 13, b3 B pin 10 |
| JOY_KEY_A | 0x4A | Port A 14B keypad buttons 0-7, 1 = pressed; latches buttons 8-11 |
| JOY_KEY_B | 0x4B | The same for Port B |
| JOY_TYPE_A | 0xE0-0xE3 | Set Port A to None, 3B Twin, 3B Single or 14B; echoes the command |
| JOY_TYPE_B | 0xE4-0xE7 | The same for Port B |

An Acorn-standard joystick such as the Bitstik uses 3B Twin, which grounds
pins 3, 5 and 6 and reads all four channels. `beeb/spitest` SPIJOY exercises
every command.

### Joystick Data Format

Joystick position values are 8-bit unsigned (0-255):
- 0x00: Minimum position (left/up)
- 0x80: Centre position
- 0xFF: Maximum position (right/down)

### Mouse Data Format

Mouse velocity values are 8-bit signed (-128 to +127):
- Positive X: rightward movement
- Positive Y: downward movement

Button bytes use bit flags:
- Bit 0: Left button (1 = pressed)
- Bit 1: Right button (1 = pressed)
- Bit 2: Middle button (1 = pressed)

## Timing

*TODO: Define timing requirements*

## Error Handling

*TODO: Define error conditions and recovery*

## Example Transactions

### Read Joystick X Position

```
Host:  CS=0, send 0x20
Host:  receive 1 byte (position)
Host:  CS=1
```

### Read Mouse Velocity

```
Host:  CS=0, send 0x30
Host:  receive 1 byte (X velocity, signed)
Host:  CS=1
Host:  CS=0, send 0x31
Host:  receive 1 byte (Y velocity, signed)
Host:  CS=1
```
