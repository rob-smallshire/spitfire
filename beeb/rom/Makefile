# SPItFIRE ROM Build - BeebAsm
#
# BBC Micro driver ROM for SPItFIRE adapter

BEEBASM ?= beebasm
SRC_DIR = src
BUILD_DIR = build

# Source files
SOURCES = $(wildcard $(SRC_DIR)/*.asm)

# Output ROM image, with an .inf file for the Econet file server
ROM = $(BUILD_DIR)/SPITFIRE
INF = $(ROM).inf

.PHONY: all clean test

all: $(ROM) $(INF)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(ROM): $(SOURCES) | $(BUILD_DIR)
	$(BEEBASM) -i $(SRC_DIR)/main.asm -o $@ -v > $(BUILD_DIR)/spitfire.lst

$(INF): | $(BUILD_DIR)
	echo "0 FFFF8000 FFFF8000 17" > $@

clean:
	rm -rf $(BUILD_DIR)

# Emulator regression test for the RTC module (needs uv; fetches py65)
test:
	uv run --with py65 python test/test_rtc.py

# Install to BeebEm ROMs directory (adjust path as needed)
install: $(ROM) $(INF)
	@echo "Copy $(ROM) to your emulator's ROM directory"
