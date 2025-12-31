/**
 * SPItFIRE - SPI Joystick and Mouse Adapter
 *
 * LED Blink Test - Verifies hardware and toolchain.
 * Blinks LED on PB0 at 1 Hz (active-low).
 */

#include <avr/io.h>
#include <util/delay.h>

namespace {
    constexpr uint16_t BLINK_DELAY_MS = 500;
}

int main() {
    // Configure PB0 as output
    DDRB |= _BV(PB0);

    // Start with LED off (PB0 high for active-low)
    PORTB |= _BV(PB0);

    while (true) {
        // Toggle LED
        PORTB ^= _BV(PB0);
        _delay_ms(BLINK_DELAY_MS);
    }
}
