#ifndef SPITFIRE_UART_HPP
#define SPITFIRE_UART_HPP

#include <stdint.h>

namespace uart {

/// Initialize UART0 with the given baud rate
void init(uint32_t baud);

/// Send a single byte
void put(uint8_t byte);

/// Send a null-terminated string
void print(const char* str);

/// Send a string followed by newline
void println(const char* str);

/// Send an integer as decimal
void print_int(int32_t value);

/// Send an integer as hex
void print_hex(uint32_t value, uint8_t digits = 2);

}  // namespace uart

#endif  // SPITFIRE_UART_HPP
