/**
 * SPItFIRE Mouse Firmware
 *
 * Reads mouse signals on Port D via pin-change interrupts (PCINT3),
 * accumulates movement deltas, and reports them over SPI.
 *
 * Port D pins are PCINT24-PCINT31, using PCMSK3/PCIE3/PCINT3_vect.
 *
 * SPI commands (from protocol.md):
 *   0x30 MOUSE_X   - returns clamped dX (int8), drains accumulator
 *   0x31 MOUSE_Y   - returns clamped dY (int8), drains accumulator
 *   0x32 MOUSE_BTN - returns button state byte
 *   0xF1 CMD_MODE_AMX   - switch to AMX/Compact pinout
 *   0xF2 CMD_MODE_AMIGA - switch to Amiga pinout
 *   0xF3 CMD_MODE_ATARI - switch to Atari pinout
 */

#include <avr/io.h>
#include <avr/interrupt.h>
#include <avr/pgmspace.h>
#include <string.h>

// Generated lookup tables (PROGMEM)
#include "mouse_tables.inc"

namespace {

    // --- SPI command codes ---
    constexpr uint8_t CMD_MOUSE_X   = 0x30;
    constexpr uint8_t CMD_MOUSE_Y   = 0x31;
    constexpr uint8_t CMD_MOUSE_BTN = 0x32;
    constexpr uint8_t CMD_MODE_AMX   = 0xF1;
    constexpr uint8_t CMD_MODE_AMIGA = 0xF2;
    constexpr uint8_t CMD_MODE_ATARI = 0xF3;

    // --- LED on PD7 (active-low) ---
    constexpr uint8_t LED_PIN = PD7;

    // --- SRAM working copies of active lookup tables ---
    uint8_t remap[128];
    uint8_t btn_remap[128];

    // --- Pointers to active decode tables (in PROGMEM) ---
    const uint8_t* dx_table_ptr = quad_dx_table;
    const uint8_t* dy_table_ptr = quad_dy_table;

    // --- Pin-change interrupt mask (set per mode) ---
    uint8_t pcint_mask = 0;

    // --- Accumulators (updated by ISR) ---
    volatile int16_t dx_accum = 0;
    volatile int16_t dy_accum = 0;

    // --- ISR state ---
    uint8_t prev_state = 0;

    // --- Initialisation ---

    void init_spi_slave() {
        DDRB = (DDRB & ~(_BV(PB4) | _BV(PB5) | _BV(PB7))) | _BV(PB6);
        SPCR = _BV(SPE);
        SPDR = 0x00;
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

    void init_mouse_pins() {
        DDRD = (DDRD & ~0x7F) | _BV(LED_PIN);
        PORTD |= 0x7F;  // Pull-ups on inputs
    }

    void init_pcint() {
        PCMSK3 = pcint_mask;     // Port D uses PCMSK3 (PCINT24-31)
        PCICR |= _BV(PCIE3);    // Enable PCINT3 vector
    }

    void load_quadrature_mode(const uint8_t* pgm_remap, const uint8_t* pgm_btn,
                              uint8_t xa_pin, uint8_t xb_pin,
                              uint8_t ya_pin, uint8_t yb_pin) {
        cli();
        memcpy_P(remap, pgm_remap, 128);
        memcpy_P(btn_remap, pgm_btn, 128);
        dx_table_ptr = quad_dx_table;
        dy_table_ptr = quad_dy_table;
        // Interrupt on all four quadrature pins
        pcint_mask = _BV(xa_pin) | _BV(xb_pin) | _BV(ya_pin) | _BV(yb_pin);
        PCMSK3 = pcint_mask;
        // Initialise state
        prev_state = pgm_read_byte(&pgm_remap[PIND & 0x7F]);
        dx_accum = 0;
        dy_accum = 0;
        sei();
    }

    int8_t clamp_and_drain(volatile int16_t& accum) {
        cli();
        int16_t val = accum;
        int8_t out;
        if (val > 127) {
            out = 127;
        } else if (val < -127) {
            out = -127;
        } else {
            out = static_cast<int8_t>(val);
        }
        accum -= out;
        sei();
        return out;
    }

}  // anonymous namespace

// --- Pin Change ISR for Port D (PCINT3, not PCINT2!) ---
// Port D pins are PCINT24-31, handled by PCINT3_vect.
ISR(PCINT3_vect) {
    uint8_t curr = remap[PIND & 0x7F];
    uint8_t idx = (prev_state << 4) | curr;

    dx_accum += static_cast<int8_t>(pgm_read_byte(&dx_table_ptr[idx]));
    dy_accum += static_cast<int8_t>(pgm_read_byte(&dy_table_ptr[idx]));
    prev_state = curr;
}

int main() {
    init_led();
    init_mouse_pins();
    init_spi_slave();

    // Default to Compact/AMX (true quadrature, XA=PD4, XB=PD0, YA=PD6, YB=PD3)
    load_quadrature_mode(remap_compact, btn_remap_compact, PD4, PD0, PD6, PD3);

    init_pcint();
    sei();

    // Startup LED flash
    for (uint8_t i = 0; i < 6; i++) {
        led_toggle();
        for (volatile uint32_t d = 0; d < 50000; d++);
    }
    led_off();

    // SPI command loop
    while (true) {
        while (!(SPSR & _BV(SPIF)));

        uint8_t cmd = SPDR;
        uint8_t response;

        switch (cmd) {
            case CMD_MOUSE_X:
                response = static_cast<uint8_t>(clamp_and_drain(dx_accum));
                led_toggle();
                break;

            case CMD_MOUSE_Y:
                response = static_cast<uint8_t>(clamp_and_drain(dy_accum));
                break;

            case CMD_MOUSE_BTN:
                response = btn_remap[PIND & 0x7F];
                break;

            case CMD_MODE_AMX:
                load_quadrature_mode(remap_compact, btn_remap_compact,
                                     PD4, PD0, PD6, PD3);
                response = 0x01;
                break;

            case CMD_MODE_AMIGA:
                load_quadrature_mode(remap_amiga, btn_remap_amiga,
                                     PD1, PD3, PD0, PD2);
                response = 0x02;
                break;

            case CMD_MODE_ATARI:
                load_quadrature_mode(remap_atari, btn_remap_atari,
                                     PD1, PD0, PD2, PD3);
                response = 0x03;
                break;

            default:
                response = 0xFF;
                break;
        }

        SPDR = response;
    }
}
