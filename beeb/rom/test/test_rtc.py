"""Regression test for the SPItFIRE ROM's RTC module, run on a 6502 emulator.

Assembles the ROM, then calls its service call &08 handler (rtc_osword) for
OSWORD &0E (read clock) and &0F (write clock) on py65, with a model DS3234
that decodes the bit-banged SPI from the User VIA port B writes. So the
parsing, weekday arithmetic, BCD formatting and the SPI code all run.

Checks:
- set and read back through subcalls 0 and 1, and length 8/15/24 writes
- the weekday for every date in a sample of 2000-2199, against Python's
  calendar, including the century bit and 2100 not being a leap year
- invalid OSWORD &0F data is passed on and changes nothing
- subcall 2 conversion, and calls the ROM must leave alone (&0E,3/4 etc.)
- reads pass on when the oscillator stop flag is set or a field is out of
  range; no call is claimed when no DS3234 is fitted (MISO high, low, noise)
- every call restores &A8-&AF, the stack and the SRAM address register,
  and leaves the decoder on Y7 (no device) with SCK high

Run from beeb/rom with `make test`, or:
    uv run --with py65 python test/test_rtc.py
"""
import ast, datetime, pathlib, random, subprocess, sys, tempfile
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 6502)

ROM_DIR = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as tmp:
    image = pathlib.Path(tmp) / "SPITFIRE"
    result = subprocess.run(["beebasm", "-i", "src/main.asm", "-o", str(image), "-d"],
                            cwd=ROM_DIR, capture_output=True, text=True)
    if result.returncode or not image.exists():
        sys.exit(f"beebasm failed:\n{result.stdout}{result.stderr}")
    rom = image.read_bytes()
# beebasm -d prints the symbol table as a Python 2 style dict (longs end in L)
syms = ast.literal_eval(result.stdout.strip().replace("L,", ",").replace("L}", "}"))[0]

IORB, SR = 0xFE60, 0xFE6A

class DS3234:
    def __init__(self):
        self.regs = bytearray(0x1A)
        self.iorb = 0xFF; self.sr = 0; self.cs = False
        self.absent = None      # None, or "high", "low", "noise": MISO floats
    def write_iorb(self, addr, v):
        prev, self.iorb = self.iorb, v
        cs = ((v >> 2) & 7) == 3
        if not cs:
            self.cs = False; return
        if not self.cs:
            assert prev & 2, "RTC selected with SCK low"
            self.cs = True; self.addr = None; self.bits = 0; self.shift = 0
        if (v & 2) and not (prev & 2):
            self.shift = ((self.shift << 1) | (v & 1)) & 0xFF
            self.bits += 1
            if self.bits == 8:
                self.bits = 0
                if self.addr is None:
                    self.addr = self.shift & 0x7F; self.writing = bool(self.shift & 0x80)
                    self.sr = 0xFF
                else:
                    if self.absent:
                        pass
                    elif self.writing:
                        self.regs[self.addr] = self.shift
                    else:
                        self.sr = self.regs[self.addr]
                    self.addr = (self.addr + 1) % len(self.regs)
    def read_iorb(self, addr): return self.iorb
    def read_sr(self, addr):
        if self.absent == "high": return 0xFF
        if self.absent == "low": return 0x00
        if self.absent == "noise": return random.randrange(256)
        return self.sr

def machine():
    mem = ObservableMemory()
    rtc = DS3234()
    mem.subscribe_to_write([IORB], rtc.write_iorb)
    mem.subscribe_to_read([IORB], rtc.read_iorb)
    mem.subscribe_to_read([SR], rtc.read_sr)
    mpu = MPU(memory=mem)
    mem[0x8000:0x8000 + len(rom)] = rom
    mem[0x0400:0x0404] = [0x20, syms["rtc_osword"] & 0xFF, syms["rtc_osword"] >> 8, 0x00]
    return mpu, mem, rtc

BLK = 0x0900
def osword(mpu, mem, a, block):
    mem[0xEF] = a; mem[0xF0] = BLK & 0xFF; mem[0xF1] = BLK >> 8
    mem[BLK:BLK + 32] = [0x23] * 32
    mem[BLK:BLK + len(block)] = list(block)
    ws = [random.randrange(256) for _ in range(8)]
    mem[0xA8:0xB0] = ws
    mpu.pc = 0x0400; mpu.sp = 0xFF
    for _ in range(200000):
        mpu.step()
        if mpu.pc == 0x0403:
            break
    else:
        raise RuntimeError("did not return")
    assert list(mem[0xA8:0xB0]) == ws, "workspace &A8-&AF not restored"
    assert mpu.sp == 0xFF, "stack unbalanced"
    touched = rtc.iorb != 0xFF or mem[0xFE62] != 0
    assert not touched or (rtc.iorb >> 2) & 7 == 7, f"left device {(rtc.iorb >> 2) & 7} selected"
    assert not touched or rtc.iorb & 2, "left SCK low"
    return not (mpu.p & 1), bytes(mem[BLK:BLK + 32])   # claimed?

bcd = lambda n: (n // 10) << 4 | n % 10
DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
MONS = [None] + "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
def acorn(d):  # "Ddd,dd Mon yyyy"
    return f"{DAYS[d.weekday()]},{d.day:02d} {MONS[d.month]} {d.year:04d}"
def weekday_reg(d): return (d.weekday() + 1) % 7 + 1   # 1 = Sunday

fails = 0
def check(cond, msg):
    global fails
    if not cond:
        fails += 1
        if fails < 20: print("FAIL:", msg)

mpu, mem, rtc = machine()

# --- Set date and time (length 24) and read back every way ---
for s in ["Wed,07 Oct 2026.23:59:30", "Sat,01 Jan 2000.00:00:00",
          "Tue,31 Dec 2199.12:34:56", "Mon,01 Mar 2100.07:08:09"]:
    rtc.regs[0x0F] = 0xC8   # OSF set (power-on default)
    ok, _ = osword(mpu, mem, 0x0F, bytes([24]) + s.encode())
    check(ok, f"set {s} not claimed")
    check(rtc.regs[0x0F] == 0x48, f"OSF not cleared: {rtc.regs[0x0F]:02X}")
    ok, out = osword(mpu, mem, 0x0E, [0])
    check(ok and out[:25] == s.encode() + b"\r", f"read 0 after set {s}: {out[:25]!r}")
    d = datetime.datetime.strptime(s[4:], "%d %b %Y.%H:%M:%S")
    ok, out = osword(mpu, mem, 0x0E, [1])
    exp = bytes([bcd(d.year % 100), bcd(d.month), bcd(d.day), weekday_reg(d),
                 bcd(d.hour), bcd(d.minute), bcd(d.second), 0x23])
    check(ok and out[:8] == exp, f"read 1 after set {s}: {out[:8].hex()} != {exp.hex()}")

# --- Weekday and register contents for many dates (length 15) ---
dates = [datetime.date(2000, 1, 1) + datetime.timedelta(n)
         for n in range(0, (datetime.date(2199, 12, 31) - datetime.date(2000, 1, 1)).days + 1)]
sample = [d for d in dates if d.day in (1, 28, 29, 31) or d.year in (2000, 2026, 2100, 2199)]
rtc.regs[0:3] = bytes([0x56, 0x34, 0x12])
for d in sample:
    s = "???," + acorn(d)[4:]           # weekday name ignored
    ok, _ = osword(mpu, mem, 0x0F, bytes([15]) + s.encode())
    exp = bytes([weekday_reg(d), bcd(d.day), bcd(d.month) | (0x80 if d.year >= 2100 else 0),
                 bcd(d.year % 100)])
    check(ok and bytes(rtc.regs[3:7]) == exp, f"date {d}: {bytes(rtc.regs[3:7]).hex()} != {exp.hex()}")
check(bytes(rtc.regs[0:3]) == bytes([0x56, 0x34, 0x12]), "length 15 changed the time")
print(f"{len(sample)} dates checked")

# --- Time only (length 8) leaves the date ---
rtc.regs[3:7] = bytes([4, 0x07, 0x10, 0x26])
ok, _ = osword(mpu, mem, 0x0F, bytes([8]) + b"01:02:03")
check(ok and bytes(rtc.regs[0:7]) == bytes([3, 2, 1, 4, 7, 0x10, 0x26]), f"time only: {bytes(rtc.regs[0:7]).hex()}")
ok, _ = osword(mpu, mem, 0x0F, bytes([15]) + b"xxx,07 oCT 2026")
check(ok and rtc.regs[5] == 0x10, "month name case")

# --- Invalid input is passed on and changes nothing ---
for blk in [b"\x08" + b"24:00:00", b"\x08" + b"12:60:00", b"\x08" + b"12:00:60", b"\x08" + b"1a:00:00",
            b"\x08" + bytes([0x20, 0x26, 0x10, 0x07, 0x04, 0x12, 0x34, 0x56]),   # BCD-with-century form
            b"\x0f" + b"Mon,00 Jan 2026", b"\x0f" + b"Mon,32 Jan 2026", b"\x0f" + b"Mon,29 Feb 2100",
            b"\x0f" + b"Mon,30 Feb 2000", b"\x0f" + b"Mon,29 Feb 2026", b"\x0f" + b"Mon,01 Foo 2026",
            b"\x0f" + b"Mon,01 Jan 1999", b"\x0f" + b"Mon,01 Jan 2200",
            b"\x18" + b"Mon,01 Jan 2026.25:00:00", b"\x18" + b"Mon,01 Jan 2026.12:00:0x",
            b"\x07" + b"1234567", b"\x01S"]:
    before = bytes(rtc.regs)
    ok, _ = osword(mpu, mem, 0x0F, blk)
    check(not ok, f"invalid {blk!r} was claimed")
    check(bytes(rtc.regs) == before, f"invalid {blk!r} changed registers")
for good in [b"\x0f" + b"Tue,29 Feb 2000", b"\x0f" + b"Thu,29 Feb 2024", b"\x0f" + b"Sat,29 Feb 2196"]:
    ok, _ = osword(mpu, mem, 0x0F, good)
    check(ok, f"leap day {good!r} rejected")

# --- Reads pass on when the oscillator has stopped; other calls ignored ---
rtc.regs[0x0F] = 0x88
for sub in (0, 1):
    ok, out = osword(mpu, mem, 0x0E, [sub])
    check(not ok and out[1:] == b"#" * 31, f"OSF set: subcall {sub} claimed")
rtc.regs[0x0F] = 0x08
for a, blk in [(0x0E, [3]), (0x0E, [4]), (0x0E, [9]), (0x0D, [0]), (0x10, [0])]:
    ok, out = osword(mpu, mem, a, blk)
    check(not ok and out[1:] == b"#" * 31, f"OSWORD {a:02X},{blk[0]} claimed or wrote")

# --- Subcall 2 conversion ---
for blk, exp in [([2, 0x26, 0x10, 0x07, 0x04, 0x12, 0x34, 0x56], "Wed,07 Oct 2026.12:34:56"),
                 ([2, 0x99, 0x12, 0x31, 0x06, 0x23, 0x59, 0x59], "Fri,31 Dec 1999.23:59:59"),
                 ([2, 0x26, 0x10, 0x07, 0x00, 0x12, 0x34, 0x56], "   ,07 Oct 2026.12:34:56")]:
    ok, out = osword(mpu, mem, 0x0E, blk)
    check(ok and out[:25] == exp.encode() + b"\r", f"convert {bytes(blk).hex()}: {out[:25]!r}")

# --- SRAM address register restored after every call ---
rtc.regs[0x18] = 0x5A
osword(mpu, mem, 0x0E, [0])
osword(mpu, mem, 0x0F, bytes([8]) + b"01:02:03")
check(rtc.regs[0x18] == 0x5A, f"SRAM address not restored: {rtc.regs[0x18]:02X}")

# --- Present but implausible fields: reads pass on, writes still work ---
good = bytes([0x30, 0x59, 0x23, 0x04, 0x07, 0x10, 0x26])
for i, bad in [(0, 0x60), (0, 0x5A), (1, 0x80), (2, 0x24), (2, 0x52), (3, 0x00), (3, 0x08),
               (4, 0x00), (4, 0x32), (4, 0x41), (5, 0x00), (5, 0x13), (5, 0x2A), (6, 0xA0), (6, 0x9A)]:
    regs = bytearray(good); regs[i] = bad
    rtc.regs[0:7] = regs; rtc.regs[0x0F] = 0x08
    for sub in (0, 1):
        ok, out = osword(mpu, mem, 0x0E, [sub])
        check(not ok and out[1:] == b"#" * 31, f"reg {i}={bad:02X}: subcall {sub} claimed")
ok, _ = osword(mpu, mem, 0x0F, bytes([24]) + b"Wed,07 Oct 2026.23:59:30")
check(ok and bytes(rtc.regs[0:7]) == good, "write over implausible fields failed")
rtc.regs[5] = 0x90                      # 2190s: century bit set is fine
ok, out = osword(mpu, mem, 0x0E, [0])
check(ok and out[11:15] == b"2126", f"century bit read: {out[:25]!r}")

# --- No DS3234: nothing claimed, whatever MISO floats at ---
for mode in ("high", "low", "noise"):
    rtc.absent = mode
    for _ in range(20 if mode == "noise" else 1):
        for a, blk in [(0x0E, [0]), (0x0E, [1]), (0x0F, bytes([24]) + b"Wed,07 Oct 2026.23:59:30"),
                       (0x0F, bytes([8]) + b"12:00:00")]:
            ok, out = osword(mpu, mem, a, blk)
            check(not ok, f"absent ({mode}): OSWORD {a:02X} claimed")
    rtc.absent = None

print("FAILURES:", fails)
sys.exit(1 if fails else 0)
