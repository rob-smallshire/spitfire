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
# SPI* = bit-bang mode, SPIT* = turbo mode (shift register)
PROGRAMS = SPITEST SPIPERF SPI256 SPITTEST SPIT256 SPITPERF SPIWALK SPIMOUSE

.PHONY: all clean $(PROGRAMS)

all: $(PROGRAMS)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Pattern rule for building programs
SPITEST: $(BUILD_DIR)/SPITEST $(BUILD_DIR)/SPITEST.inf
SPIPERF: $(BUILD_DIR)/SPIPERF $(BUILD_DIR)/SPIPERF.inf
SPI256: $(BUILD_DIR)/SPI256 $(BUILD_DIR)/SPI256.inf
SPITTEST: $(BUILD_DIR)/SPITTEST $(BUILD_DIR)/SPITTEST.inf
SPIT256: $(BUILD_DIR)/SPIT256 $(BUILD_DIR)/SPIT256.inf
SPITPERF: $(BUILD_DIR)/SPITPERF $(BUILD_DIR)/SPITPERF.inf
SPIWALK: $(BUILD_DIR)/SPIWALK $(BUILD_DIR)/SPIWALK.inf
SPIMOUSE: $(BUILD_DIR)/SPIMOUSE $(BUILD_DIR)/SPIMOUSE.inf

$(BUILD_DIR)/SPITEST: $(SRC_DIR)/spitest.asm | $(BUILD_DIR)
	cd $(BUILD_DIR) && $(BEEBASM) -i ../$(SRC_DIR)/spitest.asm -v

$(BUILD_DIR)/SPIPERF: $(SRC_DIR)/spiperf.asm | $(BUILD_DIR)
	cd $(BUILD_DIR) && $(BEEBASM) -i ../$(SRC_DIR)/spiperf.asm -v

$(BUILD_DIR)/SPI256: $(SRC_DIR)/spi256.asm | $(BUILD_DIR)
	cd $(BUILD_DIR) && $(BEEBASM) -i ../$(SRC_DIR)/spi256.asm -v

$(BUILD_DIR)/SPITTEST: $(SRC_DIR)/spittest.asm | $(BUILD_DIR)
	cd $(BUILD_DIR) && $(BEEBASM) -i ../$(SRC_DIR)/spittest.asm -v

$(BUILD_DIR)/SPIT256: $(SRC_DIR)/spit256.asm | $(BUILD_DIR)
	cd $(BUILD_DIR) && $(BEEBASM) -i ../$(SRC_DIR)/spit256.asm -v

$(BUILD_DIR)/SPITPERF: $(SRC_DIR)/spitperf.asm | $(BUILD_DIR)
	cd $(BUILD_DIR) && $(BEEBASM) -i ../$(SRC_DIR)/spitperf.asm -v

$(BUILD_DIR)/SPIWALK: $(SRC_DIR)/spiwalk.asm | $(BUILD_DIR)
	cd $(BUILD_DIR) && $(BEEBASM) -i ../$(SRC_DIR)/spiwalk.asm -v

$(BUILD_DIR)/SPIMOUSE: $(SRC_DIR)/spimouse.asm | $(BUILD_DIR)
	cd $(BUILD_DIR) && $(BEEBASM) -i ../$(SRC_DIR)/spimouse.asm -v

$(BUILD_DIR)/%.inf: | $(BUILD_DIR)
	echo "0 FFFF$(LOAD_ADDR) FFFF$(EXEC_ADDR) 17" > $@

clean:
	rm -rf $(BUILD_DIR)

# Copy to Econet file server (adjust path as needed)
install: all
	@echo "Copy $(BUILD_DIR)/* to your Econet file server"
