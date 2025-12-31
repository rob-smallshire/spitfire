# SPItFIRE SPI Protocol Specification

This document describes the SPI communication protocol between the BBC Master Compact and the SPItFIRE adapter.

## Overview

The BBC Master Compact's Mouse/Joystick port exposes a 6522 VIA. The host software bit-bangs an SPI protocol on the VIA output lines to communicate with the ATMega1284p, which operates as an SPI slave.

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
