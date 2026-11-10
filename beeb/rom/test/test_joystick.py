"""Regression test for the SPItFIRE ROM's joystick module, run on a 6502 emulator.

Assembles the ROM, then calls its service entry on py65 for the private
workspace claim (&24, &22), reset (&27) and MOS 5.x service call &2C (the
Master Compact's centisecond joystick poll), and calls its BYTEV hook
directly, against the model AVR in avr_model.py.

Checks:
- &24 asks for one page; &22 records the page in &0DF0+ROM and marks it
- &27 hands the joystick to &2C (OSBYTE &BE, X=&80, Y=&7F), installs the
  BYTEV hook through the extended vector once, keeping the old handler,
  and clears the values; none of these calls is claimed
- the poll stores ADVAL(0)-(2) in the MOS's workspace and everything else
  in the private workspace, for every pair of port types; unallocated
  channels read 0
- only every second call talks to the AVR (50 Hz); none while a foreground
  device is selected; DDRB, the ACR and port B's outputs are restored; the
  AVR is only ever selected with SCK low; Y0 is never driven
- nothing is stored when no AVR answers (MISO stuck high or low)
- without the workspace signature (after *SRLOAD ... I) the poll stores
  ADVAL(0)-(2) only
- the hook answers OSBYTE &80 for its channels with the stored values and
  passes every other call on with A, X and Y unchanged
- every &2C call is claimed with X, Y and the stack preserved
- every &2C call, busy or not, raises event 3 (OSEVEN, Y=3) with X = the
  current ADC channel (&024C), which then steps down, wrapping to the
  maximum (&024D), as the MOS's own routine does

Run from beeb/rom with `make test`, or:
    uv run --with py65 python test/test_joystick.py
"""
import ast, itertools, pathlib, random, subprocess, sys, tempfile
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory
from avr_model import AVR, CONFIG_DEFAULT

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
ROM_NUMBER = 5
PAGE = 0xDB                     # The HAZEL page &22 hands us
XVT = 0x0D9F                    # Extended vector table (OSBYTE &A8)
BYTEV = 0x020A
OLD_BYTEV = 0x0600              # A stand-in for the MOS's handler
HOOKED = (3, 4, 10, 11, 16, 17, 18, 19, 20, 26, 27)

osbyte_calls = []
passed_on = []
events = []
OSEVEN = 0xFFBF
ADC_CURRENT, ADC_MAXIMUM = 0x024C, 0x024D
def machine():
    mem = ObservableMemory()
    avr = AVR()
    avr.attach(mem)
    mpu = MPU(memory=mem)
    mem[0x8000:0x8000 + len(rom)] = rom
    mem[0x0400:0x0404] = [0x20, 0x03, 0x80, 0x00]          # JSR &8003 (service)
    mem[0x0410:0x0414] = [0x20, syms["joy_bytev"] & 0xFF, syms["joy_bytev"] >> 8, 0x00]
    mem[0xFFF4:0xFFF7] = [0x4C, 0x00, 0x05]                 # OSBYTE -> &0500: RTS
    mem[0x0500] = 0x60
    mem[OSEVEN] = 0x60
    mem[ADC_CURRENT] = mem[ADC_MAXIMUM] = 2
    mem[OLD_BYTEV] = 0x60
    mem[BYTEV], mem[BYTEV + 1] = OLD_BYTEV & 0xFF, OLD_BYTEV >> 8
    mem[0xF4] = ROM_NUMBER
    return mpu, mem, avr

def execute(mpu, mem, start, end):
    mpu.pc = start; mpu.sp = 0xFF
    for _ in range(40000):
        if mpu.pc == 0x0500:
            osbyte_calls.append((mpu.a, mpu.x, mpu.y))
            if mpu.a == 0xA8:
                mpu.x, mpu.y = XVT & 0xFF, XVT >> 8
        if mpu.pc == OLD_BYTEV:
            passed_on.append((mpu.a, mpu.x, mpu.y))
        if mpu.pc == OSEVEN:
            events.append((mpu.x, mpu.y))
        mpu.step()
        if mpu.pc == end:
            break
    else:
        raise RuntimeError("did not return")
    assert mpu.sp == 0xFF, "stack unbalanced"

def service(mpu, mem, a, y, x=ROM_NUMBER):
    mpu.a, mpu.x, mpu.y = a, x, y
    execute(mpu, mem, 0x0400, 0x0403)
    return mpu.a, mpu.x, mpu.y

def bytev(mpu, mem, a, x, y):
    mpu.a, mpu.x, mpu.y = a, x, y
    execute(mpu, mem, 0x0410, 0x0413)
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
    """One &2C call from a random resting VIA state. Returns the MOS workspace."""
    if iorb is None:
        iorb = (random.randrange(256) & 0xE3) | (Y7 << 2)
    mem[IORB] = iorb
    mem[DDRB] = random.choice([0x1F, 0x1D, 0x00, 0xFF])
    mem[ACR] = random.randrange(256)
    before = via_state(mem, avr)
    a, x, y = service(mpu, mem, 0x2C, WS)
    check(a == 0, f"&2C not claimed (A={a:02X})")
    check(x == ROM_NUMBER and y == WS, f"X/Y not preserved: {x:02X} {y:02X}")
    check(via_state(mem, avr) == before, f"VIA not restored: {before} -> {via_state(mem, avr)}")
    check(not avr.cs or (iorb >> 2) & 7 == Y1, "AVR left selected")
    return list(mem[0x0200 + WS:0x0200 + WS + 5])

def poll_twice(mpu, mem, avr):
    """Two calls, so exactly one reads the AVR."""
    t = avr.transactions
    poll(mpu, mem, avr); ws = poll(mpu, mem, avr)
    check(avr.transactions == t + 1, f"{avr.transactions - t} transactions in two calls")
    return ws

def adval(mpu, mem, ch):
    passed_on.clear()
    a, x, y = bytev(mpu, mem, 0x80, ch, 0x55)
    check(not passed_on, f"ADVAL({ch}) passed on")
    check(a == 0x80, f"ADVAL({ch}): A={a:02X}")
    return x | y << 8

mpu, mem, avr = machine()

# --- Workspace claim ---
a, x, y = service(mpu, mem, 0x24, 0xDC)
check((a, x, y) == (0x24, ROM_NUMBER, 0xDB), f"&24: A={a:02X} X={x:02X} Y={y:02X}")
a, x, y = service(mpu, mem, 0x22, PAGE)
check((a, x, y) == (0x22, ROM_NUMBER, PAGE + 1), f"&22: A={a:02X} X={x:02X} Y={y:02X}")
check(mem[0x0DF0 + ROM_NUMBER] == PAGE, f"&0DF0+ROM = {mem[0x0DF0 + ROM_NUMBER]:02X}")
check(bytes(mem[PAGE << 8:(PAGE << 8) + 3]) == b"SF" + bytes([ROM_NUMBER]), "page not marked")

# --- Reset ---
mem[(PAGE << 8) + 3:(PAGE << 8) + 26] = [0x77] * 23
osbyte_calls.clear()
a, x, y = service(mpu, mem, 0x27, 0x42)
check((a, x, y) == (0x27, ROM_NUMBER, 0x42), f"&27: returned A={a:02X} X={x:02X} Y={y:02X}")
check((0xBE, 0x80, 0x7F) in osbyte_calls, f"&27: OSBYTE calls {osbyte_calls}")
check(mem[BYTEV] | mem[BYTEV + 1] << 8 == 0xFF0F, "BYTEV is not the extended entry")
check(list(mem[XVT + 15:XVT + 18]) == [syms["joy_bytev"] & 0xFF, syms["joy_bytev"] >> 8, ROM_NUMBER],
      "extended vector not set")
check(mem[(PAGE << 8) + 26] | mem[(PAGE << 8) + 27] << 8 == OLD_BYTEV, "old BYTEV not kept")
check(list(mem[(PAGE << 8) + 3:(PAGE << 8) + 26]) == [0] * 23, "values not cleared")
service(mpu, mem, 0x27, 0x42)          # Again: the hook must not chain to itself
check(mem[(PAGE << 8) + 26] | mem[(PAGE << 8) + 27] << 8 == OLD_BYTEV, "second &27 chained to itself")

# --- Values arrive, at 50 Hz, for every pair of port types ---
seen = 0
for i in range(40):
    avr.randomise()
    t = avr.transactions
    poll(mpu, mem, avr)
    if avr.transactions != t: seen += 1
check(seen == 20, f"{seen} transactions in 40 calls, expected 20")
for ta, tb in itertools.product(range(8), repeat=2):
    avr.type = [ta, tb]
    for _ in range(3):
        avr.randomise()
        ws = poll_twice(mpu, mem, avr)
        mos, ch = avr.expected()
        check(ws == mos, f"types {ta},{tb}: MOS workspace {ws} != {mos}")
        for c in HOOKED:
            got = adval(mpu, mem, c)
            check(got == ch[c], f"types {ta},{tb}: ADVAL({c}) = {got:04X}, expected {ch[c]:04X}")
check(set(avr.commands) == {0x55}, f"unexpected commands {set(avr.commands)}")
check(avr.eeprom_writes == 0, "poll wrote the EEPROM")
check(not avr.y0, "Y0 was driven")

# --- The hook passes everything else on ---
for a0, x0, y0 in [(0x80, 0, 1), (0x80, 1, 2), (0x80, 2, 3), (0x80, 5, 4), (0x80, 9, 5),
                   (0x80, 12, 6), (0x80, 28, 7), (0x80, 0xFF, 8), (0x80, 0xF6, 9),
                   (0x81, 3, 10), (0x7E, 16, 11), (0x00, 0, 0)]:
    passed_on.clear()
    bytev(mpu, mem, a0, x0, y0)
    check(passed_on == [(a0, x0, y0)], f"OSBYTE {a0:02X},{x0:02X},{y0:02X}: passed on {passed_on}")

# --- Busy: a foreground device is selected ---
avr.type = [2, 2]
for dev in (0, 2, 3, 1, 6):
    avr.commands = []
    before = list(mem[0x0200 + WS:0x0200 + WS + 5])
    for _ in range(4):
        ws = poll(mpu, mem, avr, iorb=(random.randrange(256) & 0xE1) | (dev << 2))
    check(avr.commands == [], f"device {dev} selected: poll ran")
    check(ws == before, f"device {dev} selected: workspace changed")
    mem[IORB] = Y7 << 2

# --- No AVR: nothing stored ---
for mode in ("high", "low"):
    avr.absent = mode
    before = list(mem[0x0200 + WS:0x0200 + WS + 5])
    before_ch = [adval(mpu, mem, c) for c in HOOKED]
    for _ in range(6):
        ws = poll(mpu, mem, avr)
    check(ws == before, f"absent ({mode}): workspace changed")
    check([adval(mpu, mem, c) for c in HOOKED] == before_ch, f"absent ({mode}): channels changed")
    avr.absent = None

# --- No workspace (after *SRLOAD ... I): ADVAL(0)-(2) only ---
for broken in ("unclaimed", "unsigned"):
    m2, mem2, avr2 = machine()
    if broken == "unsigned":
        mem2[0x0DF0 + ROM_NUMBER] = PAGE           # Someone else's page
        mem2[PAGE << 8:(PAGE << 8) + 3] = [0x53, 0x46, ROM_NUMBER + 1]
    avr2.type = [2, 2]
    avr2.randomise()
    ws = poll_twice(m2, mem2, avr2)
    check(ws == avr2.expected()[0], f"{broken}: ADVAL(0)-(2) not stored")
    check(list(mem2[PAGE << 8:(PAGE << 8) + 3]) == ([0] * 3 if broken == "unclaimed"
          else [0x53, 0x46, ROM_NUMBER + 1]), f"{broken}: wrote a page")
    osbyte_calls.clear()
    service(m2, mem2, 0x27, 0)
    check(mem2[BYTEV] | mem2[BYTEV + 1] << 8 == OLD_BYTEV, f"{broken}: hook installed")
    check((0xBE, 0x80, 0x7F) in osbyte_calls, f"{broken}: joystick not handed over")

# --- ADC conversion events and the channel byte ---
def adc_run(current, maximum, calls, iorb=None):
    mem[ADC_CURRENT], mem[ADC_MAXIMUM] = current, maximum
    events.clear()
    seen = []
    for _ in range(calls):
        poll(mpu, mem, avr, iorb=iorb)
        seen.append(mem[ADC_CURRENT])
    return events[:], seen

for current, maximum, raised, after in [
    (2, 2, [2, 1, 2, 1, 2], [1, 2, 1, 2, 1]),
    (4, 4, [4, 3, 2, 1, 4, 3], [3, 2, 1, 4, 3, 2]),
    (4, 2, [4, 3, 2, 1, 2], [3, 2, 1, 2, 1]),       # *FX17,4 with *FX16,2
    (1, 1, [1, 1, 1], [1, 1, 1]),
    (0, 2, [0, 2, 1], [2, 1, 2]),
]:
    ev, seen = adc_run(current, maximum, len(raised))
    check(ev == [(c, 3) for c in raised], f"ADC {current}/{maximum}: events {ev}")
    check(seen == after, f"ADC {current}/{maximum}: channel {seen}, expected {after}")
ev, seen = adc_run(2, 2, 4, iorb=(Y7 << 2) & ~(4 << 2))   # Busy: still raised
check(ev == [(2, 3), (1, 3), (2, 3), (1, 3)], f"ADC while busy: {ev}")
mem[IORB] = Y7 << 2

# --- Other service calls are left alone ---
for call in (0x01, 0x12, 0x28):
    a, _, _ = service(mpu, mem, call, 0)
    check(a == call, f"service {call:02X} claimed")

print("FAILURES:", fails)
sys.exit(1 if fails else 0)
