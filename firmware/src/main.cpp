/**
 * SPItFIRE - SPI Joystick and Mouse Adapter
 *
 * Joystick X-axis ADC test.
 * Reads joystick X position via ADC0 (PA0) and reports via UART.
 */

#include <avr/io.h>
#include <util/delay.h>
#include "uart.hpp"
#include "adc.hpp"

namespace {
    constexpr uint16_t SAMPLE_DELAY_MS = 100;
    constexpr uint32_t BAUD_RATE = 115200;
}

int main() {
    // Initialize peripherals
    uart::init(BAUD_RATE);
    adc::init();

    uart::println("SPItFIRE Joystick X-axis Test");
    uart::println("ADC0 (PA0) -> Joystick X");
    uart::println("");

    // Configure PB0 as output for LED
    DDRB |= _BV(PB0);
    PORTB |= _BV(PB0);  // LED off

    while (true) {
        // Read joystick X position
        uint16_t x_raw = adc::read(adc::Channel::ADC0);
        uint8_t x_8bit = static_cast<uint8_t>(x_raw >> 2);

        // Report values
        uart::print("X: ");
        uart::print_int(x_raw);
        uart::print(" (0x");
        uart::print_hex(x_8bit, 2);
        uart::println(")");

        // Toggle LED to show activity
        PORTB ^= _BV(PB0);

        _delay_ms(SAMPLE_DELAY_MS);
    }
}
