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

    // Test response byte
    constexpr uint8_t RESPONSE_BYTE = 0xAA;

    void init_spi_slave() {
        // MISO (PB6) as output, others as input
        DDRB = (DDRB & ~(_BV(PB4) | _BV(PB5) | _BV(PB7))) | _BV(PB6);

        // Enable SPI, slave mode, mode 0 (CPOL=0, CPHA=0), MSB first
        SPCR = _BV(SPE);

        // Pre-load response byte
        SPDR = RESPONSE_BYTE;
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

    uint32_t idle_counter = 0;

    while (true) {
        // Wait for SPI transfer complete
        if (SPSR & _BV(SPIF)) {
            // Read received byte (clears SPIF)
            volatile uint8_t received = SPDR;
            (void)received;  // Ignore for now

            // Load next response byte
            SPDR = RESPONSE_BYTE;

            // Toggle LED to show activity
            led_toggle();
            idle_counter = 0;
        }

        // Slow heartbeat blink while idle
        if (++idle_counter >= 200000) {
            led_toggle();
            idle_counter = 0;
        }
    }
}
