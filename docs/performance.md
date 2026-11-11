# SPI Performance

Ideas for reducing the 6502's cost of talking to the AVR, especially the
ROM's 50 Hz joystick poll, which runs in the interrupt. Option 1 turned
out to be in place already; the others are for later.

## Where the time goes

All SPI to the AVR is bit-banged: the 6502 makes every clock edge itself,
and the VIA's shift register, clocked by CB1 (tied to SCK, PB1), collects
MISO. The VIA is a 1 MHz device, so each access stretches the 2 MHz
6502's cycle.

There are two loops. The general one for commands (`spi_xfer0` in
`beeb/rom/src/spi.asm`) makes three VIA accesses a bit and shifts the
outgoing byte: about 35-40 cycles a bit. The joystick poll's receive
loop (`joy_receive` in `joystick.asm`) is already receive-only: once the
command is sent, each bit is two writes to IORB, unrolled, about 130-150
cycles a byte with the call and the store.

| | Measured |
|---|---|
| The first ROM's poll (command and 6 bytes) | About 0.7 ms every 20 ms, 3.5% of the CPU (`rom-design.md`) |
| SPIPERF, bit-bang loop | 4,147 bytes/s on Rev 1, 4,139 on Rev 2 |
| SPITPERF, turbo loop | 7,388 bytes/s on Rev 1, 7,371 on Rev 2 |

The JOY_ALL burst ([protocol.md](protocol.md)) is up to 22 bytes: about
9-10% of the CPU at 50 Hz with the receive-only loop, about 5% for two
joysticks.

## 1. A receive-only loop (done)

After the command byte MOSI does not matter, so the 6502 only has to
toggle SCK. The joystick poll already works this way. Commands
(`*SPITFIRE ...`) still use the general loop, which does not matter for
a byte or two.

## 2. The VIA generating the clock

In shift register mode 2 (shift in under φ2 control) the VIA clocks 8 bits
out on CB1 at 500 kHz with no CPU involvement: about 16 µs a byte. CB1
would drive SCK, with PB1 made an input, since the two are tied. A 20-byte
burst might then cost well under 1 ms, about 2-3% of the CPU.

Risks to test first, with a SPIPERF-style program on the Compact:
- **The AVR keeping up.** An SPI slave has no transmit buffer: the AVR must
  load SPDR in the gap between bytes, a few microseconds, from a prepared
  burst. At 18.432 MHz in a tight loop it should manage.
- **Leaving the VIA as it was found.** The poll already saves and restores
  the ACR, because MMFS uses the shift register too; mode 2 must be undone
  as carefully, and PB1's direction restored.

## 3. Polling less often

For example, joystick 1 at 50 Hz and joysticks 3 and 4 at 25 Hz, or the
whole burst at 25 Hz. Simple, at the price of latency.
