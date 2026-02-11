#include "joystick.hpp"
#include "adc.hpp"
#include <avr/io.h>
#include <util/delay.h>

namespace joystick {

namespace {
    // Pin 5 detection pins (COL0 for 14B, AGND_RIGHT for 3B Twin)
    // Port A: PB0, Port B: PB1
    constexpr uint8_t PIN5_A = PB0;
    constexpr uint8_t PIN5_B = PB1;

    // Settling time for pull-up (microseconds)
    constexpr uint8_t SETTLE_US = 20;

    // State machine for each port
    struct PortState {
        Type current;       // Confirmed type
        Type pending;       // Type we're transitioning to
        uint8_t count;      // Consecutive detections of pending type
    };

    PortState state[2] = {
        {Type::NO_JOYSTICK, Type::NO_JOYSTICK, 0},
        {Type::NO_JOYSTICK, Type::NO_JOYSTICK, 0}
    };

    // Delay between variance samples (ms)
    // Must span at least one mains cycle (20ms for 50Hz) to catch drift
    constexpr uint8_t VARIANCE_SAMPLE_DELAY_MS = 3;

    // Read multiple samples spaced over time and return the range (max - min)
    // A low range indicates a stable (connected) pot
    // A high range indicates floating (no joystick) - picks up mains hum
    uint16_t measure_variance(adc::Channel ch) {
        uint16_t min_val = 1023;
        uint16_t max_val = 0;

        for (uint8_t i = 0; i < VARIANCE_SAMPLES; ++i) {
            uint16_t val = adc::read(ch);
            if (val < min_val) min_val = val;
            if (val > max_val) max_val = val;
            if (i < VARIANCE_SAMPLES - 1) {
                _delay_ms(VARIANCE_SAMPLE_DELAY_MS);
            }
        }

        return max_val - min_val;
    }

    // Check if two analog values are approximately equal
    inline bool values_match(uint16_t a, uint16_t b) {
        if (a > b) {
            return (a - b) <= ANALOG_MATCH_THRESHOLD;
        } else {
            return (b - a) <= ANALOG_MATCH_THRESHOLD;
        }
    }

    // Raw detection without state machine
    // Returns what type the port appears to be right now
    Type detect_raw(Port port) {
        // Select pin and ADC channels based on port
        uint8_t pin5_pin = (port == Port::PORT_A) ? PIN5_A : PIN5_B;
        adc::Channel ch_x = (port == Port::PORT_A) ? adc::Channel::ADC0 : adc::Channel::ADC1;
        adc::Channel ch_x_right = (port == Port::PORT_A) ? adc::Channel::ADC4 : adc::Channel::ADC5;

        // Step 1: Check stability of X axis (PA0/PA1)
        // Floating pins have high variance due to noise pickup
        uint16_t x_variance = measure_variance(ch_x);

        if (x_variance > VARIANCE_THRESHOLD) {
            // Unstable reading - no joystick connected
            return Type::NO_JOYSTICK;
        }

        // X axis is stable - a pot is connected
        // Now determine which type

        // Step 2: Check if pin 5 is grounded (indicates 3B Twin)
        // Configure as input with pull-up
        DDRB &= ~_BV(pin5_pin);   // Input
        PORTB |= _BV(pin5_pin);   // Pull-up enabled
        _delay_us(SETTLE_US);

        bool pin5_low = !(PINB & _BV(pin5_pin));

        // Disable pull-up after reading
        PORTB &= ~_BV(pin5_pin);

        if (pin5_low) {
            // Pin 5 is grounded - this is Delta 3B Twin (AGND_RIGHT)
            return Type::DELTA_3B_TWIN;
        }

        // Step 3: Check X_RIGHT stability and compare to X
        // For 3B Single, pins 12 and 15 are tied together (same pot)
        // For 14B, pin 12 is floating (high variance)
        uint16_t x_right_variance = measure_variance(ch_x_right);

        if (x_right_variance > VARIANCE_THRESHOLD) {
            // X_RIGHT is unstable (floating) while X is stable
            // This is Delta 14B (pin 12 unconnected)
            return Type::DELTA_14B;
        }

        // Both X and X_RIGHT are stable
        // Check if they read the same value (tied together)
        uint16_t x_value = adc::read(ch_x);
        uint16_t x_right_value = adc::read(ch_x_right);

        if (values_match(x_value, x_right_value)) {
            // Same value - pins tied together - Delta 3B Single
            return Type::DELTA_3B_SINGLE;
        }

        // Both stable but different values
        // This shouldn't happen with known joysticks, but default to 14B
        return Type::DELTA_14B;
    }
}

void init() {
    // Pin 5 detection pins start as inputs (high-Z)
    DDRB &= ~(_BV(PIN5_A) | _BV(PIN5_B));
    PORTB &= ~(_BV(PIN5_A) | _BV(PIN5_B));

    // Initialize state machines to NO_JOYSTICK
    for (uint8_t i = 0; i < 2; ++i) {
        state[i].current = Type::NO_JOYSTICK;
        state[i].pending = Type::NO_JOYSTICK;
        state[i].count = 0;
    }
}

Type update(Port port) {
    uint8_t idx = static_cast<uint8_t>(port);
    PortState& s = state[idx];

    // Get raw detection result
    Type detected = detect_raw(port);

    // State machine logic
    if (detected == s.current) {
        // Detection matches current confirmed type
        // Reset any pending transition
        s.pending = s.current;
        s.count = 0;
    }
    else if (detected == s.pending) {
        // Detection matches pending type - increment counter
        s.count++;

        if (s.count >= CONFIRM_THRESHOLD) {
            // Confirmed new type
            // Transitions must go through NO_JOYSTICK
            if (s.current != Type::NO_JOYSTICK && detected != Type::NO_JOYSTICK) {
                // Can't transition directly between joystick types
                // First transition to NO_JOYSTICK
                s.current = Type::NO_JOYSTICK;
                // Keep pending and count for next update
            } else {
                // Direct transition allowed (NO_JOYSTICK → type or type → NO_JOYSTICK)
                s.current = detected;
                s.pending = detected;
                s.count = 0;
            }
        }
    }
    else {
        // Detection differs from both current and pending
        // Start new pending transition
        s.pending = detected;
        s.count = 1;
    }

    return s.current;
}

Type get_type(Port port) {
    return state[static_cast<uint8_t>(port)].current;
}

const char* type_name(Type type) {
    switch (type) {
        case Type::NO_JOYSTICK:     return "No Joystick";
        case Type::DELTA_14B:       return "Delta 14B";
        case Type::DELTA_3B_SINGLE: return "Delta 3B Single";
        case Type::DELTA_3B_TWIN:   return "Delta 3B Twin";
        default:                    return "Unknown";
    }
}

}  // namespace joystick
