# Rev 1 PCB Bring-up Log

Record of bringing up the first assembled Rev 1 SPItFIRE PCB. Connectors
are fitted just-in-time, one subsystem at a time, so that expensive
connectors are not lost to a faulty board.

## Board 1 - 2026-10-03

### Initial power-up via ISP

First connection of the USBasp (5 V jumper fitted, powering the board)
caused the USBasp's red power LED to go out, indicating the 5 V rail was
being pulled down. The board was disconnected immediately; the USBasp and
the host USB port were unharmed.

After reflowing the solder joints on the ATmega1284P (TQFP-44), the fault
cleared. With the USBasp reconnected its power LED stayed lit, and 5.09 V
was measured at all unpopulated connector footprints where expected and
across the 74HC138 supply pins.

### ISP communication and fuses

The factory-fresh AVR was read at a slow ISP clock (`-B 32`, 16 kHz),
since a new part runs from the internal 8 MHz RC oscillator divided by 8.

| | Factory | Written |
|---|---|---|
| Signature | `1E 97 05` (ATmega1284P) | - |
| Low fuse | `0x62` (internal RC, CKDIV8) | `0xF7` (full-swing crystal, no CKDIV8) |
| High fuse | `0x99` (JTAG enabled) | `0xD9` (JTAG disabled, frees PC2-PC5) |
| Extended fuse | `0xFF` (BOD off) | `0xFF` |
| Lock | `0xFF` | unchanged |

Fuses were written at the slow ISP clock, with the low fuse (clock
source) written last.

The 18.432 MHz crystal was verified by reading the signature at a 1.5 MHz
ISP clock. This is only possible with a CPU clock above 6 MHz, so it
proves the crystal oscillator is running (the old 1 MHz internal clock
would fail). Normal programming uses `-B 5` (187.5 kHz).

### Status LED

The status LED on Rev 1 is **active-high** (PD7 -> R2 -> D2 -> GND),
the opposite of the breadboard prototype. Initial firmware left the LED
lit after startup. The firmware was changed to a shared `status_led`
module: three quick flashes on reset, then a once-per-second
double-flash heartbeat driven by a Timer0 compare interrupt at 100 Hz.
The LED was fitted the correct way round.

### Host DE-9 (J1) and power from the Master Compact

J1 fitted. Pinout verified against the PCB netlist and
[spi-interface.md](spi-interface.md); CB1 (pin 5) is tied to SCK (pin 3)
on the PCB, replacing the external wire used on the prototype.

Powered from the Master Compact through a 0.5 m DE-9 to DE-9 cable, the
board's 5 V rail measured **4.85 V**. This is within the ATmega1284P
specification for 18.432 MHz (4.5-5.5 V for 0-20 MHz).

Brown-out detection is currently disabled. Enabling 4.3 V BOD (extended
fuse `0xFC`) is worth considering, so that the AVR resets cleanly if the
supply sags below the 4.5 V needed at this clock speed.

#### USBasp caveats when the Compact powers the board

- J1 pin 7 connects the Compact's +5 V directly to the board's 5 V rail.
  **Remove the USBasp's 5 V jumper** (or unplug the USBasp) whenever the
  Compact is connected, otherwise two supplies drive the same rail.
- An **unpowered** USBasp attached to the ISP header holds the AVR in
  reset: RESET, SCK and MOSI are pulled low through the input protection
  diodes of its unpowered ATmega8, and the heartbeat stops. A powered
  USBasp (jumper removed) can stay attached; its pins idle in a
  high-impedance state between programming sessions.

### 74HC138 decoder

SPIWALK (about 2.1 s per address) was run from the Compact and checked
with a logic probe:

- A0-A2 (pins 1-3) count correctly.
- Y0-Y7 each go low in turn, synchronised with the address shown on the
  BBC display.
- Each Y output reaches its connector, J4-J9 inclusive.
- Y1 feeds the AVR's SS pin.

### SPI data path

AVR running the `spitest` firmware (reply = received byte XOR &55):

| Test | Result |
|---|---|
| SPITEST (bit-bang) | No bad transfers |
| SPITTEST (turbo, VIA shift register via CB1) | No bad transfers |

Both were run past &0100 good transfers, covering every byte value on
MOSI and MISO.

### Throughput

| Mode | Prototype (breadboard) | Rev 1 |
|---|---|---|
| Bit-bang (SPIPERF) | 4,124 bytes/s | 4,147 bytes/s |
| Turbo (SPITPERF) | 7,371 bytes/s | 7,388 bytes/s |

Throughput is set by the 6502 transfer loops rather than the board, so
matching figures are expected. The longer cable and the PCB layout
introduced no errors.

### Status

| Subsystem | Status |
|---|---|
| Power (from Compact) | Working, 4.85 V |
| ISP programming, fuses, crystal | Working |
| Status LED | Working (active-high) |
| 74HC138 decoder, J4-J9 chip selects | Working |
| SPI, bit-bang and turbo | Working, no errors |
| DA-15 joystick ports | Not yet fitted |
| Peripheral DE-9 (J13) | Not yet fitted |
