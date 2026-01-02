#include "uart.hpp"
#include <avr/io.h>

namespace uart {

void init(uint32_t baud) {
    // Calculate UBRR value for given baud rate
    // UBRR = F_CPU / (16 * BAUD) - 1
    uint16_t ubrr = F_CPU / (16UL * baud) - 1;

    // Set baud rate
    UBRR0H = static_cast<uint8_t>(ubrr >> 8);
    UBRR0L = static_cast<uint8_t>(ubrr);

    // Enable transmitter and receiver
    UCSR0B = _BV(TXEN0) | _BV(RXEN0);

    // Set frame format: 8 data bits, 1 stop bit, no parity
    UCSR0C = _BV(UCSZ01) | _BV(UCSZ00);
}

void put(uint8_t byte) {
    // Wait for empty transmit buffer
    while (!(UCSR0A & _BV(UDRE0))) {}
    UDR0 = byte;
}

void print(const char* str) {
    while (*str) {
        put(*str++);
    }
}

void println(const char* str) {
    print(str);
    put('\r');
    put('\n');
}

void print_int(int32_t value) {
    if (value < 0) {
        put('-');
        value = -value;
    }

    // Handle zero case
    if (value == 0) {
        put('0');
        return;
    }

    // Build digits in reverse
    char buf[11];
    uint8_t i = 0;
    while (value > 0) {
        buf[i++] = '0' + (value % 10);
        value /= 10;
    }

    // Output in correct order
    while (i > 0) {
        put(buf[--i]);
    }
}

void print_hex(uint32_t value, uint8_t digits) {
    static const char hex[] = "0123456789ABCDEF";
    for (int8_t i = digits - 1; i >= 0; --i) {
        put(hex[(value >> (i * 4)) & 0x0F]);
    }
}

}  // namespace uart
