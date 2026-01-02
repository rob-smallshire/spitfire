#ifndef SPITFIRE_KEYPAD_HPP
#define SPITFIRE_KEYPAD_HPP

#include <stdint.h>

namespace keypad {

/// Initialize keypad I/O pins
/// Columns PB0-PB2: outputs, active-high idle
/// Rows PC0-PC7: inputs with pull-ups (PC0-3 joy1, PC4-7 joy2)
void init();

/// Scan both keypads and return 24-bit state
/// Each byte represents one column, bits [3:0] = joy1 rows, bits [7:4] = joy2 rows
/// Button pressed = bit is 0
void scan(uint8_t* col0, uint8_t* col1, uint8_t* col2);

/// Scan and return state for joystick 1 only (12 bits packed into uint16_t)
/// Bits [3:0] = col0, [7:4] = col1, [11:8] = col2
uint16_t scan_joy1();

/// Scan and return state for joystick 2 only (12 bits packed into uint16_t)
uint16_t scan_joy2();

}  // namespace keypad

#endif  // SPITFIRE_KEYPAD_HPP
