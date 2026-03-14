/**
 * SPItFIRE SPI Slave Test
 *
 * Minimal SPI slave that always returns &AA.
 * Used to verify SPI communication with BBC Micro.
 *
 * Build with: make (uses existing CMake setup)
 * Temporarily replace main.cpp or modify CMakeLists.txt to build this instead.
 */

#include <avr/io.h>
#include <avr/interrupt.h>

namespace {
    // SPI pins on ATmega1284p
    // PB4 = SS (input)
    // PB5 = MOSI (input)
    // PB6 = MISO (output)
    // PB7 = SCK (input)

    // LED on PD7 (active-low) for status indication
    constexpr uint8_t LED_PIN = PD7;

    // Transform: XOR received byte with this value
    constexpr uint8_t XOR_PATTERN = 0x55;

    void init_spi_slave() {
        // MISO (PB6) as output, others as input
        DDRB = (DDRB & ~(_BV(PB4) | _BV(PB5) | _BV(PB7))) | _BV(PB6);

        // Enable SPI, slave mode, mode 1 (CPOL=0, CPHA=1), MSB first
        // Mode 1: data changes on rising edge, sampled on falling edge
        // This matches 6522 shift register which samples CB2 on falling CB1
        SPCR = _BV(SPE) | _BV(CPHA);

        // Pre-load initial response (0x00 XOR pattern)
        SPDR = XOR_PATTERN;
    }

    void init_led() {
        DDRD |= _BV(LED_PIN);
        PORTD |= _BV(LED_PIN);  // LED off (active-low)
    }

    void led_off() {
        PORTD |= _BV(LED_PIN);
    }

    void led_toggle() {
        PORTD ^= _BV(LED_PIN);
    }
}

int main() {
    init_led();
    init_spi_slave();

    // Flash LED to indicate startup
    for (uint8_t i = 0; i < 6; i++) {
        led_toggle();
        for (volatile uint32_t d = 0; d < 50000; d++);
    }
    led_off();

    while (true) {
        // Tight poll for SPI transfer complete
        while (!(SPSR & _BV(SPIF)));

        // Read received byte (clears SPIF)
        uint8_t received = SPDR;

        // Load response: received XOR pattern
        SPDR = received ^ XOR_PATTERN;

        // Toggle LED to show activity
        led_toggle();
    }
}
