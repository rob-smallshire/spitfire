# Peripheral DE-9 Pinouts

The SPItFIRE has a **male DE-9 Peripheral port** to support connection of the following devices:

* Master Compact Mouse (e.g. Prodest PC128S DigiMouse) - three button
* Master Compact/Atari Switched Joystick
* Amiga Mouse - three button
* Atari ST Mouse - two button (some three-button variants exist)
* Microsoft Bus Mouse - passive, unpowered (e.g. green-eyed mouse)
* TTL Serial port (e.g. StarTech IC232TTL TTL-to-RS232 adapter)

Port D of the AVR is connected to the Peripheral DE-9 and configured under software control to support these different device classes.

## AVR Port D Mapping

| DE-9 Pin | AVR Pin | Function    | Notes                                        |
|----------|---------|-------------|----------------------------------------------|
| 1        | PD0     | RXD0 / GPIO | UART RX for IC232TTL; GPIO for mice/joystick |
| 2        | PD1     | TXD0 / GPIO | UART TX for IC232TTL; GPIO for mice/joystick |
| 3        | PD2     | GPIO        |                                              |
| 4        | PD3     | GPIO        |                                              |
| 5        | PD4     | GPIO        |                                              |
| 6        | PD5     | GPIO        |                                              |
| 7        | —       | +5V         | Hardwired, no AVR pin                        |
| 8        | —       | GND         | Hardwired, no AVR pin                        |
| 9        | PD6     | GPIO        |                                              |
| LED      | PD7     | GPIO        | Status LED, active on prototype              |

The UART pins (PD0/PD1) are constrained by AVR hardware to map to Peripheral DE-9 pins 1/2, which conveniently aligns with the IC232TTL's RXD/TXD pins. For mouse and joystick modes, PD0/PD1 are reconfigured as standard GPIO inputs.

## Pinout Table

| Pin | AVR Pin | Compact Mouse | Joystick | Amiga Mouse | Atari Mouse | MS Bus Mouse | IC232TTL |
|-----|---------|---------------|----------|-------------|-------------|--------------|----------|
| 1   | PD0     | XB            | Up       | YB          | XB          | NC           | RXD      |
| 2   | PD1     | Right Btn     | Down     | XA          | XA          | XA           | TXD      |
| 3   | PD2     | Middle Btn    | Left     | YA          | YA          | XB           | NC       |
| 4   | PD3     | YB            | Right    | XB          | YB          | YA           | NC       |
| 5   | PD4     | XA            | NC       | Middle Btn  | NC          | YB           | 0V       |
| 6   | PD5     | Left Btn      | Fire     | Left Btn    | Left Btn    | Button 1     | NC*      |
| 7   | —       | +5V           | NC       | +5V         | +5V         | (B3)*        | NC       |
| 8   | —       | 0V            | 0V       | 0V          | 0V          | Button 2     | NC       |
| 9   | PD6     | YA            | NC       | Right Btn   | Right Btn   | 0V           | NC       |

**Notes:**
- NC* = Pin 6 on IC232TTL is a 5V *output* (device powered from RS232 side). Configure as Hi-Z.
- (B3)* = Bus mouse interface cards support Button 3 on pin 7, but SPItFIRE hardwires pin 7 to +5V for mouse/joystick compatibility. Third button not supported on bus mouse.
- Quadrature signals use standard notation: XA/XB for horizontal axis, YA/YB for vertical axis.
- Acorn documentation uses alternate naming: Xaxis=XA, Xdir=XB, Yaxis=YA, Ydir=YB.
- All button signals are active-low (directly connect to ground when pressed).

## Quadrature Signal Convention

All quadrature mice use the same encoding, only the pinout differs:

```
Movement right/down: (0,0) → (1,0) → (1,1) → (0,1) → (0,0)
Movement left/up:    (0,0) → (0,1) → (1,1) → (1,0) → (0,0)

When A leads B by 90°: positive direction (right/down)
When B leads A by 90°: negative direction (left/up)
```

## Gender Changer Requirements

The SPItFIRE Peripheral port is **male DE-9**. Standard mice and joysticks have female DE-9 plugs and connect directly. The following devices have male DE-9 plugs and require a **female-to-female gender changer**:

| Device                 | Connector   | Gender Changer Required  |
|------------------------|-------------|--------------------------|
| Compact Mouse          | Female DE-9 | No - direct connection   |
| Amiga Mouse            | Female DE-9 | No - direct connection   |
| Atari Mouse            | Female DE-9 | No - direct connection   |
| Atari/Compact Joystick | Female DE-9 | No - direct connection   |
| Microsoft Bus Mouse    | Male DE-9   | **Yes - F-F adapter**    |
| StarTech IC232TTL      | Male DE-9   | **Yes - F-F adapter**    |

## Device-Specific Notes

### Master Compact Mouse

The Compact mouse pinout matches the BBC Master Compact's Mouse/Joystick port directly. The quadrature signals are on pins 1, 4, 5, 9 with buttons on pins 2, 3, 6.

Reference: [mdfs.net BBC Mouse](https://mdfs.net/Info/Comp/BBC/Mouse/)

### Amiga Mouse

The Amiga uses V-pulse/VQ-pulse (vertical) and H-pulse/HQ-pulse (horizontal) naming:
- V-pulse = YB, VQ-pulse = YA
- H-pulse = XA, HQ-pulse = XB

Pin 5 supports middle button/scroll wheel on three-button mice.

Reference: [AllPinouts Amiga Mouse](https://allpinouts.org/pinouts/connectors/input_device/mouse-joystick-amiga-9-pin/)

### Atari ST Mouse

The Atari ST pinout differs from Amiga - pins 1 and 4 carry different signals. Some third-party mice have an Amiga/Atari switch that swaps these signals.

The right mouse button (pin 9) on port 0 is shared with the fire button of port 1 on the Atari ST.

Reference: [old.pinouts.ru Atari ST](https://old.pinouts.ru/InputCables/atari_st_joystick_pinout.shtml)

### Microsoft Bus Mouse (Green-Eyed Mouse)

The original 1983 Microsoft mouse is entirely passive and requires no power supply. All six sensors operate as active-low switches. Pins 1 and 7 are physically not fitted on the original mouse connector, preventing accidental connection to RS-232 serial ports.

While the bus mouse ISA interface card supports a third button on pin 7, SPItFIRE hardwires this pin to +5V for compatibility with other mice. This means only two buttons are supported on bus mice - acceptable since the original green-eyed mouse has only two buttons anyway.

Reference: [What is a Bus Mouse?](https://blog.smallshire.no/blog/what-is-a-bus-mouse/)

### StarTech IC232TTL

TTL-level serial adapter. The device is powered from the RS232 side, with pin 6 being a 5V output. SPItFIRE should configure pin 6 as Hi-Z input to avoid conflict.

Reference: [IC232TTL Manual (PDF)](https://sgcdn.startech.com/005329/media/sets/IC232TTL_manual/IC232TTL_manual.pdf)

## Amiga vs Atari Comparison

The key difference between Amiga and Atari mice is the quadrature signal routing:

| Pin | Amiga | Atari |
|-----|-------|-------|
| 1   | YB    | XB    |
| 2   | XA    | XA    |
| 3   | YA    | YA    |
| 4   | XB    | YB    |

Pins 1 and 4 differ. This is why mice with an "Amiga/Atari" switch exist.

**Note on MDFS pinout labelling:** The Amiga and Atari mouse pinouts shown on
[mdfs.net](https://mdfs.net/Info/Comp/BBC/Mouse/) have the Y-axis signal
designations (YA/YB) reversed with respect to native Amiga and Atari
conventions. The MDFS assignments are correct for BBC Micro use - the Y-axis
labels are swapped to make the mouse coordinate system handedness match BBC
Micro software conventions. The X-axis labels are not affected. The pinout
table in this document uses the native Amiga/Atari conventions, not the
MDFS/BBC-adapted labelling.

# BBC Micro User Port Connector

The SPItFIRE unit is intended for the Master Compact mouse/joystick port. This machine
lacks the traditional User Port sported by all other models of BBC Micro and Master.
The User Port exposed all 10 data signals of the User VIA of the BBC Micro, CB1, CB2 and PB0 to PB7
inclusive. The user port was used for many peripherals, perhaps most notably the Marconi RB2
trackerball, the AMX Mouse and other mouses such as the Nidd Valley DigiMouse. The various mouses
seem to follow a common pinout, but the Marconi Trackerball is different.

The User Port used a 20 way 2x10 pin header connector with male on the machine and a female IDC
connector on the peripheral cable.

## Mouse and Trackerball User Port Pinouts

| Pin | VIA | Mouse | Trackerball |
|-----|-----|-------|-------------|
|  2  | CB1 |  XA   | XA          |
|  4  | CB2 |  YA   | YB          |
|  6  | PB0 |  XB   | LB          |
|  8  | PB1 |       | MB          |
| 10  | PB2 |  YB   | RB          |
| 12  | PB3 |       | XB          |
| 14  | PB4 |       | YA          |
| 16  | PB5 |  LB   |             |
| 18  | PB6 |  MB   |             |
| 20  | PB7 |  RB   |             |

The Marconi RB2 documentation uses X1/X2/Y1/Y2 notation (X1=XA, X2=XB, Y1=YA, Y2=YB).
Note that CB2 carries YA for mice but YB for the trackerball - the devices are not identical.

References:
- Mouse: [mdfs.net BBC Mouse](https://mdfs.net/Info/Comp/BBC/Mouse/)
- Trackerball: [Marconi RB2 User Guide (PDF)](https://www.domesday86.com/wp-content/uploads/2017/01/Marconi-RB2-User-Guide-BBC-Model-B.pdf)

These two devices cover all 10 signal pins of the user port, so we don't have
enough available signals on AVR Port D (7 bits, one reserved for status LED)
to individually service all ten User Port pins.

## User Port to DE-9 Adapter

A small adapter PCB can convert User Port mice and trackerballs for use with
SPItFIRE's Peripheral DE-9. The adapter uses the **Master Compact Mouse pinout**
on the DE-9 end, which gives it dual-purpose capability:

- **AMX Mouse (and compatibles):** Works with SPItFIRE (Compact Mouse mode)
  **and** directly with the Master Compact's mouse port (no SPItFIRE required).
- **Marconi RB2 Trackerball:** Works with SPItFIRE only (requires dedicated
  trackerball firmware mode). Not directly compatible with the Master Compact
  due to pinout differences.

The adapter merges signals from both device types onto seven DE-9 signal pins,
since only one device is connected at a time.

### Adapter Connectors

- **Input:** Female 20-way (2x10) IDC shrouded header (accepts User Port cable)
- **Output:** Male DE-9 (plugs into SPItFIRE Peripheral DE-9 or Master Compact
  Mouse/Joystick port)

### Adapter Wiring

| IDC Pin | VIA | Mouse | Trackerball | DE-9 Pin | Compact Signal | AVR Pin |
|---------|-----|-------|-------------|----------|----------------|---------|
|  2      | CB1 |  XA   | XA          | 5        | XA (Xaxis)     | PD4     |
|  4      | CB2 |  YA   | YB          | 9        | YA (Yaxis)     | PD6     |
|  6      | PB0 |  XB   | LB          | 1        | XB (Xdir)      | PD0     |
|  8      | PB1 |       | MB          | 3        | Middle Btn     | PD2     |
| 10      | PB2 |  YB   | RB          | 4        | YB (Ydir)      | PD3     |
| 12      | PB3 |       | XB          | 6        | Left Btn       | PD5     |
| 14      | PB4 |       | YA          | 2        | Right Btn      | PD1     |
| 16      | PB5 |  LB   |             | 6        | Left Btn       | PD5     |
| 18      | PB6 |  MB   |             | 3        | Middle Btn     | PD2     |
| 20      | PB7 |  RB   |             | 2        | Right Btn      | PD1     |
| 1/3     |     | +5V   | +5V         | 7        | +5V            | —       |
| odd     |     | GND   | GND         | 8        | 0V             | —       |

Merged connections (wire both IDC pins to the same DE-9 pin):
- DE-9 pin 2: IDC pins 14 + 20
- DE-9 pin 3: IDC pins 8 + 18
- DE-9 pin 6: IDC pins 12 + 16

This works because the unused pins on each device are physically unconnected
inside the peripheral, so no signal conflict occurs.

### Why AMX Mouse Works Directly with the Master Compact

The AMX Mouse signals map exactly to the Master Compact Mouse pinout through
the adapter. The trackerball-only IDC pins (8, 12, 14) are not connected inside
the mouse, so they float harmlessly on the merged DE-9 lines.

### Trackerball via SPItFIRE

When a Marconi RB2 trackerball is connected via the adapter, SPItFIRE sees:

| DE-9 Pin | AVR Pin | Trackerball Signal |
|----------|---------|--------------------|
| 1        | PD0     | LB                 |
| 2        | PD1     | YA                 |
| 3        | PD2     | MB                 |
| 4        | PD3     | RB                 |
| 5        | PD4     | XA                 |
| 6        | PD5     | XB                 |
| 9        | PD6     | YB                 |

This requires a dedicated "User Port Trackerball" firmware mode. No additional
mode is needed for the AMX Mouse since it appears identical to a Compact Mouse.

### Firmware Modes Summary

| Mode                  | Device                      | Source      |
|-----------------------|-----------------------------|-------------|
| Compact Mouse         | Master Compact Mouse (DE-9) | Direct      |
| Compact Mouse         | AMX Mouse (via adapter)     | Via adapter |
| Amiga Mouse           | Amiga Mouse (DE-9)          | Direct      |
| Atari Mouse           | Atari ST Mouse (DE-9)       | Direct      |
| Bus Mouse             | Microsoft Bus Mouse (DE-9)  | Direct      |
| Joystick              | Switched joystick (DE-9)    | Direct      |
| User Port Trackerball | Marconi RB2 (via adapter)   | Via adapter |
| Serial                | IC232TTL (DE-9)             | Direct      |