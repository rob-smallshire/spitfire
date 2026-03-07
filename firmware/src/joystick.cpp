#include "joystick.hpp"

namespace joystick {

namespace {
    // Current type for each port
    Type port_type[2] = {Type::NO_JOYSTICK, Type::NO_JOYSTICK};
}

void init() {
    port_type[0] = Type::NO_JOYSTICK;
    port_type[1] = Type::NO_JOYSTICK;
}

void set_type(Port port, Type type) {
    port_type[static_cast<uint8_t>(port)] = type;
}

Type get_type(Port port) {
    return port_type[static_cast<uint8_t>(port)];
}

const char* type_name(Type type) {
    switch (type) {
        case Type::NO_JOYSTICK:     return "No Joystick";
        case Type::DELTA_3B_TWIN:   return "Delta 3B Twin";
        case Type::DELTA_3B_SINGLE: return "Delta 3B Single";
        case Type::DELTA_14B:       return "Delta 14B";
        default:                    return "Unknown";
    }
}

const char* type_code(Type type) {
    switch (type) {
        case Type::NO_JOYSTICK:     return "---";
        case Type::DELTA_3B_TWIN:   return "3BT";
        case Type::DELTA_3B_SINGLE: return "3BS";
        case Type::DELTA_14B:       return "14B";
        default:                    return "???";
    }
}

}  // namespace joystick
