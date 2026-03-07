| DA-15 pin | Acorn | Delta 3b Single  | Delta 3b Twin | Delta 14b |  SPItfire   |
|           |       |                  |               |           |  A   |  B   |
|-----------|-------|------------------|---------------|-----------|-------------|
| 1         | +5V   |                  |               |           |
| 2         | 0V    |                  |               | COL2      | PC0  | PC1  |
| 3         | 0V    | COL1             | ROW3_RIGHT    | COL1      | PB2  | PB3  |
| 4         | CH3   | Y_RIGHT (Y_LEFT) | Y_RIGHT       | ROW0      | PA6  | PA7  | 
| 5         | AGND  |                  | AGND_RIGHT    | COL0      | PB0  | PB1  |
| 6         | 0V    |                  | ROW3_LEFT     | ROW1      | PC2  | PC3  |
| 7         | CH1   | Y_LEFT (Y_RIGHT) | Y_LEFT        | Y         | PA2  | PA3  |
| 8         | AGND  | AGND             | AGND_LEFT     | AGND      | AGND | AGND |
| 9         | LPSTB |                  |               |           |      |      |
| 10        | PB1   | ROW3             | COL1_RIGHT    | ROW2      | PC4  | PC5  |
| 11        | VREF  |                  | VREF_RIGHT    |           | VREF | VREF |
| 12        | CH2   | X_RIGHT (X_LEFT) | X_RIGHT       |           | PA4  | PA5  |
| 13        | PB0   | ROW4             | COL1_LEFT     | ROW3      | PC6  | PC7  |
| 14        | VREF  | VREF             | VREF_LEFT     | VREF      | VREF | VREF |
| 15        | CH0   | X_LEFT (X_RIGHT) | X_LEFT        | X         | PA0  | PA1  |

DA-15 pin : The pin number on the DA-15 analogue port or joystick connector
Acorn     : The Acorn designation according to Acorn Application Note 021
Delta 3B single: The designation for a Delta 3B Single joystick
Delta 3B twin: The designation for a Delta 3B Twin joystick
Delta 14B: The designation for a Delta 14B joystick
Spitfire A and B: How the pins of the two DA-15 ports on the SPItFIRE module map
  to the digital I/O ports of the ATMega1284p microcontroller

Note that Voltmace repurpose some of the pins such a Acorn's AGND when the
Delta 14B joystick is used with the Delta 14B/1 control box which places
additional logic between the joystick and the analogue user ports
of the BBC Micro. This is rather clever, as these pins have no ill effects
when such a joystick is connected directly to the BBC Micro analogue port,
other than some buttons becoming undetectable.

## Fire Button Wiring

The standard BBC Micro DA-15 analogue port provides only two digital inputs
for fire buttons: PB0 (DA-15 pin 13) and PB1 (DA-15 pin 10).

### Delta 3B Twin

The 3B Twin has two handsets, each with three physical fire buttons.
All three buttons on each handset are wired in parallel:
- Left handset buttons → PB0 (DA-15 pin 13) → PC6 (Port A) / PC7 (Port B)
- Right handset buttons → PB1 (DA-15 pin 10) → PC4 (Port A) / PC5 (Port B)

This gives 2 logical buttons (one per handset), active-low with internal pull-ups.

Note: Internally, the 3B Twin wires buttons with rows grounded and columns as
signals (opposite to the 3B Single). This difference is handled by the joystick
PCB wiring to the DA-15 connector, so the software interface is identical.

### Delta 3B Single

The 3B Single is an unusual design: a single handset with potentiometers wired
to both X/Y pairs, allowing it to serve as either player's joystick in a
turn-based two-player game.

It has three physical buttons in two groups:
- 2 buttons → PB0 (left fire, DA-15 pin 13) → PC6 (Port A) / PC7 (Port B)
- 1 button → PB1 (right fire, DA-15 pin 10) → PC4 (Port A) / PC5 (Port B)

This gives 2 logical buttons, active-low with internal pull-ups.

### Delta 14B

The 14B has a 3×4 keypad matrix (12 buttons) which requires the full matrix
scanning implemented in keypad.cpp. The original Delta 14B/1 interface box
handled this scanning and connected to both the BBC Micro analogue port and
User Port. SPItFIRE replaces the 14B/1 interface with AVR-based scanning.
