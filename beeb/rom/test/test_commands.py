"""Regression test for the SPItFIRE ROM's *SPITFIRE and *HELP handling, on a 6502 emulator.

Calls the service entry for service calls &04 (unrecognised command) and &09
(*HELP) on py65 with command lines in memory, capturing OSASCI/OSNEWL output,
OSBYTE calls and errors (the ROM copies an error block to &0100 and jumps
there).

Run from beeb/rom with `make test`, or:
    uv run --with py65 python test/test_commands.py
"""
import pathlib, subprocess, sys, tempfile
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

ROM_DIR = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as tmp:
    image = pathlib.Path(tmp) / "SPITFIRE"
    result = subprocess.run(["beebasm", "-i", "src/main.asm", "-o", str(image)],
                            cwd=ROM_DIR, capture_output=True, text=True)
    if result.returncode or not image.exists():
        sys.exit(f"beebasm failed:\n{result.stdout}{result.stderr}")
    rom = image.read_bytes()

OSASCI, OSNEWL, OSBYTE = 0xFFE3, 0xFFE7, 0xFFF4
LINE = 0x0700
joystick_byte = [0x05]

def run(call, text):
    """Offer service call `call` for the text after '*'. Returns
    (A, output, osbyte calls, error message or None)."""
    mem = ObservableMemory()
    mpu = MPU(memory=mem)
    mem[0x8000:0x8000 + len(rom)] = rom
    mem[0x0400:0x0404] = [0x20, 0x03, 0x80, 0x00]          # JSR &8003
    for v in (OSASCI, OSNEWL, OSBYTE):
        mem[v] = 0x60                                       # RTS; trapped below
    mem[LINE:LINE + len(text) + 1] = list(text.encode()) + [13]
    mem[0xF2], mem[0xF3] = LINE & 0xFF, LINE >> 8
    mpu.a, mpu.x, mpu.y = call, 7, 0
    mpu.pc, mpu.sp = 0x0400, 0xFF
    out, osbytes = [], []
    for _ in range(100000):
        if mpu.pc == OSASCI:
            out.append("\n" if mpu.a == 13 else chr(mpu.a))
        elif mpu.pc == OSNEWL:
            out.append("\n")
        elif mpu.pc == OSBYTE:
            osbytes.append((mpu.a, mpu.x, mpu.y))
            if mpu.a == 0xBE:                               # (old AND Y) EOR X
                old = joystick_byte[0]
                joystick_byte[0] = (old & mpu.y) ^ mpu.x
                mpu.x = old
        elif mpu.pc == 0x0100:
            msg = bytes(mem[0x0102:0x0102 + 60]).split(b"\0")[0].decode()
            return None, "".join(out), osbytes, msg
        mpu.step()
        if mpu.pc == 0x0403:
            break
    else:
        raise RuntimeError("did not return")
    assert mpu.sp == 0xFF, "stack unbalanced"
    assert (mpu.x, mpu.y) == (7, 0), f"{text!r}: X/Y not preserved"
    return mpu.a, "".join(out), osbytes, None

fails = 0
def check(cond, msg):
    global fails
    if not cond:
        fails += 1
        print("FAIL:", msg)

# --- *SPITFIRE ---
for text in ("SPITFIRE", "spitfire", "SpitFire  "):
    a, out, _, err = run(4, text)
    check(a == 0 and "SPItFIRE 0.01" in out and "JOYSTICK" in out, f"*{text}: {a} {out!r} {err}")

# --- *SPITFIRE JOYSTICK ON|OFF and status ---
joystick_byte[0] = 0x05
a, out, osb, err = run(4, "SPITFIRE JOYSTICK OFF")
check(a == 0 and osb == [(0xBE, 0x00, 0x7F)] and joystick_byte[0] == 0x05, f"OFF: {a} {osb} {err}")
a, out, _, _ = run(4, "SPITFIRE JOYSTICK")
check(a == 0 and "off" in out, f"status off: {out!r}")
a, out, osb, err = run(4, "spitfire  joystick  on")
check(a == 0 and osb == [(0xBE, 0x80, 0x7F)] and joystick_byte[0] == 0x85, f"ON: {a} {osb} {err}")
a, out, _, _ = run(4, "SPITFIRE JOYSTICK")
check(a == 0 and out == "Joystick on (Port A CH0/CH1)\n", f"status on: {out!r}")
run(4, "SPITFIRE JOYSTICK OFF")
check(joystick_byte[0] == 0x05, f"OFF kept other bits: {joystick_byte[0]:02X}")

# --- Syntax errors ---
for text in ("SPITFIRE FOO", "SPITFIRE JOYSTICK MAYBE", "SPITFIRE JOYSTICK ON X",
             "SPITFIRE JOYSTICKS", "SPITFIRE JOY"):
    a, out, osb, err = run(4, text)
    check(err and err.startswith("Syntax") and not osb, f"*{text}: {a} {err} {osb}")

# --- Not ours ---
for text in ("SPITFIRES", "SPIT", "JOYSTICK", "HELP", "SPITFIRE.", "XSPITFIRE"):
    a, out, osb, err = run(4, text)
    check(a == 4 and not out and not osb and not err, f"*{text} claimed: {a} {out!r} {err}")

# --- *HELP ---
a, out, _, _ = run(9, "")
check(a == 9 and "SPItFIRE 0.01" in out and "  SPITFIRE\n" in out, f"*HELP: {out!r}")
check(out.endswith("  Joystick off\n"), f"*HELP settings (off): {out!r}")
joystick_byte[0] = 0x85
a, out, _, _ = run(9, "")
check(out.endswith("  Joystick on (Port A CH0/CH1)\n"), f"*HELP settings (on): {out!r}")
a, out, _, _ = run(9, "SPITFIRE JOYSTICK")
check(out.endswith("  Joystick on (Port A CH0/CH1)\n"), f"*HELP SPITFIRE JOYSTICK settings: {out!r}")
a, out, _, _ = run(4, "SPITFIRE JOYSTICK")
check(out == "Joystick on (Port A CH0/CH1)\n", f"status: {out!r}")
joystick_byte[0] = 0x05
a, out, _, _ = run(9, "SPITFIRE")
check(a == 9 and "SPITFIRE JOYSTICK [ON|OFF]" in out and "  SPITFIRE\n" in out, f"*HELP SPITFIRE: {out!r}")
a, out, _, _ = run(9, "spitfire joystick")
check(a == 9 and "SPITFIRE JOYSTICK [ON|OFF]" in out and "  SPITFIRE\n" not in out,
      f"*HELP SPITFIRE JOYSTICK: {out!r}")
for text in ("JOYSTICK", "MOS", "SPITFIRE MOUSE"):
    a, out, _, _ = run(9, text)
    check(a == 9 and (not out or text == "SPITFIRE MOUSE"), f"*HELP {text}: {out!r}")

print("FAILURES:", fails)
sys.exit(1 if fails else 0)
