#ifndef SPITFIRE_KEYPAD_HPP
#define SPITFIRE_KEYPAD_HPP

#include <stdint.h>
#include "joystick.hpp"

namespace keypad {

/// Initialize keypad I/O pins for Delta 14B scanning
/// New pin mapping (Even=A, Odd=B):
/// - Columns: PB0/PB1 (COL0), PB2/PB3 (COL1), PC0/PC1 (COL2)
/// - Rows: PA6/PA7 (ROW0), PC2/PC3 (ROW1), PC4/PC5 (ROW2), PC6/PC7 (ROW3)
void init();

/// Scan keypad for a specific port and return 12-bit button state
/// Button numbering: switch_number = row * 3 + column (0-11)
/// Bit N = switch N, where 0 = pressed, 1 = not pressed
/// @param port Which joystick port to scan (PORT_A or PORT_B)
/// @return 12-bit button state in lower 12 bits of uint16_t
uint16_t scan(joystick::Port port);

/// Scan keypad and return raw column data for a specific port
/// @param port Which joystick port to scan
/// @param col0 Output: ROW3:ROW2:ROW1:ROW0 for column 0 (bits 3:2:1:0)
/// @param col1 Output: ROW3:ROW2:ROW1:ROW0 for column 1
/// @param col2 Output: ROW3:ROW2:ROW1:ROW0 for column 2
void scan_raw(joystick::Port port, uint8_t* col0, uint8_t* col1, uint8_t* col2);

}  // namespace keypad

#endif  // SPITFIRE_KEYPAD_HPP
