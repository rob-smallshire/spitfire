/**
 * SPItFIRE - SPI Joystick and Mouse Adapter
 *
 * Dual joystick port test with automatic type detection.
 * Supports Delta 14B, Delta 3B Single, and Delta 3B Twin joysticks.
 */

#include <avr/io.h>
#include <util/delay.h>
#include "uart.hpp"
#include "adc.hpp"
#include "keypad.hpp"
#include "joystick.hpp"

namespace {
    constexpr uint16_t SAMPLE_DELAY_MS = 100;
    constexpr uint16_t DETECT_INTERVAL_MS = 1000;
    constexpr uint32_t BAUD_RATE = 115200;

    // LED on PD7 (active-low)
    constexpr uint8_t LED_PIN = PD7;

    // Cached joystick types
    joystick::Type type_a = joystick::Type::NO_JOYSTICK;
    joystick::Type type_b = joystick::Type::NO_JOYSTICK;

    // Detection counter
    uint16_t detect_counter = 0;

    void update_joysticks() {
        joystick::Type new_a = joystick::update(joystick::Port::PORT_A);
        joystick::Type new_b = joystick::update(joystick::Port::PORT_B);

        if (new_a != type_a) {
            type_a = new_a;
            uart::print("Port A: ");
            uart::println(joystick::type_name(type_a));
        }

        if (new_b != type_b) {
            type_b = new_b;
            uart::print("Port B: ");
            uart::println(joystick::type_name(type_b));
        }
    }

    const char* type_prefix(joystick::Type type) {
        switch (type) {
            case joystick::Type::NO_JOYSTICK:     return "---";
            case joystick::Type::DELTA_14B:       return "14B";
            case joystick::Type::DELTA_3B_SINGLE: return "3BS";
            case joystick::Type::DELTA_3B_TWIN:   return "3BT";
            default:                              return "???";
        }
    }

    void print_port_data(joystick::Port port, joystick::Type type) {
        // Print type prefix
        uart::print(type_prefix(type));
        uart::put(' ');

        if (type == joystick::Type::NO_JOYSTICK) {
            uart::print("----:----");
            return;
        }

        // Read analog axes
        uint16_t x = adc::read_x(port);
        uint16_t y = adc::read_y(port);

        uart::print_int_padded(x, 4);
        uart::put(':');
        uart::print_int_padded(y, 4);

        if (type == joystick::Type::DELTA_14B) {
            // Read keypad
            uint16_t buttons = keypad::scan(port);
            uart::print(" K:");
            uart::print_hex(static_cast<uint8_t>(buttons >> 8), 1);
            uart::print_hex(static_cast<uint8_t>(buttons & 0xFF), 2);
        }

        if (type == joystick::Type::DELTA_3B_TWIN) {
            // Read additional axes for twin joystick
            uint16_t x_r = adc::read_x_right(port);
            uint16_t y_r = adc::read_y_right(port);
            uart::print(" R:");
            uart::print_int_padded(x_r, 4);
            uart::put(':');
            uart::print_int_padded(y_r, 4);
        }
    }
}

int main() {
    // Initialize peripherals
    uart::init(BAUD_RATE);
    adc::init();
    keypad::init();
    joystick::init();

    uart::println("SPItFIRE Dual Joystick Test");
    uart::println("Detecting joysticks...");
    uart::println("");

    // Configure LED on PD7 as output (active-low)
    DDRD |= _BV(LED_PIN);
    PORTD |= _BV(LED_PIN);  // LED off

    // Initial detection
    update_joysticks();

    while (true) {
        // Print both ports on same line: A data | B data
        print_port_data(joystick::Port::PORT_A, type_a);
        uart::print(" | ");
        print_port_data(joystick::Port::PORT_B, type_b);
        uart::println("");

        // Toggle LED to show activity
        PORTD ^= _BV(LED_PIN);

        _delay_ms(SAMPLE_DELAY_MS);

        // Periodic re-detection for hot-plug
        detect_counter += SAMPLE_DELAY_MS;
        if (detect_counter >= DETECT_INTERVAL_MS) {
            detect_counter = 0;
            update_joysticks();
        }
    }
}
