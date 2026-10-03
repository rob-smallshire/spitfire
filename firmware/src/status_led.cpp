#include "status_led.hpp"
#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/delay.h>

namespace {
    constexpr uint8_t LED_PIN = PD7;

    // Heartbeat timing, in 10 ms ticks
    constexpr uint8_t HEARTBEAT_PERIOD = 100;   // 1 second
    constexpr uint8_t FLASH_LENGTH = 5;         // 50 ms on
    constexpr uint8_t SECOND_FLASH_START = 15;  // 100 ms gap between flashes

    uint8_t heartbeat_tick = 0;

    void led_on() {
        PORTD |= _BV(LED_PIN);
    }

    void led_off() {
        PORTD &= ~_BV(LED_PIN);
    }
}

// Heartbeat: two brief flashes once per second
ISR(TIMER0_COMPA_vect) {
    uint8_t t = heartbeat_tick;

    if (t == 0 || t == SECOND_FLASH_START) {
        led_on();
    } else if (t == FLASH_LENGTH || t == SECOND_FLASH_START + FLASH_LENGTH) {
        led_off();
    }

    if (++t == HEARTBEAT_PERIOD) {
        t = 0;
    }
    heartbeat_tick = t;
}

namespace status_led {

void init() {
    DDRD |= _BV(LED_PIN);
    led_off();
}

void startup_flash() {
    for (uint8_t i = 0; i < 6; i++) {
        PORTD ^= _BV(LED_PIN);
        _delay_ms(40);
    }
    led_off();
}

void start_heartbeat() {
    // Timer0: CTC mode, clk/1024, 18432000 / 1024 / 180 = 100 Hz exactly
    TCCR0A = _BV(WGM01);
    TCCR0B = _BV(CS02) | _BV(CS00);
    OCR0A = 179;
    TIMSK0 = _BV(OCIE0A);
}

}  // namespace status_led
