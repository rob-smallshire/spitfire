/**
 * SPItFIRE - SPI Joystick and Mouse Adapter
 *
 * Dual joystick port test with manual type configuration.
 * Supports Delta 14B, Delta 3B Single, and Delta 3B Twin joysticks.
 */

#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/delay.h>
#include "uart.hpp"
#include "adc.hpp"
#include "keypad.hpp"
#include "joystick.hpp"
#include "status_led.hpp"

namespace {
    constexpr uint16_t SAMPLE_DELAY_MS = 100;
    constexpr uint32_t BAUD_RATE = 115200;

    void print_menu() {
        uart::println("");
        uart::println("SPItFIRE Joystick Test");
        uart::println("----------------------");
        uart::print("Port A: ");
        uart::println(joystick::type_name(joystick::get_type(joystick::Port::PORT_A)));
        uart::print("Port B: ");
        uart::println(joystick::type_name(joystick::get_type(joystick::Port::PORT_B)));
        uart::println("");
        uart::println("Configure:");
        uart::println("  0-3: Port A (0=None, 1=3BT, 2=3BS, 3=14B)");
        uart::println("  4-7: Port B (4=None, 5=3BT, 6=3BS, 7=14B)");
        uart::println("");
    }

    void handle_command(uint8_t cmd) {
        joystick::Port port;
        joystick::Type type;

        if (cmd >= '0' && cmd <= '3') {
            port = joystick::Port::PORT_A;
            type = static_cast<joystick::Type>(cmd - '0');
        } else if (cmd >= '4' && cmd <= '7') {
            port = joystick::Port::PORT_B;
            type = static_cast<joystick::Type>(cmd - '4');
        } else {
            return;  // Invalid command, ignore
        }

        joystick::configure(port, type);

        // Print confirmation
        uart::print(port == joystick::Port::PORT_A ? "Port A: " : "Port B: ");
        uart::println(joystick::type_name(type));
    }

    void print_port_data(joystick::Port port) {
        joystick::Type type = joystick::get_type(port);

        // Print type code
        uart::print(joystick::type_code(type));
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

        if (type == joystick::Type::DELTA_3B_TWIN || type == joystick::Type::DELTA_3B_SINGLE) {
            // Read fire buttons (active-low: 0=pressed, 1=released)
            uint8_t buttons = joystick::fire_buttons(port);
            uart::print(" B:");
            uart::put((buttons & 0x01) ? 'L' : '-');  // Left fire
            uart::put((buttons & 0x02) ? 'R' : '-');  // Right fire
            // Debug: show raw PINC and PINB (ground pins)
            uart::print(" PC:");
            uart::print_hex(PINC, 2);
            uart::print(" PB:");
            uart::print_hex(PINB, 2);
        }
    }
}

int main() {
    // Initialize peripherals
    uart::init(BAUD_RATE);
    adc::init();
    keypad::init();
    joystick::init();

    status_led::init();
    status_led::startup_flash();
    status_led::start_heartbeat();
    sei();

    // Print startup menu
    print_menu();

    while (true) {
        // Check for serial commands
        if (uart::available()) {
            uint8_t cmd = uart::get();
            handle_command(cmd);
        }

        // Print both ports on same line: A data | B data
        print_port_data(joystick::Port::PORT_A);
        uart::print(" | ");
        print_port_data(joystick::Port::PORT_B);
        uart::println("");

        _delay_ms(SAMPLE_DELAY_MS);
    }
}
