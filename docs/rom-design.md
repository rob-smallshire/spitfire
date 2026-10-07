# SPItFIRE ROM Design

This document describes the proposed architecture for the BBC Micro Sideways
ROM that drives the SPItFIRE adapter. It is a working proposal and will
evolve as we implement and learn.

## Goals

- Provide standard BBC Micro APIs (ADVAL, INKEY, OSWORD &40, *MOUSE, etc.)
  so existing software works without modification.
- Be modular: support optional features matching the hardware actually
  plugged into the SPItFIRE.
- Share a common SPI driver across all modules.
- Compatible with the BBC sideways ROM ecosystem and existing conventions.

## Architecture Overview

```
┌─────────────────────────────────────────┐
│           SPItFIRE ROM Image            │
├─────────────────────────────────────────┤
│  ROM Header (one per ROM)               │
│    - JMP to Service dispatcher          │
│    - Standard BBC Micro ROM type/title  │
│    - Copyright, version                 │
├─────────────────────────────────────────┤
│  Service Dispatcher                     │
│    - Offers each service call to each   │
│      enabled module in turn             │
│    - Standard claim/pass conventions    │
├─────────────────────────────────────────┤
│  Module: SPI Core (always present)      │
│    - Bit-bang SPI routines              │
│    - Turbo (shift register) routines    │
│    - 74HC138 device selection           │
│    - Shared zero-page workspace         │
├─────────────────────────────────────────┤
│  Module: Mouse (optional)               │
│    - Hooks BYTEV, EVENTV                │
│    - Uses SPI Core                      │
│    - Provides ADVAL 7-9, OSWORD &40     │
│    - *MOUSE [ON|OFF|TYPE]               │
├─────────────────────────────────────────┤
│  Module: Joystick (optional)            │
│    - Hooks BYTEV                        │
│    - Uses SPI Core                      │
│    - Provides ADVAL 1-4 (or extended)   │
├─────────────────────────────────────────┤
│  Module: RTC (optional)                 │
│    - *TIME, *DATE commands              │
│    - Updates &028D-&028F system clock   │
└─────────────────────────────────────────┘
```

The SD card filing system is not part of this ROM: it is MMFS, built
with a SPItFIRE device driver, in a ROM of its own. See
[SD Card Filing System](#sd-card-filing-system-separate-mmfs-rom).

## Reference: JGH's Module System

J.G. Harston's relocatable module system at
[mdfs.net](https://mdfs.net/Software/BBC/Modules/) provides useful precedent:

- **MouseROM** - reference for mouse API conventions (we'll rewrite the
  hardware-facing end completely; the MOS-facing API is identical).
- **SoftRTC2** - reference for RTC integration with system clock.
- **SMLib** - relocatable module framework (we may adopt later, not
  required for first version).
- **MMFS** - existing MMC filing system. Standard MMFS ties SS to
  ground, so we added a SPItFIRE device driver to it (see below).

We should not be wilfully different on the MOS-facing side. Standard
APIs and command syntax should match the existing BBC ecosystem.

## Module: SPI Core

Always present. Provides shared low-level routines used by all other
modules.

### Responsibilities
- Initialise User VIA for SPI bit-bang and shift register modes
- Bit-bang SPI transfer routine (~4100 bytes/sec)
- Turbo SPI transfer routine using VIA shift register (~7400 bytes/sec)
- 74HC138 device selection (constants for each device assignment)
- Common workspace allocation

### Public Routines
| Routine | Inputs | Outputs | Description |
|---------|--------|---------|-------------|
| `init_via` | - | - | One-time VIA setup |
| `select_device` | A=device | - | Set SCK to the device's idle level, then select it via 74HC138 |
| `deselect_device` | - | - | Deselect (Y0 = no device) |
| `spi_transfer` | A=byte | A=received | Bit-bang transfer |
| `spi_turbo_read` | - | A=received | Fast read using shift register |

### Per-device SPI mode
The 6522 shift register samples MISO on the rising edge of SCK (CB1), so
every device must present data that is stable at the rising edge:

| Device | SPI mode | SCK idle level when selected |
|--------|----------|------------------------------|
| SPItFIRE AVR | 0 | Low |
| DS3234 RTC | 3 (it picks CPOL from SCK at CS falling) | High |
| SD card | 3 (as MMFS) | High |

`select_device` must therefore set SCK to the device's idle level
*before* asserting chip select, and the transfer routines must keep that
idle level between bytes. Verified with SPIRTC on the Rev 1 board.

### Device Assignments
See [spi-interface.md](spi-interface.md) and
[peripheral-pinouts.md](peripheral-pinouts.md).

| Output | Device | Constant |
|--------|--------|----------|
| Y0 | None (deselect) | `DEV_NONE` |
| Y1 | SPItFIRE AVR | `DEV_SPITFIRE` |
| Y2 | SD card (J4, Adafruit microSD breakout) | `DEV_SD` |
| Y3 | RTC (J5, SparkFun DeadOn DS3234) | `DEV_RTC` |
| Y4-Y7 | Unassigned | |

## The `*SPITFIRE` Command Namespace

Standard commands like `*MOUSE`, `*TIME`, `*DATE` are kept in their
established namespaces for ecosystem compatibility. SPItFIRE-specific
configuration and extensions live under a `*SPITFIRE` command with a
subcommand structure that mirrors the module hierarchy.

### Rationale
- Avoids polluting the global `*` command namespace
- Groups all SPItFIRE-specific functionality under one prefix
- The hierarchy maps naturally to the modular ROM design
- Tab-style discoverability via `*HELP SPITFIRE`

### Proposed Subcommand Structure
This is a working sketch, not a final design:

| Command | Description |
|---------|-------------|
| `*SPITFIRE` | Show ROM version and active modules |
| `*SPITFIRE INFO` | Show hardware status, AVR firmware version, attached devices |
| `*SPITFIRE HELP [topic]` | Show help (optionally for a subsystem) |
| `*SPITFIRE MOUSE ON\|OFF` | Alias for `*MOUSE ON\|OFF` |
| `*SPITFIRE MOUSE TYPE AMX\|AMIGA\|ATARI` | Select pinout (AVR mode) |
| `*SPITFIRE MOUSE SENSITIVITY sx [,sy]` | Set per-axis sensitivity (2^sx GU/pulse) |
| `*SPITFIRE MOUSE INFO` | Report current state, pulse counts, mode |
| `*SPITFIRE JOYSTICK A 14B\|3B\|3B-TWIN\|...` | Configure joystick port A |
| `*SPITFIRE JOYSTICK B ...` | Configure joystick port B |
| `*SPITFIRE JOYSTICK INFO` | Report joystick state |
| `*SPITFIRE RTC SET hh:mm:ss dd/mm/yyyy` | Set RTC |
| `*SPITFIRE RTC INFO` | Show RTC status |
| `*SPITFIRE SD INFO` | Show SD card status |

### Implementation Note
Each module registers its own `*SPITFIRE <name>` subcommand handler.
The top-level `*SPITFIRE` parser dispatches to the appropriate module
based on the first word after `*SPITFIRE`. A module's subcommand
handler need not be present if the module is excluded from the build.

## Module: Mouse

Replicates the JGH/AMX mouse API. Polls the SPItFIRE AVR via SPI on a
periodic timer event instead of using CB1/CB2 IRQs.

### MOS-facing API (drop-in compatible)
| Call | Description |
|------|-------------|
| `*MOUSE ON` | Enable mouse |
| `*MOUSE OFF` | Disable mouse |
| `*HELP MOUSE` | Show help text |
| `ADVAL(5)` | Mouse X boundary (max X) |
| `ADVAL(6)` | Mouse Y boundary (max Y) |
| `ADVAL(7)` | X position (graphics units, 0-1279) |
| `ADVAL(8)` | Y position (graphics units, 0-1023) |
| `ADVAL(9)` | Buttons - active HIGH (b0=Left, b1=Middle, b2=Right) |
| `INKEY-10` | Left button (-1 if pressed) |
| `INKEY-11` | Middle button |
| `INKEY-12` | Right button |
| `OSWORD &40` | Full mouse state to user buffer (see below) |

### OSWORD &40 buffer format
7 bytes returned at the address pointed to by XY:

| Offset | Content |
|--------|---------|
| +0 | LSB of X co-ordinate |
| +1 | MSB of X co-ordinate |
| +2 | LSB of Y co-ordinate |
| +3 | MSB of Y co-ordinate |
| +4 | Text X co-ordinate (0-19 / 0-39 / 0-79 depending on MODE) |
| +5 | Text Y co-ordinate (0-31) |
| +6 | Buttons - format `cme00000`, **active LOW** (bit reset = pressed) |

Note the dual button conventions:
- **ADVAL(9)**: active-high in bits 0-2, order Left/Middle/Right
- **OSWORD &40 byte 6**: active-low in bits 5-7, order Execute/Move/Cancel
  (= Left/Middle/Right) - this matches the raw IORB layout on a BBC/Master
  with buttons on PB5-PB7

### Coordinate Systems

The mouse driver returns positions in two coordinate systems:

| Coordinate | Units | Range | Origin |
|------------|-------|-------|--------|
| Graphics X | Graphics units (GU) | 0-1279 | Bottom-left |
| Graphics Y | Graphics units (GU) | 0-1023 | Bottom-left |
| Text X | Character cells | 0-19 (MODE 7), 0-39 (MODE 1/4/5), 0-79 (MODE 0/3/6) | Top-left |
| Text Y | Character cells | 0-24 (MODE 3/6), 0-31 (others) | Top-left |

Important conventions inherited from BBC Micro / Acorn MOS:

- **Graphics origin is bottom-left**: Y=0 at the bottom of the screen,
  Y increases upward. This is opposite to many other systems (notably
  modern displays, X11, Windows, etc. which place origin at top-left).
- **Text origin is top-left**: text Y=0 at the top, increasing downward.
- **Mouse Y increment direction**: when the mouse is moved upward (away
  from the user), graphics Y increases, matching BBC graphics convention.
- The graphics coordinate system is independent of screen MODE - it is
  always 1280x1024 GU regardless of the actual pixel resolution. The MOS
  scales graphics commands appropriately.

The text coordinate ranges depend on the current screen MODE:

| MODE | Text Width | Text Height |
|------|-----------|-------------|
| 0 | 80 columns | 32 rows |
| 1 | 40 columns | 32 rows |
| 2 | 20 columns | 32 rows |
| 3 | 80 columns | 25 rows |
| 4 | 40 columns | 32 rows |
| 5 | 20 columns | 32 rows |
| 6 | 40 columns | 25 rows |
| 7 | 40 columns | 25 rows (teletext) |

### Standard commands not directly implemented
The original AMX ROM provided pointer/icon/window helper commands and
a `*SENSITIVITY sx [,sy]` command. We do not reimplement these in
`*MOUSE` namespace; instead:
- Pointer/icon/window helpers are out of scope (they are GUI helpers,
  not core mouse driver functionality)
- Sensitivity adjustment is exposed via `*SPITFIRE MOUSE SENSITIVITY`
  (see SPItFIRE namespace below)

References:
- [BeebWiki OSBYTE &80](https://beebwiki.mdfs.net/OSBYTE_%2680) - ADVAL details
- AMX Mouse User Guide: `docs/datasheets/AMX_MouseUG.pdf` chapter 5
- ADVAL(9) bit ordering: BeebWiki says "b0=Left, b1=Middle, b2=Right";
  JGH's `%rml` notation describes the same bits (binary digit positions:
  r is highest, m middle, l lowest = b2,b1,b0).
- BeebWiki notes: "Most mouse drivers do not implement calls 5, 6 and 9."
  We should implement all of them for completeness since the AVR provides
  the data cheaply.

### SPItFIRE-specific extensions
SPItFIRE-specific configuration is exposed via the `*SPITFIRE` namespace
(see above) rather than extending the standard `*MOUSE` command:

| Command | Description |
|---------|-------------|
| `*SPITFIRE MOUSE TYPE AMX` | Select AMX/Compact pinout (AVR mode 0xF1) |
| `*SPITFIRE MOUSE TYPE AMIGA` | Select Amiga pinout (AVR mode 0xF2) |
| `*SPITFIRE MOUSE TYPE ATARI` | Select Atari pinout (AVR mode 0xF3) |
| `*SPITFIRE MOUSE SENSITIVITY sx [,sy]` | Set per-axis sensitivity (2^sx GU/pulse) |
| `*SPITFIRE MOUSE INFO` | Report state, mode, pulse counts |

### Workspace (drop-in compatible with JGH)
| Address | Use |
|---------|-----|
| `&DA5` | Status (b7=enabled, b3-b0=type/speed) |
| `&DA6-&DA9` | Position (X.lo, X.hi, Y.lo, Y.hi) |
| `&DAA` | Flag |
| `&D9B-&D9D` | Saved BYTEV (3 bytes) |
| `&DAE-&DB0` | Extended BYTEV (XBYTEV) |

### Polling Mechanism
- Hook EVENTV
- Use Event 4 (vsync) for 50 Hz polling, OR
- Use Event 5 with OSWORD &03 interval timer for 100 Hz
- 50 Hz vsync is simpler and likely sufficient
- Each event: select SPItFIRE, send 0x30/0x31/0x32 commands, deselect,
  accumulate dX/dY into position, store buttons

### Button Format Conversion
The AVR returns buttons as `b0=L, b1=R, b2=M`. ADVAL(9) requires `%rml`
which is `b0=L, b1=M, b2=R`. The driver swaps bits 1 and 2.

### Position Bounds
- Initial position: X=&280 (640), Y=&200 (512)
- Increment of 4 graphics units per pulse (matches BBC convention)
- Bound to screen extent via OSBYTE &A0 (read VDU vars)

## Module: Joystick

Provides analogue joystick support via SPItFIRE.

### MOS-facing API
| Call | Description |
|------|-------------|
| `ADVAL(1)` | Channel 0 X (joystick A) |
| `ADVAL(2)` | Channel 0 Y |
| `ADVAL(3)` | Channel 1 X (joystick B) |
| `ADVAL(4)` | Channel 1 Y |
| `OSBYTE &80` with X=0 | Last channel converted |
| Various INKEY values | Fire buttons |

### SPItFIRE-specific commands
TBD - configuration of joystick types (3B Single, 3B Twin, 14B keypad, etc.)
matching the existing AVR firmware test interface.

### Polling Mechanism
- ADC values change slowly (analogue position)
- Could poll on demand (each ADVAL call) or periodically
- Periodic polling at 25 Hz via vsync should be sufficient

## Module: RTC

Real-time clock support for an SPI RTC chip on Y2 or Y3 of the 74HC138.

### Hardware
Off-the-shelf SPI RTC breakout board (DS3234, DS3231, etc.).

### MOS-facing API
| Call | Description |
|------|-------------|
| `*TIME` | Display current time |
| `*DATE` | Display current date |
| `*SETTIME hh:mm:ss` | Set RTC time |
| `*SETDATE dd/mm/yyyy` | Set RTC date |

### Integration with system clock
Read RTC at boot, update &028D-&028F (system clock low bytes).
Could also periodically resync.

## SD Card Filing System (separate MMFS ROM)

**Decision:** the SD card is served by MMFS in its own ROM, not by a
module of the SPItFIRE ROM. MMFS gets a SPItFIRE device driver and
nothing else, so the change stays small enough to offer upstream.

- Fork: <https://github.com/rob-smallshire/MMFS>, branch `spitfire`
  (upstream <https://github.com/hoglet67/MMFS>). Local clone at
  `~/Code/MMFS` with `origin` = the fork, `upstream` = hoglet67.
- Driver: `MMC_Spitfire.asm`, MMFS device `S`. Based on the non-turbo
  User Port driver (`MMC_UserPort.asm`, device `U`).
- Build: the Master build (`top_MAMMFS.asm`) is the one for the Compact.
  MMFS2 (FAT32 card with `.ssd`/`.dsd` files) is the variant in use.
- Tested on the Rev 1 board: `*DCAT`, `*DIN` and running games from a
  FAT32 SDHC card. Writes are not yet tested on hardware.

### How the driver differs from the User Port driver
- PB0-PB4 are outputs, and every write to IORB carries the SD card's
  select code (Y2, `&08`), so the card stays selected throughout a
  transaction.
- The bit-banged byte write keeps PB2-PB4 constant. The User Port
  version lets unsent data bits ripple across PB2-PB7, which on our
  board would switch the decoder between devices mid-byte. The rewrite
  is about 1.6x slower, but writes are only bit-banged commands and data
  blocks; bulk reads use shift register mode 2 and run at the original
  speed.
- `MMC_DEVICE_RESET` (called from `MMC_BEGIN1` at the start of every
  transaction) raises SCK with no device selected, then selects the card
  (SPI mode 3).
- `MMC_DEVICE_DESELECT`, called from `MMC_END`, selects Y0 and sends 8
  clocks so the card releases MISO.
- The TurboMMC mode 6 write path is not used: it relies on external
  buffers switched by PB2-PB4, which on our board are decoder inputs.

### ROM space
The Master MMFS2 build leaves about 3.4 KB free, which could only just
hold the rest of the SPItFIRE modules (estimated 2.3-3.7 KB) with no
margin. Keeping them separate also keeps the MMFS fork upstreamable.
The cost is a second ROM slot; at least one Compact socket takes a 32K
ROM spanning two 16K sideways slots, so this is not a constraint in
practice.

### Bus access between the two ROMs (to be designed)
The mouse (and possibly joystick) module will poll the AVR from an
interrupt, and that poll must not disturb an MMFS transaction in
progress. Points to settle:

- A "bus busy" flag set in `MMC_BEGIN1` and cleared in `MMC_END`, at an
  address both ROMs agree on. The interrupt-time poll must *skip* when
  the flag is set; it must never wait, because MMFS cannot proceed until
  the interrupt returns.
- Errors raised mid-transaction (BRK) never reach `MMC_END`, so the flag
  (and today the deselect) would be left set. MMFS needs to clear it on
  its error path, or the poll needs a way to recover.
- Outside a transaction, a poll changes PB2-PB4, the SCK idle level and
  possibly the shift register mode. Either the poll restores what it
  found, or MMFS reselects at the start of every transaction. It already
  does the latter in `MMC_DEVICE_RESET`.

## Build/Configuration System

### Directory Structure
```
beeb/spitfire-rom/
├── src/
│   ├── header.asm          # ROM header, service dispatcher
│   ├── spi_core.asm        # Shared SPI driver
│   ├── mod_mouse.asm       # Mouse module
│   ├── mod_joystick.asm    # Joystick module
│   ├── mod_rtc.asm         # RTC module
│   ├── mod_sdcard.asm      # SD card filing system
│   └── workspace.asm       # Shared workspace allocation
├── configs/
│   ├── full.asm            # All modules
│   ├── mouse_only.asm      # SPI core + mouse only
│   ├── input.asm           # SPI core + mouse + joystick
│   └── storage.asm         # SPI core + RTC + SD card
└── Makefile                # Build rule per config
```

### Configuration Files
Each `configs/<name>.asm` is a thin wrapper:
```asm
ROM_TITLE = "SPItFIRE Mouse"
ROM_VERSION = "0.01"

INCLUDE "../src/header.asm"
INCLUDE "../src/workspace.asm"
INCLUDE "../src/spi_core.asm"
INCLUDE "../src/mod_mouse.asm"
INCLUDE "../src/footer.asm"

SAVE "SPITFIRE", start, end
```

### Module Conventions
Each module file should:
- Define its own labels in a unique prefix (e.g. `mouse_init`)
- Provide a service entry point `<module>_service`
- Declare its workspace requirements
- Document its dependencies (e.g. requires SPI Core)

### Service Dispatch Pattern
Header's service dispatcher offers the call to each module in turn:
```asm
.Service
    JSR mouse_service
    BEQ exit_service           ; A=0 means claimed
    JSR joystick_service
    BEQ exit_service
    JSR rtc_service
    BEQ exit_service
    ; ... unclaimed, exit normally
.exit_service
    RTS
```

Modules return claim status in A:
- A=0: claimed (stop dispatch)
- A unchanged: not handled (continue dispatch)

## Open Questions

1. **Single ROM vs multiple ROMs?**
   - Single 16K ROM with all modules: consumes one bank slot, simple to load
   - Multiple ROMs: better separation, but uses multiple bank slots
   - **Decision:** Two ROMs. The SPItFIRE ROM holds the SPI core, mouse,
     joystick and RTC modules, configurable at build time. The SD card
     filing system is a separate MMFS ROM (see
     [SD Card Filing System](#sd-card-filing-system-separate-mmfs-rom)).

2. **Relocation support?**
   - JGH's SMLib provides full relocatability
   - Not needed if we always build for &8000
   - **Initial preference:** Build for fixed address, add relocation later if needed

3. **Module enable/disable at runtime?**
   - User could disable modules with `*CONFIG`-style commands
   - More flexible but more complex
   - **Initial preference:** Build-time configuration only

4. **MMFS_Spitfire vs adopting an existing variant?**
   - Could fork existing MMFS source
   - Or implement minimal MMC layer for our hardware
   - **Decision:** Forked MMFS and added a device driver
     (`MMC_Spitfire.asm`, device `S`); working on the Rev 1 board

5. **RTC chip selection?**
   - DS3231 is popular and accurate (built-in TCXO)
   - DS3234 is the SPI variant of DS3231
   - **Decision:** Pick one when we have a board to test

## Implementation Plan (Proposed Order)

1. **SPI Core module** - foundation for everything else
2. **ROM header and service dispatcher** - basic ROM that loads cleanly
3. **Mouse module** - first user-visible feature, hardware proven
4. **Joystick module** - reuse AVR firmware joystick code path
5. **Single-config build first** - all modules in one ROM, configurable later
6. **RTC module** - when hardware available
7. **SD card** - done, as a separate MMFS ROM; still to do is the bus
   access protocol shared with the mouse module

## References

- [BeebWiki OSBYTE &80](https://beebwiki.mdfs.net/OSBYTE_%2680) - ADVAL details
- AMX Mouse User Guide: `docs/datasheets/AMX_MouseUG.pdf`
  ([source](https://chrisacorns.computinghistory.org.uk/docs/AMX/AMX_MouseUG.pdf))
- [JGH's relocatable modules](https://mdfs.net/Software/BBC/Modules/)
- [JGH's MouseROM source](https://mdfs.net/Software/CommandSrc/Mouse/ROMMouse.src)
- [MDFS BBC Mouse documentation](https://mdfs.net/Info/Comp/BBC/Mouse/)
- Internal: [protocol.md](protocol.md) - SPI command set
- Internal: [spi-interface.md](spi-interface.md) - hardware layer
- Internal: [peripheral-pinouts.md](peripheral-pinouts.md) - device pinouts
- Internal: [mouse-trackball-peripheral.md](mouse-trackball-peripheral.md) - mouse details
