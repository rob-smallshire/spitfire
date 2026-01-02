#include "keypad.hpp"
#include <avr/io.h>
#include <util/delay.h>

namespace keypad {

namespace {
    // Column strobe pins (directly on PORTB)
    constexpr uint8_t COL0_PIN = PB0;
    constexpr uint8_t COL1_PIN = PB1;
    constexpr uint8_t COL2_PIN = PB2;
    constexpr uint8_t COL_MASK = _BV(COL0_PIN) | _BV(COL1_PIN) | _BV(COL2_PIN);

    // Row input pins (directly on PORTC)
    // Joy1: PC0-PC3, Joy2: PC4-PC7
    constexpr uint8_t ROW_MASK = 0xFF;  // All 8 bits of PORTC

    // Settling time for column strobe and pull-up recovery (microseconds)
    constexpr uint8_t SETTLE_US = 20;
}

void init() {
    // Configure column pins as inputs (high-Z) initially
    // They will be set to output only when strobing
    DDRB &= ~COL_MASK;
    PORTB &= ~COL_MASK;  // No pull-ups

    // Configure row pins as inputs with pull-ups
    DDRC &= ~ROW_MASK;
    PORTC |= ROW_MASK;
}

void scan(uint8_t* col0, uint8_t* col1, uint8_t* col2) {
    // Scan column 0: set to output-low, read, then back to high-Z
    PORTB &= ~_BV(COL0_PIN);  // Ensure output will be low
    DDRB |= _BV(COL0_PIN);    // Set as output (drives low)
    _delay_us(SETTLE_US);
    *col0 = PINC;
    DDRB &= ~_BV(COL0_PIN);   // Back to high-Z
    _delay_us(SETTLE_US);     // Let pull-ups recover

    // Scan column 1
    PORTB &= ~_BV(COL1_PIN);
    DDRB |= _BV(COL1_PIN);
    _delay_us(SETTLE_US);
    *col1 = PINC;
    DDRB &= ~_BV(COL1_PIN);
    _delay_us(SETTLE_US);

    // Scan column 2
    PORTB &= ~_BV(COL2_PIN);
    DDRB |= _BV(COL2_PIN);
    _delay_us(SETTLE_US);
    *col2 = PINC;
    DDRB &= ~_BV(COL2_PIN);
}

uint16_t scan_joy1() {
    uint8_t col0, col1, col2;
    scan(&col0, &col1, &col2);

    // Extract lower 4 bits from each column
    return static_cast<uint16_t>(col0 & 0x0F)
         | (static_cast<uint16_t>(col1 & 0x0F) << 4)
         | (static_cast<uint16_t>(col2 & 0x0F) << 8);
}

uint16_t scan_joy2() {
    uint8_t col0, col1, col2;
    scan(&col0, &col1, &col2);

    // Extract upper 4 bits from each column, shift down
    return static_cast<uint16_t>((col0 >> 4) & 0x0F)
         | (static_cast<uint16_t>((col1 >> 4) & 0x0F) << 4)
         | (static_cast<uint16_t>((col2 >> 4) & 0x0F) << 8);
}

}  // namespace keypad
