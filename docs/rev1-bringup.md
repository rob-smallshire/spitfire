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

### Peripheral DE-9 (J13) - mirrored footprint

J13 fitted (male DE-9). Measuring the connector directly (looking into
the pins, wide row uppermost, pin 1 top-left) gave **pin 7 = 0 V and
pin 8 = 4.8 V**: power and ground are swapped.

Cause: the custom male footprint
`DE9_Male_..._MountingHolesOffset12.5mm_1.kicad_mod` has pad coordinates
identical to the custom female footprint used for J1. Male and female
footprints must be mirror images (compare KiCad's stock `DSUB-9_Pins`,
pins running +x, with `DSUB-9_Socket`, pins running -x). The female
footprint is correct (J1 works with the Compact via a straight cable);
the male footprint was not mirrored when it was created.

Effect on Rev 1 (physical J13 pin -> signal): 1=PD4, 2=PD3, 3=PD2,
4=PD1, 5=PD0, 6=PD6, 7=GND, 8=+5V, 9=PD5.

**On a Rev 1 board with J13 fitted on the component side, do not plug a
mouse directly into J13** - Compact, Amiga and Atari mice take +5 V on
pin 7 and would be reverse-powered. Software remapping cannot correct the
swapped supply pins.

Two workarounds restore the designed pinout, so the mouse firmware and
[peripheral-pinouts.md](peripheral-pinouts.md) apply unchanged:

1. **Fit J13 on the reverse (solder) side of the board** (adopted on
   board 1). Mounting the right-angle connector on the opposite side
   mirrors it relative to the footprint, cancelling the footprint's
   mirroring. The connector still faces out of the same board edge, but
   upside down. Verified on board 1: pin 7 = 4.8 V, pin 8 = 0 V, and
   serial transmit and receive work through PD0/PD1 on pins 1/2.
2. A mirroring adapter (female on the board side, male on the
   peripheral side) wired 1-5, 2-4, 3-3, 4-2, 5-1, 6-9, 7-8, 8-7, 9-6.
   Used initially; replaced by option 1 as the chained breakouts were
   fragile.

The custom female DA-15 footprint used for J11/J12 was checked against
KiCad's stock `DSUB-15_Socket` and has the correct handedness.

### Serial (USART0) via the Peripheral DE-9

With the designed pinout restored (first via the mirroring adapter, then
with J13 re-mounted on the reverse side), a USB-TTL serial adapter was connected
to the designed Peripheral DE-9 pins: pin 1 (PD0, AVR RX, TQFP pin 9) to
the adapter's TXD, pin 2 (PD1, AVR TX, TQFP pin 10) to its RXD, and
pin 8 to GND. Continuity was checked end to end from the AVR pins.

Running the joystick firmware (`spitfire` target) at 115200 8N1:

- Transmit: periodic status lines received cleanly at the 100 ms
  reporting interval. 18.432 MHz gives an exact divisor (UBRR = 9,
  0% baud error).
- Receive: sending `3` set Port A to Delta 14B and the firmware
  confirmed `Port A: Delta 14B`; sending `0` restored `No Joystick`.

With J11 not yet fitted, Port A's ADC inputs float (readings around
700/690 of 1023), as expected.

Lesson from this step: DE-9 breakout boards may label their screw
terminals for one of their two connectors only. Check continuity to the
AVR pins themselves rather than trusting connector numbering when
several breakouts and adapters are chained.

### Joystick A (J11) - Delta 3B Twin

J11 fitted (female DA-15). Before soldering, the custom DA-15 footprint
was checked against KiCad's stock `DSUB-15_Socket` and the proven J1
female DE-9 footprint: same pin direction, row placement and second-row
offset. With the board powered, J11 pins 11 and 14 (VREF, from AVCC via
L1) read 4.85 V.

Delta 3B Twin connected, Port A set to 3B Twin over serial (`1`):

| | Left handset | Right handset |
|---|---|---|
| X at rest | 564 | 536 |
| Y at rest | 506 | 534 |
| X range | 0-1023 | 2-1023 |
| Y range | 0-1023 | 2-1023 |
| Fire button | Reported as `L` only | Reported as `R` only |

Rest readings were stable to within about 2 counts. Moving either
handset through its full range changed the other handset's readings by
at most 1 count, so there is no crosstalk between the four ADC
channels, and each handset and fire button maps to the correct side.

### Joystick A (J11) - Delta 3B Single

Delta 3B Single connected, Port A set to 3B Single over serial (`2`).
At rest X=495, Y=583, stable to 1 count. X and Y each covered the full
0-1023 range. The three physical buttons registered as two separate
left-fire (`L`) presses and one right-fire (`R`) press, matching the
handset's wiring (two buttons on PB0, one on PB1). The axes stayed
within 1 count while buttons were pressed.

The 3B Single drives both pot pairs so it can act as either player's
handset. With Port A switched to 3B Twin mode (`1`) to report all four
channels, the second pair (ADC4/ADC6, J11 pins 12 and 4) covered
0-1023 and tracked the primary pair (ADC0/ADC2) exactly: correlation
+1.000 on both axes, mean difference under 1 count, same direction, no
X/Y swap. Each wiper is evidently connected to both channels in
parallel.

### Joystick A (J11) - Delta 14B

Delta 14B connected, Port A set to 14B over serial (`3`). At rest
X=509, Y=502, keypad `FFF` (no buttons). X and Y each covered 0-1023.

Pressing the keypad from bottom-left to top-right, row by row, produced
buttons 0-11 in order, each as a single cleared bit (`FFE`, `FFD`,
`FFB` ... `7FF`), with no ghosting or multiple keys reported. The two
extra physical buttons, wired in parallel with button 10, both reported
as button 10 (`BFF`). The axes stayed within 1-3 counts while keys were
pressed, so keypad scanning does not disturb the ADC.

With the 3B Twin, 3B Single and 14B results, every Port A signal on J11
is verified: ADC0/2/4/6, both fire inputs and the full 3x4 keypad matrix.

### Joystick B (J12) - Delta 3B Twin, with Port A as a crosstalk reference

J12 fitted; pins 11 and 14 read 4.85 V. A second Delta 3B Twin was
connected to J12 while the first remained on J11, and both ports were
set to 3B Twin over serial (`1`, `5`). The Port A handsets were left
untouched while Port B was exercised.

| | Left X | Left Y | Right X | Right Y |
|---|---|---|---|---|
| Port B range | 0-1023 | 0-1023 | 0-1023 | 0-1023 |

- Each Port B handset moved only its own channels; three left-fire
  and three right-fire presses registered on Port B only.
- Port A's left handset held a constant reading (zero spread) while the
  Port B left handset swept its full range. It later stepped once,
  permanently, by about 20 counts at the moment the Port B right handset
  was picked up, which is consistent with a physical nudge (Delta
  handsets stay where they are left), not electrical crosstalk.
- Port A's right handset stayed within 1 count throughout.

### Joystick B (J12) - Delta 14B

Delta 14B connected to J12 (Port B set to 14B, `7`), with the 3B Twin
left on J11 as a reference. At rest X=488, Y=499, keypad `FFF`. X and Y
each covered 0-1023. Buttons 0-11 were reported in order, one bit each,
with no ghosting, and the two extra buttons reported as button 10. The
axes stayed within 2 counts while keys were pressed. The untouched
Port A channels varied by at most 1 count and reported no fire events.

With the 3B Twin and 14B results, every Port B signal on J12 is
verified: ADC1/3/5/7, both fire inputs and the full 3x4 keypad matrix.

### Mouse on the Peripheral DE-9 (J13) - Golden Image GI-6000

Firmware: `spimouse` (quadrature decoding on Port D via the PCINT3
pin-change interrupt). Test program: SPIMOUSE on the Master Compact.

The Golden Image GI-6000 is an optical mouse (it needs its own printed
pad) with a switch selecting Amiga or Atari wiring, so one mouse tests
both pinouts. It was plugged directly into the re-mounted J13.

| Mouse switch | SPIMOUSE mode | Result |
|---|---|---|
| Amiga | `2` (Amiga) | Both axes and all three buttons working |
| Atari | `3` (Atari) | Both axes and left/right buttons working |

No middle button in Atari mode is expected: the Atari pinout leaves
pin 5 unconnected and the firmware's Atari button table has no middle
button, matching standard two-button Atari mice.

### Peripheral User Port (J14) - AMX-compatible mice

J14 (20-way header) was checked against the adapter wiring in
[peripheral-pinouts.md](peripheral-pinouts.md) before fitting: every
signal pin matches, pins 1 and 3 are +5V and the odd pins 5-19 are GND.
Its pad numbering matches KiCad's stock 2x10 IDC header (not mirrored).
J13 and J14 share Port D, so only one peripheral connector is used at a
time.

An AMX mouse in SPIMOUSE mode `1` (AMX/Compact) gave both axes working,
confirming the AMX quadrature path (PD4/PD0/PD6/PD3). Buttons:

| | Left (pin 16, PD5) | Right (pin 20, PD1) |
|---|---|---|
| AMX mouse | Working | Not working |
| Second AMX-compatible mouse | Not working | Working |

Each J14 button path works with at least one mouse; a fault on J14
would break the same button on both. The failures are therefore in the
(old) mice, not the board.

### RTC header (J5) - SparkFun DeadOn DS3234

J5's pin order (GND, VCC, SQW, CLK, MISO, MOSI, SS) matches the DeadOn
breakout header; SQW is not connected. The RTC is selected by `~SS_3`,
decoder output Y3 (`DEV_RTC = %00001100`). No backup battery fitted.

**SPI mode.** The DS3234 picks its clock polarity from the state of SCLK
when CS falls. The 6522 shift register samples MISO on the rising edge
of CB1 (as MMFS assumes; MMFS idles the clock high). With SCLK low at CS,
the DS3234 would change DOUT on rising edges, racing the VIA's sample.
SCK is therefore idled **high** before the RTC is selected, giving
CPOL=1/CPHA=1: DOUT changes on falling edges and both ends sample on
rising edges. (The AVR is SPI mode 0 and is unaffected: it is only
selected with SCK idling low.)

New BBC test program SPIRTC (`beeb/spitest/src/spirtc.asm`):

| Test | Result |
|---|---|
| Write `55 AA 00 FF 01 80 5A A5` to SRAM, burst read back | Identical (`OK`) |
| Control register (0Eh) | `1C`, the power-on default |
| Status register (0Fh) | `C8` (OSF, BB32kHz, EN32kHz), the power-on default with no battery |
| Time/date burst read (00h-06h) | Counting from 00:00:00 01/01/2000, seconds advancing once per second |
| Temperature (11h-12h) | 23.50 C |

Register values matching their power-on defaults exactly confirm bit
alignment in both directions.

A second program, SPISETTIME (`beeb/spitest/src/spisettime.asm`), prompts
for the date and time, computes the day of the week (Sakamoto's method,
checked against Python's calendar for every date 2000-2099), waits for a
key press so the clock starts on an exact second, burst-writes registers
00h-06h and clears OSF. After setting, SPIRTC showed the new time
ticking and the status register no longer flagged OSF, confirming writes
to the time and status registers.

With a CR1225 backup cell fitted, the board was powered off for five
minutes and powered on again: the RTC had kept time throughout and OSF
remained clear.

### SD card header (J4) - Adafruit MicroSD breakout+

J4's pin order (5V, 3V, GND, CLK, DO, DI, CS, CD) matches the Adafruit
breakout; 3V and CD are not connected. The breakout regulates its own
3.3 V and level-shifts CLK/DI/CS with a 74HC4050; DO reaches MISO at
3.3 V, above the 6522's 2.0 V input threshold. The card is selected by
`~SS_2`, decoder output Y2 (`DEV_SD = %00001000`).

New BBC test program SPISD (`beeb/spitest/src/spisd.asm`), SPI mode 3
(SCK idling high, as MMFS). Because an SD card keeps driving DO for a
few clocks after CS goes high, every deselect is followed by one byte of
clocks with no device selected, so the card cannot contend with other
devices on the shared MISO line.

All steps passed with a card inserted: 80 power-up clocks, CMD0
(R1=01), CMD8 (SD v2, R7 echo correct), ACMD41 until ready (R1=00),
CMD58 (OCR read), CMD10 (CID read, with sensible manufacturer, product
name, serial number and date) and CMD17 (sector 0 read, with a valid
55 AA signature and partition entry).

Card used: a SanDisk 16 GB microSDHC. CID as reported by SPISD:

| Field | Value |
|---|---|
| Manufacturer ID | `03` (SanDisk) |
| OEM ID | `SD` |
| Product name | `SC16G` |
| Revision | 8.0 |
| Serial number | `AC9304AB` |
| Manufacture date | 2018/04 |

### Expansion SPI headers (J6-J9) - continuity checked

Four 6-pin headers for future SPI add-ons, one per spare decoder output,
all with the same project-specific pinout:

| Pin | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| Signal | SCK | +5V | MISO | GND | MOSI | `~SS_n` |

| Header | Chip select | Decoder output | Device constant |
|---|---|---|---|
| J6 | `~SS_4` | Y4 | `%00010000` |
| J7 | `~SS_5` | Y5 | `%00010100` |
| J8 | `~SS_6` | Y6 | `%00011000` |
| J9 | `~SS_7` | Y7 | `%00011100` |

No add-ons exist yet. Each chip select was checked for continuity from
the 74HC138 and power was confirmed at each header. SCK, MISO and MOSI
are the shared nets already proven end to end by the AVR, RTC and SD
card, and SPIWALK showed Y4-Y7 switching correctly. Considered low risk.

### Host User Port (J2) and User Port Passthrough (J3) - not yet tested

J2 is the alternative host connection for a BBC Micro or Master with a
20-way User Port (instead of J1 for the Master Compact). J3 passes the
User Port through to further devices that do not use the SPItFIRE's pin
allocations; it is only useful when the host is connected via J2.

No machine with a working 20-way User Port was available, so neither
was tested. Netlist check: J2 pins 2/4/6/8/10/12/14 (CB1, CB2, PB0-PB4)
carry SCK, MISO, MOSI, SCK, A0, A1, A2, the same nets proven end to end
through J1; pins 16/18/20 (PB5-PB7) go only to J3. The untested parts are
therefore the connectors themselves and the PB5-PB7 passthrough tracks.
Considered low risk.

### Bus idle levels - no pull resistors on the shared SPI nets

The netlist has no pull resistors on MISO, MOSI, SCK or the decoder
inputs A0-A2 (the only resistors are R3-R6, the 1k series resistors to
the AVR). Two consequences:

**MISO floats when no device drives it.** With no device selected, or
with the selected device absent (e.g. no DeadOn on J5), the VIA's CB2
input reads whatever the floating line settles at, so software cannot
reliably tell that nothing answered. A pull-up makes an absent device
read `&FF` on every SPI device. Proposed: 10k to +5V. When the AVR
drives low through its 1k series resistor (R5) the line sits at about
0.45 V, still a good low; the SD breakout's 3.3 V DO is fed only about
0.1 mA when tri-stated. Rev 1 bodge, no soldering: a 10k resistor
across **pins 2 (+5V) and 3 (MISO)** of a spare expansion header
(J6-J8). Not pins 3-4: pin 4 is GND, and that would pull MISO down.

The SPItFIRE ROM does not rely on the pull-up: it validates what the
DS3234 returns before claiming a clock call (see
[rom-design.md](rom-design.md)), so Rev 1 boards without the bodge
still fall back to ANFS or the MOS when the RTC is absent.

**The decoder selects whatever A0-A2 float to** whenever the VIA is not
driving PB2-PB4: at power-up and reset (port B is all inputs), before
any SPItFIRE software has set the port up, and when the cable is
plugged into a running machine. The Compact's port is a joystick port
(switches pull lines to ground), so it probably has its own pull-ups on
PB0-PB4; if so the idle lines read all ones and select **Y7**, not Y0.
Options for Rev 2:

- Make Y7 the "no device" code, with on-board pull-ups agreeing with the
  Compact's. Every unconfigured state then selects nothing. Software
  change: `DEV_NONE` in the test programs and ROM, and `nosel` in the
  MMFS driver.
- Keep Y0 as "no device" and add pull-downs. These would fight any
  pull-ups in the Compact and could leave the lines at an indeterminate
  level.

To decide, measure the Compact with SPItFIRE unplugged and the machine
just reset: the voltage on DE-9 pins 1, 2 and 4 (PB3, PB2, PB4), then
again with 10k from each pin to ground. If the voltage stays high the
Compact has pull-ups, and the ratio gives their strength.

On Rev 1 this is harmless while nothing is fitted to J9 (Y7). Keep J9
empty until it is resolved.

SCK and MOSI need no resistors: devices ignore them while deselected.

### Rev 2 errata

| # | Issue | Fix |
|---|---|---|
| 1 | J13 male DE-9 footprint mirrored (pins 1-5, 2-4, 6-9, 7-8 swapped) | Negate pad X coordinates in the custom male DE-9 footprint so it mirrors the female footprint |
| 2 | MISO floats when no device drives it, so an absent device reads noise | 10k pull-up from MISO to +5V (Rev 1 bodge: 10k across pins 2-3 of J6, J7 or J8) |
| 3 | Decoder inputs A0-A2 float while the VIA is not driving them, so the idle device is undefined (probably Y7, via the Compact's own pull-ups) | Measure the Compact's PB2-PB4 idle levels, then either make Y7 "no device" with pull-ups, or keep Y0 with pull-downs (see "Bus idle levels") |

### Status

| Subsystem | Status |
|---|---|
| Power (from Compact) | Working, 4.85 V |
| ISP programming, fuses, crystal | Working |
| Status LED | Working (active-high) |
| 74HC138 decoder, J4-J9 chip selects | Working |
| SPI, bit-bang and turbo | Working, no errors |
| Joystick A (J11) | Working: Delta 3B Twin, 3B Single and 14B; all pins verified |
| Joystick B (J12) | Working: Delta 3B Twin and 14B; all pins verified, no crosstalk with Port A |
| Peripheral DE-9 (J13) | Working; fitted on reverse side to correct mirrored footprint (erratum 1) |
| Serial (USART0, 115200 8N1) | Working, transmit and receive |
| Mouse on J13, Amiga and Atari modes | Working (Golden Image GI-6000) |
| Peripheral User Port (J14), AMX mode | Working (button faults traced to the mice) |
| RTC (J5, DS3234 DeadOn) | Working: SRAM, set/read time, status, temperature, battery backup; `*TIME` and `TIME$` through the SPItFIRE ROM |
| SD card (J4, Adafruit microSD) | Working: initialisation, CID and sector reads; MMFS2 with the SPItFIRE device driver |
| Expansion headers (J6-J9) | Continuity and power checked; no add-ons yet |
| Host User Port (J2), passthrough (J3) | Not tested (no 20-way User Port host available); netlist checked |
