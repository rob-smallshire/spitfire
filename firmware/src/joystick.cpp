#include "joystick.hpp"
#include <avr/io.h>

namespace joystick {

namespace {
    // Current type for each port
    Type port_type[2] = {Type::NO_JOYSTICK, Type::NO_JOYSTICK};

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

    // AGND_RIGHT for 3BT mode (right handset potentiometer ground)
    // DA-15 pin 5 → PB0 (Port A) / PB1 (Port B)
    constexpr uint8_t AGND_RIGHT_A = PB0;
    constexpr uint8_t AGND_RIGHT_B = PB1;

    void init_fire_buttons() {
        // Configure fire button pins as inputs with pull-ups
        DDRC &= ~(_BV(FIRE_LEFT_A) | _BV(FIRE_LEFT_B) | _BV(FIRE_RIGHT_A) | _BV(FIRE_RIGHT_B));
        PORTC |= _BV(FIRE_LEFT_A) | _BV(FIRE_LEFT_B) | _BV(FIRE_RIGHT_A) | _BV(FIRE_RIGHT_B);
    }

    // Y_RIGHT analog pins (shared with keypad ROW0)
    // PA6 (Port A) / PA7 (Port B) - need pull-ups disabled for 3BT analog
    constexpr uint8_t Y_RIGHT_A = PA6;
    constexpr uint8_t Y_RIGHT_B = PA7;

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
                // Release to input with pull-up (for keypad ROW1/COL1)
                DDRB &= ~_BV(GND_PIN3_A);
                PORTB &= ~_BV(GND_PIN3_A);  // No pull-up on COL1 (active-low strobe)
                DDRC &= ~_BV(GND_PIN6_A);
                PORTC |= _BV(GND_PIN6_A);   // Pull-up on ROW1
            }
        } else {
            if (enable) {
                PORTB &= ~_BV(GND_PIN3_B);
                DDRB |= _BV(GND_PIN3_B);
                PORTC &= ~_BV(GND_PIN6_B);
                DDRC |= _BV(GND_PIN6_B);
            } else {
                // Release to input with pull-up (for keypad ROW1/COL1)
                DDRB &= ~_BV(GND_PIN3_B);
                PORTB &= ~_BV(GND_PIN3_B);  // No pull-up on COL1 (active-low strobe)
                DDRC &= ~_BV(GND_PIN6_B);
                PORTC |= _BV(GND_PIN6_B);   // Pull-up on ROW1
            }
        }
    }

    // Configure PA6/PA7 for 3BT mode (disable pull-ups for analog input)
    // Also drive PB0/PB1 low to provide AGND_RIGHT for right handset pots
    void configure_3bt_analog(joystick::Port port, bool enable) {
        if (port == joystick::Port::PORT_A) {
            if (enable) {
                // Disable pull-up on PA6 for Y_RIGHT analog input
                PORTA &= ~_BV(Y_RIGHT_A);
                // Drive PB0 low to provide AGND_RIGHT (pin 5)
                PORTB &= ~_BV(AGND_RIGHT_A);
                DDRB |= _BV(AGND_RIGHT_A);
            } else {
                // Re-enable pull-up for keypad ROW0 (14B mode)
                PORTA |= _BV(Y_RIGHT_A);
                // Release PB0 to high-Z for keypad COL0 (no pull-up needed)
                DDRB &= ~_BV(AGND_RIGHT_A);
                PORTB &= ~_BV(AGND_RIGHT_A);
            }
        } else {
            if (enable) {
                // Disable pull-up on PA7 for Y_RIGHT analog input
                PORTA &= ~_BV(Y_RIGHT_B);
                // Drive PB1 low to provide AGND_RIGHT (pin 5)
                PORTB &= ~_BV(AGND_RIGHT_B);
                DDRB |= _BV(AGND_RIGHT_B);
            } else {
                // Re-enable pull-up for keypad ROW0 (14B mode)
                PORTA |= _BV(Y_RIGHT_B);
                // Release PB1 to high-Z for keypad COL0 (no pull-up needed)
                DDRB &= ~_BV(AGND_RIGHT_B);
                PORTB &= ~_BV(AGND_RIGHT_B);
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

}

void init() {
    port_type[0] = Type::NO_JOYSTICK;
    port_type[1] = Type::NO_JOYSTICK;
    init_fire_buttons();
}

void configure(Port port, Type type) {
    set_type(port, type);

    // Configure ground pins for button reading in 3BS/3BT modes
    set_button_grounds(port, type == Type::DELTA_3B_SINGLE ||
                             type == Type::DELTA_3B_TWIN);

    // Configure PA6/PA7 for 3BT analog input (disable pull-ups from keypad::init)
    configure_3bt_analog(port, type == Type::DELTA_3B_TWIN);
}

uint8_t fire_buttons(Port port) {
    return read_fire_buttons(port);
}

void set_type(Port port, Type type) {
    port_type[static_cast<uint8_t>(port)] = type;
}

Type get_type(Port port) {
    return port_type[static_cast<uint8_t>(port)];
}

const char* type_name(Type type) {
    switch (type) {
        case Type::NO_JOYSTICK:     return "No Joystick";
        case Type::DELTA_3B_TWIN:   return "Delta 3B Twin";
        case Type::DELTA_3B_SINGLE: return "Delta 3B Single";
        case Type::DELTA_14B:       return "Delta 14B";
        default:                    return "Unknown";
    }
}

const char* type_code(Type type) {
    switch (type) {
        case Type::NO_JOYSTICK:     return "---";
        case Type::DELTA_3B_TWIN:   return "3BT";
        case Type::DELTA_3B_SINGLE: return "3BS";
        case Type::DELTA_14B:       return "14B";
        default:                    return "???";
    }
}

}  // namespace joystick
