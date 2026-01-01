# SPItFIRE

**SPI + joystick FIRE button** - An analogue joystick and quadrature mouse adapter for the Acorn BBC Master Compact.

## Overview

The Acorn BBC Master Compact lacks the analogue-to-digital converter (ADC) hardware found in other BBC Micro models, making it incompatible with standard analogue joysticks. SPItFIRE bridges this gap by providing:

- **Analogue joystick support** via ADC sampling of potentiometer positions
- **DE-9 quadrature mouse port** for connecting a standard mouse
- **Keyboard matrix scanning** for joystick buttons

The system uses an ATMega1284p microcontroller as an SPI slave device. The BBC Master Compact's Mouse/Joystick port (an exposed 6522 VIA) communicates with the microcontroller via a bit-banged SPI protocol.

## Architecture

```
┌─────────────────────┐         SPI          ┌──────────────────────┐
│  BBC Master Compact │◄────────────────────►│     ATMega1284p      │
│                     │   (bit-banged on     │                      │
│  6522 VIA Port      │    User VIA Port B)  │  ┌────────────────┐  │
└─────────────────────┘                      │  │ ADC: Joystick  │  │
                                             │  │ GPIO: Buttons  │  │
                                             │  │ GPIO: Mouse    │  │
                                             │  └────────────────┘  │
                                             └──────────────────────┘
                                                      │
                              ┌────────────────┬──────┴───────┐
                              ▼                ▼              ▼
                        ┌──────────┐    ┌──────────┐   ┌────────────┐
                        │ Joystick │    │  Keypad  │   │ DE-9 Mouse │
                        │ (Analog) │    │  Matrix  │   │(Quadrature)│
                        └──────────┘    └──────────┘   └────────────┘
```

## Repository Structure

```
spitfire/
├── firmware/           ATMega1284p C++ firmware (SPI slave)
│   ├── src/            Source files
│   ├── include/        Header files
│   ├── cmake/          CMake toolchain files
│   ├── CMakeLists.txt  Build configuration
│   └── CMakePresets.json
├── rom/                BBC Micro 6502 assembly ROM driver
│   └── src/            BeebAsm source files
├── hardware/           KiCAD hardware designs
│   └── spitfire/       Main schematic and PCB
└── docs/               Documentation
    └── protocol.md     SPI protocol specification
```

## Building

### Firmware (ATMega1284p)

Requirements:
- CMake 3.20+
- avr-gcc toolchain
- avrdude (for programming)

```bash
cd firmware
cmake --preset release
cmake --build --preset release
cmake --build --preset release --target upload
```

### ROM (BBC Micro)

Requirements:
- BeebAsm assembler

```bash
cd rom
make
```

## Hardware

The hardware design is created in KiCAD. See the `hardware/` directory for schematics and PCB layouts.

### Connections

- **Mouse/Joystick Port**: Directly connected to BBC Master Compact's exposed 6522 VIA
- **DE-9 Mouse Port**: Standard Atari/Amiga-style quadrature mouse connection
- **Joystick Inputs**: Analogue potentiometer inputs via ADC channels

## Protocol

The BBC Micro bit-bangs an SPI protocol on the VIA port to:
- Configure the adapter
- Request joystick position data (X/Y axes)
- Request mouse velocity data
- Read button states

See [docs/protocol.md](docs/protocol.md) for the full protocol specification.

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.
