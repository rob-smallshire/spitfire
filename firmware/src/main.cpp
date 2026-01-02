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

    uart::println("SPItFIRE Joystick Test");
    uart::println("ADC0 (PA0) -> X, ADC1 (PA1) -> Y");
    uart::println("");

    // Configure PB0 as output for LED
    DDRB |= _BV(PB0);
    PORTB |= _BV(PB0);  // LED off

    while (true) {
        // Read joystick position
        uint16_t x_raw = adc::read(adc::Channel::ADC0);
        uint16_t y_raw = adc::read(adc::Channel::ADC1);

        // Report values
        uart::print("X: ");
        uart::print_int(x_raw);
        uart::print("  Y: ");
        uart::print_int(y_raw);
        uart::println("");

        // Toggle LED to show activity
        PORTB ^= _BV(PB0);

        _delay_ms(SAMPLE_DELAY_MS);
    }
}
