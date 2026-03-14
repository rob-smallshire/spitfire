# SPItFIRE SPI Test Program
#
# Builds a raw binary and INF file for Econet file server

BEEBASM ?= beebasm
SRC_DIR = src
BUILD_DIR = build

# Program settings
PROG_NAME = SPITEST
LOAD_ADDR = 1900
EXEC_ADDR = 1900

# Output files
BINARY = $(BUILD_DIR)/$(PROG_NAME)
INF = $(BUILD_DIR)/$(PROG_NAME).inf

.PHONY: all clean

all: $(BINARY) $(INF)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# BeebAsm SAVE creates file in current directory; move to build/
$(BINARY): $(SRC_DIR)/spitest.asm | $(BUILD_DIR)
	cd $(BUILD_DIR) && $(BEEBASM) -i ../$(SRC_DIR)/spitest.asm -v

$(INF): | $(BUILD_DIR)
	echo "0 FFFF$(LOAD_ADDR) FFFF$(EXEC_ADDR) 17" > $@

clean:
	rm -rf $(BUILD_DIR)

# Copy to Econet file server (adjust path as needed)
install: all
	@echo "Copy $(BINARY) and $(INF) to your Econet file server"
