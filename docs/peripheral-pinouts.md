# Peripheral DE-9 Pinouts

The SPItFIRE has a **male DE-9 Peripheral port** to support connection of the following devices:

* Master Compact Mouse (e.g. Prodest PC128S DigiMouse) - three button
* Master Compact/Atari Switched Joystick
* Amiga Mouse - three button
* Atari ST Mouse - two button (some three-button variants exist)
* Microsoft Bus Mouse - passive, unpowered (e.g. green-eyed mouse)
* TTL Serial port (e.g. StarTech IC232TTL TTL-to-RS232 adapter)

Port D of the AVR is connected to the Peripheral DE-9 and configured under software control to support these different device classes.

## Pinout Table

| Pin | Compact Mouse | Joystick | Amiga Mouse | Atari Mouse | MS Bus Mouse | IC232TTL |
|-----|---------------|----------|-------------|-------------|--------------|----------|
| 1   | XB            | Up       | YA          | XB          | NC           | RXD      |
| 2   | Right Btn     | Down     | XA          | XA          | XA           | TXD      |
| 3   | Middle Btn    | Left     | YB          | YA          | XB           | NC       |
| 4   | YB            | Right    | XB          | YB          | YA           | NC       |
| 5   | XA            | NC       | Middle Btn  | NC          | YB           | 0V       |
| 6   | Left Btn      | Fire     | Left Btn    | Left Btn    | Button 1     | NC*      |
| 7   | +5V           | NC       | +5V         | +5V         | (B3)*        | NC       |
| 8   | 0V            | 0V       | 0V          | 0V          | Button 2     | NC       |
| 9   | YA            | NC       | Right Btn   | Right Btn   | 0V           | NC       |

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

| Device | Connector | Gender Changer Required |
|--------|-----------|------------------------|
| Compact Mouse | Female DE-9 | No - direct connection |
| Amiga Mouse | Female DE-9 | No - direct connection |
| Atari Mouse | Female DE-9 | No - direct connection |
| Atari/Compact Joystick | Female DE-9 | No - direct connection |
| Microsoft Bus Mouse | Male DE-9 | **Yes - F-F adapter** |
| StarTech IC232TTL | Male DE-9 | **Yes - F-F adapter** |

## Device-Specific Notes

### Master Compact Mouse

The Compact mouse pinout matches the BBC Master Compact's Mouse/Joystick port directly. The quadrature signals are on pins 1, 4, 5, 9 with buttons on pins 2, 3, 6.

Reference: [mdfs.net BBC Mouse](https://mdfs.net/Info/Comp/BBC/Mouse/)

### Amiga Mouse

The Amiga uses V-pulse/VQ-pulse (vertical) and H-pulse/HQ-pulse (horizontal) naming:
- V-pulse = YA, VQ-pulse = YB
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
| 1   | YA    | XB    |
| 2   | XA    | XA    |
| 3   | YB    | YA    |
| 4   | XB    | YB    |

Pins 1, 3, and 4 differ. This is why mice with an "Amiga/Atari" switch exist.
