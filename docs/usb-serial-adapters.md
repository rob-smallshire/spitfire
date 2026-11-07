# USB Serial Adapters on macOS

We use a **CP2102 USB-to-TTL module** (Silicon Labs CP2102) for the AVR's
USART0, in place of the FTDI adapter used early in the project.

## The FTDI problem

The original adapter was a SparkFun FTDI Basic Breakout (FT232R). On macOS
Sequoia, standard tools such as `picocom`, `screen` and `cat` hung the
terminal when they opened its port.

Since macOS moved serial drivers out of the kernel, FTDI chips are handled
by Apple's DriverKit extension `com.apple.DriverKit-AppleUSBFTDI.dext`, a
user-space replacement for the old `AppleUSBFTDI` kext. The hangs came from
that driver, not from our hardware or firmware.

The workaround was **Serial 2** (Decisive Tactics, Mac App Store), which
includes its own FTDI driver. It worked, but it ties you to one app, and
our Python tools (`firmware/tools/serread.py`) can't use it. FTDI's own
DriverKit VCP driver (`com.ftdi.vcp.dext`) is also installed on the
development Mac; its effect on the hangs isn't recorded.

## The CP2102 alternative

The CP2102 works with no extra drivers installed. macOS matches it with
Apple's built-in `com.apple.DriverKit-AppleUSBSLCOM` driver, and it works with
ordinary tools such as pyserial and our `serread.py`.

| | |
|---|---|
| USB ID | `10c4:ea60` (Silicon Laboratories) |
| Device node | `/dev/cu.usbserial-0001` (from the chip's serial number, `0001`) |
| Driver | `com.apple.DriverKit-AppleUSBSLCOM` (built in) |
| Verified on | macOS 15.7.3 |

Example:

```bash
picocom -b 115200 /dev/cu.usbserial-0001
python3 firmware/tools/serread.py /dev/cu.usbserial-0001 2 3
```

## Wiring

The firmware uses 115200 8N1. At 18.432 MHz that rate has an exact divisor
(UBRR = 9, 0% error). Cross TX and RX between the adapter and the AVR:

| CP2102 | SPItFIRE Peripheral DE-9 (J13) | AVR |
|---|---|---|
| TXD | pin 1 | RXD0 (PD0) |
| RXD | pin 2 | TXD0 (PD1) |
| GND | pin 8 | GND |

Leave the module's 5V/3V3 pins unconnected when the board has its own
power.
