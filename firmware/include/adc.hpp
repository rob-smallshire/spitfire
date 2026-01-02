#ifndef SPITFIRE_ADC_HPP
#define SPITFIRE_ADC_HPP

#include <stdint.h>

namespace adc {

/// ADC channel numbers (PA0-PA7)
enum class Channel : uint8_t {
    ADC0 = 0,  // PA0 - Joystick X
    ADC1 = 1,  // PA1 - Joystick Y
    ADC2 = 2,
    ADC3 = 3,
    ADC4 = 4,
    ADC5 = 5,
    ADC6 = 6,
    ADC7 = 7
};

/// Initialize ADC with AVCC reference and appropriate prescaler
void init();

/// Read 10-bit value from specified channel (0-1023)
uint16_t read(Channel channel);

/// Read 8-bit value from specified channel (0-255)
uint8_t read8(Channel channel);

}  // namespace adc

#endif  // SPITFIRE_ADC_HPP
