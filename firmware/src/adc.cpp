#include "adc.hpp"
#include <avr/io.h>

namespace adc {

void init() {
    // Set ADC reference to AVCC with external capacitor on AREF
    // REFS1:0 = 01
    ADMUX = _BV(REFS0);

    // Enable ADC and set prescaler to 128
    // 18.432 MHz / 128 = 144 kHz (within 50-200 kHz recommended range)
    // ADEN = 1, ADPS2:0 = 111
    ADCSRA = _BV(ADEN) | _BV(ADPS2) | _BV(ADPS1) | _BV(ADPS0);

    // Disable digital input buffers on ADC pins to reduce power
    // (optional, can be enabled per-pin as needed)
}

uint16_t read(Channel channel) {
    // Select channel (MUX4:0 in ADMUX, but we only use lower 3 bits for single-ended)
    ADMUX = (ADMUX & 0xE0) | (static_cast<uint8_t>(channel) & 0x07);

    // Start conversion
    ADCSRA |= _BV(ADSC);

    // Wait for conversion to complete
    while (ADCSRA & _BV(ADSC)) {}

    // Read result (must read ADCL first, then ADCH)
    return ADC;
}

uint8_t read8(Channel channel) {
    // Return upper 8 bits of 10-bit result
    return static_cast<uint8_t>(read(channel) >> 2);
}

}  // namespace adc
