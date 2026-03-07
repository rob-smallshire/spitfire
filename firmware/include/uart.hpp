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

/// Send an integer as decimal with right-alignment padding
/// @param value The value to print
/// @param width Minimum width (pads with spaces on left)
void print_int_padded(int32_t value, uint8_t width);

/// Send an integer as hex
void print_hex(uint32_t value, uint8_t digits = 2);

/// Check if a byte is available to read
/// @return true if a byte is waiting in the receive buffer
bool available();

/// Read a single byte (non-blocking)
/// @return The received byte, or 0 if none available
uint8_t get();

}  // namespace uart

#endif  // SPITFIRE_UART_HPP
