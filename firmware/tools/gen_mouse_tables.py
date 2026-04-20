#!/usr/bin/env python3
"""Generate lookup tables for SPItFIRE mouse decoding.

Generates mouse_tables.inc containing:
- Per-pinout remap tables (PIND -> packed nibble for XA, XB, YA, YB)
- Per-pinout button remap tables (PIND -> packed button byte)
- Pulse + direction decode tables (for Acorn-ecosystem mice)
- True quadrature decode tables (for Amiga/Atari/Bus mice)

Packed nibble format: bit0=XA, bit1=XB, bit2=YA, bit3=YB
Button byte format: bit0=Left, bit1=Right, bit2=Middle (1=pressed)

All mouse/button signals are active-low (directly grounded when active).

Pulse + direction: XA/YA are pulse signals (generate edges on movement),
XB/YB are direction signals (steady level indicating direction).
True quadrature: XA/XB and YA/YB are 90-degree offset square waves.
"""

import sys
from dataclasses import dataclass, field


@dataclass
class MousePinout:
    """Pin assignments for a mouse type. Values are Port D bit numbers."""
    name: str
    xa: int  # X axis A (pulse or quadrature A)
    xb: int  # X axis B (direction or quadrature B)
    ya: int  # Y axis A (pulse or quadrature A)
    yb: int  # Y axis B (direction or quadrature B)
    left: int    # Left button (-1 if not available)
    right: int   # Right button (-1 if not available)
    middle: int  # Middle button (-1 if not available)
    quadrature: bool = False  # True = true quadrature, False = pulse + direction


# Pin assignments from docs/peripheral-pinouts.md
# AVR Port D mapping: DE-9 pin 1=PD0, 2=PD1, 3=PD2, 4=PD3, 5=PD4, 6=PD5, 9=PD6
PINOUTS = [
    # Compact Mouse (pulse + direction): Pin1=XB, Pin2=RightBtn, Pin3=MiddleBtn,
    #   Pin4=YB, Pin5=XA, Pin6=LeftBtn, Pin9=YA
    # XA/YA are pulse signals (from CB1/CB2), XB/YB are direction signals
    MousePinout("compact", xa=4, xb=0, ya=6, yb=3, left=5, right=1, middle=2),

    # Amiga Mouse (true quadrature): Pin1=YB, Pin2=XA, Pin3=YA, Pin4=XB,
    #   Pin5=MiddleBtn, Pin6=LeftBtn, Pin9=RightBtn
    MousePinout("amiga", xa=1, xb=3, ya=2, yb=0, left=5, right=6, middle=4,
                quadrature=True),

    # Atari Mouse (true quadrature): Pin1=XB, Pin2=XA, Pin3=YA, Pin4=YB,
    #   Pin5=NC, Pin6=LeftBtn, Pin9=RightBtn
    MousePinout("atari", xa=1, xb=0, ya=2, yb=3, left=5, right=6, middle=-1,
                quadrature=True),

    # Microsoft Bus Mouse (true quadrature): Pin1=NC, Pin2=XA, Pin3=XB, Pin4=YA,
    #   Pin5=YB, Pin6=Button1, Pin8=Button2, Pin9=GND
    MousePinout("busmouse", xa=1, xb=2, ya=3, yb=4, left=5, right=-1, middle=-1,
                quadrature=True),

    # User Port Trackerball via adapter (pulse + direction):
    #   DE-9 Pin1=LB, Pin2=YA, Pin3=MB, Pin4=RB, Pin5=XA, Pin6=XB, Pin9=YB
    MousePinout("trackerball", xa=4, xb=5, ya=1, yb=6, left=0, right=3, middle=2),
]


def generate_remap_table(pinout: MousePinout) -> list[int]:
    """Generate 128-entry remap table: PIND (masked to 7 bits) -> packed nibble.

    Output nibble: bit0=XA, bit1=XB, bit2=YA, bit3=YB
    """
    table = []
    for i in range(128):
        xa = (i >> pinout.xa) & 1
        xb = (i >> pinout.xb) & 1
        ya = (i >> pinout.ya) & 1
        yb = (i >> pinout.yb) & 1
        nibble = xa | (xb << 1) | (ya << 2) | (yb << 3)
        table.append(nibble)
    return table


def generate_button_table(pinout: MousePinout) -> list[int]:
    """Generate 128-entry button remap table: PIND (masked to 7 bits) -> button byte.

    Output: bit0=Left, bit1=Right, bit2=Middle (1=pressed)
    Input pins are active-low (0 = pressed).
    """
    table = []
    for i in range(128):
        btn = 0
        if pinout.left >= 0:
            if not ((i >> pinout.left) & 1):  # Active-low
                btn |= 0x01
        if pinout.right >= 0:
            if not ((i >> pinout.right) & 1):
                btn |= 0x02
        if pinout.middle >= 0:
            if not ((i >> pinout.middle) & 1):
                btn |= 0x04
        table.append(btn)
    return table


def generate_quadrature_table(axis_bit_a: int, axis_bit_b: int) -> list[int]:
    """Generate 256-entry true quadrature decode table for one axis.

    Index: (prev_state << 4) | curr_state
    where state is 4-bit packed nibble (XA, XB, YA, YB).

    Returns: signed int8 values (-1, 0, +1) as unsigned bytes.

    Gray code forward sequence:  00 -> 01 -> 11 -> 10 -> 00  = +1 per step
    Gray code reverse sequence:  00 -> 10 -> 11 -> 01 -> 00  = -1 per step
    """
    # Standard quadrature decode table for 2-bit state (A, B)
    # Index: (prev_AB << 2) | curr_AB (numerical order)
    quad = [
        #        curr: 00  01  10  11
        # prev 00:
         0, +1, -1,  0,
        # prev 01:
        -1,  0,  0, +1,
        # prev 10:
        +1,  0,  0, -1,
        # prev 11:
         0, -1, +1,  0,
    ]

    table = []
    for idx in range(256):
        prev_state = (idx >> 4) & 0x0F
        curr_state = idx & 0x0F

        prev_ab = ((prev_state >> axis_bit_a) & 1) | (((prev_state >> axis_bit_b) & 1) << 1)
        curr_ab = ((curr_state >> axis_bit_a) & 1) | (((curr_state >> axis_bit_b) & 1) << 1)

        delta = quad[(prev_ab << 2) | curr_ab]
        # Store as uint8 (two's complement for -1 = 0xFF)
        table.append(delta & 0xFF)
    return table


def generate_pulse_dir_table(pulse_bit: int, dir_bit: int) -> list[int]:
    """Generate 256-entry pulse + direction decode table for one axis.

    Index: (prev_state << 4) | curr_state
    where state is 4-bit packed nibble.

    pulse_bit: bit position of the pulse signal (XA or YA) in the nibble
    dir_bit: bit position of the direction signal (XB or YB) in the nibble

    Decode rule:
    - If pulse bit changed (edge detected):
        direction bit = 1 -> +1
        direction bit = 0 -> -1
    - If pulse bit didn't change -> 0
    """
    table = []
    for idx in range(256):
        prev_state = (idx >> 4) & 0x0F
        curr_state = idx & 0x0F

        prev_pulse = (prev_state >> pulse_bit) & 1
        curr_pulse = (curr_state >> pulse_bit) & 1
        curr_dir = (curr_state >> dir_bit) & 1

        if prev_pulse != curr_pulse:
            # Pulse edge detected - check direction
            delta = +1 if curr_dir else -1
        else:
            delta = 0

        table.append(delta & 0xFF)
    return table


def format_table(name: str, table: list[int], storage: str, width: int = 16) -> str:
    """Format a table as a C++ PROGMEM array initialiser."""
    lines = []
    type_str = "int8_t" if storage == "int8_t" else "uint8_t"
    lines.append(f"const {type_str} {name}[{len(table)}] PROGMEM = {{")
    for i in range(0, len(table), width):
        row = table[i:i + width]
        vals = ", ".join(f"0x{v:02X}" for v in row)
        lines.append(f"    {vals},")
    lines.append("};")
    return "\n".join(lines)


def main():
    lines = []
    lines.append("// Auto-generated by gen_mouse_tables.py - do not edit")
    lines.append("// Lookup tables for SPItFIRE mouse quadrature decoding")
    lines.append("")
    lines.append('#include <avr/pgmspace.h>')
    lines.append('#include <stdint.h>')
    lines.append("")

    # Generate per-pinout remap and button tables
    for pinout in PINOUTS:
        lines.append(f"// {pinout.name.capitalize()} mouse pinout:")
        lines.append(f"//   XA=PD{pinout.xa}, XB=PD{pinout.xb}, "
                     f"YA=PD{pinout.ya}, YB=PD{pinout.yb}")
        btn_parts = []
        if pinout.left >= 0:
            btn_parts.append(f"Left=PD{pinout.left}")
        if pinout.right >= 0:
            btn_parts.append(f"Right=PD{pinout.right}")
        if pinout.middle >= 0:
            btn_parts.append(f"Middle=PD{pinout.middle}")
        lines.append(f"//   Buttons: {', '.join(btn_parts)}")

        remap = generate_remap_table(pinout)
        lines.append(format_table(f"remap_{pinout.name}", remap, "uint8_t"))
        lines.append("")

        btn_table = generate_button_table(pinout)
        lines.append(format_table(f"btn_remap_{pinout.name}", btn_table, "uint8_t"))
        lines.append("")

    # Generate pulse + direction decode tables
    lines.append("// Pulse + direction decode tables (Acorn-ecosystem mice)")
    lines.append("// XA/YA are pulse signals, XB/YB are direction signals")
    lines.append("// Index: (prev_state << 4) | curr_state")
    lines.append("// Packed nibble: bit0=XA, bit1=XB, bit2=YA, bit3=YB")
    lines.append("// Values: 0x00=no change, 0x01=+1, 0xFF=-1")
    lines.append("")

    # X axis: pulse=bit0 (XA), direction=bit1 (XB)
    pdx = generate_pulse_dir_table(pulse_bit=0, dir_bit=1)
    lines.append(format_table("pulse_dx_table", pdx, "uint8_t"))
    lines.append("")

    # Y axis: pulse=bit2 (YA), direction=bit3 (YB)
    pdy = generate_pulse_dir_table(pulse_bit=2, dir_bit=3)
    lines.append(format_table("pulse_dy_table", pdy, "uint8_t"))
    lines.append("")

    # Generate true quadrature decode tables
    lines.append("// True quadrature decode tables (Amiga/Atari/Bus mice)")
    lines.append("// Both signals are 90-degree offset square waves")
    lines.append("// Index: (prev_state << 4) | curr_state")
    lines.append("// Values: 0x00=no change, 0x01=+1, 0xFF=-1")
    lines.append("")

    # X axis uses bits 0 (XA) and 1 (XB)
    dx = generate_quadrature_table(axis_bit_a=0, axis_bit_b=1)
    lines.append(format_table("quad_dx_table", dx, "uint8_t"))
    lines.append("")

    # Y axis uses bits 2 (YA) and 3 (YB)
    dy = generate_quadrature_table(axis_bit_a=2, axis_bit_b=3)
    lines.append(format_table("quad_dy_table", dy, "uint8_t"))
    lines.append("")

    output = "\n".join(lines)

    if len(sys.argv) > 1:
        with open(sys.argv[1], "w") as f:
            f.write(output)
        print(f"Written to {sys.argv[1]}")
    else:
        print(output)


if __name__ == "__main__":
    main()
