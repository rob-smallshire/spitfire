#ifndef SPITFIRE_JOYSTICK_HPP
#define SPITFIRE_JOYSTICK_HPP

#include <stdint.h>

namespace joystick {

/// Joystick type detected on a port
enum class Type : uint8_t {
    NO_JOYSTICK,    ///< No joystick connected (pins floating)
    DELTA_14B,      ///< Delta 14B: 2-axis analog + 12-button keypad
    DELTA_3B_SINGLE,///< Delta 3B Single: 2-axis analog + 3 buttons
    DELTA_3B_TWIN   ///< Delta 3B Twin: 4-axis analog + 6 buttons (2 joysticks)
};

/// Physical joystick port (DA-15 connector)
enum class Port : uint8_t {
    PORT_A = 0,  ///< Even-numbered AVR pins
    PORT_B = 1   ///< Odd-numbered AVR pins
};

/// Initialize joystick detection pins and state machine
void init();

/// Update detection state machine for a port
/// Call this periodically (e.g., once per second).
/// Uses variance-based stability detection:
/// - Floating pins are noisy (high variance) → NO_JOYSTICK
/// - Stable readings allow type discrimination
/// State machine ensures transitions go through NO_JOYSTICK
/// and require multiple consistent readings (hysteresis).
/// @param port Which port to update
/// @return Current confirmed joystick type (may lag raw detection)
Type update(Port port);

/// Get current confirmed type without running detection
/// @param port Which port to query
/// @return Last confirmed joystick type
Type get_type(Port port);

/// Get string name for joystick type (for debug output)
const char* type_name(Type type);

/// Threshold for analog comparison (PA4 vs PA0)
/// Values within this range are considered "equal" (pins tied together)
constexpr uint16_t ANALOG_MATCH_THRESHOLD = 50;

/// Variance threshold for stability detection
/// Floating pins have variance above this (typically 100-500 counts range)
/// Connected pots have variance below this (typically <20 counts range)
constexpr uint16_t VARIANCE_THRESHOLD = 30;

/// Number of samples for variance calculation
constexpr uint8_t VARIANCE_SAMPLES = 8;

/// Number of consistent detections required before confirming type change
constexpr uint8_t CONFIRM_THRESHOLD = 3;

}  // namespace joystick

#endif  // SPITFIRE_JOYSTICK_HPP
