# AVR Programming Notes

This document tracks fuse settings, programming parameters, and configuration changes for the ATMega1284p-PU.

## Hardware Configuration

- **MCU**: ATMega1284p-PU (40-pin DIP)
- **Target Clock**: 18.432 MHz external crystal
- **Load Capacitors**: 15 pF (22 pF failed on breadboard)
- **Programmer**: USBasp v1.04
- **Power**: External 5V (tested also with programmer power)

## Successful Programming Parameters

```bash
avrdude -c usbasp -p m1284p -B 125kHz
```

- SCK frequency: 93750 Hz
- Device signature: 1E 97 05 (ATmega1284P)

## Fuse Settings

### Current (Factory Default)

| Fuse  | Value | Description |
|-------|-------|-------------|
| lfuse | 0x62  | Internal 8MHz RC, CKDIV8 enabled (1MHz actual) |
| hfuse | 0x99  | JTAG enabled, SPIEN enabled |
| efuse | 0xff  | BOD disabled |

### Target Settings

| Fuse  | Value | Description |
|-------|-------|-------------|
| lfuse | 0xf7  | External full-swing crystal, no CKDIV8 |
| hfuse | 0xd9  | JTAG disabled, SPIEN enabled |
| efuse | 0xff  | BOD disabled (unchanged) |

## Low Fuse (lfuse) Bit-by-Bit

Current: 0x62 = 0b01100010
Target:  0xf7 = 0b11110111

| Bit   | Name    | Current | Target | Notes |
|-------|---------|---------|--------|-------|
| 7     | CKDIV8  | 0 (on)  | 1 (off)| Divide clock by 8. Off = full speed |
| 6     | CKOUT   | 1 (off) | 1 (off)| Clock output on PB1. Unchanged |
| 5     | SUT1    | 1       | 1      | Startup time select bit 1 |
| 4     | SUT0    | 0       | 0      | Startup time select bit 0 |
| 3     | CKSEL3  | 0       | 1      | Clock source select |
| 2     | CKSEL2  | 0       | 1      | Clock source select |
| 1     | CKSEL1  | 1       | 1      | Clock source select |
| 0     | CKSEL0  | 0       | 1      | Clock source select |

**CKSEL[3:0] change: 0010 → 0111**
- 0010 = Internal 8MHz RC oscillator (factory default)
- 0111 = Full-swing crystal oscillator, 8-16+ MHz

**Why full-swing crystal?** More reliable oscillation startup, recommended for noisy environments or when driving other clock inputs.

## High Fuse (hfuse) Bit-by-Bit

Current: 0x99 = 0b10011001
Target:  0xd9 = 0b11011001

| Bit   | Name    | Current | Target | Notes |
|-------|---------|---------|--------|-------|
| 7     | OCDEN   | 1 (off) | 1 (off)| On-chip debug. Unchanged |
| 6     | JTAGEN  | 0 (on)  | 1 (off)| JTAG interface. **Disable to free PC2-PC5** |
| 5     | SPIEN   | 0 (on)  | 0 (on) | SPI programming. Must stay enabled! |
| 4     | WDTON   | 1 (off) | 1 (off)| Watchdog always on. Unchanged |
| 3     | EESAVE  | 1 (off) | 1 (off)| Preserve EEPROM on erase. Unchanged |
| 2     | BOOTSZ1 | 0       | 0      | Boot size select |
| 1     | BOOTSZ0 | 0       | 0      | Boot size select |
| 0     | BOOTRST | 1 (off) | 1 (off)| Boot reset vector. Unchanged |

**Only change: JTAGEN 0 → 1 (disable JTAG)**

Why disable JTAG? Frees up pins PC2 (TCK), PC3 (TMS), PC4 (TDO), PC5 (TDI) for GPIO use.

## Extended Fuse (efuse)

Current: 0xff = 0b11111111
Target:  0xff = 0b11111111

No changes. BOD (Brown-Out Detection) remains disabled.

## Programming Log

| Date | Action | Command | Result |
|------|--------|---------|--------|
| 2024-12-31 | Initial connection test | `avrdude -c usbasp -p m1284p -B 125kHz` | Success |
| 2024-12-31 | Read fuses | `avrdude -c usbasp -p m1284p -B 125kHz -U lfuse:r:-:h -U hfuse:r:-:h -U efuse:r:-:h` | 0x62, 0x99, 0xff |
| 2024-12-31 | Write fuses | `avrdude -c usbasp -p m1284p -B 125kHz -U lfuse:w:0xf7:m -U hfuse:w:0xd9:m -U efuse:w:0xff:m` | Success, verified |
| 2024-12-31 | Flash LED blink | `avrdude -c usbasp -p m1284p -B 5 -U flash:w:spitfire.hex:i` | 200 bytes, LED blinking at 1 Hz |
| 2025-01-02 | Flash UART test | `avrdude -c usbasp -p m1284p -B 5 -U flash:w:spitfire.hex:i` | 890 bytes, serial output confirmed |
| 2025-01-02 | Crystal test | 18.432 MHz with 15pF caps | Working (22pF failed on breadboard) |

## Serial Debugging Setup

**macOS Sequoia FTDI Driver Issue**: Apple's built-in FTDI DEXT (`com.apple.DriverKit-AppleUSBFTDI.dext`) causes terminal hangs when accessing FTDI serial ports via standard tools (picocom, screen, cat).

**Workaround**: Use "Serial 2" app from Decisive Tactics, which includes its own FTDI driver.
- App Store: Search "Serial 2" by Decisive Tactics
- Works with Sparkfun FTDI Basic Breakout
- Baud rate: 115200, 8N1

**Hardware connection:**
- FTDI RXI → AVR TXD0 (PD1, pin 15)
- FTDI TXO → AVR RXD0 (PD0, pin 14)
- FTDI GND → AVR GND

## Dual Joystick Port Wiring

Two DA-15 ports (Port A and Port B) with interleaved pin assignments.
Even-numbered AVR pins → Port A, Odd-numbered pins → Port B.

See `docs/joystick-detection.md` for automatic type detection algorithm.
See `docs/voltmace-pinouts.md` for complete DA-15 to AVR mapping.

### Analog Inputs (Port A - all 8 channels)

| Function | Port A | Port B | ADC | DA-15 Pin |
|----------|--------|--------|-----|-----------|
| X axis | PA0 (pin 40) | PA1 (pin 39) | ADC0/1 | 15 |
| Y axis | PA2 (pin 38) | PA3 (pin 37) | ADC2/3 | 7 |
| X_RIGHT | PA4 (pin 36) | PA5 (pin 35) | ADC4/5 | 12 |
| Y_RIGHT | PA6 (pin 34) | PA7 (pin 33) | ADC6/7 | 4 |

Note: PA6/PA7 are Y_RIGHT for Delta 3B Twin, or ROW0 for Delta 14B (mutually exclusive).

### Keypad Matrix (Delta 14B)

**Columns (active-low strobe, high-Z idle):**
| Column | Port A | Port B | DA-15 Pin |
|--------|--------|--------|-----------|
| COL0 | PB0 (pin 1) | PB1 (pin 2) | 5 |
| COL1 | PB2 (pin 3) | PB3 (pin 4) | 3 |
| COL2 | PC0 (pin 22) | PC1 (pin 23) | 2 |

**Rows (active-low with internal pull-ups):**
| Row | Port A | Port B | DA-15 Pin |
|-----|--------|--------|-----------|
| ROW0 | PA6 (pin 34) | PA7 (pin 33) | 4 |
| ROW1 | PC2 (pin 24) | PC3 (pin 25) | 6 |
| ROW2 | PC4 (pin 26) | PC5 (pin 27) | 10 |
| ROW3 | PC6 (pin 28) | PC7 (pin 29) | 13 |

**Button numbering:** switch = row * 3 + column (0-11)

### Other Pins

- **LED:** PD7 (pin 21) - Active-low activity indicator
- **UART:** PD0 (RX), PD1 (TX) - Serial debug at 115200 baud
- **SPI:** PB4 (SS), PB5 (MOSI), PB6 (MISO), PB7 (SCK) - Reserved for BBC Micro
- **VREF:** AVCC (pin 30) ← DA-15 pins 11/14
- **AGND:** GND ← DA-15 pin 8

## Commands Reference

```bash
# Test connection
avrdude -c usbasp -p m1284p -B 125kHz

# Read fuses
avrdude -c usbasp -p m1284p -B 125kHz -U lfuse:r:-:h -U hfuse:r:-:h -U efuse:r:-:h

# Write fuses (CAREFUL!)
avrdude -c usbasp -p m1284p -B 125kHz \
    -U lfuse:w:0xf7:m \
    -U hfuse:w:0xd9:m \
    -U efuse:w:0xff:m

# Flash firmware
avrdude -c usbasp -p m1284p -B 5 -U flash:w:spitfire.hex:i
```
