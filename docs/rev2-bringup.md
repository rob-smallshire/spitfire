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
