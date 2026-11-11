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
│    - Provides ADVAL 5-9, OSWORD &40     │
│    - *MOUSE [ON|OFF|TYPE]               │
├─────────────────────────────────────────┤
│  Module: Joystick (optional)            │
│    - MOS 5.x service call &2C (100 Hz)  │
│    - Uses SPI Core                      │
│    - Provides ADVAL 0-2 (done); 3-4,    │
│      10-11, 16-20, 26-27 via BYTEV      │
├─────────────────────────────────────────┤
│  Module: RTC (optional)                 │
│    - Service call &08: OSWORD &0E/&0F   │
│    - So *TIME and TIME$ read the DS3234 │
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
| `deselect_device` | - | - | Deselect (Y7 = no device) |
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
| Y0 | Unassigned (unconnected on Rev 1; spare header on Rev 2) | |
| Y1 | SPItFIRE AVR | `DEV_SPITFIRE` |
| Y2 | SD card (J4, Adafruit microSD breakout) | `DEV_SD` |
| Y3 | RTC (J5, SparkFun DeadOn DS3234) | `DEV_RTC` |
| Y4-Y6 | Unassigned (spare headers J6-J8) | |
| Y7 | None (deselect): the Compact's idle state, see [spi-interface.md](spi-interface.md) | `DEV_NONE` |

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
| `*SPITFIRE JOYSTICK PORT A\|B <type>` | Set a port's type; see "Design: port types and joystick allocation" |
| `*SPITFIRE JOYSTICK` | Report joystick state |
| `*SPITFIRE RTC INFO` | Show RTC status (oscillator stop flag, temperature, aging) |
| `*SPITFIRE SD INFO` | Show SD card status |

### Implemented so far
`beeb/rom/src/commands.asm`:

| Command | Effect |
|---------|--------|
| `*SPITFIRE` | Version and modules |
| `*SPITFIRE JOYSTICK` | The joystick settings |
| `*SPITFIRE JOYSTICK ON\|OFF` | Set or clear bit 7 of the MOS joystick byte, keeping the rest |
| `*SPITFIRE JOYSTICK PORT A\|B <type>` | Set and save a port's type (NONE, SINGLE, DUAL, 3BS, 3BT, 14B, BITSTIK, QUINKEY) |
| `*SPITFIRE ADVAL [ALL]` | The channels SPItFIRE answers, with their values |
| `*STATUS [SPITFIRE]` | The settings, after the MOS's |
| OSWORD &3F | Identify SPItFIRE and describe the joysticks, for software |

`*HELP SPITFIRE [JOYSTICK]` lists the commands, and plain `*HELP` lists
`SPITFIRE` as a topic. Both end with the settings, as the network filing
systems show their station number, in the layout under "Status display"
below. "on" or "off" is the MOS's joystick byte; the rest is read from
the AVR (JOY_CONFIG). "SPItFIRE not responding" replaces it if the AVR
does not answer, and is the error if a setting cannot be made. Keywords
match in either case; anything else after `*SPITFIRE` is a Syntax error.

The EEPROM is written only by `PORT`, and the AVR rewrites only bytes
that differ, so repeating a setting costs nothing. ON and OFF are not
kept in the AVR: the MOS byte is set at every reset (service &27).

### Implementation Note
Each module registers its own `*SPITFIRE <name>` subcommand handler.
The top-level `*SPITFIRE` parser dispatches to the appropriate module
based on the first word after `*SPITFIRE`. A module's subcommand
handler need not be present if the module is excluded from the build.

## Module: Mouse

Replicates the JGH/AMX mouse API, and the Master Compact's own PMFS
driver's. Polls the SPItFIRE AVR via SPI on a periodic timer event
instead of using CB1/CB2 IRQs. What is known about these drivers, and
the sources, is in
[adval-and-mouse-conventions.md](adval-and-mouse-conventions.md).

### MOS-facing API (drop-in compatible)
| Call | Description |
|------|-------------|
| `*MOUSE ON` | Enable mouse |
| `*MOUSE OFF` | Disable mouse |
| `*HELP MOUSE` | Show help text |
| `ADVAL(5)` | Mouse X boundary (our meaning: max X; see below) |
| `ADVAL(6)` | Mouse Y boundary (max Y) |
| `ADVAL(7)` | X position (graphics units, 0-1279) |
| `ADVAL(8)` | Y position (graphics units, 0-1023) |
| `ADVAL(9)` | Buttons - active HIGH (b0=Left, b1=Middle, b2=Right) |
| `INKEY-10` | Left button (-1 if pressed) |
| `INKEY-11` | Middle button |
| `INKEY-12` | Right button |
| `INKEY-107`/`-108`/`-109` | The same buttons as AMX software reads them (JGH's driver answers both sets) |
| `OSWORD &40` | Full mouse state to user buffer (see below) |

Corrections from the research:
- AMX software reads the buttons as `INKEY-107` to `-109` (AMX guide),
  not -10 to -12, so we answer both, as JGH's driver does.
- "Boundary" is all any source says about `ADVAL(5)`/`(6)`. JGH's driver
  doesn't implement them, so "max X/Y" is our own meaning. PMFS returns
  its `*TMAX` limits there, which agrees.
- JGH's transient driver also takes `*MOUSE AMX|COMPACT|MARCONI|RB5`.

#### Compatibility with the Compact's PMFS driver
The Master Compact's Welcome disc drives its pointer with PMFS, a
sideways ROM. SPItFIRE can't run alongside it: PMFS makes port B all
inputs and counts CB1 edges. Welcome-era software expects its interface:
- `ADVAL(7)`/`(8)`, the pointer in graphics units;
- `*POINTER [0|2]` (a software pointer), `*TSET x,y` and `*TMAX x,y`;
- buttons as keys in the keyboard buffer: RETURN, &C0, and TAB's code.

The one conflict is `ADVAL(9)`. PMFS returns the device mode there,
with 0 meaning mouse, where JGH and AMX return the buttons. Welcome's
TimPaint tests `ADVAL(9)=0` to detect a mouse, and a buttons answer is 0
too while nothing is pressed. So we keep the JGH/AMX meaning.

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

Provides analogue joystick support via SPItFIRE. The first step, done in
`beeb/rom/src/joystick.asm`, makes one handset (by default Port A
CH0/CH1, e.g. the left handset of a Delta 3B Twin) the BBC's first joystick, with full
analogue range, through the Master Compact's joystick service call. As far
as we know nothing has used that call before.

### The MOS 5.x joystick service call (&2C)

Sources: [the Master Compact joystick article][compact-joystick] and Tom
Seddon's [MOS disassembly][mos-disassembly] (`handleDigitalJoystick` in
`src/mos.s65`).

- The MOS's digital joystick routine runs every centisecond from the
  System VIA timer interrupt, with interrupts disabled. It returns at once
  if `*FX16,0` has set the number of ADC channels to zero.
- If bit 7 of the joystick byte (`adcConversionType`, written by
  `*FX190`) is set, it tail-calls ROM service call &2C with Y = &B6 and
  does nothing else: no proportional or switched simulation, no cursor
  key joystick. A ROM returns A=0 to claim.
- Y is the offset in page 2 of the ADVAL workspace that OSBYTE &80
  reads: &0200+Y = `ADVAL(0)` low byte (switches), +1/+2 = `ADVAL(1)`,
  +3/+4 = `ADVAL(2)`. Every odd channel returns `ADVAL(1)` and every even
  one `ADVAL(2)`, so `ADVAL(3)` and `(4)` mirror the first joystick. The
  high byte of `ADVAL(0)` is the MOS's current ADC channel.
- &0200+Y+5 and +6 are the proportional mode's temporaries, free once
  the call is delegated. +7 is not free: `*FX190,64` (joystick as cursor
  keys) keeps its repeat delay there, and that feature still runs before
  the call, from the switch byte we store.
- The MOS loads the joystick byte from CMOS during reset, before service
  call &27, so the ROM sets bit 7 at &27 with OSBYTE &BE, X=&80, Y=&7F
  (keeping the other bits). Nothing is written to CMOS, so without the
  ROM the built-in joystick handling is back.
- With SPItFIRE fitted, the built-in routine would read our SPI lines
  (PB0-PB4) as joystick switches, so taking over the call also stops
  spurious directions.
- The built-in routine also raises the ADC conversion event (event 3)
  and steps the current channel. Delegating skips that; the ROM could do
  it later for software that waits on conversions.

### How the module works

The design below ("Design: port types and joystick allocation") is
built, in `beeb/rom/src/joystick.asm` and `commands.asm`:

- **Every second call (50 Hz, the field rate)** reads the AVR's JOY_ALL
  burst ([protocol.md](protocol.md)): a record (switch byte, X, Y) for
  each joystick, then the keypads. Joystick 1's record goes into the
  MOS's workspace as `ADVAL(0)`-`(2)`, with joystick 2's fire added in
  bit 1 of `ADVAL(0)`; the rest go to the private HAZEL page, cleared
  first so that unallocated channels read 0. The AVR does the scaling,
  allocation and direction bits; the 6502 copies, and combines fire bits
  into `ADVAL(0)` and `(16)`.
- **The BYTEV hook** answers OSBYTE &80 for channels 3, 4, 10-12, 16-20
  and 26-28 from the page, reading each 16-bit value with interrupts
  off, and passes everything else to the previous handler (kept in the
  page) by pushing its address and returning to it.
- **Bus sharing.** The poll runs in the interrupt, so it can arrive
  during a foreground SPI transaction. It runs only when the decoder
  rests on Y7: MMFS keeps the SD card selected for a whole card operation
  and the RTC module keeps the DS3234 selected, so a selected device means
  "busy". Otherwise it saves DDRB, the ACR and port B's outputs, takes SCK
  low (the AVR's idle; MMFS leaves it high) with no device selected,
  selects the AVR, and restores everything afterwards. The joystick
  values hold during disc access.
- **Robustness.** The two header bytes (&A0 OR n, &50 OR k) show the AVR
  answered: a floating MISO cannot produce them, and a bad header leaves
  the values alone. The AVR applies its saved port types at power-up, so
  the poll needs no presence check or set-up and never sends a
  configuration command.
- **Cost.** The poll's receive loop is already receive-only (two port
  writes a bit); see [performance.md](performance.md).
- **ADC emulation.** The hand-over to &2C skips the end of the MOS's own
  routine, which raises event 3 (ADC conversion complete) every
  centisecond with X = the current channel (`currentADCChannel`, &024C)
  and steps that channel down, wrapping to `maximumADCChannel` (&024D,
  set by `*FX16`). The high byte of `ADVAL(0)` is that channel, and
  `*FX17` sets it. Every &2C call does the same, busy or not, so
  software that waits for a conversion behaves as without the ROM.
  (`*FX16,0` stops the MOS calling &2C at all.)

### Design: port types and joystick allocation
This is the design the module is heading towards. It was agreed in
discussion on 2026-11-10 and replaces an earlier design built on presets,
`SETTYPE` and `USE`, which was flexible but confusing. Nothing beyond
`ADVAL(0)`-`(2)` is built yet. The research behind the channel numbers is
in [adval-and-mouse-conventions.md](adval-and-mouse-conventions.md).

#### Aims
- **One idea to learn:** say what is plugged into each port. Joystick
  numbers follow from that, like counters dropped into Connect Four.
- **Multiplayer games just work.** Two, three or four handsets become
  joysticks 1-4 with no mapping to set up.
- **Classic software sees a BBC Micro.** Joysticks 1 and 2 are
  `ADVAL(0)`-`(4)`, exactly as on a BBC with an analogue port.
- More deliberate mapping tools can come later, on top of this.

#### Commands
```
*SPITFIRE JOYSTICK                    Status
*SPITFIRE JOYSTICK PORT A|B <type>    Set and save a port's type
*SPITFIRE JOYSTICK ON|OFF             The MOS's joystick byte, as now
*SPITFIRE ADVAL [ALL]                 The channel allocation, with values
```

`SETTYPE` and `USE` go, and with them the idea of choosing a "handset".

#### Port types

| Type | Name | Notes | Channels | Joysticks |
|---|---|---|---|---|
| `NONE` | No joystick | | 0 | 0 |
| `SINGLE` | Standard single joystick | Two axes | 2 | 1 |
| `DUAL` | Standard dual joystick | Two handsets on one port | 4 | 2 |
| `3BS` | Voltmace Delta 3B Single | One stick wired to both channel pairs, so four logical axes | 4 | 2 |
| `3BT` | Voltmace Delta 3B Twin | A synonym for `DUAL` | 4 | 2 |
| `14B` | Voltmace Delta 14B | One stick and a 3x4 keypad | 2 | 1 |
| `BITSTIK` | Acorn Bitstik | X, Y, twist, and a button on an analogue channel | 4 | 2 slots, one device |
| `QUINKEY` | Microwriter Quinkey | Up to four on the four-way adapter, one channel each | 4 | 4 handsets in 2 slots |

The status display uses the full names.

A `3BS` works fine as a `SINGLE`. `3BS` is for software that wants the
Delta 3B Single's unusual behaviour: one stick seen as two joysticks.

#### Allocation
The analogue slots are `ADVAL(1)`-`(4)` and then `ADVAL(17)`-`(20)`.
Port A's channels take slots from the start, in order, and Port B's
carry on from where Port A's ended.

| A | B | 1 | 2 | 3 | 4 | 17 | 18 | 19 | 20 | Use |
|---|---|---|---|---|---|---|---|---|---|---|
| SINGLE | NONE | A | A | | | | | | | One player |
| NONE | SINGLE | B | B | | | | | | | The same, from Port B |
| SINGLE | SINGLE | A | A | B | B | | | | | Two players |
| DUAL/3BT | NONE | A | A | A | A | | | | | Two players on one port |
| 3BS | NONE | A | A | A | A | | | | | Two-player game, one stick |
| 14B | NONE | A | A | | | | | | | One player with keypad |
| 14B | 14B | A | A | B | B | | | | | Two players with keypads |
| DUAL/3BT | SINGLE | A | A | A | A | B | B | | | Three players |
| DUAL/3BT | DUAL/3BT | A | A | A | A | B | B | B | B | Four players |
| BITSTIK | NONE | A | A | A | A | | | | | Bitstik software |
| BITSTIK | BITSTIK | A | A | A | A | B | B | B | B | Two Bitstiks |
| QUINKEY | NONE | A | A | A | A | | | | | Four Quinkeys |

Properties:
- **It always fits.** A port uses at most four channels, so the two
  ports never need more than the eight slots.
- **X and Y stay together.** Every type uses an even number of channels,
  so each joystick lands on (1,2), (3,4), (17,18) or (19,20). Joystick
  n is the nth pair.
- **Unallocated channels read 0,** as do their fire bits and keypads.
  That is what a Compact returns for `ADVAL(1)` after power-up with no
  joystick (checked on the real machine), and software that detects a
  joystick by looking for roughly centred readings must not be fooled.
  The BYTEV hook answers 3, 4 and 17-20 itself even when nothing is
  allocated to them, rather than passing them to MOS 5, which would
  return copies of `ADVAL(1)` and `(2)`. With no joystick 1, the poll
  writes 0 to `ADVAL(1)` and `(2)` in the MOS's workspace.
- **Port A's type moves Port B's joysticks.** Port B's stick is
  joystick 2 behind a `SINGLE` but joystick 3 behind a `DUAL`. The
  status shows the result.

#### Status display
`*SPITFIRE JOYSTICK`, and the end of `*HELP SPITFIRE JOYSTICK`, show the
full type names with the allocation on its own line, so the longest name
fits in 40 columns:

```
Joystick on
Port A: Voltmace Delta 3B Twin
        Joysticks 1, 2
Port B: Standard single joystick
        Joystick 3
```

A Bitstik or Quinkeys show their slots rather than joysticks
(`Slots 1-4`), and an empty port shows just its name, `No joystick`.

#### `*SPITFIRE ADVAL [ALL]`
A table of the channels SPItFIRE answers, what each carries, the port it
comes from, and its value at the moment the command runs. It doubles as a
quick hardware test. It sits at the top level rather than under
`JOYSTICK` so that the mouse module's channels can join it later.

```
>*SPITFIRE ADVAL
Ch Use               Port Value
 0 Fire 1, 2         A    &01
 1 Joystick 1 X      A    32768
 2 Joystick 1 Y      A    30112
 3 Joystick 2 X      A    65520
 4 Joystick 2 Y      A    0
12 Switches 1, 2     A    &8001
16 Fire 3            B    &00
17 Joystick 3 X      B    33024
18 Joystick 3 Y      B    32640
28 Switches 3        B    &0020
```

- Values are what OSBYTE &80 returns: 16-bit analogue readings in
  decimal; fire bits, switch bytes and keypads in hex (`ADVAL(0)` and
  `(16)` show their low byte).
- Without `ALL`, only the channels in use are listed. `ALL` lists every
  channel in the map (0-4, 10-12, 16-20, 26-28), with `-` for those
  unused, and adds `5-9 Passed on (mouse)`.
- Each type names its channels in its own terms: `Bitstik X`, `Bitstik
  twist`, `Bitstik button`; `Quinkey 1` to `Quinkey 4`;
  `Joystick 3 keypad` for a 14B's keypad.
- The table fits in 40 columns.

#### Buttons and keypads
One fire bit per joystick, and keypads by joystick number, so both
follow the allocation:

| Joystick | X, Y | Fire | Switch byte | Keypad |
|---|---|---|---|---|
| 1 | `ADVAL(1)`, `(2)` | `ADVAL(0)` bit 0 | `ADVAL(12)` low byte | `ADVAL(10)` |
| 2 | `ADVAL(3)`, `(4)` | `ADVAL(0)` bit 1 | `ADVAL(12)` high byte | `ADVAL(11)` |
| 3 | `ADVAL(17)`, `(18)` | `ADVAL(16)` bit 0 | `ADVAL(28)` low byte | `ADVAL(26)` |
| 4 | `ADVAL(19)`, `(20)` | `ADVAL(16)` bit 1 | `ADVAL(28)` high byte | `ADVAL(27)` |

- **Joysticks 1 and 2** behave as on a BBC, so two-player BBC games work
  unchanged. On the Compact, `ADVAL(0)` bits 4-7 also carry joystick 1's
  directions, so digital-joystick software keeps working.
- **Switch bytes** give every joystick the same digital view: bit 0 its
  fire, bits 4-7 its directions (left, down, up, right) in the layout of
  `ADVAL(0)`'s low byte, bits 1-3 zero. Two calls read four joysticks
  digitally, with one decoder for all four, and every program gets the
  firmware's threshold (a quarter of full scale from the centre) rather
  than its own. These came from Don't Dither!, which treats four
  joysticks as eight-way digital inputs (GitHub issue #2). We considered
  and rejected:
  - an OSWORD &3F call reading everything at once, which would freeze a
    large block layout duplicating ADVAL, and be clumsy from BASIC;
  - a summary channel with a nibble per joystick, in a layout unlike
    `ADVAL(0)`'s, leaving fire elsewhere;
  - a mode that turns the high bytes of `ADVAL(0)` and `(16)` into
    joysticks 2 and 4's switch bytes: no fewer calls, and hidden global
    state that leaks into the next program if a game exits without
    restoring it.
- **`SINGLE`, `DUAL`, `3BT`:** each handset's button is its joystick's
  fire bit.
- **`3BS`:** as wired, two buttons on the first joystick's fire bit and
  one on the second's, as on a BBC.
- **`14B`:** fire is key 10, which the two side buttons are wired in
  parallel with. Every key, 10 included, is also in the keypad channel
  (bit n = key n, 1 = pressed, bits 12-15 zero). On a BBC's analogue port
  a 14B gives two fire buttons (keys 9-11 one, 6-8 the other); no known
  game relies on that without the 14B/1 box, so one fire bit per
  joystick wins.
- **`BITSTIK`:** two slots, so two fire bits, which is where its two
  digital buttons are on a BBC. The third button stays on its analogue
  channel, and the readings are passed through unchanged, as Bitstik
  software expects the real hardware. Only the first slot (X and Y) has
  direction bits; the second slot's would come from the twist and the
  third button, which have no direction.
- **`QUINKEY`:** no fire bits; each Quinkey's thumb key is part of its
  chord on its channel.
- A joystick with no keypad reads 0 in its keypad channel.

#### The channel map

| Channel | Use |
|---|---|
| 0 | Fire bits for joysticks 1 and 2 (bits 0, 1). Bits 4-7: joystick 1's directions (Compact). High byte: the channel number |
| 1-4 | Joysticks 1 and 2 |
| 5-9 | Mouse. Left to the mouse module, or passed on to the next BYTEV handler. PMFS uses 5-9 (with 9 as its device mode); JGH and AMX use 7-9 |
| 10, 11 | Keypads of joysticks 1 and 2 |
| 12 | Switch bytes of joysticks 1 (low byte) and 2 (high byte) |
| 16 | Fire bits for joysticks 3 and 4 (bits 0, 1). Bits 4-7: joystick 3's directions. High byte: 0 |
| 17-20 | Joysticks 3 and 4 |
| 26, 27 | Keypads of joysticks 3 and 4 |
| 28 | Switch bytes of joysticks 3 (low byte) and 4 (high byte) |

Setting bit 4 of a channel number moves from joysticks 1 and 2 to 3 and
4: `ORA #16` in machine code, `ADVAL(16+n)` in BASIC. Channels 13-15,
21-25 and 29-126 are unused; 127 is a Tube 16-bit GET, and 128 upwards
are buffers. None of the joystick channels collides with any mouse
driver's: PMFS passes 0-4 and 10 upwards to the previous BYTEV, so the
two chain in either order (checked against the PMFS 136 analysis in the
acorn-compact-mouse-driver project). PMFS itself can never run with
SPItFIRE, because its mouse interrupts are on CB1 and CB2, which carry
SCK and MISO; a PMFS-compatible API could come later from our own
mouse module.

#### How it is served
- **The poll:** the 50 Hz poll (service call &2C) reads one burst from
  the AVR. It stores `ADVAL(0)`-`(2)` in the MOS's workspace, as now. The
  other values go to the ROM's own workspace.
- **BYTEV:** a hook, installed at each reset through an extended vector,
  answers OSBYTE &80 for channels 3, 4, 10-12, 16-20 and 26-28.
  Everything else, 5-9 included, goes to the previous BYTEV, so it chains
  with other drivers.
- **No SPI from BYTEV:** values come from the poll's copy. Software that
  reads the keypads once per key per frame, such as a ported Elite, then
  costs only the OSBYTE call.
- **Burst size:** the AVR sends only what the port types use: a 5-byte
  record per joystick and two bytes per keypad. At about 150 cycles a
  byte, a full burst of 22 bytes takes about 9-10% of the 6502's time.
- **The AVR does the allocation.** It knows both port types, so it can
  lay the burst out in slot order, and the ROM stores bytes without
  knowing the rules.
- **Detection and enumeration:** without our ROM, MOS 5 answers every
  channel with a copy of `ADVAL(1)` or `(2)`, and no standard call lists
  joysticks. SPItFIRE-aware software uses OSWORD &3F (below).
- **Workspace:** one page of private HAZEL workspace, which the poll (in
  the interrupt) and the BYTEV hook (in the foreground) both reach. See
  "Workspace" below.

#### `*STATUS` and `*CONFIGURE`
`*STATUS` on its own prints the MOS's settings and then issues service
call &29, so that ROMs can add theirs; `*CONFIGURE` on its own does the
same with &28 for the list of options. A keyword the MOS does not know
reaches the ROMs through the same calls (`src/configure_table_driven.s65`
in the MOS disassembly). Where a ROM keeps its settings is up to it, so
SPItFIRE's stay in the AVR's EEPROM.

- **`*STATUS`** (service &29, no keyword): the ROM prints the joystick
  settings, as `*SPITFIRE JOYSTICK` does, then two notes:
  ```
  SPItFIRE: Joystick on
  Port A: Standard dual joystick
          Joysticks 1, 2
  Port B: No joystick
  Proportional, Switched, Stick unused
  Configure with *SPITFIRE JOYSTICK
  ```
  The MOS's own `Proportional`, `Switched` and `Stick` options do nothing
  while SPItFIRE has the joystick: they configure MOS code that the
  service call &2C hand-over skips. `*STATUS SPITFIRE` prints the same
  lines. Without workspace, the lines are replaced by the Ctrl-Break
  reminder.
- **`*CONFIGURE`:** not used. Setting the ports there would duplicate
  `*SPITFIRE JOYSTICK PORT`, would want an awkward keyword, and
  `*CONFIGURE` settings conventionally take effect at the next reset
  while ours apply at once. It can be added later if users ask. Any
  keyword must avoid MOS 5's: Baud, Boot, Caps, Country, Data, Delay,
  Dir, ExTube, Fdrive, File, Floppy, Hard, Ignore, InTube, Lang, Loud,
  Mode, NoBoot, NoCaps, NoDir, NoScroll, NoTube, NoSRWipe, Print, Quiet,
  Repeat, Scroll, ShCaps, SRWipe, Tube, TubeWait, Proportional,
  Switched, Stick, TV.

#### Enumeration: OSWORD &3F
SPItFIRE-aware software finds SPItFIRE and learns what is plugged in
with OSWORD &3F. The number is unallocated in both the
[mdfs.net](https://mdfs.net/Docs/Comp/BBC/Oswords) and
[BeebWiki](https://beebwiki.mdfs.net/OSWORDs) lists, and sits just below
AMX Super Art's mouse calls (&40, &41). MOS 5 offers it to the ROMs as
service call 8 (it handles only &00-&0F and &42/&43 itself, and sends
&E0 upwards to USERV), the route the RTC module already takes. Being
below &80 it needs no length bytes: the default Tube transfer of 16 bytes
each way covers the block.

The design follows from what a game or other program wants to know, and
from not tying programs to particular versions of the ROM (GitHub issue
#3, which came from porting Don't Dither!):

- **Can I use SPItFIRE now?** Present, with its workspace, the hardware
  answering, joystick handling on (bit 7 of `*FX190`) and updates running
  (not `*FX16,0`). The last two are states in which ADVAL returns rubbish
  or stops changing.
- **Which joysticks are there, and which can I play with?** A program
  should choose players by what a device can do, not by its type number:
  a Bitstik's second slot and the Quinkeys are not steering joysticks,
  and a type table in a program goes stale when types are added.
- **What do I call them?** The port type's keyword (`3BT`) and full name
  ("Voltmace Delta 3B Twin"), for a title or setup screen.
- **Which parts of SPItFIRE are there?** The modules in the ROM.

What SPItFIRE cannot report is whether a joystick is plugged in: floating
analogue inputs cross-talk too much for presence detection, so it reports
the configuration only. A game confirms a player by asking them to press
fire.

**Rules for staying version-independent:**

- **Feature detection by call.** A reason code the ROM does not know is
  not claimed, so the block comes back unchanged (byte 0 still holds the
  reason code). A program tests the call it needs, not a version number.
  The API version is informative only.
- **Fixed contracts.** Joystick *j*'s channels are a permanent function of
  *j* ([the channel map](#the-channel-map)), so no call returns channel
  numbers. Type numbers never change meaning; new types get new numbers.
  Fields are only ever added, at the end of a block or in bits now
  reserved (which read 0).
- **Capabilities for what varies.** A joystick reports its kind, its
  capabilities and its number of buttons; names come from the ROM. A
  program that uses these works unchanged with port types added later.

Every block fits in 16 bytes. The joystick module's status flags, used
by reasons 0 and 1:

| Bit | Set when |
|---|---|
| 0 | The ROM has no workspace (press Ctrl-Break) |
| 1 | The SPItFIRE hardware did not answer |
| 2 | Joystick handling is off (bit 7 of the `*FX190` byte clear, e.g. `*SPITFIRE JOYSTICK OFF`): ADVAL comes from the MOS's own routine |
| 3 | Updates are stopped (`*FX16,0`): values keep their last readings |

With bit 0 or 1 set, no joystick is reported. Bits 4-7 are reserved.

**Reason 0, identify:**

| Offset | On entry | On exit |
|---|---|---|
| 0 | 0 | &53 ("S"): SPItFIRE answered |
| 1 | | API version (1) |
| 2 | | ROM version, major, in BCD (`&00` for 0.03) |
| 3 | | ROM version, minor, in BCD (`&03` for 0.03) |
| 4 | | Modules in this ROM: bit 0 joystick, bit 1 RTC; others reserved |
| 5 | | Status flags |

**Reason 1, joystick summary:**

| Offset | On entry | On exit |
|---|---|---|
| 0 | 1 | &53 |
| 1 | | n, joysticks allocated (0-4) |
| 2 | | Port A type (as [protocol.md](protocol.md)) |
| 3 | | Port B type |
| 4-7 | | Joysticks 1-4: bit 7 the port (0 = A, 1 = B), bit 6 the handset (0 = the port's first joystick, 1 = its second), bits 0-5 the type; &FF if not allocated |
| 8 | | Status flags |

**Reason 2, describe joystick j:**

| Offset | On entry | On exit |
|---|---|---|
| 0 | 2 | &53 |
| 1 | j (1-4) | Unchanged |
| 2 | | Port, handset and type, as in reason 1; &FF if not allocated (then bytes 3-5 are 0) |
| 3 | | Kind: 0 none, 1 stick, 2 position, 3 auxiliary, 4 chord |
| 4 | | Capabilities: bit 0 the X and Y channels carry readings, bit 1 its switch byte carries directions, bit 2 it has a keypad; others reserved |
| 5 | | Buttons, n: they are bits 0 to n-1 of its switch byte, and bit 0 is also its fire bit in `ADVAL(0)` or `(16)` |

| Kind | Meaning | Types |
|---|---|---|
| 1 stick | A self-centring joystick: steer with it | `SINGLE`, `DUAL`, `3BS`, `3BT`, `14B` |
| 2 position | Absolute position, not self-centring | `BITSTIK` (first slot) |
| 3 auxiliary | Extra controls of the device in the slot before it | `BITSTIK` (second slot: twist and a button) |
| 4 chord | A chord keyboard on X and Y | `QUINKEY` |

A game that wants players picks the joysticks of kind 1, or of any kind
with bit 1 (directions) set if it can use a Bitstik too. Directions are
not computed for a Bitstik's twist or a Quinkey. Buttons beyond the
first are for later types (a 3B Single or Bitstik could report its other
buttons in bits 1-3 of the switch byte); today every joystick has 0 or 1.

**Reason 3, name a port type:**

| Offset | On entry | On exit |
|---|---|---|
| 0 | 3 | &53 |
| 1 | Type number | Unchanged |
| 2 | 0 = keyword (`3BT`), 1 = full name ("Voltmace Delta 3B Twin") | Unchanged |
| 3-4 | Buffer address, low byte first | Unchanged |
| 5 | Buffer size, in bytes | Unchanged |
| 6 | | Characters copied, not counting the CR |
| 7 | | Bit 0: no such type or name (the buffer holds just CR) |

The name is copied with a CR after it, cut to fit the buffer (a size of
0 copies nothing). Full names are at most 24 characters, so a 25-byte
buffer holds any of today's. The buffer is in the I/O processor's
memory, which on a Compact (no Tube) is the only memory.

- **Detection:** software puts 0 in byte 0 and makes the call. If no ROM
  claims it, the MOS returns the block unchanged, so byte 0 still holds
  0; &53 means SPItFIRE answered. The same works for every reason code.
- **No workspace:** after `*SRLOAD ... I` without a reset, the calls
  still answer, with status bit 0 set and no joysticks.
- **Not provided:**
  - *Channel numbers per joystick*, which the issue proposed: the map
    cannot move without breaking every BASIC program that reads
    `ADVAL(1)`, so returning it would suggest a flexibility that does
    not exist. The guide states it as permanent instead.
  - *Setting port types from software:* it writes the EEPROM, and a
    temporary setting would be hidden state that outlives the program.
    Configuration stays with `*SPITFIRE JOYSTICK` until a program needs
    more.
  - *Presence detection*, as above.
- To make the number official, ask the mdfs.net/BeebWiki maintainer to
  list &3F for SPItFIRE.

#### Workspace
Checked in the MOS 5.00 disassembly (`acorn_mos_disassembly`, whose
joystick commentary is ours):

- **Both paths see HAZEL.** `makeROMServiceCall` (`src/mos.s65`) pages
  HAZEL in before calling each ROM, so service call &2C, issued from the
  interrupt, sees it. `extendedVectorEntryPoint` does the same before
  entering a ROM through an extended vector, so the BYTEV hook sees it.
  Each restores the previous state afterwards.
- **Passing BYTEV on is safe with HAZEL paged in.** The MOS's handler,
  `osbyteEntryPoint`, is at &EF8B and OSBYTE &80 at &EDC5, both above the
  HAZEL window (&C000-&DFFF).
- **Claiming a page.** At a hard reset (power-on or Ctrl-Break, not a
  soft Break), `utils.s65` asks for private HAZEL workspace in two calls,
  answered as the MMFS fork does (`mmfs100.asm`):
  - &24 (count): `DEY` once per page needed (one), and don't claim.
  - &22 (claim): store Y in `&0DF0,X` (X = our ROM number), `INY`, and
    don't claim.
- **Finding the page.** The poll gets it from `&0DF0,X`, X being the ROM
  number on a service call. The hook gets the ROM number from `&F4`,
  which the extended vector has just set. Both reach the page through a
  zero-page pointer saved on the stack and restored.
- **Every reset (service &27)** clears the page's values and installs the
  BYTEV extended vector, as well as handing the joystick to &2C.

#### Starting without a reset
`*SRLOAD SPITFIRE 8000 <bank> I` does not give the ROM its workspace.
The `I` flag only copies the ROM type byte (`&8006`) into the MOS's ROM
table (`LF8D1`, `src/sram_access_helpers_3.s65`). It issues none of the
reset service calls: no &24/&22, so no page, and no &27, so no BYTEV
hook and no joystick hand-over. The ROM does receive the calls after
that (`*` commands, `*HELP`, OSWORD), and `&0DF0+<bank>` holds whatever
was there before. A page cannot be safely claimed later, because the
MOS hands HAZEL out in one pass at reset and other ROMs (DFS, ADFS) take
theirs then.

This affects anyone running SPItFIRE from sideways RAM, not only
development, so the ROM must cope:
- **Trust the page only when it is marked as ours.** On &22 the ROM
  writes a signature into its page (a few bytes plus its ROM number).
  Until the signature is found through `&0DF0,X`, it treats the entry as
  stale and does not touch that page. A SPItFIRE image reloaded into the
  same bank without a reset finds its own signature, and that page is
  still legitimately its own.
- **Offer what works without a page.** The RTC module and the commands
  work. `*SPITFIRE JOYSTICK` and `*SPITFIRE ADVAL` print
  `Press Ctrl-Break to start SPItFIRE` instead of their output, and
  `*SPITFIRE` and `*HELP SPITFIRE` show the same reminder.
- **In ROM** (for example a One ROM Fire 28) the image is present at
  power-on and always gets the full start-up.

#### Still to decide
- A scale or sensitivity control for all joysticks, perhaps kept in the
  AVR's EEPROM. Until then readings are raw, including the Bitstik's
  (its axes span only about 0-630 of 1023), which Bitstik software
  expects.
- Whether the AVR's `SINGLE` and `DUAL` need their own firmware types or
  are the 3B Twin reading with a different allocation.

#### Delta 14B background
- On a BBC's analogue port, a 14B is a single joystick on CH0/CH1. The
  top five buttons act as fire 1 (PB0), the next three as fire 2 (PB1),
  and the bottom six do nothing.
- The 14B/1 interface added the user port: two handsets as `ADVAL(1)`/`(2)`
  (rear) and `(3)`/`(4)` (side). Each keypad is a 3x4 matrix, strobed on
  User VIA PB4-PB6 and read on PB0-PB3, with PB7 choosing the handset.
- Software used the keypads through Voltmace's driver generators, or by
  scanning the matrix directly as Mark Moxon's Delta 14B Elite-A does.
  See the conventions document for references.

An Acorn Bitstik works in the firmware's 3B Twin mode. It needs a
Bitstik type in the ROM because of three quirks, measured in
`docs/rev1-bringup.md`:
- Its third button is reported on CH3 (pressed below about half scale).
- Its axes span only about 0-630 of 1023, so they need scaling.
- Twist is reported on CH2.

Its axes are reversed relative to Acorn joystick convention (high at the
left and at the top), reading low at the left and at the front. A real
BBC sees the same polarity, so the ROM should report the readings
unchanged.

A Microwriter Quinkey is a chord keyboard rather than a joystick, but it
uses the same port, also in 3B Twin mode. A four-way adapter puts up to
four Quinkeys on CH0-CH3. Each Quinkey's six keys switch a binary
resistor ladder, so the chord is `(reading - offset + 8) / 16`. The
offset was about 6 counts on the Rev 1 board; the ROM should measure it
per channel with no keys pressed rather than assume it. Microwriter's
BBC driver polled at 100 Hz, ORed the keys held during a chord, and
inserted the character into the input buffer on release. A Quinkey
module would do the same and need the driver's command and shift tables
as well as its letters. See the Quinkey section of `docs/rev1-bringup.md`
for the measurements and references. `beeb/spitest` SPIJOY's Quinkey x4
mode is a working decoder.

## Module: RTC

Makes the DS3234 on J5 (decoder output Y3, `DEV_RTC`) the machine's
clock, so `*TIME`, BASIC's `TIME$` and anything else using OSWORD &0E
(read clock) and &0F (write clock) see real time. The Master 128 had a
clock; the Compact's was removed to save cost, and MOS 5.10 only returns
a fixed default.

### Findings on the Compact
Probed with TIMEPROBE (`beeb/spitest/src/timeprobe.asm`), which calls
OSWORD &0E with all ROMs, with every ROM hidden, and with each ROM on its
own. Results on our Compact (MOS 5.10, ANFS 4.25 in slot 3):

| Call | All ROMs (ANFS answers) | MOS only |
|------|-------------------------|----------|
| &0E,0 string | `   ,71 Oct 1994.23:25:49` | `Fri,31 Dec 1999.23:59:59` |
| &0E,1 BCD | `94 10 71 00 23 25 49` | `99 12 31 06 23 59 59` |
| &0E,2 of `26 10 07 04 12 34 56` | - | `Wed,07 Oct 1926.12:34:56` |
| &0E,2 of `26 10 07 00 12 34 56` | - | `   ,07 Oct 1926.12:34:56` |

- **MOS 5.10 offers OSWORD &0E to sideways ROMs** with service call &08
  (unrecognised OSWORD). ANFS 4.25 answers subcalls 0 and 1 by asking the
  Econet file server. With no ROM answering, the MOS returns its default,
  Fri 31 Dec 1999 23:59:59. (The Master 128 MOS handles these calls
  itself and never offers them to ROMs; a Master add-on would have to
  claim WORDV instead.)
- **MOS subcall 2 always prints the century as 19**, so 2026 comes out
  as 1926. A weekday of 0 prints as three spaces. The MOS offers subcall
  2 to ROMs first, though: with the SPItFIRE ROM loaded, TIMEPROBE's
  all-ROMs conversion of year &26 gives 2026.
- Every string is 25 bytes, `Ddd,dd Mon yyyy.hh:mm:ss` plus CR.
- **ANFS 4.25 mis-decodes file server dates after 1996.** The server puts
  the high year bits in bits 5-7 of the day byte, and ANFS passes the
  whole byte on as the date. `71` with year `94` decodes as
  day = 71 AND 31 = 7, year = (71 AND &E0)/2 + 94 + 1900 = 2026: the
  correct date, 7 Oct 2026. The file server is right; ANFS is wrong.
  ANFS also returns weekday 0 ("unknown"). This is what `*TIME` showed
  before SPItFIRE.

### How the module hooks in
- **Service call &08.** On entry the OSWORD number is at &EF and the
  parameter block address at &F0/&F1. Handle OSWORD &0E and &0F, return
  A=0 to claim, and preserve X and Y. Anything not handled returns with
  A unchanged, so other ROMs (ANFS especially) still see it.
- **ROM slot above ANFS.** Service calls are offered from the highest slot
  down, so the SPItFIRE ROM must sit in a higher slot than ANFS (slot 3
  on our Compact) to answer before it.
- **If no DS3234 is fitted, or the clock is not valid**, pass the call
  on, so the machine falls back to ANFS or the MOS default.
  - *Presence* (all calls): MISO floats when nothing drives it (Rev 1
    has no pull-up; see Rev 2 erratum 2 in
    [rev1-bringup.md](rev1-bringup.md)), so a read alone cannot show that
    a DS3234 answered. The module writes the complement of the SRAM
    address register (18h, no side effects) and reads it back, then
    restores it. A floating line cannot echo the value.
  - *Validity* (reads only): the oscillator stop flag must be clear and
    every time field valid BCD within its range. The ranges also cover
    the bits that always read 0, and reject 12-hour mode. Writes do not
    require a valid stored time, so `*TIME` can always repair the clock.

### Calls to implement

| Call | Data | Notes |
|------|------|-------|
| &0E,0 | Return `Ddd,dd Mon yyyy.hh:mm:ss` + CR (25 bytes) | Build the string ourselves with the real century; do not use MOS subcall 2 |
| &0E,1 | Return 7 BCD bytes: year, month, date, weekday, hours, minutes, seconds | Weekday &01-&07 = Sun-Sat, as SPISETTIME writes it to the DS3234 |
| &0E,2 | Convert 7 BCD bytes at XY+1 to a string | MOS 5.10 offers it to ROMs before converting it itself, so claiming it fixes the century for every caller. Year &00-&79 = 20xx, &80-&99 = 19xx |
| &0F,8 | `hh:mm:ss` | Set the time, leave the date |
| &0F,15 | `Ddd,dd Mon yyyy` | Set the date, leave the time |
| &0F,24 | `Ddd,dd Mon yyyy.hh:mm:ss` | Set both |

Leave alone: &0E subcalls 3 and 4, which ANFS uses for the file server's
time (and other ROMs use inconsistently), and every other subcall or
length. The string field positions are fixed: programs parse `TIME$`.

### Conventions (from the Stardot discussions)
- **OSWORD calls never raise errors.** Invalid OSWORD &0F data is
  ignored (or passed on). Errors belong to `*` commands.
- **&A8-&AF belong to `*` commands.** An OSWORD handler that uses them
  as workspace must save and restore them (e.g. on the stack).
- **Return the real four-digit year** in subcall 0. Copying the
  Master's 19xx is not required by the specification.
- The 6502's V flag is not valid in decimal mode, which matters for any
  BCD arithmetic (e.g. a future timezone offset).

### Setting the clock
`*TIME <string>` and `TIME$=` set the clock through OSWORD &0F, so
nothing extra is needed beyond the &0F handler: verified on the Compact,
where MOS 5.10's `*TIME` passes its argument to OSWORD &0F. Any of the
three forms (time, date, or both) works from either.

The handler ignores the weekday name and computes the weekday from the
date (Sakamoto's method, reduced to 8 bits for 2000-2199). It accepts
years 2000-2199, the range of the DS3234's century bit, checks the date
against the length of the month (2100 is not a leap year), and passes
anything invalid on. A successful write clears the oscillator stop flag.

### Possible later extensions
Time & Config defines further subcalls: &0E,5 for century and timezone,
&0E,6 for when the clock was last set, &0F lengths for synchronising to
the second and adjusting drift. None is a settled standard; leave them
out of the first version.

### Not to be confused with the system clock
OSWORD 1/2 (`TIME` in BASIC) is a centisecond counter, unrelated to the
calendar clock; the earlier idea of writing the RTC into &028D-&028F is
wrong.

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
- `MMC_DEVICE_DESELECT` selects Y7 (no device) and sends 8 clocks so the card
  releases MISO. It is called from `ResetLEDS`, which MMFS calls at the
  end of every card operation and when reporting any error, and from
  `MMC_END`. `MMC_END` alone was not enough: `MMC_BEGIN`/`MMC_END`
  bracket a zero page save, not a card operation (`MMC_BEGIN2` calls
  both at once, and the reads follow), so the card was left selected
  after booting with MMFS2 active and after `*DCAT`. Verified on the
  Compact: the decoder now rests on no device and the SD card's LED is off
  except while loading.
- The TurboMMC mode 6 write path is not used: it relies on external
  buffers switched by PB2-PB4, which on our board are decoder inputs.

### ROM space
The Master MMFS2 build leaves about 3.4 KB free, which could only just
hold the rest of the SPItFIRE modules (estimated 2.3-3.7 KB) with no
margin. Keeping them separate also keeps the MMFS fork upstreamable.
The cost is a second ROM slot; at least one Compact socket takes a 32K
ROM spanning two 16K sideways slots, so this is not a constraint in
practice.

### Bus access between the two ROMs
The joystick module polls the AVR from an interrupt (and the mouse
module will), and that poll must not disturb an MMFS transaction in
progress. The joystick module settles it without a flag: MMFS keeps the
card selected throughout each card operation, so the poll skips whenever
the decoder is not on Y7, and restores the VIA state it changes (see
"Module: Joystick"). The notes below were the earlier plan for a shared
flag, kept in case a case turns up that the chip select does not cover:

- A "bus busy" flag at an address both ROMs agree on. The
  interrupt-time poll must *skip* when the flag is set; it must never
  wait, because MMFS cannot proceed until the interrupt returns.
- Where MMFS sets and clears it: not `MMC_BEGIN1`/`MMC_END`, which do
  not bracket card operations (see above). `SetLEDS` and `ResetLEDS`
  bracket nearly all of them, and `ResetLEDS` also runs on every error
  report, so the flag would not be left set by a BRK. Exceptions to
  cover: `MMC_GetCIDCRC` (card ID check) reads the card without
  `SetLEDS`.
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
│   └── workspace.asm       # Shared workspace allocation
├── configs/
│   ├── full.asm            # All modules
│   ├── mouse_only.asm      # SPI core + mouse only
│   ├── input.asm           # SPI core + mouse + joystick
│   └── clock.asm           # SPI core + RTC
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
   - **Decision:** DS3234 (SparkFun DeadOn breakout on J5); proven on the
     Rev 1 board by SPIRTC and SPISETTIME

## Implementation Plan (Proposed Order)

The RTC hardware is proven and its MOS interface is now understood, so
the RTC module comes first and brings the ROM skeleton with it:

1. **RTC module** - ROM header, service dispatcher, SPI core, OSWORD &0E
   and &0F (done, working on the Compact)
2. **Mouse module** - first input feature, hardware proven
3. **Joystick module** - first step done: one handset, chosen with
   `*SPITFIRE JOYSTICK USE` and kept in the AVR's EEPROM, as
   `ADVAL(0)`-`(2)` through MOS 5.x service call &2C. Next: port types
   and joystick allocation, above (`PORT`, BYTEV, keypads, joysticks
   3 and 4)
4. **Single-config build first** - all modules in one ROM, configurable later
5. **SD card** - done, as a separate MMFS ROM; still to do is the bus
   access protocol shared with the mouse module

## References

- [BeebWiki OSBYTE &80](https://beebwiki.mdfs.net/OSBYTE_%2680) - ADVAL details
- [Acorn BBC Master Compact Joystick][compact-joystick] - MOS 5.x joystick
  handling, `*FX190` and service call &2C
- [Acorn MOS disassembly][mos-disassembly] (Tom Seddon) - annotated MOS
  5.x source, including `handleDigitalJoystick`
- AMX Mouse User Guide: `docs/datasheets/AMX_MouseUG.pdf`
  ([source](https://chrisacorns.computinghistory.org.uk/docs/AMX/AMX_MouseUG.pdf))
- [JGH's relocatable modules](https://mdfs.net/Software/BBC/Modules/)
- [BeebWiki OSWORD &0E](https://beebwiki.mdfs.net/OSWORD_%260E) and
  [OSWORD &0F](https://beebwiki.mdfs.net/OSWORD_%260F) - clock calls,
  per-MOS behaviour, the ANFS date fix
- Stardot: [OSWORD 14 & 15 numbers](https://stardot.org.uk/forums/viewtopic.php?t=28743)
  and [Time & Config](https://stardot.org.uk/forums/viewtopic.php?t=30412)
  (Barney Hilken's RTC board; ROM source at
  <https://codeberg.org/Barneyntd/Time-Config.>)
- [JGH's MouseROM source](https://mdfs.net/Software/CommandSrc/Mouse/ROMMouse.src)
- [MDFS BBC Mouse documentation](https://mdfs.net/Info/Comp/BBC/Mouse/)
- Internal: [protocol.md](protocol.md) - SPI command set
- Internal: [spi-interface.md](spi-interface.md) - hardware layer
- Internal: [peripheral-pinouts.md](peripheral-pinouts.md) - device pinouts
- Internal: [mouse-trackball-peripheral.md](mouse-trackball-peripheral.md) - mouse details
- Internal: [adval-and-mouse-conventions.md](adval-and-mouse-conventions.md) -
  OSBYTE &80 channel uses, mouse drivers (JGH, AMX, the Compact's PMFS),
  multi-joystick precedents

[compact-joystick]: https://blog.smallshire.no/blog/compact-joystick/acorn-bbc-master-compact-joystick/
[mos-disassembly]: https://github.com/tom-seddon/acorn_mos_disassembly
