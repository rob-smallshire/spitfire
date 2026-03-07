/**
 * SPItFIRE - SPI Joystick and Mouse Adapter
 *
 * Dual joystick port test with manual type configuration.
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
    constexpr uint32_t BAUD_RATE = 115200;

    // LED on PD7 (active-low)
    constexpr uint8_t LED_PIN = PD7;

    // Fire button pins (directly reading Acorn PB0/PB1)
    // Left fire (PB0): DA-15 pin 13 → PC6 (Port A) / PC7 (Port B)
    // Right fire (PB1): DA-15 pin 10 → PC4 (Port A) / PC5 (Port B)
    constexpr uint8_t FIRE_LEFT_A = PC6;
    constexpr uint8_t FIRE_LEFT_B = PC7;
    constexpr uint8_t FIRE_RIGHT_A = PC4;
    constexpr uint8_t FIRE_RIGHT_B = PC5;

    // Ground pins for 3BS/3BT button circuits
    // DA-15 pin 3 → PB2 (Port A) / PB3 (Port B)
    // DA-15 pin 6 → PC2 (Port A) / PC3 (Port B)
    constexpr uint8_t GND_PIN3_A = PB2;
    constexpr uint8_t GND_PIN3_B = PB3;
    constexpr uint8_t GND_PIN6_A = PC2;
    constexpr uint8_t GND_PIN6_B = PC3;

    void init_fire_buttons() {
        // Configure fire button pins as inputs with pull-ups
        DDRC &= ~(_BV(FIRE_LEFT_A) | _BV(FIRE_LEFT_B) | _BV(FIRE_RIGHT_A) | _BV(FIRE_RIGHT_B));
        PORTC |= _BV(FIRE_LEFT_A) | _BV(FIRE_LEFT_B) | _BV(FIRE_RIGHT_A) | _BV(FIRE_RIGHT_B);
    }

    // Configure ground pins for 3BS/3BT modes on a specific port
    void set_button_grounds(joystick::Port port, bool enable) {
        if (port == joystick::Port::PORT_A) {
            if (enable) {
                // Drive pins 3 and 6 low
                PORTB &= ~_BV(GND_PIN3_A);
                DDRB |= _BV(GND_PIN3_A);
                PORTC &= ~_BV(GND_PIN6_A);
                DDRC |= _BV(GND_PIN6_A);
            } else {
                // Release to high-Z
                DDRB &= ~_BV(GND_PIN3_A);
                DDRC &= ~_BV(GND_PIN6_A);
            }
        } else {
            if (enable) {
                PORTB &= ~_BV(GND_PIN3_B);
                DDRB |= _BV(GND_PIN3_B);
                PORTC &= ~_BV(GND_PIN6_B);
                DDRC |= _BV(GND_PIN6_B);
            } else {
                DDRB &= ~_BV(GND_PIN3_B);
                DDRC &= ~_BV(GND_PIN6_B);
            }
        }
    }

    // Read fire buttons for a port, returns 2 bits: bit0=left, bit1=right (1=pressed)
    // Buttons directly connected to row pins (active-low)
    uint8_t read_fire_buttons(joystick::Port port) {
        uint8_t result = 0;
        if (port == joystick::Port::PORT_A) {
            if (!(PINC & _BV(FIRE_LEFT_A))) result |= 0x01;
            if (!(PINC & _BV(FIRE_RIGHT_A))) result |= 0x02;
        } else {
            if (!(PINC & _BV(FIRE_LEFT_B))) result |= 0x01;
            if (!(PINC & _BV(FIRE_RIGHT_B))) result |= 0x02;
        }
        return result;
    }

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

        joystick::set_type(port, type);

        // Configure ground pins for button reading in 3BS/3BT modes
        bool needs_grounds = (type == joystick::Type::DELTA_3B_SINGLE ||
                              type == joystick::Type::DELTA_3B_TWIN);
        set_button_grounds(port, needs_grounds);

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
            uint8_t buttons = read_fire_buttons(port);
            uart::print(" B:");
            uart::put((buttons & 0x01) ? 'L' : '-');  // Left fire
            uart::put((buttons & 0x02) ? 'R' : '-');  // Right fire
            // Debug: show raw PINC
            uart::print(" PC:");
            uart::print_hex(PINC, 2);
        }
    }
}

int main() {
    // Initialize peripherals
    uart::init(BAUD_RATE);
    adc::init();
    keypad::init();
    joystick::init();
    init_fire_buttons();

    // Configure LED on PD7 as output (active-low)
    DDRD |= _BV(LED_PIN);
    PORTD |= _BV(LED_PIN);  // LED off

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

        // Toggle LED to show activity
        PORTD ^= _BV(LED_PIN);

        _delay_ms(SAMPLE_DELAY_MS);
    }
}
