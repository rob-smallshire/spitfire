# SPItFIRE ROM Build - BeebAsm
#
# BBC Micro driver ROM for SPItFIRE adapter

BEEBASM ?= beebasm
ROM_NAME = spitfire
SRC_DIR = src
BUILD_DIR = build

# Source files
SOURCES = $(wildcard $(SRC_DIR)/*.asm)

# Output ROM file
ROM = $(BUILD_DIR)/$(ROM_NAME).rom

.PHONY: all clean

all: $(ROM)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(ROM): $(SOURCES) | $(BUILD_DIR)
	$(BEEBASM) -i $(SRC_DIR)/main.asm -o $@ -v

clean:
	rm -rf $(BUILD_DIR)

# Install to BeebEm ROMs directory (adjust path as needed)
install: $(ROM)
	@echo "Copy $(ROM) to your emulator's ROM directory"
