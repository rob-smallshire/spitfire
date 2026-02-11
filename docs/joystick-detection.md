# Joystick Type Detection

SPItFIRE supports automatic detection of connected joystick types using a fully passive algorithm that requires no button presses from the user.

## Supported Joystick Types

| Type | Analog Axes | Buttons | Notes |
|------|-------------|---------|-------|
| Delta 14B | 2 (X, Y) | 12 (3x4 keypad) | Full keypad matrix |
| Delta 3B Single | 2 (X, Y) | 3 | Single joystick with fire buttons |
| Delta 3B Twin | 4 (X, Y, X_RIGHT, Y_RIGHT) | 6 | Two joysticks per connector |

## Detection Algorithm

The algorithm exploits the fact that each joystick type repurposes certain DA-15 pins differently.

### Detection Flow

```
         pin 5 pulled LOW?
                |
        +-------+-------+
        |               |
       YES              NO
        |               |
   3B Twin         PA4 ≈ PA0?
   (AGND_RIGHT     (pins 12 & 15 tied?)
    grounded)           |
               +-------+-------+
               |               |
              YES              NO
               |               |
          3B Single      PA0 mid-range?
          (X on both     (valid pot reading?)
           pins)              |
                      +-------+-------+
                      |               |
                     YES              NO
                      |               |
                  Delta 14B      No Joystick
                  (pin 12        (all floating)
                   floating)
```

### Step 1: Check for Delta 3B Twin

**Pin 5 (DA-15) behavior:**
- Delta 14B: COL0 strobe output (floating when not driven)
- Delta 3B Single: Unconnected (floating)
- Delta 3B Twin: AGND_RIGHT (tied to ground)

**Detection:** Configure PB0 (Port A) or PB1 (Port B) as input with internal pull-up. If the pin reads LOW, the joystick is a **Delta 3B Twin**.

### Step 2: Compare Analog Readings (PA0 vs PA4)

**Pin 12 and Pin 15 (DA-15) behavior:**
- Delta 3B Single: Both pins tied together to the X pot wiper
- Delta 14B: Pin 15 is X pot, Pin 12 is unconnected

**Detection:**
- Read ADC channel for PA0 (X axis, pin 15)
- Read ADC channel for PA4 (X_RIGHT, pin 12)
- If values match within threshold (~50 counts) AND PA0 is mid-range → **Delta 3B Single**
- If PA4 is railed (0 or 1023) while PA0 is mid-range → **Delta 14B**

### Step 3: Check for No Joystick

If PA0 is also railed (stuck at 0 or 1023), no valid potentiometer is connected → **No Joystick**.

## Thresholds

| Parameter | Value | Description |
|-----------|-------|-------------|
| ANALOG_MATCH_THRESHOLD | 50 | Max difference for "equal" analog values |
| ANALOG_LOW_RAIL | 50 | Values below this are considered "railed low" |
| ANALOG_HIGH_RAIL | 973 | Values above this are considered "railed high" |

## Timing

| Operation | Duration |
|-----------|----------|
| Pin 5 check | ~20 µs |
| ADC read (PA0) | ~25 µs |
| ADC read (PA4) | ~25 µs |
| **Total** | **~75 µs** |

Detection is fast enough to run periodically (once per second) for hot-plug support without disrupting normal operation.

## Limitations

1. **PA6/PA7 dual use**: These pins are Y_RIGHT analog for Delta 3B Twin, but ROW0 digital for Delta 14B. The firmware must reconfigure these pins based on detected type.

2. **Mid-range assumption**: Detection assumes the joystick pot is not at an extreme position during detection. If the pot is exactly at 0 or 1023, detection may incorrectly report "No Joystick".

3. **Electrical noise**: In noisy environments, the analog threshold may need adjustment.

## Pin Reference

### DA-15 Pin Usage by Joystick Type

| DA-15 Pin | Delta 14B | Delta 3B Single | Delta 3B Twin |
|-----------|-----------|-----------------|---------------|
| 2 | COL2 | - | - |
| 3 | COL1 | COL1 | ROW3_RIGHT |
| 4 | ROW0 | Y (tied to pin 7) | Y_RIGHT |
| 5 | COL0 | - | AGND_RIGHT |
| 6 | ROW1 | - | ROW3_LEFT |
| 7 | Y | Y | Y_LEFT |
| 8 | AGND | AGND | AGND_LEFT |
| 10 | ROW2 | ROW3 | COL1_RIGHT |
| 12 | - | X (tied to pin 15) | X_RIGHT |
| 13 | ROW3 | ROW4 | COL1_LEFT |
| 14 | VREF | VREF | VREF_LEFT |
| 15 | X | X | X_LEFT |
