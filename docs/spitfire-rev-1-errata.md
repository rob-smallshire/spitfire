# SPItFIRE Rev 1 errata and Rev 2 changes

What the Rev 2 PCB must fix, and optional improvements, from bringing up
Rev 1 board 1. The measurements and reasoning behind each item are in
[rev1-bringup.md](rev1-bringup.md).

## Required changes

### 1. Peripheral DE-9 (J13) footprint is mirrored

**Problem.** The custom male DE-9 footprint
(`DE9_Male_..._MountingHolesOffset12.5mm_1.kicad_mod`) has the same pad
coordinates as the custom female footprint used for J1. Male and female
footprints must be mirror images (compare KiCad's stock `DSUB-9_Pins`,
pins running +x, with `DSUB-9_Socket`, pins running -x). Fitted normally,
pins 1-5, 2-4, 6-9 and 7-8 are swapped: **+5V lands on pin 8 and GND on
pin 7**, which would reverse-power a Compact, Amiga or Atari mouse.

Rev 1 physical pin -> signal: 1=PD4, 2=PD3, 3=PD2, 4=PD1, 5=PD0, 6=PD6,
7=GND, 8=+5V, 9=PD5.

**Fix.** Negate the pad X coordinates in the male footprint so it mirrors
the female one (or use KiCad's stock `DSUB-9_Pins` family). Check the
result against the designed pinout in
[peripheral-pinouts.md](peripheral-pinouts.md): pin 7 = +5V, pin 8 = GND.
The female DE-9 (J1) and female DA-15 (J11, J12) footprints were checked
and are correct.

**Rev 1 workaround.** Fit J13 on the reverse (solder) side, as on board 1.
Never plug a mouse into a component-side J13.

### 2. MISO has no pull-up

**Problem.** Nothing pulls MISO when no device drives it: with nothing
selected, or with the selected device absent (for example no RTC on J5).
The VIA's CB2 input then reads noise, so software cannot reliably tell
that nothing answered.

**Fix.** 10k from MISO to +5V. An absent device then reads `&FF`.

- The AVR drives MISO through its 1k series resistor (R5). Against the
  pull-up, its low is about 0.45 V, still a good low.
- The SD breakout's 3.3 V DO is fed only about 0.1 mA when tri-stated.

**Rev 1 workaround.** A 10k resistor across pins 2 (+5V) and 3 (MISO) of
a spare expansion header (J6, J7 or J8). Not pins 3-4: pin 4 is GND, and
that would pull MISO down. The ROM does not depend on it: it validates
the RTC's replies before claiming a clock call.

### 3. Reallocate the decoder outputs: Y7 is "no device"

**Problem.** The design used Y0 (A2-A0 = 000) as "no device" and put
expansion header J9 on Y7. But whenever the VIA is not driving PB2-PB4
(power-up, reset, before any SPItFIRE code runs, hot-plugging), the
Compact's own pull-ups (about 4.1k each, measured) hold the decoder on
**Y7**, so J9 is selected. Pull-downs strong enough to hold Y0 instead
would need to be about 1.5k or less, and the VIA's NMOS port B outputs
cannot then drive a good high.

**Fix.** Make the resting all-ones state select nothing:

- Leave **Y7 unconnected**.
- Move expansion header **J9 from Y7 to Y0**.

| Output | A2 A1 A0 | Rev 1 | Rev 2 |
|---|---|---|---|
| Y0 | 000 | Unconnected | J9 (spare header) |
| Y1 | 001 | SPItFIRE AVR | SPItFIRE AVR |
| Y2 | 010 | SD card (J4) | SD card (J4) |
| Y3 | 011 | RTC (J5) | RTC (J5) |
| Y4 | 100 | J6 | J6 |
| Y5 | 101 | J7 | J7 |
| Y6 | 110 | J8 | J8 |
| Y7 | 111 | J9 (must stay empty) | **No device** (unconnected) |

This gives seven usable chip selects on Rev 2 (Y0-Y6) instead of six.

**Software.** Already done, and it works on Rev 1: "no device" is
`%00011100` (Y7) in the test programs (`DEV_NONE`), the ROM (`spi_init`,
`spi_deselect`) and the MMFS driver (`nosel`). A device on J9 will need a
new constant, `%00000000` (Y0).

**Rev 1 workaround.** Keep J9 empty.

### 4. Crystal load capacitors C2 and C6 are 0201

**Problem.** C2 (XTAL1 to GND) and C6 (XTAL2 to GND), the load
capacitors for the 18.432 MHz crystal Y1, use the 0201 footprint
(`Capacitor_SMD:C_0201_0603Metric`). That is at the limit of what can be
placed by hand. All the other passives are 0603 hand-solder footprints.
Their value field is also still the placeholder `C_Small`.

**Fix.** Change both to `Capacitor_SMD:C_0603_1608Metric_Pad1.08x0.95mm_HandSolder`,
like C1 and C4-C10, and set the value to 15 pF. That is the value proven
with this crystal; 22 pF failed on the breadboard (see
[avr-programming-notes.md](avr-programming-notes.md)). Keep them close to
Y1 and the AVR's XTAL pins when re-routing for the larger pads.

## Optional improvements

### 5. Weak pull-ups on the decoder inputs A0-A2

47k-100k from each of A0-A2 to +5V, so that the decoder also rests on Y7
(no device) when the board is powered without the Compact, for example
from the USBasp. Not 10k: in parallel with the Compact's 4.1k, the VIA
would sink about 1.7 mA per line when driving low, above its 1.6 mA
rating. Goes with item 3.

### 6. Protect the 5V rail from two supplies

J1 pin 7 connects the Compact's +5V straight to the board's 5V rail, and
the ISP header's VCC is on the same rail. A USBasp with its 5V jumper
fitted therefore fights the Compact's supply. On Rev 1 this relies on
procedure: remove the USBasp's jumper when the Compact is connected.
Options: a Schottky diode in the ISP header's VCC line, or a jumper or
solder link to disconnect it. A diode drops the USBasp-powered rail to
about 4.7 V, which is still within the AVR's 4.5-5.5 V at 18.432 MHz.

A related caveat that a board change cannot remove: an unpowered USBasp
left attached holds the AVR in reset through RESET, SCK and MOSI.

### 7. Supply voltage margin

The board's rail measured 4.85 V when powered from the Compact through a
0.5 m cable. That leaves 0.35 V above the AVR's 4.5 V minimum at
18.432 MHz, and only about 0.5 V above a 4.3 V brown-out threshold
(item 8). Keep the supply path short and wide on Rev 2, and keep any
series element (such as item 6's diode) out of the Compact's supply
path.

### 8. Fuses for production boards (no PCB change)

- **Brown-out detection** is off (extended fuse `0xFF`). `0xFC` resets
  the AVR below about 4.3 V, which protects the EEPROM configuration
  while the supply rises and falls. The saved record's check byte
  catches corruption, but only by falling back to the defaults.
- **EESAVE** is off (high fuse `0xD9`), so every reflash erases the saved
  joystick configuration. Useful during development; `0xD1` keeps the
  EEPROM across reflashes.

### 9. Footprint library tidy-ups (no electrical change)

- C3 (10 uF, +5V to GND) uses an LED footprint
  (`LED_SMD:LED_0603_1608Metric_Pad1.05x0.95mm_HandSolder`). The pads are
  practically the same size as the capacitor's, but the footprint should
  be `Capacitor_SMD:C_0603_1608Metric_Pad1.08x0.95mm_HandSolder`, so that
  no LED polarity marking appears on the silkscreen or assembly drawing.
- R1-R6 use the 0603 capacitor footprint. Again harmless, but
  `Resistor_SMD:R_0603_1608Metric_Pad0.98x0.95mm_HandSolder` makes the
  BOM and placement files read correctly.

### 10. Label J10's VCC and GND pins on the silkscreen

J10, the 2x3 ISP header, is a shrouded and keyed IDC header, but the
USBasp's female 2x3 header has no key, so it is easy to plug in
backwards. The USBasp's pins are labelled, so labelling J10's +5V (pin 2)
and GND (pin 6) on the silkscreen lets the two be lined up by eye. A
pin 1 marker alone is less useful, because MISO is not marked on the
programmer.

J10 pinout (standard Atmel 6-pin ISP): 1 MISO, 2 +5V, 3 SCK, 4 MOSI,
5 RESET, 6 GND.

### 11. Mounting holes for add-on boards on J6-J9

The expansion headers J6-J9 are single-row 1x6 sockets, so a board
plugged into one is held at one edge only and will rock. Add M2 holes
next to each header (or one shared pattern per pair) for standoffs to
support an add-on's far edge. Rev 1 has eight M2 holes: four at the
corners (H301-H304) and four in a 20.3 mm square (H305-H308) around
U1, next to the SD card header J4, but none near J6-J9.

With Rev 2 adding J9 on Y0 (item 3), consider fixing a standard add-on
footprint (header position plus hole positions) and recording it in the
docs, so that add-on boards can be designed to it.

### 12. Ground pours on front and back copper

These were just forgotten in Rev 1.

## Not yet verified on Rev 1

These parts may still have faults that should be found before Rev 2 is
finalised:

- **Host User Port (J2) and User Port passthrough (J3).** No machine with
  a 20-way User Port was available. Checked against the netlist only:
  the connectors themselves and the PB5-PB7 passthrough tracks are
  untested.
- **Expansion headers (J6-J9).** Continuity and power only. No add-on has
  used them yet.

## Checked and not board faults

- The 5V rail was pulled down at first power-up; reflowing the
  ATmega1284P (TQFP-44) fixed it. An assembly fault, not a design fault.
- Serial dropouts on J13 were an intermittent contact in the chained
  DE-9 breakouts.
- AMX mouse button faults on J14 were traced to the mice.
- The status LED is active-high on Rev 1 (PD7 -> R2 -> D2 -> GND); the
  breadboard prototype was active-low. The firmware matches the PCB.
