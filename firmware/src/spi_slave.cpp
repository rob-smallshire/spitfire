/**
 * SPItFIRE SPI Slave Test
 *
 * Minimal SPI slave that returns each received byte XORed with &55.
 * Used to verify SPI communication with BBC Micro.
 */

#include <avr/io.h>
#include <avr/interrupt.h>
#include "status_led.hpp"

namespace {
    // SPI pins on ATmega1284p
    // PB4 = SS (input)
    // PB5 = MOSI (input)
    // PB6 = MISO (output)
    // PB7 = SCK (input)

    // Transform: XOR received byte with this value
    constexpr uint8_t XOR_PATTERN = 0x55;

    void init_spi_slave() {
        // MISO (PB6) as output, others as input
        DDRB = (DDRB & ~(_BV(PB4) | _BV(PB5) | _BV(PB7))) | _BV(PB6);

        // Enable SPI, slave mode, mode 0 (CPOL=0, CPHA=0), MSB first
        // Mode 0: data sampled on rising edge
        SPCR = _BV(SPE);

        // Pre-load initial response (0x00 XOR pattern)
        SPDR = XOR_PATTERN;
    }
}

int main() {
    status_led::init();
    init_spi_slave();

    status_led::startup_flash();
    status_led::start_heartbeat();
    sei();

    while (true) {
        // Tight poll for SPI transfer complete
        while (!(SPSR & _BV(SPIF)));

        // Read received byte (clears SPIF)
        uint8_t received = SPDR;

        // Load response: received XOR pattern
        SPDR = received ^ XOR_PATTERN;
    }
}
