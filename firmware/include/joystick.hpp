#ifndef SPITFIRE_JOYSTICK_HPP
#define SPITFIRE_JOYSTICK_HPP

#include <stdint.h>

namespace joystick {

/// Joystick type for a port
enum class Type : uint8_t {
    NO_JOYSTICK,    ///< No joystick connected
    DELTA_3B_TWIN,  ///< Delta 3B Twin: 4-axis analog (2 joysticks per connector)
    DELTA_3B_SINGLE,///< Delta 3B Single: 2-axis analog + 3 buttons
    DELTA_14B       ///< Delta 14B: 2-axis analog + 12-button keypad
};

/// Physical joystick port (DA-15 connector)
enum class Port : uint8_t {
    PORT_A = 0,  ///< Even-numbered AVR pins
    PORT_B = 1   ///< Odd-numbered AVR pins
};

/// Initialize joystick module (both ports set to NO_JOYSTICK, fire inputs
/// pulled up)
void init();

/// Set joystick type for a port
/// @param port Which port to configure
/// @param type Joystick type to set
void set_type(Port port, Type type);

/// Set the type for a port and configure its DA-15 pins to match:
/// 3BS and 3BT drive pins 3 and 6 low, 3BT also drives pin 5 (AGND) low
/// and takes the pull-up off pin 4. Call keypad::init() first.
void configure(Port port, Type type);

/// Read a port's fire inputs: bit 0 = PB0 (pin 13), bit 1 = PB1 (pin 10),
/// 1 = pressed
uint8_t fire_buttons(Port port);

/// Get current type for a port
/// @param port Which port to query
/// @return Current joystick type
Type get_type(Port port);

/// Get string name for joystick type (for debug output)
const char* type_name(Type type);

/// Get short code for joystick type (3 chars for display)
const char* type_code(Type type);

}  // namespace joystick

#endif  // SPITFIRE_JOYSTICK_HPP
