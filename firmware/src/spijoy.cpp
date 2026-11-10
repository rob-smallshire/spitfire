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
 *   0x55      JOY_ALL   - the allocation burst (below)
 *   0x58      JOY_CONFIG - the saved configuration:
 *                         b0-2 Port A type, b3-5 Port B type, b6 = 1,
 *                         b7 = 0
 *   0xD0-0xD7 CFG_PORT_A - set and save Port A's type (0-7)
 *   0xD8-0xDF CFG_PORT_B - set and save Port B's type
 *   0xE0-0xE7 JOY_PORT_A - set Port A's type until the next reset or CFG_
 *                         command (not saved)
 *   0xE8-0xEF JOY_PORT_B - the same for Port B
 *                         (CFG_ and JOY_PORT_ reply with the command byte)
 *
 * Port types (see docs/protocol.md): 0 None, 1 Single, 2 Dual, 3 Delta 3B
 * Single, 4 Delta 3B Twin, 5 Delta 14B, 6 Bitstik, 7 Quinkey. Each is
 * driven in one of the joystick module's electrical modes; the others
 * differ only in how many joysticks they give and how fire and direction
 * bits are derived.
 *
 * Joysticks are allocated to ADVAL slot pairs (1,2), (3,4), (17,18),
 * (19,20): Port A's first, then Port B's. JOY_ALL sends only what is
 * allocated, in one chip select:
 *   header  0xA0 | n (joysticks, 0-4), 0x50 | k (keypad mask)
 *   J1      ADVAL(0) switches, ADVAL(1), ADVAL(2)  (always)
 *   J2      ADVAL(3), ADVAL(4)                     (n >= 2)
 *   J3      ADVAL(16) switches, ADVAL(17), (18)    (n >= 3)
 *   J4      ADVAL(19), ADVAL(20)                   (n = 4)
 *   keypads keys 0-11, low byte first, for each joystick in k
 * ADVAL values are 16-bit, low byte first. A switch byte has the pair's
 * fire bits in b0 and b1 and the first joystick's directions in b4-7
 * (left, down, up, right). The J1 bytes are the MOS 5.x ADVAL workspace
 * (&02B6-&02BA), so the ROM's service call &2C handler just stores them.
 * Raising SS ends a burst early.
 *
 * The configuration lives in EEPROM and is applied at power-up; a blank
 * or corrupt record (including one saved by the old four-type firmware)
 * gives Port A Dual and Port B None. The SPI interrupt updates it at
 * once, so JOY_CONFIG reads back a change straight away; the main loop
 * applies it to the ports and writes the EEPROM (3.3 ms a byte, too long
 * for the interrupt).
 */

#include <avr/io.h>
#include <avr/interrupt.h>
#include <avr/eeprom.h>
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
    constexpr uint8_t CMD_JOY_ALL    = 0x55;
    constexpr uint8_t CMD_JOY_CONFIG = 0x58;
    constexpr uint8_t CMD_CFG_PORT_A = 0xD0;
    constexpr uint8_t CMD_CFG_LAST   = 0xDF;
    constexpr uint8_t CMD_JOY_PORT_A = 0xE0;
    constexpr uint8_t CMD_JOY_PORT_LAST = 0xEF;

    constexpr uint8_t NO_REQUEST = 0xFF;

    // Port types, as the protocol numbers them
    enum class PortType : uint8_t {
        NONE, SINGLE, DUAL, DELTA_3BS, DELTA_3BT, DELTA_14B, BITSTIK, QUINKEY
    };
    constexpr uint8_t TYPE_MASK = 7;

    // Switch bits, as in MOS 5.x ADVAL(0). Bits 0 and 1 are fire.
    constexpr uint8_t SW_LEFT    = 0x10;
    constexpr uint8_t SW_DOWN    = 0x20;
    constexpr uint8_t SW_UP      = 0x40;
    constexpr uint8_t SW_RIGHT   = 0x80;

    // The 14B's fire button: key 10, which its two side buttons share
    constexpr uint16_t KEY_FIRE_14B = 1 << 10;

    // Configuration byte, as JOY_CONFIG returns it
    constexpr uint8_t CONFIG_VALID   = 0x40;
    constexpr uint8_t CONFIG_DEFAULT = CONFIG_VALID |
        static_cast<uint8_t>(PortType::DUAL) |
        static_cast<uint8_t>(PortType::NONE) << 3;

    // EEPROM record: a marker, the configuration and its complement. The
    // marker differs from the four-type firmware's (0x53), so its records
    // read as blank.
    constexpr uint8_t RECORD_MARKER = 0x54;
    struct Record {
        uint8_t marker;
        uint8_t config;
        uint8_t check;
    };
    Record EEMEM saved_record;

    // Directions are reported beyond a quarter of full scale from centre
    constexpr uint16_t LOW_THRESHOLD = 256;
    constexpr uint16_t HIGH_THRESHOLD = 768;

    // JOY_ALL: a 2-byte header, groups of 5, 4, 5 and 4 bytes for
    // joysticks 1-4, and at most two keypads (only a 14B has one)
    constexpr uint8_t HEADER_N = 0xA0;
    constexpr uint8_t HEADER_K = 0x50;
    constexpr uint8_t MAX_BURST = 2 + 5 + 4 + 5 + 4 + 2 * 2;

    // --- Written by interrupts ---
    volatile uint16_t samples[8];          // ADC interrupt
    volatile uint8_t type_request = NO_REQUEST;  // SPI interrupt
    volatile uint8_t config = CONFIG_DEFAULT;    // SPI interrupt
    volatile bool config_changed = false;        // SPI interrupt

    // --- Written by the main loop, read by the SPI interrupt ---
    volatile uint16_t keys[2];             // Active high, bit N = button N
    volatile uint8_t staged[MAX_BURST];    // The next JOY_ALL burst
    volatile uint8_t staged_len = 0;

    // --- SPI and pin change interrupts ---
    volatile uint8_t burst[MAX_BURST];
    volatile uint8_t burst_pos = 0;
    volatile uint8_t burst_len = 0;        // 0 when no burst is running

    // --- Main loop only ---
    PortType port_types[2] = {PortType::NONE, PortType::NONE};

    uint8_t adc_channel = 0;
    uint8_t latched_hi = 0;

    void init_spi_slave() {
        DDRB = (DDRB & ~(_BV(PB4) | _BV(PB5) | _BV(PB7))) | _BV(PB6);
        SPCR = _BV(SPIE) | _BV(SPE);
        SPDR = 0x00;
        PCMSK1 |= _BV(PCINT12);            // SS (PB4), to end bursts
        PCICR |= _BV(PCIE1);
    }

    // 10-bit reading to a 16-bit ADVAL value: 0 -> 0x0000, 1023 -> 0xFFFF
    uint16_t adval_value(uint16_t reading) {
        return (reading << 6) | (reading >> 4);
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

    // The joystick module's electrical mode for each port type
    joystick::Type electrical_mode(PortType type) {
        switch (type) {
            case PortType::NONE:      return joystick::Type::NO_JOYSTICK;
            case PortType::DELTA_3BS: return joystick::Type::DELTA_3B_SINGLE;
            case PortType::DELTA_14B: return joystick::Type::DELTA_14B;
            default:                  return joystick::Type::DELTA_3B_TWIN;
        }
    }

    // How many joysticks (slot pairs) each port type takes
    uint8_t joysticks_of(PortType type) {
        switch (type) {
            case PortType::NONE:      return 0;
            case PortType::SINGLE:
            case PortType::DELTA_14B: return 1;
            default:                  return 2;
        }
    }

    void set_port(uint8_t port, PortType type) {
        port_types[port] = type;
        joystick::configure(static_cast<joystick::Port>(port), electrical_mode(type));
    }

    PortType config_type(uint8_t value, uint8_t port) {
        return static_cast<PortType>((value >> (3 * port)) & TYPE_MASK);
    }

    void apply_config(uint8_t value) {
        set_port(0, config_type(value, 0));
        set_port(1, config_type(value, 1));
    }

    // Read the saved configuration, or the default if there is none
    uint8_t load_config() {
        Record record;
        eeprom_read_block(&record, &saved_record, sizeof record);
        if (record.marker == RECORD_MARKER &&
            record.check == static_cast<uint8_t>(~record.config) &&
            (record.config & 0xC0) == CONFIG_VALID) {
            return record.config;
        }
        return CONFIG_DEFAULT;
    }

    void save_config(uint8_t value) {
        Record record = {RECORD_MARKER, value, static_cast<uint8_t>(~value)};
        eeprom_update_block(&record, &saved_record, sizeof record);
    }

    // Apply and save a configuration change made over SPI. Changes that
    // arrive while the EEPROM is being written are picked up next time.
    void service_config() {
        if (!config_changed) return;
        config_changed = false;
        uint8_t value = config;
        apply_config(value);
        save_config(value);
    }

    // Apply a type change requested over SPI, then refresh the keypads
    void service_ports() {
        uint8_t request = type_request;
        if (request != NO_REQUEST) {
            type_request = NO_REQUEST;
            set_port((request >> 3) & 1, static_cast<PortType>(request & TYPE_MASK));
        }

        for (uint8_t p = 0; p < 2; p++) {
            uint16_t value = 0;
            if (port_types[p] == PortType::DELTA_14B) {
                value = ~keypad::scan(static_cast<joystick::Port>(p)) & 0x0FFF;
            }
            ATOMIC_BLOCK(ATOMIC_RESTORESTATE) {
                keys[p] = value;
            }
        }
    }

    // One allocated joystick, as JOY_ALL reports it
    struct Stick {
        uint16_t x, y;      // 10-bit readings
        bool fire;
        bool has_dirs;
        bool has_keypad;
        uint16_t keypad;
    };

    // Describe joystick j (0 or 1) of a port
    Stick describe(uint8_t port, uint8_t j) {
        Stick s;
        uint8_t first = 4 * j + port;      // samples[] index of X: CH(2j)
        ATOMIC_BLOCK(ATOMIC_RESTORESTATE) {
            s.x = samples[first];
            s.y = samples[first + 2];
        }
        PortType type = port_types[port];
        uint8_t buttons = joystick::fire_buttons(static_cast<joystick::Port>(port));
        s.has_keypad = type == PortType::DELTA_14B;
        s.keypad = s.has_keypad ? keys[port] : 0;
        s.has_dirs = type != PortType::QUINKEY;
        if (type == PortType::DELTA_14B) {
            s.fire = (s.keypad & KEY_FIRE_14B) != 0;
        } else if (type == PortType::QUINKEY) {
            s.fire = false;
        } else {
            // Pin 13 is the first joystick's fire, pin 10 the second's
            s.fire = (buttons >> j) & 1;
        }
        return s;
    }

    // Acorn joysticks read high at the left and at the top, which is the
    // ADVAL convention, so nothing is inverted.
    uint8_t directions(const Stick& s) {
        if (!s.has_dirs) return 0;
        uint8_t switches = 0;
        if (s.x >= HIGH_THRESHOLD) switches |= SW_LEFT;
        if (s.x < LOW_THRESHOLD) switches |= SW_RIGHT;
        if (s.y >= HIGH_THRESHOLD) switches |= SW_UP;
        if (s.y < LOW_THRESHOLD) switches |= SW_DOWN;
        return switches;
    }

    uint8_t put_value(uint8_t* out, uint8_t pos, uint16_t reading) {
        uint16_t value = adval_value(reading);
        out[pos++] = static_cast<uint8_t>(value);
        out[pos++] = static_cast<uint8_t>(value >> 8);
        return pos;
    }

    // Build the next JOY_ALL burst from the current readings
    void update_burst() {
        Stick sticks[4];
        uint8_t n = 0;
        for (uint8_t p = 0; p < 2; p++) {
            for (uint8_t j = 0; j < joysticks_of(port_types[p]); j++) {
                sticks[n++] = describe(p, j);
            }
        }

        uint8_t out[MAX_BURST];
        uint8_t k = 0;
        for (uint8_t i = 0; i < n; i++) {
            if (sticks[i].has_keypad) k |= 1 << i;
        }
        out[0] = HEADER_N | n;
        out[1] = HEADER_K | k;
        uint8_t pos = 2;

        // Joystick pairs: J1 (and J2), then J3 (and J4). J1 is always sent.
        for (uint8_t pair = 0; pair < 2; pair++) {
            uint8_t first = 2 * pair;
            if (first > 0 && n <= first) break;
            uint8_t switches = 0;
            uint16_t x = 0, y = 0;
            if (first < n) {
                switches = directions(sticks[first]) | (sticks[first].fire ? 1 : 0);
                x = sticks[first].x;
                y = sticks[first].y;
            }
            if (first + 1 < n && sticks[first + 1].fire) switches |= 2;
            out[pos++] = switches;
            pos = put_value(out, pos, x);
            pos = put_value(out, pos, y);
            if (first + 1 < n) {
                pos = put_value(out, pos, sticks[first + 1].x);
                pos = put_value(out, pos, sticks[first + 1].y);
            }
        }

        for (uint8_t i = 0; i < n; i++) {
            if (sticks[i].has_keypad) {
                out[pos++] = static_cast<uint8_t>(sticks[i].keypad);
                out[pos++] = static_cast<uint8_t>(sticks[i].keypad >> 8);
            }
        }

        ATOMIC_BLOCK(ATOMIC_RESTORESTATE) {
            for (uint8_t i = 0; i < pos; i++) {
                staged[i] = out[i];
            }
            staged_len = pos;
        }
    }

}  // anonymous namespace

ISR(ADC_vect) {
    samples[adc_channel] = ADC;
    adc_channel = (adc_channel + 1) & 7;
    ADMUX = (ADMUX & 0xE0) | adc_channel;
    ADCSRA |= _BV(ADSC);
}

// SS rose: the host has finished with us, so end any burst
ISR(PCINT1_vect) {
    if (PINB & _BV(PB4)) {
        burst_len = 0;
    }
}

ISR(SPI_STC_vect) {
    // A burst runs first: the host leaves little time between bytes
    if (burst_len) {
        if (burst_pos < burst_len) {
            SPDR = burst[burst_pos++];
        } else {
            burst_len = 0;
            SPDR = 0xFF;
        }
        return;
    }

    uint8_t cmd = SPDR;
    uint8_t response;
    uint16_t value;

    if (cmd == CMD_JOY_ALL) {
        // Answer the header at once; the copy finishes long before the
        // host asks for the second byte.
        SPDR = staged[0];
        uint8_t len = staged_len;
        for (uint8_t i = 0; i < len; i++) {
            burst[i] = staged[i];
        }
        burst_pos = 1;
        burst_len = len;
        return;
    } else if (cmd >= CMD_JOY_A0 && cmd <= CMD_JOY_B3) {
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
    } else if (cmd == CMD_JOY_CONFIG) {
        response = config;
    } else if (cmd >= CMD_CFG_PORT_A && cmd <= CMD_CFG_LAST) {
        uint8_t shift = 3 * ((cmd >> 3) & 1);  // Port A, Port B
        config = (config & ~(TYPE_MASK << shift)) | ((cmd & TYPE_MASK) << shift);
        config_changed = true;
        response = cmd;
    } else if (cmd >= CMD_JOY_PORT_A && cmd <= CMD_JOY_PORT_LAST) {
        type_request = cmd & 0x0F;
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
    config = load_config();
    apply_config(config);
    init_spi_slave();
    start_adc();

    status_led::startup_flash();
    status_led::start_heartbeat();
    sei();

    while (true) {
        service_config();
        service_ports();
        update_burst();
    }
}
