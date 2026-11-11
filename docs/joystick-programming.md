# Programming SPItFIRE Joysticks

How a program on a BBC Master Compact detects SPItFIRE, finds out which
joysticks are plugged in, and reads them, from BBC BASIC or 6502 assembly
language. This is the interface the SPItFIRE ROM provides; other projects
can implement joystick support against it.

It covers ordinary analogue joysticks and the Voltmace Delta 3B Single,
3B Twin and 14B. Acorn Bitstik and Microwriter Quinkey support will be
documented later.

## At a glance

| To | BASIC | 6502 |
|---|---|---|
| Detect SPItFIRE | OSWORD &3F, byte 0 becomes `&53` | The same |
| Read joystick *j*'s X, Y | `ADVAL(x)`, `ADVAL(x+1)`, with x = 1, 3, 17, 19 for j = 1-4 | OSBYTE &80, X = channel; result in X (low), Y (high) |
| Read fire buttons | `ADVAL(0) AND 3` (joysticks 1, 2), `ADVAL(16) AND 3` (3, 4) | OSBYTE &80, X = 0 or 16; bits 0 and 1 of X |
| Read every joystick digitally (directions and fire) | `ADVAL(12)` (joysticks 1, 2), `ADVAL(28)` (3, 4): a switch byte each, low byte first | OSBYTE &80, X = 12 or 28; X = odd joystick, Y = even |
| Read a 14B keypad | `ADVAL(10)`, `(11)`, `(26)`, `(27)` for joysticks 1-4 | OSBYTE &80, X = 10, 11, 26 or 27 |

Joysticks 1 and 2 behave exactly as on a BBC Micro with an analogue port,
so existing two-player software works unchanged.

## Requirements

- A Master Compact (MOS 5.x) with SPItFIRE connected to its joystick port.
- The SPItFIRE ROM (version 0.02 or later) in a sideways ROM or RAM bank.
- After loading the ROM into sideways RAM with `*SRLOAD`, press
  **Ctrl-Break**. The ROM claims its workspace only at a hard reset; until
  then the joystick commands say `Press Ctrl-Break to start SPItFIRE` and
  OSWORD &3F reports no workspace (below).
- `*SPITFIRE JOYSTICK` must report `Joystick on` (the default after every
  reset).

## Concepts

### Ports and port types

SPItFIRE has two analogue joystick ports, **Port A** and **Port B** (DA-15
sockets, wired like the BBC Micro's analogue port). Each port is set to a
**type**, saved in SPItFIRE's own memory, so the setting survives power
cycles. The user sets it with:

```
*SPITFIRE JOYSTICK PORT A|B <type>
```

| Type number | Keyword | Hardware | Joysticks it provides |
|---|---|---|---|
| 0 | `NONE` | Nothing plugged in | 0 |
| 1 | `SINGLE` | An ordinary single joystick (two axes, one button) | 1 |
| 2 | `DUAL` | Two ordinary joysticks on one socket | 2 |
| 3 | `3BS` | Voltmace Delta 3B Single | 2 (see below) |
| 4 | `3BT` | Voltmace Delta 3B Twin | 2 |
| 5 | `14B` | Voltmace Delta 14B | 1, with a keypad |
| 6 | `BITSTIK` | Acorn Bitstik | (documented later) |
| 7 | `QUINKEY` | Microwriter Quinkey | (documented later) |

The defaults are Port A `DUAL` and Port B `NONE`.

A port left set to a joystick type with nothing plugged in gives readings
that drift around the middle of the range; it is up to the user to set
unused ports to `NONE`. A program cannot tell an empty port from a
joystick at rest.

### Joysticks 1-4

SPItFIRE numbers the joysticks 1 to 4 by **allocating** them from the two
ports in order: Port A's joysticks first, then Port B's. A program never
needs to know which port a joystick is on; it asks for joystick 1, 2, 3 or
4.

| Port A | Port B | Joystick 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| `SINGLE` | `NONE` | A | | | |
| `NONE` | `SINGLE` | B | | | |
| `SINGLE` | `SINGLE` | A | B | | |
| `3BT` | `NONE` | A (left handset) | A (right handset) | | |
| `14B` | `14B` | A | B | | |
| `3BT` | `SINGLE` | A (left) | A (right) | B | |
| `3BT` | `3BT` | A (left) | A (right) | B (left) | B (right) |

At most four joysticks can be allocated.

### The channel map

Each joystick has an X and a Y channel, a fire bit, a switch byte (fire
and directions) and, for a 14B, a keypad channel. Joysticks 3 and 4
repeat the layout of joysticks 1 and 2 sixteen channels up.

| Joystick | X | Y | Fire | Switch byte | Keypad |
|---|---|---|---|---|---|
| 1 | `ADVAL(1)` | `ADVAL(2)` | `ADVAL(0)` bit 0 | `ADVAL(12)` low byte | `ADVAL(10)` |
| 2 | `ADVAL(3)` | `ADVAL(4)` | `ADVAL(0)` bit 1 | `ADVAL(12)` high byte | `ADVAL(11)` |
| 3 | `ADVAL(17)` | `ADVAL(18)` | `ADVAL(16)` bit 0 | `ADVAL(28)` low byte | `ADVAL(26)` |
| 4 | `ADVAL(19)` | `ADVAL(20)` | `ADVAL(16)` bit 1 | `ADVAL(28)` high byte | `ADVAL(27)` |

- **Unallocated channels read 0**, as do fire bits and keypads that nothing
  is allocated to. A Master Compact with no joystick also reads 0 for
  `ADVAL(1)`.
- **Channels 5-9 are left to mouse drivers**, and are not SPItFIRE's.
- Values are refreshed 50 times a second. Reading more often returns the
  same value; reading costs only the OSBYTE call (no hardware access).

## Detecting SPItFIRE

Use OSWORD &3F. Without the SPItFIRE ROM, nothing claims the call and the
parameter block comes back unchanged, so a program puts 0 in byte 0, makes
the call, and checks for `&53` ("S").

Do not try to detect SPItFIRE through `ADVAL`: without the ROM, MOS 5
answers every channel above 0 with a copy of `ADVAL(1)` or `ADVAL(2)`, so
an extra channel cannot be told from a real one.

### The OSWORD &3F block

On entry, byte 0 is the reason code: 0 = describe the joysticks. The block
is 11 bytes; allow 16. Other reason codes are reserved and not claimed.

| Byte | On exit |
|---|---|
| 0 | `&53`: SPItFIRE answered (unchanged, 0, if not) |
| 1 | API version: 1 |
| 2 | Port A's type (0-7) |
| 3 | Port B's type (0-7) |
| 4 | n: the number of joysticks allocated (0-4) |
| 5 | Keypad mask: bit j-1 set if joystick j has a keypad |
| 6-9 | Joysticks 1-4: bit 7 = port (0 = A, 1 = B), bits 0-2 = the port's type; `&FF` if not allocated |
| 10 | Flags: bit 0 = no workspace (the user must press Ctrl-Break); bit 1 = the SPItFIRE hardware did not answer |

If either flag is set, n is 0 and no joystick is allocated. Bits 3-6 of
bytes 6-9 are 0.

### BASIC

```
10 DIM B% 15
20 ?B%=0:A%=&3F:X%=B% MOD 256:Y%=B% DIV 256:CALL &FFF1
30 IF ?B%<>&53 PRINT "No SPItFIRE":END
40 IF B%?10 AND 1 PRINT "Press Ctrl-Break to start SPItFIRE":END
50 IF B%?10 AND 2 PRINT "SPItFIRE hardware not responding":END
60 N%=B%?4
70 PRINT "Joysticks: ";N%
80 FOR J%=1 TO N%
90   D%=B%?(5+J%)
100  IF D% AND &80 THEN P$="B" ELSE P$="A"
110  PRINT "Joystick ";J%;": port ";P$;", type ";D% AND 7;
120  IF B%?5 AND 2^(J%-1) THEN PRINT ", keypad" ELSE PRINT
130 NEXT
```

### 6502

```
OSWORD = &FFF1

.detect
    LDA #0
    STA block               ; Reason code 0
    LDA #&3F
    LDX #LO(block)
    LDY #HI(block)
    JSR OSWORD
    LDA block
    CMP #&53
    BNE no_spitfire         ; Nothing answered
    LDA block+10
    BNE not_ready           ; Needs Ctrl-Break, or hardware not answering
    LDA block+4             ; n, the joysticks allocated
    ...

.block
    SKIP 16
```

## Reading joysticks

### Positions

`ADVAL(c)` returns a 16-bit value, 0 to 65535. SPItFIRE reads each axis
with 10 bits of resolution, spread across the full 16-bit range: 0 is one
end, 65535 the other, and about 32768 the centre.

The direction follows the Acorn convention, as on a BBC Micro:

| Axis | High values | Low values |
|---|---|---|
| X | Left | Right |
| Y | Up | Down |

So, for a screen position, invert X: `(65535 - ADVAL(1)) DIV 64` gives
0-1023 left to right.

Real joysticks rarely reach exactly 0 or 65535, and their centre varies
from handset to handset; allow a dead zone around the centre and do not
rely on reaching the extremes.

### Fire buttons

`ADVAL(0)` and `ADVAL(16)` return the fire buttons of joysticks 1 and 2,
and 3 and 4, in their low byte. 1 means pressed.

| Bit | `ADVAL(0)` | `ADVAL(16)` |
|---|---|---|
| 0 | Joystick 1 fire | Joystick 3 fire |
| 1 | Joystick 2 fire | Joystick 4 fire |
| 4 | Joystick 1 left | Joystick 3 left |
| 5 | Joystick 1 down | Joystick 3 down |
| 6 | Joystick 1 up | Joystick 3 up |
| 7 | Joystick 1 right | Joystick 3 right |

Bits 2 and 3 are 0. The direction bits are set when the stick is more
than a quarter of full scale from the centre. They are where the
Compact's own digital joystick reports its directions, so software
written for that works with a SPItFIRE joystick 1. For directions from
every joystick, use the switch bytes (below).

The **high byte of `ADVAL(0)`** is not a button: as on every BBC, it is the
analogue-to-digital converter's current channel. Mask it off with
`AND 255` (or use the X register only). The high byte of `ADVAL(16)` is 0.

### Switch bytes: every joystick as a digital joystick

`ADVAL(12)` and `ADVAL(28)` give each joystick's fire button and
directions in one byte, its **switch byte**:

| Channel | Low byte | High byte |
|---|---|---|
| `ADVAL(12)` | Joystick 1 | Joystick 2 |
| `ADVAL(28)` | Joystick 3 | Joystick 4 |

| Bit | Value | Meaning |
|---|---|---|
| 0 | 1 | Fire |
| 4 | 16 | Left |
| 5 | 32 | Down |
| 6 | 64 | Up |
| 7 | 128 | Right |

Bits 1-3 are 0. This is the layout of `ADVAL(0)`'s low byte for joystick
1, so code that decodes joystick 1 from `ADVAL(0)` decodes any switch
byte unchanged. A direction is set when the stick is more than a quarter
of full scale from the centre, the same threshold as `ADVAL(0)`; two
adjacent directions together are a diagonal. A joystick that is not
allocated has a switch byte of 0.

Two calls read four joysticks: a game that treats its players as
eight-way digital joysticks needs nothing else, and every program that
uses the switch bytes agrees on what counts as "up".

### Delta 3B Twin (`3BT`) and Dual (`DUAL`)

Two independent joysticks. On a 3B Twin, the left handset is the port's
first joystick and the right handset its second; each handset's button is
that joystick's fire.

### Delta 3B Single (`3BS`)

The 3B Single's one stick is wired to both channel pairs, so it appears
as **two joysticks that move together**. Its three buttons are wired as
two fire buttons: the two buttons on one side are the first joystick's
fire, the single button is the second joystick's fire. This lets one 3B
Single act as either player in a two-player game, or give one player two
fire buttons (`ADVAL(0) AND 1` and `ADVAL(0) AND 2`).

A user who wants a 3B Single to be just one joystick sets the port to
`SINGLE`; it then takes one slot, and its single button is not read.

### Delta 14B (`14B`)

One joystick and a 12-key keypad. The keypad is read from the joystick's
keypad channel (`ADVAL(10)` for joystick 1, and so on); bit *n* is 1 while
key *n* is pressed. Bits 12-15 are 0.

```
Top     [ 9] [10] [11]
        [ 6] [ 7] [ 8]
        [ 3] [ 4] [ 5]
Bottom  [ 0] [ 1] [ 2]
```

The two buttons on the side of the handset are wired to key 10. **Key 10
is also the joystick's fire button**, so a 14B works as a one-button
joystick in software that knows nothing of keypads: pressing key 10 or
either side button sets the fire bit, and also bit 10 of the keypad
channel.

Several keys can be held at once, and each sets its own bit. SPItFIRE
has been tested with single keys; the keypad is a 3 x 4 matrix, and
whether some combinations of three or more keys make an unpressed key
appear pressed depends on the handset's wiring, which is not known.
Software that relies on chords should test the combinations it uses.

On a BBC Micro's analogue port, a 14B (without the 14B/1 interface)
reported keys 9-11 as one fire button and 6-8 as another. SPItFIRE gives
each joystick one fire bit instead; the full keypad is in the keypad
channel.

## Examples

### BASIC: helper functions

```
1000 DEF FNx(J%)=ADVAL(J%*2-1-12*(J%>2))
1010 DEF FNy(J%)=ADVAL(J%*2-12*(J%>2))
1020 DEF FNfire(J%)=(ADVAL(-16*(J%>2)) AND (2+(J% MOD 2=1)))<>0
1030 DEF FNkeys(J%)=ADVAL(9+J%-14*(J%>2))
1040 DEF FNkey(J%,K%)=(FNkeys(J%) AND 2^K%)<>0
1050 DEF FNsw(J%)=ADVAL(12-16*(J%>2)) DIV (1-255*(J% MOD 2=0)) AND 255
```

In BBC BASIC a true comparison is -1, so `-12*(J%>2)` adds 12 for
joysticks 3 and 4, and `2+(J% MOD 2=1)` is 1 for odd joysticks and 2 for
even ones. `FNfire` and `FNkey` return TRUE or FALSE. `FNsw` returns the
switch byte: the low byte of `ADVAL(12)` or `(28)` for odd joysticks, the
high byte for even ones.

### BASIC: four digital joysticks

```
10 REPEAT
20   S%=ADVAL(12):T%=ADVAL(28)
30   PRINT TAB(0,0);
40   PROCsw(1,S% AND 255):PROCsw(2,S% DIV 256)
50   PROCsw(3,T% AND 255):PROCsw(4,T% DIV 256)
60 UNTIL FALSE
70 DEF PROCsw(J%,W%)
80 PRINT "Joystick ";J%;" ";
90 IF W% AND 16 PRINT "L"; ELSE PRINT " ";
100 IF W% AND 128 PRINT "R"; ELSE PRINT " ";
110 IF W% AND 64 PRINT "U"; ELSE PRINT " ";
120 IF W% AND 32 PRINT "D"; ELSE PRINT " ";
130 IF W% AND 1 PRINT " Fire" ELSE PRINT "     "
140 ENDPROC
```

### BASIC: show every joystick

```
10 DIM B% 15
20 ?B%=0:A%=&3F:X%=B% MOD 256:Y%=B% DIV 256:CALL &FFF1
30 IF ?B%<>&53 OR B%?10 PRINT "SPItFIRE not ready":END
40 N%=B%?4:K%=B%?5
50 CLS
60 REPEAT
70   PRINT TAB(0,0);
80   FOR J%=1 TO N%
90     PRINT "Joystick ";J%;"  X ";FNx(J%);"  Y ";FNy(J%);"  Fire ";-FNfire(J%);"   "
100    IF K% AND 2^(J%-1) PRINT "  Keys ";~FNkeys(J%);"    "
110  NEXT
120 UNTIL FALSE
```

with the functions above appended.

### BASIC: a 14B keypad as twelve buttons

```
10 REPEAT
20   K%=ADVAL(10)
30   FOR N%=0 TO 11
40     IF K% AND 2^N% PRINT N%;" ";
50   NEXT
60   PRINT
70 UNTIL FALSE
```

### 6502: read a channel

OSBYTE &80 with X = the channel returns the value in X (low byte) and Y
(high byte), exactly as BASIC's `ADVAL`.

```
OSBYTE = &FFF4

; Read joystick 1's X into xpos (2 bytes)
    LDA #&80
    LDX #1
    JSR OSBYTE
    STX xpos
    STY xpos+1

; Joystick 2's fire button: Z clear if pressed
    LDA #&80
    LDX #0
    JSR OSBYTE
    TXA
    AND #2

; Joystick 1's 14B keypad into keys (2 bytes)
    LDA #&80
    LDX #10
    JSR OSBYTE
    STX keys
    STY keys+1
```

### 6502: four digital joysticks

```
; The switch bytes of joysticks 1-4 into sw (4 bytes)
    LDA #&80
    LDX #12
    JSR OSBYTE
    STX sw                  ; Joystick 1
    STY sw+1                ; Joystick 2
    LDA #&80
    LDX #28
    JSR OSBYTE
    STX sw+2                ; Joystick 3
    STY sw+3                ; Joystick 4

; Then for joystick j (index 0-3 in X), the same code for every player
    LDA sw, X
    AND #&10                ; Left; &20 down, &40 up, &80 right, 1 fire
```

The channel for joysticks 3 and 4 is the joystick 1 and 2 channel with
bit 4 set (`ORA #16`): X 17, Y 18, fire 16, keypad 26 for joystick 3.

### 6502: a channel table

```
; By joystick 1-4 (index 0-3)
.x_channel      EQUB 1, 3, 17, 19
.y_channel      EQUB 2, 4, 18, 20
.fire_channel   EQUB 0, 0, 16, 16
.fire_mask      EQUB 1, 2, 1, 2
.switch_channel EQUB 12, 12, 28, 28     ; Low byte for 1 and 3, high for 2 and 4
.keypad_channel EQUB 10, 11, 26, 27
```

## Behaviour to rely on

- **Joysticks 1 and 2 are the BBC's.** `ADVAL(0)`-`(4)` behave as on a BBC
  Micro with an analogue port, so existing software needs no change for
  two players.
- **The MOS's ADC behaviour is kept.** Event 3 (ADC conversion complete)
  is raised every centisecond, and the high byte of `ADVAL(0)` steps
  through the channels as `*FX16` and `*FX17` set them. Software that
  waits for a conversion works.
- **`*FX16,0` stops all joystick updates**, and `*FX190,<n>` without a
  mask turns SPItFIRE off. See "MOS 5 joystick options".
- **Other drivers keep working.** SPItFIRE answers only the channels in
  the map and passes every other OSBYTE call, and every other `ADVAL`
  channel (including negative ones, the buffer counts), to whatever was
  there before.

## MOS 5 joystick options

MOS 5 has its own handling for the Compact's digital joystick port, set
up by `*CONFIGURE` options and the joystick byte (`*FX190`, OSBYTE &BE).
SPItFIRE takes over by setting bit 7 of the joystick byte at every reset;
the MOS then hands its whole joystick routine to the SPItFIRE ROM (service
call &2C) instead of running its own. What follows is from the MOS 5.00
code, and the joystick-as-keys behaviour has been checked on a Compact.

| MOS option | With SPItFIRE |
|---|---|
| `*CONFIGURE PROPORTIONAL`, `SWITCHED`, `STICK <n>` | **No effect.** They configure how the MOS turns digital switches into analogue values, code that is skipped while SPItFIRE has the joystick. `*STATUS` says so. They stay in the CMOS settings and apply again if SPItFIRE is turned off |
| `*FX190` (OSBYTE &BE), the joystick byte | Bit 7 is SPItFIRE's on/off (`*SPITFIRE JOYSTICK ON\|OFF`). **Writing the whole byte**, as `*FX190,<n>` does, clears bit 7 unless n includes it, which turns SPItFIRE off (below). To change other bits, keep bit 7 with a mask: OSBYTE &BE sets the byte to (old AND Y) EOR X, so `*FX190,64,191` sets bit 6 alone |
| `*FX190,64` (bit 6): the joystick types cursor keys and COPY | **Works, from joystick 1.** This part of the MOS routine runs before the hand-over, from `ADVAL(0)`'s switch byte, which SPItFIRE fills: joystick 1's directions type the cursor keys, and either fire bit (joystick 1 or 2) types COPY, with the keyboard's auto-repeat. Use it with bit 7 kept: `*FX190,64,191` |
| `*FX4,3`: the cursor keys and COPY act as a joystick | **No effect.** The MOS reads these keys only in the part of its routine that is skipped. A program that wants keyboard control alongside SPItFIRE must read the keys itself |
| `*FX16,<n>` (number of ADC channels) | `*FX16,0` stops all joystick updates: the MOS then never calls SPItFIRE. Any other value sets how far the high byte of `ADVAL(0)` counts |
| `*FX17,<n>` (start a conversion) | Sets the high byte of `ADVAL(0)`, as without SPItFIRE |
| `*FX14,3` / `*FX13,3` (enable / disable event 3) | Event 3 is raised every centisecond, as without SPItFIRE |

### Turning SPItFIRE off

`*SPITFIRE JOYSTICK OFF` (or anything that clears bit 7 of the joystick
byte) gives the joystick back to the MOS until the next reset, when the
ROM takes it again. While off:

- `ADVAL(0)`-`(2)` come from the MOS's own routine, which reads the
  joystick port's lines. With SPItFIRE connected those lines are its SPI
  bus, so the values are meaningless.
- The other channels (3, 4, 10-12, 16-20, 26-28) keep their last values:
  SPItFIRE still answers them but no longer updates them.
- OSWORD &3F still describes the configured joysticks.

A program should not turn SPItFIRE off; if it must change the joystick
byte, it should keep bit 7.

## Checking from the command line

| Command | Shows |
|---|---|
| `*SPITFIRE JOYSTICK` | The port types and which joysticks they provide |
| `*SPITFIRE ADVAL` | Every channel in use, what it carries, its port and its current value |
| `*SPITFIRE ADVAL ALL` | The same for every channel in the map, unused ones too |
| `*STATUS` | The joystick settings, after the MOS's |

For example, with a Delta 3B Twin on Port A and a single joystick on
Port B:

```
>*SPITFIRE JOYSTICK
Joystick on
Port A: Voltmace Delta 3B Twin
        Joysticks 1, 2
Port B: Standard single joystick
        Joystick 3
>*SPITFIRE ADVAL
Ch Use               Port Value
 0 Fire 1, 2         A    &00
 1 Joystick 1 X      A    33024
 2 Joystick 1 Y      A    32640
 3 Joystick 2 X      A    31872
 4 Joystick 2 Y      A    33408
16 Fire 3            B    &00
17 Joystick 3 X      B    32896
18 Joystick 3 Y      B    32512
```

## See also

- [rom-design.md](rom-design.md): how the ROM implements this, in
  "Module: Joystick".
- [protocol.md](protocol.md): the SPI protocol between the ROM and the
  SPItFIRE hardware, which programs do not need.
- [adval-and-mouse-conventions.md](adval-and-mouse-conventions.md): ADVAL
  conventions on Acorn machines and mouse drivers.
