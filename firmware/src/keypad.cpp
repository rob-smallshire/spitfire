#include "keypad.hpp"
#include <avr/io.h>
#include <util/delay.h>

namespace keypad {

namespace {
    // Column strobe pins
    // COL0: PB0 (A) / PB1 (B)
    // COL1: PB2 (A) / PB3 (B)
    // COL2: PC0 (A) / PC1 (B)
    constexpr uint8_t COL0_A = PB0;
    constexpr uint8_t COL0_B = PB1;
    constexpr uint8_t COL1_A = PB2;
    constexpr uint8_t COL1_B = PB3;
    constexpr uint8_t COL2_A = PC0;
    constexpr uint8_t COL2_B = PC1;

    // Row input pins
    // ROW0: PA6 (A) / PA7 (B)
    // ROW1: PC2 (A) / PC3 (B)
    // ROW2: PC4 (A) / PC5 (B)
    // ROW3: PC6 (A) / PC7 (B)
    constexpr uint8_t ROW0_A = PA6;
    constexpr uint8_t ROW0_B = PA7;
    constexpr uint8_t ROW1_A = PC2;
    constexpr uint8_t ROW1_B = PC3;
    constexpr uint8_t ROW2_A = PC4;
    constexpr uint8_t ROW2_B = PC5;
    constexpr uint8_t ROW3_A = PC6;
    constexpr uint8_t ROW3_B = PC7;

    // Masks for PORTB columns (COL0 and COL1)
    constexpr uint8_t PORTB_COL_MASK = _BV(COL0_A) | _BV(COL0_B) | _BV(COL1_A) | _BV(COL1_B);

    // Masks for PORTC columns (COL2)
    constexpr uint8_t PORTC_COL_MASK = _BV(COL2_A) | _BV(COL2_B);

    // Masks for PORTA rows (ROW0)
    constexpr uint8_t PORTA_ROW_MASK = _BV(ROW0_A) | _BV(ROW0_B);

    // Masks for PORTC rows (ROW1-ROW3)
    constexpr uint8_t PORTC_ROW_MASK = _BV(ROW1_A) | _BV(ROW1_B) | _BV(ROW2_A) | _BV(ROW2_B) |
                                       _BV(ROW3_A) | _BV(ROW3_B);

    // Settling time for column strobe and pull-up recovery (microseconds)
    constexpr uint8_t SETTLE_US = 20;

    // Read 4 row bits for a given port, returns ROW3:ROW2:ROW1:ROW0 in bits 3:2:1:0
    inline uint8_t read_rows(joystick::Port port) {
        uint8_t result = 0;

        if (port == joystick::Port::PORT_A) {
            // ROW0 from PORTA bit 6
            if (!(PINA & _BV(ROW0_A))) result |= 0x01;
            // ROW1 from PORTC bit 2
            if (!(PINC & _BV(ROW1_A))) result |= 0x02;
            // ROW2 from PORTC bit 4
            if (!(PINC & _BV(ROW2_A))) result |= 0x04;
            // ROW3 from PORTC bit 6
            if (!(PINC & _BV(ROW3_A))) result |= 0x08;
        } else {
            // ROW0 from PORTA bit 7
            if (!(PINA & _BV(ROW0_B))) result |= 0x01;
            // ROW1 from PORTC bit 3
            if (!(PINC & _BV(ROW1_B))) result |= 0x02;
            // ROW2 from PORTC bit 5
            if (!(PINC & _BV(ROW2_B))) result |= 0x04;
            // ROW3 from PORTC bit 7
            if (!(PINC & _BV(ROW3_B))) result |= 0x08;
        }

        return result;
    }

    // Strobe a column low for the given port
    // col: 0, 1, or 2
    inline void strobe_column(uint8_t col, joystick::Port port) {
        if (port == joystick::Port::PORT_A) {
            switch (col) {
                case 0:
                    PORTB &= ~_BV(COL0_A);
                    DDRB |= _BV(COL0_A);
                    break;
                case 1:
                    PORTB &= ~_BV(COL1_A);
                    DDRB |= _BV(COL1_A);
                    break;
                case 2:
                    PORTC &= ~_BV(COL2_A);
                    DDRC |= _BV(COL2_A);
                    break;
            }
        } else {
            switch (col) {
                case 0:
                    PORTB &= ~_BV(COL0_B);
                    DDRB |= _BV(COL0_B);
                    break;
                case 1:
                    PORTB &= ~_BV(COL1_B);
                    DDRB |= _BV(COL1_B);
                    break;
                case 2:
                    PORTC &= ~_BV(COL2_B);
                    DDRC |= _BV(COL2_B);
                    break;
            }
        }
    }

    // Release a column back to high-Z for the given port
    inline void release_column(uint8_t col, joystick::Port port) {
        if (port == joystick::Port::PORT_A) {
            switch (col) {
                case 0: DDRB &= ~_BV(COL0_A); break;
                case 1: DDRB &= ~_BV(COL1_A); break;
                case 2: DDRC &= ~_BV(COL2_A); break;
            }
        } else {
            switch (col) {
                case 0: DDRB &= ~_BV(COL0_B); break;
                case 1: DDRB &= ~_BV(COL1_B); break;
                case 2: DDRC &= ~_BV(COL2_B); break;
            }
        }
    }
}

void init() {
    // Configure column pins as inputs (high-Z) initially
    DDRB &= ~PORTB_COL_MASK;
    PORTB &= ~PORTB_COL_MASK;
    DDRC &= ~PORTC_COL_MASK;
    PORTC &= ~PORTC_COL_MASK;

    // Configure row pins as inputs with pull-ups
    // ROW0 on PORTA
    DDRA &= ~PORTA_ROW_MASK;
    PORTA |= PORTA_ROW_MASK;

    // ROW1-ROW3 on PORTC
    DDRC &= ~PORTC_ROW_MASK;
    PORTC |= PORTC_ROW_MASK;
}

void scan_raw(joystick::Port port, uint8_t* col0, uint8_t* col1, uint8_t* col2) {
    // Scan column 0
    strobe_column(0, port);
    _delay_us(SETTLE_US);
    *col0 = read_rows(port);
    release_column(0, port);
    _delay_us(SETTLE_US);

    // Scan column 1
    strobe_column(1, port);
    _delay_us(SETTLE_US);
    *col1 = read_rows(port);
    release_column(1, port);
    _delay_us(SETTLE_US);

    // Scan column 2
    strobe_column(2, port);
    _delay_us(SETTLE_US);
    *col2 = read_rows(port);
    release_column(2, port);
}

uint16_t scan(joystick::Port port) {
    uint8_t col0, col1, col2;
    scan_raw(port, &col0, &col1, &col2);

    // Pack into 12-bit value: button N at bit N
    // Button numbering: switch = row * 3 + col
    // col0 has buttons 0, 3, 6, 9 (column 0)
    // col1 has buttons 1, 4, 7, 10 (column 1)
    // col2 has buttons 2, 5, 8, 11 (column 2)

    uint16_t result = 0;

    // Column 0: bits 0, 3, 6, 9
    if (col0 & 0x01) result |= (1 << 0);   // ROW0, COL0 -> button 0
    if (col0 & 0x02) result |= (1 << 3);   // ROW1, COL0 -> button 3
    if (col0 & 0x04) result |= (1 << 6);   // ROW2, COL0 -> button 6
    if (col0 & 0x08) result |= (1 << 9);   // ROW3, COL0 -> button 9

    // Column 1: bits 1, 4, 7, 10
    if (col1 & 0x01) result |= (1 << 1);   // ROW0, COL1 -> button 1
    if (col1 & 0x02) result |= (1 << 4);   // ROW1, COL1 -> button 4
    if (col1 & 0x04) result |= (1 << 7);   // ROW2, COL1 -> button 7
    if (col1 & 0x08) result |= (1 << 10);  // ROW3, COL1 -> button 10

    // Column 2: bits 2, 5, 8, 11
    if (col2 & 0x01) result |= (1 << 2);   // ROW0, COL2 -> button 2
    if (col2 & 0x02) result |= (1 << 5);   // ROW1, COL2 -> button 5
    if (col2 & 0x04) result |= (1 << 8);   // ROW2, COL2 -> button 8
    if (col2 & 0x08) result |= (1 << 11);  // ROW3, COL2 -> button 11

    // Invert: scan returns 1 for pressed, but we want 0 for pressed
    // to match the convention of active-low
    return ~result & 0x0FFF;
}

}  // namespace keypad
