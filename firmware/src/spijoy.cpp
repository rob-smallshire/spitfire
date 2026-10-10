/**
 * SPItFIRE Analogue Joystick Firmware
 *
 * Reports both DA-15 joystick ports over SPI. Each port is configured
 * for a joystick type (None, Delta 3B Twin, Delta 3B Single or Delta
 * 14B) exactly as in the serial test firmware. An Acorn-standard
 * joystick such as the Bitstik uses 3B Twin, which drives pins 3, 5 and
 * 6 (0 V and AGND on the Acorn port) low and reads all four channels.
 *
 * The ADC interrupt converts all eight inputs continuously, and the main
 * loop scans the keypad of any 14B port. The SPI interrupt answers each
 * command from these cached values, so the response is ready well
 * before the host clocks it out.
 *
 * Channels are numbered as on the Acorn port: CH0-CH3 are DA-15 pins
 * 15, 7, 12 and 4. Port A channel n is ADC 2n, Port B channel n is
 * ADC 2n+1.
 *
 * SPI commands (command byte, then a dummy byte that clocks out the
 * response):
 *   0x40-0x43 JOY_A0-3  - low byte of Port A CH0-3 (10 bits); latches
 *                         the high byte for JOY_HI
 *   0x44-0x47 JOY_B0-3  - the same for Port B
 *   0x48      JOY_HI    - latched high byte
 *   0x49      JOY_BTN   - fire inputs, active high:
 *                         b0 Port A PB0 (pin 13), b1 Port A PB1 (pin 10),
 *                         b2 Port B PB0, b3 Port B PB1
 *   0x4A      JOY_KEY_A - Port A 14B keypad buttons 0-7, active high;
 *                         latches buttons 8-11 for JOY_HI
 *   0x4B      JOY_KEY_B - the same for Port B
 *   0xE0-0xE3 JOY_TYPE_A - set Port A to None, 3BT, 3BS or 14B
 *   0xE4-0xE7 JOY_TYPE_B - the same for Port B
 *                         (both reply with the command byte)
 */

#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/atomic.h>
#include "joystick.hpp"
#include "keypad.hpp"
#include "status_led.hpp"

namespace {

    // --- SPI command codes ---
    constexpr uint8_t CMD_JOY_A0     = 0x40;
    constexpr uint8_t CMD_JOY_B3     = 0x47;
    constexpr uint8_t CMD_JOY_HI     = 0x48;
    constexpr uint8_t CMD_JOY_BTN    = 0x49;
    constexpr uint8_t CMD_JOY_KEY_A  = 0x4A;
    constexpr uint8_t CMD_JOY_KEY_B  = 0x4B;
    constexpr uint8_t CMD_JOY_TYPE_A = 0xE0;
    constexpr uint8_t CMD_JOY_TYPE_B = 0xE7;

    constexpr uint8_t NO_REQUEST = 0xFF;

    // --- Written by interrupts ---
    volatile uint16_t samples[8];          // ADC interrupt
    volatile uint8_t type_request = NO_REQUEST;  // SPI interrupt

    // --- Written by the main loop, read by the SPI interrupt ---
    volatile uint16_t keys[2];             // Active high, bit N = button N

    uint8_t adc_channel = 0;
    uint8_t latched_hi = 0;

    void init_spi_slave() {
        DDRB = (DDRB & ~(_BV(PB4) | _BV(PB5) | _BV(PB7))) | _BV(PB6);
        SPCR = _BV(SPIE) | _BV(SPE);
        SPDR = 0x00;
    }

    void start_adc() {
        // AVCC reference, channel 0; clk/128 = 144 kHz, interrupt on
        // completion. Each conversion takes about 90 us, so all eight
        // inputs are refreshed every 0.7 ms.
        DIDR0 = 0x3F;   // PA6/PA7 keep their digital buffers (14B ROW0)
        ADMUX = _BV(REFS0);
        ADCSRA = _BV(ADEN) | _BV(ADIE) | _BV(ADSC) |
                 _BV(ADPS2) | _BV(ADPS1) | _BV(ADPS0);
    }

    uint8_t fire_buttons() {
        return joystick::fire_buttons(joystick::Port::PORT_A) |
               (joystick::fire_buttons(joystick::Port::PORT_B) << 2);
    }

    // Apply a type change requested over SPI, then refresh the keypads
    void service_ports() {
        uint8_t request = type_request;
        if (request != NO_REQUEST) {
            type_request = NO_REQUEST;
            auto port = static_cast<joystick::Port>((request >> 2) & 1);
            auto type = static_cast<joystick::Type>(request & 3);
            joystick::configure(port, type);
        }

        for (uint8_t p = 0; p < 2; p++) {
            auto port = static_cast<joystick::Port>(p);
            uint16_t value = 0;
            if (joystick::get_type(port) == joystick::Type::DELTA_14B) {
                value = ~keypad::scan(port) & 0x0FFF;
            }
            ATOMIC_BLOCK(ATOMIC_RESTORESTATE) {
                keys[p] = value;
            }
        }
    }

}  // anonymous namespace

ISR(ADC_vect) {
    samples[adc_channel] = ADC;
    adc_channel = (adc_channel + 1) & 7;
    ADMUX = (ADMUX & 0xE0) | adc_channel;
    ADCSRA |= _BV(ADSC);
}

ISR(SPI_STC_vect) {
    uint8_t cmd = SPDR;
    uint8_t response;
    uint16_t value;

    if (cmd >= CMD_JOY_A0 && cmd <= CMD_JOY_B3) {
        uint8_t index = cmd - CMD_JOY_A0;
        value = samples[2 * (index & 3) + (index >> 2)];
        latched_hi = static_cast<uint8_t>(value >> 8);
        response = static_cast<uint8_t>(value);
    } else if (cmd == CMD_JOY_HI) {
        response = latched_hi;
    } else if (cmd == CMD_JOY_BTN) {
        response = fire_buttons();
    } else if (cmd == CMD_JOY_KEY_A || cmd == CMD_JOY_KEY_B) {
        value = keys[cmd - CMD_JOY_KEY_A];
        latched_hi = static_cast<uint8_t>(value >> 8);
        response = static_cast<uint8_t>(value);
    } else if (cmd >= CMD_JOY_TYPE_A && cmd <= CMD_JOY_TYPE_B) {
        type_request = cmd & 7;
        response = cmd;
    } else {
        response = 0xFF;
    }

    SPDR = response;
}

int main() {
    status_led::init();
    keypad::init();
    joystick::init();
    init_spi_slave();
    start_adc();

    status_led::startup_flash();
    status_led::start_heartbeat();
    sei();

    while (true) {
        service_ports();
    }
}
