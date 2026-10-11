"""Regression test for the SPItFIRE ROM's joystick module, run on a 6502 emulator.

Assembles the ROM, then calls its service entry for MOS 5.x service call &2C
(the Master Compact's centisecond joystick poll) and &27 (reset) on py65. A
model AVR decodes the bit-banged SPI (mode 0) from the User VIA port B writes
and answers the spijoy firmware's JOY_ADVAL burst and type commands.

Checks:
- the burst's five bytes land in the ADVAL workspace (&0200+Y..+4)
- only every second call talks to the AVR (50 Hz)
- no transaction while a foreground device is selected (decoder not on Y7)
- DDRB, the ACR and port B's outputs (PB5-PB7 included) are restored, the
  AVR is only ever selected with SCK low, and Y0 is never driven
- a port of the wrong type is set to 3B Twin and its values not stored
- nothing is stored when no AVR answers (MISO stuck high or low)
- every &2C call is claimed with X, Y and the stack preserved
- service &27 calls OSBYTE &BE with X=&80, Y=&7F and is not claimed

Run from beeb/rom with `make test`, or:
    uv run --with py65 python test/test_joystick.py
"""
import ast, pathlib, random, subprocess, sys, tempfile
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
syms = ast.literal_eval(result.stdout.strip().replace("L,", ",").replace("L}", "}"))[0]

IORB, DDRB, SR, ACR, IER = 0xFE60, 0xFE62, 0xFE6A, 0xFE6B, 0xFE6E
WS = 0xB6                       # Y on service call &2C: ADVAL workspace &02B6
Y1, Y7 = 1, 7

class AVR:
    """The spijoy firmware's SPI slave, as seen through the decoder."""
    def __init__(self):
        self.iorb = 0xFF; self.sr = 0; self.cs = False
        self.type = [1, 0]                       # Port A 3B Twin, Port B None
        self.adval = [[random.randrange(256) for _ in range(5)] for _ in range(4)]
        self.absent = None                       # None, "high" or "low"
        self.transactions = 0; self.commands = []
        self.y0 = False
    def write_iorb(self, addr, v):
        prev, self.iorb = self.iorb, v
        dev = (v >> 2) & 7
        if dev == 0: self.y0 = True
        if dev != Y1:
            if self.cs: self.burst = []          # SS rising ends a burst
            self.cs = False; return
        if not self.cs:
            assert not (v & 2), "AVR selected with SCK high"
            self.cs = True; self.bits = 0; self.rx = 0; self.burst = []
            self.out = 0xFF; self.transactions += 1
        if (v & 2) and not (prev & 2):           # Rising edge
            if self.bits == 0: self.tx = self.out
            self.rx = ((self.rx << 1) | (v & 1)) & 0xFF
            self.bits += 1
            if self.bits == 8:
                self.bits = 0; self.sr = self.tx; self.isr(self.rx)
    def isr(self, b):
        if self.burst:
            self.out = self.burst.pop(0); return
        self.commands.append(b)
        if 0x50 <= b <= 0x53:
            h = b - 0x50
            data = [0xA0 | self.type[h >> 1]] + self.adval[h]
            self.out = data[0]; self.burst = data[1:] + [0xFF]
        elif 0xE0 <= b <= 0xE7:
            self.type[(b >> 2) & 1] = b & 3; self.out = b
        else:
            self.out = 0xFF
    def read_iorb(self, addr): return self.iorb
    def read_sr(self, addr):
        if self.absent == "high": return 0xFF
        if self.absent == "low": return 0x00
        return self.sr

osbyte_calls = []
def machine():
    mem = ObservableMemory()
    avr = AVR()
    mem.subscribe_to_write([IORB], avr.write_iorb)
    mem.subscribe_to_read([IORB], avr.read_iorb)
    mem.subscribe_to_read([SR], avr.read_sr)
    mpu = MPU(memory=mem)
    mem[0x8000:0x8000 + len(rom)] = rom
    mem[0x0400:0x0404] = [0x20, 0x03, 0x80, 0x00]          # JSR &8003 (service)
    mem[0xFFF4:0xFFF7] = [0x4C, 0x00, 0x05]                 # OSBYTE -> &0500: RTS
    mem[0x0500] = 0x60
    return mpu, mem, avr

def service(mpu, mem, a, y, x=5):
    mpu.a, mpu.x, mpu.y = a, x, y
    mpu.pc = 0x0400; mpu.sp = 0xFF
    for _ in range(20000):
        if mpu.pc == 0x0500:
            osbyte_calls.append((mpu.a, mpu.x, mpu.y))
        mpu.step()
        if mpu.pc == 0x0403:
            break
    else:
        raise RuntimeError("did not return")
    assert mpu.sp == 0xFF, "stack unbalanced"
    return mpu.a, mpu.x, mpu.y

fails = 0
def check(cond, msg):
    global fails
    if not cond:
        fails += 1
        if fails < 20: print("FAIL:", msg)

def via_state(mem, avr):
    return (avr.iorb, mem[DDRB], mem[ACR])

def poll(mpu, mem, avr, iorb=None):
    """One &2C call from a random resting VIA state. Returns the workspace."""
    if iorb is None:
        iorb = (random.randrange(256) & 0xE3) | (Y7 << 2)
    mem[IORB] = iorb
    mem[DDRB] = random.choice([0x1F, 0x1D, 0x00, 0xFF])
    mem[ACR] = random.randrange(256)
    before = via_state(mem, avr)
    a, x, y = service(mpu, mem, 0x2C, WS)
    check(a == 0, f"&2C not claimed (A={a:02X})")
    check(x == 5 and y == WS, f"X/Y not preserved: {x:02X} {y:02X}")
    check(via_state(mem, avr) == before, f"VIA not restored: {before} -> {via_state(mem, avr)}")
    check(not avr.cs or (iorb >> 2) & 7 == Y1, "AVR left selected")
    return list(mem[0x0200 + WS:0x0200 + WS + 5])

mpu, mem, avr = machine()

# --- Values arrive, at 50 Hz ---
mem[0x0200 + WS:0x0200 + WS + 8] = [0x11] * 8
seen = 0
for i in range(40):
    avr.adval[0] = [random.randrange(256) for _ in range(5)]
    t = avr.transactions
    ws = poll(mpu, mem, avr)
    if avr.transactions != t:
        seen += 1
        check(ws == avr.adval[0], f"poll {i}: workspace {ws} != {avr.adval[0]}")
check(seen == 20, f"{seen} transactions in 40 calls, expected 20")
check(set(avr.commands) == {0x50}, f"unexpected commands {set(avr.commands)}")
check(not avr.y0, "Y0 was driven")

# --- Busy: a foreground device is selected ---
for dev in (0, 2, 3, 1, 6):
    avr.commands = []
    before = list(mem[0x0200 + WS:0x0200 + WS + 5])
    for _ in range(4):
        ws = poll(mpu, mem, avr, iorb=(random.randrange(256) & 0xE1) | (dev << 2))
    check(avr.commands == [], f"device {dev} selected: poll ran")
    check(ws == before, f"device {dev} selected: workspace changed")
    mem[IORB] = Y7 << 2

# --- Wrong port type: set to 3B Twin, values not stored that time ---
for wrong in (0, 2, 3):
    avr.type[0] = wrong; avr.commands = []
    before = list(mem[0x0200 + WS:0x0200 + WS + 5])
    for _ in range(2):
        ws = poll(mpu, mem, avr)
    check(ws == before, f"type {wrong}: values stored")
    cmds = [c for c in avr.commands if c]  # The echo's dummy byte is a no-op command
    check(cmds == [0x50, 0xE1], f"type {wrong}: commands {[hex(c) for c in cmds]}")
    check(avr.type[0] == 1, f"type {wrong}: not set to 3B Twin")
    for _ in range(2):
        ws = poll(mpu, mem, avr)
    check(ws == avr.adval[0], f"type {wrong}: no values after repair")

# --- No AVR: nothing stored ---
for mode in ("high", "low"):
    avr.absent = mode
    before = list(mem[0x0200 + WS:0x0200 + WS + 5])
    for _ in range(6):
        ws = poll(mpu, mem, avr)
    check(ws == before, f"absent ({mode}): workspace changed")
    avr.absent = None

# --- Service &27: hand joystick handling to &2C ---
osbyte_calls.clear()
a, x, y = service(mpu, mem, 0x27, 0x42, x=9)
check(osbyte_calls == [(0xBE, 0x80, 0x7F)], f"&27: OSBYTE calls {osbyte_calls}")
check(a == 0x27 and x == 9 and y == 0x42, f"&27: returned A={a:02X} X={x:02X} Y={y:02X}")

# --- Other service calls are left alone ---
for call in (0x01, 0x04, 0x12, 0x28):
    a, _, _ = service(mpu, mem, call, 0)
    check(a == call, f"service {call:02X} claimed")

print("FAILURES:", fails)
sys.exit(1 if fails else 0)
