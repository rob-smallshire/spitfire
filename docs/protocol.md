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

The commands that set port types and read joystick data for the ROM are
under "Joystick allocation" below. Test programs use the raw reads above:
SPIJOY plots each port, and SPIALL shows the JOY_ALL burst.

### Joystick allocation

This is the protocol for the ROM design in
[rom-design.md](rom-design.md) ("Design: port types and joystick
allocation"), implemented in the `spijoy` firmware. It replaced JOY_ADVAL,
JOY_MOS, CFG_HANDSET and the four-type CFG_TYPE_/JOY_TYPE_ commands of the
first ROM; the raw reads (0x40-0x4B) stay for test programs.

#### Port types

| Number | Type | Name | Joysticks | Electrical mode |
|---|---|---|---|---|
| 0 | `NONE` | No joystick | 0 | None |
| 1 | `SINGLE` | Standard single joystick | 1 | 3B Twin |
| 2 | `DUAL` | Standard dual joystick | 2 | 3B Twin |
| 3 | `3BS` | Voltmace Delta 3B Single | 2 | 3B Single |
| 4 | `3BT` | Voltmace Delta 3B Twin | 2 | 3B Twin |
| 5 | `14B` | Voltmace Delta 14B | 1 | 14B (keypad scan) |
| 6 | `BITSTIK` | Acorn Bitstik | 2 | 3B Twin |
| 7 | `QUINKEY` | Microwriter Quinkey | 2 | 3B Twin |

The electrical mode is how the AVR drives and reads the port: the same
three modes as now. The other types differ only in allocation and in how
fire and direction bits are derived. `DUAL` and `3BT` behave identically;
both are kept so that the status shows what the user chose.

#### Commands

| Command | Code | Response |
|---------|------|----------|
| JOY_ALL | 0x55 | The allocation burst (below) |
| JOY_CONFIG | 0x58 | The saved configuration (below) |
| CFG_PORT_A | 0xD0-0xD7 | Set Port A to type 0-7 and save it; echoes the command |
| CFG_PORT_B | 0xD8-0xDF | The same for Port B |
| JOY_PORT_A | 0xE0-0xE7 | Set Port A's type until the next reset or CFG_ command (not saved); echoes the command |
| JOY_PORT_B | 0xE8-0xEF | The same for Port B |

#### Saved configuration

| Bits | Content |
|------|---------|
| 0-2 | Port A type (0-7) |
| 3-5 | Port B type (0-7) |
| 6 | Always 1 |
| 7 | Always 0 |

As before, bits 6 and 7 show the AVR answered. The EEPROM record gets a
new marker, so a record saved by the old firmware reads as blank and gives
the defaults: Port A `DUAL`, Port B `NONE` (joysticks 1 and 2 on Port A).
The CFG_ commands take effect in JOY_CONFIG at once; the main loop then
sets up the ports and writes the EEPROM, rewriting only bytes that
differ, so repeating a setting costs no write cycles. JOY_PORT_ changes
the active type only, so test programs leave the saved configuration
alone.

The fuses leave EESAVE unprogrammed (high fuse 0xD9), so the chip erase
before each upload also erases the EEPROM, and the AVR comes back with the
defaults after reflashing.

#### JOY_ALL burst

Slots are allocated as in the ROM design: Port A's joysticks first, then
Port B's, giving joysticks 1-4 (channel pairs (1,2), (3,4), (17,18),
(19,20)). The burst carries a record for each allocated joystick, the
same for every joystick, then the keypads, in one chip select:

| Group | Bytes | Present | Content |
|---|---|---|---|
| Header | 2 | Always | Byte 0: &A0 OR n, n = joysticks allocated (0-4). Byte 1: &50 OR k, k = keypad mask (bit j-1 set if joystick j has a keypad) |
| J1 | 5 | Always | Switch byte, X, Y |
| J2 | 5 | n >= 2 | Switch byte, X, Y |
| J3 | 5 | n >= 3 | Switch byte, X, Y |
| J4 | 5 | n = 4 | Switch byte, X, Y |
| Keypads | 2 each | Per bit of k, joystick order | Keys 0-11, 1 = pressed, low byte first, bits 12-15 zero |

- **Values** (X and Y) are 16-bit ADVAL values, low byte first,
  `v<<6 OR v>>4` from the 10-bit reading.
- **Switch byte:** bit 0 is the joystick's fire; bits 4-7 are its
  directions (left, down, up, right), set beyond a quarter of full scale
  from centre. Bits 1-3 are 0. The threshold is applied here, in the
  firmware only, so every program gets the same answer.
- **What the ROM makes of them:** the switch bytes are `ADVAL(12)`
  (joysticks 1 and 2, low byte first) and `ADVAL(28)` (3 and 4).
  `ADVAL(0)` and `(16)` are the odd joystick's switch byte with the even
  joystick's fire added in bit 1, the BBC's layout. The J1 record, with
  that bit added, is MOS 5's &02B6-&02BA.
- **J1 is always sent**, as zeros when nothing is allocated, so the ROM
  always writes the MOS's five bytes and an empty configuration reads 0.
- **The ROM zeroes** the groups that are not sent, so unallocated
  channels, fire bits and keypads read 0.
- **Fire and directions by type:**
  - `SINGLE`, `DUAL`, `3BT`: each handset's fire input is its joystick's
    fire bit.
  - `3BS`: pin 13 (two buttons) is the first joystick's fire, pin 10 (one
    button) the second's.
  - `14B`: key 10 is the fire bit; the keypad carries all twelve keys.
  - `BITSTIK`: the two digital buttons are the two fire bits; channels
    are raw, with the third button on CH3. Directions only for the first
    joystick (X and Y): the second is the twist and the third button.
  - `QUINKEY`: no fire or direction bits; channels are raw.
- **Validity:** the two header marker nibbles (&A, &5) cannot come from a
  floating or stuck MISO. The ROM ignores a burst whose header is wrong,
  or whose n or k is out of range.
- **Length:** 7 bytes with none or one joystick, then 5 more for each
  joystick, plus 2 per keypad. Only a `14B` has a keypad, and it is one
  joystick, so the longest bursts are 22 bytes (four joysticks), 19
  (`DUAL` and `14B`) and 16 (two `14B`s). The ROM reads the burst with a
  receive-only loop; at 50 Hz, 22 bytes cost about 9-10% of the 6502
  (see [performance.md](performance.md)). Raising SS ends a burst early.

#### Empty ports
A port set to a joystick type with nothing plugged in floats (about
700/1023 on Rev 1, with J11 not fitted), not 0, and can look like a
joystick to software that checks for centred readings. It is up to the
user to set an unused port to `NONE`. The AVR does not try to detect an
empty port: floating analogue inputs on the AVR show a lot of crosstalk,
so any presence test would be unreliable.

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
