cmake_minimum_required(VERSION 3.20)

# Must set toolchain before project()
set(CMAKE_TOOLCHAIN_FILE ${CMAKE_CURRENT_SOURCE_DIR}/cmake/avr-toolchain.cmake)

project(spitfire
    VERSION 0.1.0
    DESCRIPTION "SPI joystick and mouse adapter for BBC Master Compact"
    LANGUAGES CXX C
)

# Target MCU configuration
set(AVR_MCU "atmega1284p" CACHE STRING "Target AVR microcontroller")
set(AVR_MCU_SPEED "18432000UL" CACHE STRING "MCU clock frequency")
set(AVR_PROGRAMMER "usbasp" CACHE STRING "Programmer type for avrdude")
set(AVR_PROGRAMMER_PORT "" CACHE STRING "Programmer port (leave empty for USB)")

# Fuse settings for ATMega1284p with external crystal
set(AVR_H_FUSE "0xd9" CACHE STRING "High fuse byte")
set(AVR_L_FUSE "0xf7" CACHE STRING "Low fuse byte")
set(AVR_E_FUSE "0xff" CACHE STRING "Extended fuse byte")

message(STATUS "Target MCU: ${AVR_MCU}")
message(STATUS "MCU Speed: ${AVR_MCU_SPEED}")
message(STATUS "Programmer: ${AVR_PROGRAMMER}")

# Collect source files
file(GLOB_RECURSE SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/*.c
)

# Create executable
add_executable(${PROJECT_NAME} ${SOURCES})

# Include directories
target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# Compiler definitions
target_compile_definitions(${PROJECT_NAME} PRIVATE
    F_CPU=${AVR_MCU_SPEED}
)

# Compiler options - modern target-based approach
target_compile_options(${PROJECT_NAME} PRIVATE
    -mmcu=${AVR_MCU}
    -fpack-struct
    -fshort-enums
    -funsigned-char
    -funsigned-bitfields
    -ffunction-sections
    -fdata-sections
    -Wall
    -Wextra
    -Werror
    -pedantic
    $<$<COMPILE_LANGUAGE:CXX>:-std=c++17>
    $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions>
    $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti>
    $<$<COMPILE_LANGUAGE:C>:-std=c11>
)

# Build-type specific options
target_compile_options(${PROJECT_NAME} PRIVATE
    $<$<CONFIG:Release>:-Os>
    $<$<CONFIG:Debug>:-Og -g -gdwarf-3>
    $<$<CONFIG:RelWithDebInfo>:-Os -g -gdwarf-3>
)

# Linker options
target_link_options(${PROJECT_NAME} PRIVATE
    -mmcu=${AVR_MCU}
    -Wl,--gc-sections
    -Wl,-Map,${PROJECT_NAME}.map
)

# Set output to .elf
set_target_properties(${PROJECT_NAME} PROPERTIES
    OUTPUT_NAME ${PROJECT_NAME}
    SUFFIX ".elf"
)

# Generate HEX file from ELF
add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O ihex -R .eeprom $<TARGET_FILE:${PROJECT_NAME}> ${PROJECT_NAME}.hex
    COMMAND ${CMAKE_SIZE} --mcu=${AVR_MCU} -C $<TARGET_FILE:${PROJECT_NAME}>
    COMMENT "Generating ${PROJECT_NAME}.hex"
)

# Generate EEPROM file
add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O ihex -j .eeprom --set-section-flags=.eeprom=alloc,load
        --no-change-warnings --change-section-lma .eeprom=0
        $<TARGET_FILE:${PROJECT_NAME}> ${PROJECT_NAME}.eep
    COMMENT "Generating ${PROJECT_NAME}.eep"
)

# Upload target
set(AVRDUDE_OPTIONS -B 5)
if(AVR_PROGRAMMER_PORT)
    list(APPEND AVRDUDE_OPTIONS -P ${AVR_PROGRAMMER_PORT})
endif()

add_custom_target(upload
    COMMAND avrdude -c ${AVR_PROGRAMMER} -p m1284p ${AVRDUDE_OPTIONS}
        -U flash:w:${PROJECT_NAME}.hex:i
    DEPENDS ${PROJECT_NAME}
    COMMENT "Uploading ${PROJECT_NAME}.hex to ${AVR_MCU}"
)

# Upload EEPROM target
add_custom_target(upload_eeprom
    COMMAND avrdude -c ${AVR_PROGRAMMER} -p m1284p ${AVRDUDE_OPTIONS}
        -U eeprom:w:${PROJECT_NAME}.eep:i
    DEPENDS ${PROJECT_NAME}
    COMMENT "Uploading ${PROJECT_NAME}.eep to ${AVR_MCU}"
)

# Fuse programming targets
add_custom_target(read_fuses
    COMMAND avrdude -c ${AVR_PROGRAMMER} -p m1284p ${AVRDUDE_OPTIONS}
        -U hfuse:r:-:h -U lfuse:r:-:h -U efuse:r:-:h
    COMMENT "Reading fuses from ${AVR_MCU}"
)

add_custom_target(write_fuses
    COMMAND avrdude -c ${AVR_PROGRAMMER} -p m1284p ${AVRDUDE_OPTIONS}
        -U hfuse:w:${AVR_H_FUSE}:m -U lfuse:w:${AVR_L_FUSE}:m -U efuse:w:${AVR_E_FUSE}:m
    COMMENT "Writing fuses to ${AVR_MCU}"
)

# Disassembly target
add_custom_target(disassemble
    COMMAND ${CMAKE_OBJDUMP} -h -S $<TARGET_FILE:${PROJECT_NAME}> > ${PROJECT_NAME}.lst
    DEPENDS ${PROJECT_NAME}
    COMMENT "Generating disassembly listing"
)
