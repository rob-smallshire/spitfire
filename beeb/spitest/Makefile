# SPItFIRE SPI Test Programs
#
# Builds raw binaries and INF files for Econet file server

BEEBASM ?= beebasm
SRC_DIR = src
BUILD_DIR = build

# Common settings
LOAD_ADDR = 1900
EXEC_ADDR = 1900

# Programs to build
PROGRAMS = SPITEST SPIPERF

.PHONY: all clean $(PROGRAMS)

all: $(PROGRAMS)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Pattern rule for building programs
SPITEST: $(BUILD_DIR)/SPITEST $(BUILD_DIR)/SPITEST.inf
SPIPERF: $(BUILD_DIR)/SPIPERF $(BUILD_DIR)/SPIPERF.inf

$(BUILD_DIR)/SPITEST: $(SRC_DIR)/spitest.asm | $(BUILD_DIR)
	cd $(BUILD_DIR) && $(BEEBASM) -i ../$(SRC_DIR)/spitest.asm -v

$(BUILD_DIR)/SPIPERF: $(SRC_DIR)/spiperf.asm | $(BUILD_DIR)
	cd $(BUILD_DIR) && $(BEEBASM) -i ../$(SRC_DIR)/spiperf.asm -v

$(BUILD_DIR)/%.inf: | $(BUILD_DIR)
	echo "0 FFFF$(LOAD_ADDR) FFFF$(EXEC_ADDR) 17" > $@

clean:
	rm -rf $(BUILD_DIR)

# Copy to Econet file server (adjust path as needed)
install: all
	@echo "Copy $(BUILD_DIR)/* to your Econet file server"
