/**
 * SPItFIRE - SPI Joystick and Mouse Adapter
 *
 * Joystick and keypad test.
 * Reads joystick X/Y via ADC and scans 3x4 keypad matrix.
 */

#include <avr/io.h>
#include <util/delay.h>
#include "uart.hpp"
#include "adc.hpp"
#include "keypad.hpp"

namespace {
    constexpr uint16_t SAMPLE_DELAY_MS = 100;
    constexpr uint32_t BAUD_RATE = 115200;
}

int main() {
    // Initialize peripherals
    uart::init(BAUD_RATE);
    adc::init();
    keypad::init();

    uart::println("SPItFIRE Joystick + Keypad Test");
    uart::println("X/Y: ADC0/1, Keys: PB0-2 cols, PC0-7 rows");
    uart::println("");

    // Configure PB3 as output for LED
    DDRB |= _BV(PB3);
    PORTB |= _BV(PB3);  // LED off

    while (true) {
        // Read joystick position
        uint16_t x_raw = adc::read(adc::Channel::ADC0);
        uint16_t y_raw = adc::read(adc::Channel::ADC1);

        // Scan keypad
        uint8_t col0, col1, col2;
        keypad::scan(&col0, &col1, &col2);

        // Report values
        uart::print("X:");
        uart::print_int(x_raw);
        uart::print(" Y:");
        uart::print_int(y_raw);
        uart::print(" K:");
        uart::print_hex(col0, 2);
        uart::print_hex(col1, 2);
        uart::print_hex(col2, 2);
        uart::println("");

        // Toggle LED to show activity
        PORTB ^= _BV(PB3);

        _delay_ms(SAMPLE_DELAY_MS);
    }
}
