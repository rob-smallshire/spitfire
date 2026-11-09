# Rev 2 PCB Bring-up Log

Record of bringing up the first assembled Rev 2 SPItFIRE PCB. As with
Rev 1 (see [rev1-bringup.md](rev1-bringup.md)), connectors are fitted
just-in-time, one subsystem at a time, because they are the hardest parts
to recover from an abandoned board.

## Board 1 - 2026-11-07

### Initial assembly

Fitted first: the AVR and its supporting components, the 74HC138 decoder
and the ISP header (J10). The 100k pull-ups on the decoder inputs (R8-R10,
A2-A0) were not yet available and were left unfitted.

### Initial power-up via ISP

Powered from the USBasp (5 V jumper fitted). The USBasp's power LED stayed
lit, and 5.08 V was measured at the header positions. D2 stayed dark, as
expected with a blank AVR.

### ISP communication and fuses

The AVR was read at a slow ISP clock (`-B 32`, 16 kHz):

| | Factory | Written |
|---|---|---|
| Signature | `1E 97 06` (ATmega1284) | - |
| Low fuse | `0x62` (internal RC, CKDIV8) | `0xF7` (full-swing crystal, no CKDIV8) |
| High fuse | `0x99` (JTAG enabled) | `0xD9` (JTAG disabled, frees PC2-PC5) |
| Extended fuse | `0xFF` (BOD off) | `0xFF` |
| Lock | `0xFF` | unchanged |

The fitted part is an **ATmega1284-AU (non-P)**, which matches its marking.
It is pin-, memory- and fuse-compatible with the 1284P used on Rev 1; the
P part's picoPower features are not used. The ATmega1284 is now the
standard part. The firmware build defaults to `AVR_MCU=atmega1284` and
avrdude part `AVR_PART=m1284`, because avrdude refuses the chip under
`m1284p`.

Fuses were written at the slow ISP clock, with the low fuse last, and each
was verified. The fuses then read back correctly at a 1.5 MHz ISP clock,
which needs a CPU clock above 6 MHz, so the 18.432 MHz crystal is running.

### Status LED

`spitfire` firmware (2934 bytes) flashed and verified. D2 gave three quick
flashes on reset, then the once-per-second double-flash heartbeat. The
status LED is active-high, as on Rev 1.

## Board 1 - 2026-11-08

### Host DE-9 (J1) and power from the Master Compact

The `spitest` firmware was flashed first, with the USBasp powering the
board, ready for the SPI data path tests.

J1 fitted with the USBasp's 5 V jumper removed. Powered from the Compact
on a new 5 V 3 A supply, the board's rail measured **4.98 V** (Rev 1:
4.85 V on the old supply). The heartbeat continued. Firmware can be
flashed with the Compact powering the board and the USBasp attached
without its jumper.

### 74HC138 decoder

At first SPIWALK did not count correctly. A1 (measured at the R9 pad,
unfitted) sat at 0.16-0.24 V regardless of the walk, while the Compact's
PB3 switched cleanly between 0.000 V and 5.000 V. Continuity from J1
(through the connector, via a male DE-9 breakout) to R8-R10 and U1 pins
1-3 was 0 Ω. There were no bridges between U1 pins other than the
intended ~G0/~G1 (pins 4-5, both to GND), and the supply on U1 pins 8 and
16 was good.

**Cleaning the flux residue from around J1's joints fixed it.** It is not
clear whether the residue was loading the line or the cleaning reseated a
marginal joint. If A1 misbehaves again, reflow J1 pin 1.

After cleaning, SPIWALK checked with a logic probe:

- A0-A2 (U1 pins 1-3) count correctly.
- Y0-Y7 each go low in turn, exclusively, in step with the walk.
- Each Y output reaches its connector or the AVR: Y0 → J9 (moved from Y7
  on Rev 2), Y1 → AVR SS, Y2 → J4, Y3 → J5, Y4-Y6 → J6-J8.

The decoder works without R8-R10 while the Compact is connected, because
the Compact's own pull-ups (about 4.1k) hold A0-A2. The pull-ups are still
to be fitted.

### SPI data path

AVR running the `spitest` firmware (reply = received byte XOR &55):

| Test | Result |
|---|---|
| SPITEST (bit-bang) | No bad transfers in about an hour of running |
| SPITTEST (turbo, VIA shift register via CB1) | No bad transfers |

### Throughput

| Mode | Rev 1 | Rev 2 |
|---|---|---|
| Bit-bang (SPIPERF) | 4,147 bytes/s | 4,139 bytes/s |
| Turbo (SPITPERF) | 7,388 bytes/s | 7,371 bytes/s |

As on Rev 1, throughput is set by the 6502 transfer loops, so matching
figures are expected.

## Board 1 - 2026-11-08 to 2026-11-09

### Remaining connectors

All the remaining connectors were fitted together, to avoid repeated
soldering, cleaning and drying cycles.

### Peripheral DE-9 (J13)

Rev 2 corrects the Rev 1 mirroring (erratum 1): J13's pad coordinates are
now the mirror image of J1's. On the fitted connector, pin 7 measured
+4.98 V and pin 8 GND, with good continuity to ground, so J13 is fitted on
the component side as designed.

Serial (USART0), `spitfire` firmware, CP2102 adapter (TXD to pin 1, RXD to
pin 2, GND to pin 8), 115200 8N1:

- Transmit (PD1, pin 2): status lines received cleanly every 100 ms.
- Receive (PD0, pin 1): `1` set Port A to Delta 3B Twin, confirmed by the
  firmware; `0` restored `No Joystick`.

### Flux residue on the SPI lines

With `spimouse` running, SPIMOUSE at first worked, then reported both
axes counting steadily down and all three buttons pressed, with or
without a mouse and in every mode. That is every reply reading `&FF`
(-1 as a delta, all bits set as buttons): `spimouse` answers `&FF` to
any command it does not recognise. The heartbeat kept running, so the
AVR was not in reset, and SS was toggling. With `spitest` reflashed,
SPITEST, clean for an hour before the other connectors were fitted, now
showed many bad transfers.

SCK, MOSI, MISO and A0-A2 all run through the User Port headers (J2,
J3) on closely spaced 0.1" pins, and SCK, MOSI and MISO through J4-J9.
**A thorough clean and dry of the whole board fixed it**, and SPITEST
was clean again. As with the A1 fault on J1, residual flux between
fine-pitch connector pins is enough to break the SPI bus: clean
thoroughly after every soldering session.

### Mouse on the Peripheral DE-9 (J13)

`spimouse` firmware, SPIMOUSE on the Compact. An Amiga mouse (mode 2) and
an Atari mouse (mode 3) on J13 both worked correctly: axes, direction and
buttons.

J14 (the 20-way AMX mouse header) was then fully soldered. With the AVR
reflashed with `spimouse` and nothing on J13 (J13 and J14 share PD0-PD6),
an AMX mouse on J14 in AMX mode (1) worked correctly: axes, direction and
all three buttons.

### Joystick ports (J11, J12)

`spijoy` firmware, SPIJOY on the Compact. A Delta 14B on Port B (J12)
worked fully: both axes and buttons 0-11. On Port A (J11), each
left-column button (0, 3, 6, 9) also lit the other two buttons in its row,
while the middle and right columns were correct.

The keypad scan drives one column low at a time with the others released,
and reads the pulled-up rows. A column stuck low makes any of its buttons
pull that row low during every column's strobe, which lights the whole
row. So Port A's COL0 (PB0, J11 pin 5) was stuck low. PB0 is TQFP pin 40,
next to GND on pin 39: a solder bridge between them measured 0.1 Ω.
Reworking and cleaning the joint cleared it.

After the rework, every joystick type available (Delta 3B Single, 3B
Twin and 14B, Acorn Bitstik) and the Microwriter Quinkey (on the
four-way adapter) worked on both Port A and Port B.
