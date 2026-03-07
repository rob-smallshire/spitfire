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

/// Initialize joystick module (both ports set to NO_JOYSTICK)
void init();

/// Set joystick type for a port
/// @param port Which port to configure
/// @param type Joystick type to set
void set_type(Port port, Type type);

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
