# ADVAL and Mouse Conventions on Acorn 8-bit Machines

Research notes from October 2026. They gather what is known about OSBYTE
&80 (BASIC's `ADVAL`) and the mouse drivers for the BBC Micro, the Master
and especially the Master Compact. The aim is to fit SPItFIRE's extra
joysticks, keypads and mouse around them without clashing. Much of this is
scattered or undocumented elsewhere. The Master Compact's own mouse driver,
PMFS, seems not to have been described before.

The SPItFIRE decisions that follow from this are in
[rom-design.md](rom-design.md) ("The ADVAL channel map").

Every claim gives its source. "Inferred" marks conclusions drawn from code
or behaviour rather than stated anywhere.

## OSBYTE &80 in the MOS

OSBYTE &80 takes a channel number in X. BASIC's `ADVAL(n)` calls it with X
= n, passing only X: JGH's mouse driver notes that "BASIC only passes X, Y
must be ignored" ([ROMMouse.src][rommouse]).

| MOS | X = 0 | X = 1-4 | X = 5-127 | X = 128-255 |
|---|---|---|---|---|
| BBC and Master (MOS 3.x and earlier) | Fire buttons and last channel | ADC channels 1-4 | X=Y=&FF: `CPX #5 : BCS` | Buffer status |
| Master Compact (MOS 5.x) | Digital joystick byte and current channel | Odd X gives `ADVAL(1)`, even X gives `ADVAL(2)` | No range check: aliased as for 1-4 | Buffer status |

Sources: Tom Seddon's [MOS disassembly][mos-disassembly], `osbyte80` in
`src/mos.s65`, and [mdfs.net OSBYTE &80][mdfs-osbyte80].

The consequences are:
- **Only bit 7 of X separates channels from buffers,** so channels 0-127
  are all "channels".
- **No MOS offers unknown channels to sideways ROMs.** Every driver that
  adds channels hooks BYTEV and passes on what it doesn't own: JGH's mouse
  driver, the Mertec Compact Companion and PMFS (below). BeebWiki's
  [ADVAL page][beebwiki-adval] says MOS 5 passes unknown calls to ROMs,
  but the disassembly shows otherwise.
- **Without a driver, an extra channel cannot be told from a real one.**
  MOS 3.x answers with &FFFF (full deflection), and MOS 5 with a copy of
  `ADVAL(1)` or `(2)`. Software needs some other way to detect the driver.

## The channel map

| X | Use | Source |
|---|---|---|
| 0 | Buttons and channel number (layouts below) | MOS disassembly |
| 1, 2 | Joystick 1 X, Y (ADC channels 1, 2) | [BeebWiki ADVAL][beebwiki-adval] |
| 3, 4 | Joystick 2 X, Y. On MOS 5 they repeat 1 and 2 | BeebWiki; MOS disassembly |
| 5, 6 | Mouse "boundary" X, Y. PMFS: the `*TMAX` limits | [BeebWiki OSBYTE &80][beebwiki-osbyte80]; PMFS |
| 7, 8 | Mouse or pointer X, Y | JGH; AMX; PMFS; RISC OS reason codes 7 and 8 |
| 9 | Mouse buttons (JGH and AMX style); **device mode** in PMFS | JGH; PMFS (below) |
| 10-126 | No documented use found | Absent from BeebWiki, mdfs.net and the RISC OS reason codes; nothing found in a web search |
| 127 | 16-bit GET on some second processors and emulators (cZ80Tube, PDPTube, Brandy) | [BeebWiki ADVAL][beebwiki-adval] |
| 128 + n | Buffer n-1: BASIC's negative ADVALs, e.g. -10 is the mouse buffer | BeebWiki; [RISC OS OS_Byte 128][riscos-osbyte128] |

BeebWiki also notes that "most mouse drivers do not implement calls 5, 6
and 9".

### ADVAL(0)

The low byte reports buttons, in three different layouts:

| Machine | Bit 0 | Bit 1 | Bits 2-3 | Bits 4-7 |
|---|---|---|---|---|
| BBC and Master | Joystick 1 fire | Joystick 2 fire | 0 | 0 |
| Master Compact (MOS 5) | Fire | Mouse left | Mouse middle, right | Left, down, up, right |
| RISC OS | Joystick 0 switch | Joystick 1 switch | | |

The high byte is the last channel converted (BBC, Master) or the current
channel (Compact).

On the Compact, the MOS sets aside bits 1-3 for mouse buttons but never
sets them. Its digital joystick routine reads only PB0-PB4 as the four
directions and fire. Its switch-to-key table maps bits 1-3 to DELETE,
RETURN and COPY, so only a ROM that fills the workspace through service
call &2C could use them (MOS disassembly, `handleDigitalJoystick`).

## Mouse drivers

### JGH's mouse driver (ROM and transient)

Source: [ROMMouse.src][rommouse] and the [MDFS mouse page][mdfs-mouse].

- `*MOUSE [ON|OFF]`. The transient version also takes `*MOUSE AMX`,
  `COMPACT`, `MARCONI` and `RB5` to choose the wiring.
- `ADVAL(7)`, `(8)`: position in graphics units. It starts at &280, &200
  and moves 4 per quadrature edge. Both axes are clamped with the same
  high-byte test, so Y may run to about 1279 rather than 1023 (inferred).
- `ADVAL(9)`: buttons, 1 = pressed: bit 0 left, bit 1 middle, bit 2 right.
- Channels 5 and 6 are not implemented. They and every other channel go
  on to the previous BYTEV.
- **Buttons as INKEY:** both `INKEY-10`, `-11`, `-12` and `INKEY-107`,
  `-108`, `-109` (OSBYTE &81 with X=&F6-&F4 or &95-&93, Y=&FF).
- **OSWORD &40:** see the AMX section below.
- **Workspace:** status &DA5, position &DA6-&DA9, flag &DAA, saved BYTEV
  &D9B, extended BYTEV &DAE.

### AMX Mouse

Source: the AMX Mouse User Guide, chapter 5
(`docs/datasheets/AMX_MouseUG.pdf`).

- Positions are 0-1279 by 0-1023 graphics units.
- **Buttons as INKEY:** only `-107`, `-108`, `-109` and `-129` are
  documented. AMX software uses these, not -10 to -12.
- **OSWORD &40** (the Super Art call) fills 7 bytes:
  - X (2 bytes) and Y (2 bytes) in graphics units;
  - text X and Y;
  - buttons `cme00000`, active low: c cancel, m move, e execute.
- **OSWORD &41:** subcommand 7 sets the position and subcommand 8 reads the
  ROM's details, including sensitivity ([mdfs.net OSWORDs][mdfs-oswords]).
- **Commands** include `*MCURSOR`, `*SENSITIVITY`, `*POINTER` and
  `*BUTTONS`.

### Other mouse calls

From [mdfs.net OSWORDs][mdfs-oswords]:
- **Arthur OSWORD &15** has four subcommands: 1 bounding box (left,
  bottom, right, top), 2 multipliers, 3 set position, 4 read the
  unbuffered position.
- **Integra-B OSWORD &49** is a windowing interface.

## PMFS: the Master Compact's mouse driver

The Master Compact's Welcome disc has no program called MOUSE. Its pointer
and mouse driver is a sideways ROM image, `$.WIMPS.R.PMFS`.

**Identification:**

| | |
|---|---|
| Title | "PMFS", version "136" |
| Copyright | "(C)1986 PMF", with "JPG,PMF" near the end |
| Code | 65C02 (it uses STZ, for example), so it needs a Master |

**Builds:**

| Size | MD5 | Found on |
|---|---|---|
| 6 KB | `8826f28b3575e9481944528ebf09893c` | tbi103-2, the "Prodest" image and the Watford image |
| 8 KB | `6f95ee5f69b7273c7bf0b932ebdb975f` | tbi103-2a3 and tbi103-2a4 |

The two builds have the same command table and the same ADVAL handling.
The addresses below are from the 6 KB build.

The disc images came from the Stardot thread on the Welcome disc
([viewtopic.php?t=33348][stardot-welcome]): `tbi103-2a.zip` and
SevernWolf's `master compact welcome.zip`. They were read with
[oaknut-disc][oaknut].

### Loading

The Welcome loader (`$.Loader`) puts PMFS in sideways RAM bank 5 and turns
it on:

```
190 *SRLOAD PMFS 8000 5 Q
...
230 _%?5=&82:_%?4=&82:*DIGITAL
```

`_%` is &2A1, the ROM type table. The poke marks banks 4 and 5 as service
ROMs. PMFS keeps its workspace at &9000-&9037 inside its own bank, so it
must run from sideways RAM (inferred).

### Commands

The command table is at &81FF.

| Command | Effect |
|---|---|
| `*MOUSE`, `*TRACKERBALL` | Mouse mode (the same code) |
| `*DIGITAL` | Steers the pointer from the MOS digital joystick (`ADVAL(0)` direction bits) |
| `*JOYSTICK` | Steers from `ADVAL(1)` and `(2)`: high byte &C0 or above, or below &40 |
| `*KEYS` | Steers from the cursor keys (INKEY -26, -122, -58, -42), faster with SHIFT. Also `*FX4,2` and `*FX226,0` |
| `*POINTER` | Shows the software pointer in modes 0, 1, 2, 4 and 5. `*POINTER 0` or `2` removes it |
| `*TMAX x,y` | Sets the limits that `ADVAL(5)` and `(6)` return |
| `*TSET x,y` | Moves the pointer to x, y |
| `*SETPAL` | Sets logical colours 0 and 1 with VDU 19 |

Giving a device command the argument 0 turns the driver off: it restores
the vectors and removes the pointer.

### ADVAL

PMFS hooks BYTEV and answers OSBYTE &80 at &8786. Other OSBYTEs, and
channels 0-4 and 10 upwards, go to the previous BYTEV, saved at &0D97.

| Channel | Returns |
|---|---|
| `ADVAL(5)`, `(6)` | The `*TMAX` x, y (from &9000, &9002) |
| `ADVAL(7)` | Pointer X, 0-1276, in graphics units (from &9004) |
| `ADVAL(8)` | Pointer Y, 0-1020, in graphics units (from &9006) |
| `ADVAL(9)` | **Device mode**, not buttons: 0 mouse or trackerball, &20 keys, &40 digital, &80 joystick (X from &9031, Y = 0) |

The pointer starts at 640, 512. Each axis moves 4 graphics units per
counted edge. The limits it enforces are fixed in the code; nothing else
in the 6 KB build reads the `*TMAX` values (inferred).

### Buttons

PMFS has no INKEY numbers and no OSWORD. When a button has been pressed
for two 100 Hz polls, it puts a key in the keyboard buffer with OSBYTE
&99:

| Button | Key |
|---|---|
| Left | RETURN (&0D) |
| Right | &C0 |
| Middle | The TAB key's code, read with OSBYTE &DB |

A routine at &87B2 packs the buttons into X but is never called, so it
looks like dead code (inferred).

### Hooks and hardware

**Service calls:**

| Call | Use |
|---|---|
| &04 | Commands |
| &07 | OSBYTE &A3 with X=&F3: sets or steps the pointer and palette colours |
| &15 | Polling, turned on with OSBYTE &16 and off with &17. It moves the pointer for the joystick, digital and keys modes, reads the buttons and redraws the pointer |
| &27 | Reset clears its state |

**Vectors:**
- **BYTEV:** an extended vector, set up with OSBYTE &A8.
- **IRQ1V:** a trampoline at &0D99 calls extended vector 2 (handler &87E4)
  and then jumps to the old IRQ1V, saved at &0D9D.

**Hardware:**
- **When turned on,** it sets the User VIA so that CB1 and CB2 interrupt
  on falling edges: the PCR, the ACR, the IER (&98) and DDRB = 0 (all
  inputs).
- **Movement:** each CB1 interrupt moves X by 4 and each CB2 interrupt
  moves Y by 4. A port B bit read at the edge gives the direction. Only
  one edge is counted, so one count per quadrature cycle (inferred).
- **Two pinouts,** chosen automatically from a table at &8B36:

  | Pinout | X direction | Y direction | Buttons |
  |---|---|---|---|
  | AMX user port | PB0 | PB2 | PB5-PB7 |
  | Compact | PB3 | PB4 | PB0-PB2 |

- **Any mouse interrupt in another mode** switches to mouse mode and
  recentres the pointer.

MOS 5 itself sets the User VIA IER to &98 (CB1 and CB2) at reset but has
no handler for those interrupts. All mouse handling is PMFS's.

### How the Welcome software uses it

| Program | Uses |
|---|---|
| `WELCOME.Menu` | Reads `ADVAL(7)` and `ADVAL(8)`; shows and hides the pointer with `*POINTER` and `*POINTER 0`; also uses `*POINTER 2` |
| `WELCOME.Menu` | Waits for `GET=13 OR (ADVAL(0) AND 7)<>0`, i.e. RETURN from the left button or a button bit in `ADVAL(0)` |
| `WIMPS.P.crnw` | Moves the pointer with `*TSET x,y` |
| TimPaint | Detects a mouse with `IF ADVAL(9)=0`, then reads `ADVAL(7)` and `(8)` |
| TimPaint | Otherwise reads the joystick with `ADVAL(1)` and `(2)`, X reversed: `1276-ADVAL(1)*5 DIV 256` |
| TimPaint | Fire is `ADVAL(0) AND 1` |

With the Compact pinout the mouse buttons are on PB0-PB2. The MOS digital
joystick routine reads those lines too, so a mouse button probably also
shows in `ADVAL(0)` as fire (inferred).

### PMFS and SPItFIRE

PMFS cannot run with SPItFIRE, because:
- it makes port B all inputs, which releases SPItFIRE's chip select lines;
- it counts CB1 edges, and the turbo SPI clock drives CB1.

For Welcome-era software to work with a SPItFIRE mouse, the SPItFIRE ROM
must offer PMFS's interface itself:
- `ADVAL(5)`-`(8)`;
- `*POINTER`, `*TSET` and `*TMAX`;
- the buttons as keys in the keyboard buffer.

Its `ADVAL(9)` conflicts with the JGH and AMX convention, but mildly.
Software that tests `ADVAL(9)=0` for "mouse mode" also sees 0 from a
driver that returns buttons, as long as no button is held.

## More than two joysticks

No precedent was found on any Acorn MOS:

| Source | What it supports |
|---|---|
| **Mertec Compact Companion** | Four ADC channels, so two joysticks, as `ADVAL(1)`-`(4)`. Its spec says it uses IND3V/XBYTEV and BYTEV to intercept OSBYTE 16, 17 and 128, "i.e. ADVAL(n) where n=1..4", and polls two fire buttons every centisecond ([Mertec spec][mertec-spec]) |
| **RISC OS** | Joysticks 0 and 1 through `ADVAL(0)`-`(4)`; more only through the Joystick module's `Joystick_Read` SWI |
| **Acorn Application Note 021** | Four channels, two joysticks (`docs/datasheets/acorn-application-note-021-connecting-joysticks.pdf`) |

## Delta 14B keypads

The Voltmace Delta 14B/1 interface read the 14B keypads through the User
VIA (port B, with PB7 choosing the handset). No OS call ever existed for
them. Software scanned the hardware itself or used Voltmace's driver
generators:
- **KEYPAD** puts keys in the keyboard buffer every vsync.
- **JOYSTIK** answers `INKEY(-key)` through BYTEV.

See the annotated disassemblies at
[acornaeology.uk/voltmace-delta14b-driver][voltmace-driver]. Mark Moxon's
Delta 14B version of Elite-A ([`b_14`][elite-b14]) also scans the matrix
directly, one button per call.

[mos-disassembly]: https://github.com/tom-seddon/acorn_mos_disassembly
[mdfs-osbyte80]: https://mdfs.net/Docs/Comp/BBC/Osbyte80
[mdfs-oswords]: https://mdfs.net/Docs/Comp/BBC/Oswords
[mdfs-mouse]: https://mdfs.net/Info/Comp/BBC/Mouse/
[rommouse]: https://mdfs.net/Software/CommandSrc/Mouse/ROMMouse.src
[beebwiki-adval]: https://beebwiki.mdfs.net/ADVAL
[beebwiki-osbyte80]: https://beebwiki.mdfs.net/OSBYTE_%2680
[riscos-osbyte128]: https://riscosopen.org/wiki/documentation/source/OS_Byte%20128
[mertec-spec]: https://chrisacorns.computinghistory.org.uk/docs/Mertec/Mertec_CompactCompSpec.pdf
[stardot-welcome]: https://stardot.org.uk/forums/viewtopic.php?t=33348
[oaknut]: https://rob-smallshire.github.io/oaknut/disc/install.html
[voltmace-driver]: https://acornaeology.uk/voltmace-delta14b-driver/
[elite-b14]: https://elite.bbcelite.com/elite-a/flight/subroutine/b_14.html
