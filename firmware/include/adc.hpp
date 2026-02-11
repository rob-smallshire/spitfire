#ifndef SPITFIRE_ADC_HPP
#define SPITFIRE_ADC_HPP

#include <stdint.h>
#include "joystick.hpp"

namespace adc {

/// ADC channel numbers (PA0-PA7)
/// Channel assignments for joystick ports:
///   X axis:      ADC0 (Port A) / ADC1 (Port B)
///   Y axis:      ADC2 (Port A) / ADC3 (Port B)
///   X_RIGHT:     ADC4 (Port A) / ADC5 (Port B) - Delta 3B Twin only
///   Y_RIGHT:     ADC6 (Port A) / ADC7 (Port B) - Delta 3B Twin only
enum class Channel : uint8_t {
    ADC0 = 0,  // PA0 - X axis (Port A)
    ADC1 = 1,  // PA1 - X axis (Port B)
    ADC2 = 2,  // PA2 - Y axis (Port A)
    ADC3 = 3,  // PA3 - Y axis (Port B)
    ADC4 = 4,  // PA4 - X_RIGHT (Port A) / detection pin
    ADC5 = 5,  // PA5 - X_RIGHT (Port B)
    ADC6 = 6,  // PA6 - Y_RIGHT (Port A) or ROW0 for Delta 14B
    ADC7 = 7   // PA7 - Y_RIGHT (Port B) or ROW0 for Delta 14B
};

/// Initialize ADC with AVCC reference and appropriate prescaler
void init();

/// Read 10-bit value from specified channel (0-1023)
uint16_t read(Channel channel);

/// Read 8-bit value from specified channel (0-255)
uint8_t read8(Channel channel);

/// Read X axis for a given joystick port
inline uint16_t read_x(joystick::Port port) {
    return read(port == joystick::Port::PORT_A ? Channel::ADC0 : Channel::ADC1);
}

/// Read Y axis for a given joystick port
inline uint16_t read_y(joystick::Port port) {
    return read(port == joystick::Port::PORT_A ? Channel::ADC2 : Channel::ADC3);
}

/// Read X_RIGHT axis for a given joystick port (Delta 3B Twin only)
inline uint16_t read_x_right(joystick::Port port) {
    return read(port == joystick::Port::PORT_A ? Channel::ADC4 : Channel::ADC5);
}

/// Read Y_RIGHT axis for a given joystick port (Delta 3B Twin only)
inline uint16_t read_y_right(joystick::Port port) {
    return read(port == joystick::Port::PORT_A ? Channel::ADC6 : Channel::ADC7);
}

}  // namespace adc

#endif  // SPITFIRE_ADC_HPP
