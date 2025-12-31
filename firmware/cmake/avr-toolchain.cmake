# AVR-GCC Toolchain file for CMake
# For cross-compiling to AVR microcontrollers

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR avr)

# Prevent CMake from testing the compiler (it will fail for cross-compilation)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Find AVR toolchain
# On macOS with Homebrew: brew install avr-gcc
# On Linux: apt install gcc-avr avr-libc
find_program(CMAKE_C_COMPILER avr-gcc REQUIRED)
find_program(CMAKE_CXX_COMPILER avr-g++ REQUIRED)
find_program(CMAKE_OBJCOPY avr-objcopy REQUIRED)
find_program(CMAKE_OBJDUMP avr-objdump REQUIRED)
find_program(CMAKE_SIZE avr-size REQUIRED)
find_program(CMAKE_AR avr-ar REQUIRED)

# Set the toolchain root path if available (useful for finding headers)
get_filename_component(AVR_TOOLCHAIN_DIR ${CMAKE_C_COMPILER} DIRECTORY)
get_filename_component(AVR_TOOLCHAIN_DIR ${AVR_TOOLCHAIN_DIR} DIRECTORY)

# Search paths for libraries and includes
set(CMAKE_FIND_ROOT_PATH ${AVR_TOOLCHAIN_DIR})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
