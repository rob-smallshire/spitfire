"""Regression test for the SPItFIRE ROM's *SPITFIRE and *HELP handling, on a 6502 emulator.

Calls the service entry for service calls &04 (unrecognised command) and &09
(*HELP) on py65 with command lines in memory, capturing OSASCI/OSNEWL output,
OSBYTE calls and errors (the ROM copies an error block to &0100 and jumps
there). The model AVR in avr_model.py holds the joystick configuration and
counts its EEPROM writes.

Run from beeb/rom with `make test`, or:
    uv run --with py65 python test/test_commands.py
"""
import pathlib, subprocess, sys, tempfile
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory
from avr_model import AVR

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
avr = AVR()

def run(call, text):
    """Offer service call `call` for the text after '*'. Returns
    (A, output, osbyte calls, error message or None)."""
    mem = ObservableMemory()
    avr.attach(mem)
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
check(a == 0 and out == "Joystick off, Port A 1\nPorts A 3B Twin, B 3B Twin\n", f"status off: {out!r}")
a, out, osb, err = run(4, "spitfire  joystick  on")
check(a == 0 and osb == [(0xBE, 0x80, 0x7F)] and joystick_byte[0] == 0x85, f"ON: {a} {osb} {err}")
a, out, _, _ = run(4, "SPITFIRE JOYSTICK")
check(a == 0 and out.startswith("Joystick on, Port A 1\n"), f"status on: {out!r}")
run(4, "SPITFIRE JOYSTICK OFF")
check(joystick_byte[0] == 0x05, f"OFF kept other bits: {joystick_byte[0]:02X}")
check(avr.eeprom_writes == 0, "ON/OFF or status wrote the EEPROM")

# --- Port types ---
for text, config in (("SPITFIRE JOYSTICK B NONE", 0x41), ("SPITFIRE JOYSTICK a single", 0x42),
                     ("SPITFIRE JOYSTICK A 14b", 0x43), ("SPITFIRE JOYSTICK B TWIN", 0x47),
                     ("SPITFIRE JOYSTICK A TWIN", 0x45)):
    a, out, osb, err = run(4, text)
    check(a == 0 and not out and not err and avr.config == config and avr.eeprom == config,
          f"*{text}: {a} {out!r} {err} config {avr.config:02X}")
a, out, _, _ = run(4, "SPITFIRE JOYSTICK")
check(out == "Joystick off, Port A 1\nPorts A 3B Twin, B 3B Twin\n", f"status: {out!r}")
run(4, "SPITFIRE JOYSTICK B 14B")
a, out, _, _ = run(4, "SPITFIRE JOYSTICK")
check(out.endswith("Ports A 3B Twin, B 14B\n"), f"status B 14B: {out!r}")

# --- Handset ---
for text, h in (("SPITFIRE JOYSTICK USE A 2", 1), ("SPITFIRE JOYSTICK USE B", 2),
                ("spitfire joystick use b 2", 3), ("SPITFIRE JOYSTICK USE A 1", 0)):
    a, out, osb, err = run(4, text)
    check(a == 0 and not out and not err and (avr.config >> 4) & 3 == h and avr.eeprom == avr.config,
          f"*{text}: {a} {out!r} {err} config {avr.config:02X}")
    a, out, _, _ = run(4, "SPITFIRE JOYSTICK")
    want = f"Joystick off, Port {'AB'[h >> 1]} {(h & 1) + 1}\n"
    check(out.startswith(want), f"status after *{text}: {out!r}")

# --- The EEPROM is written only when a value changes ---
writes = avr.eeprom_writes
for text in ("SPITFIRE JOYSTICK A TWIN", "SPITFIRE JOYSTICK USE A", "SPITFIRE JOYSTICK B 14B"):
    run(4, text)
check(avr.eeprom_writes == writes, f"unchanged settings wrote the EEPROM {avr.eeprom_writes - writes} times")
run(4, "SPITFIRE JOYSTICK B TWIN")
check(avr.eeprom_writes == writes + 1, "a change was not saved")

# --- No AVR ---
for mode in ("high", "low"):
    avr.absent = mode
    a, out, _, err = run(4, "SPITFIRE JOYSTICK A NONE")
    check(err == "SPItFIRE not responding", f"absent ({mode}) set: {err}")
    a, out, _, err = run(4, "SPITFIRE JOYSTICK")
    check(out == "Joystick off, SPItFIRE not responding\n", f"absent ({mode}) status: {out!r}")
    avr.absent = None
check(avr.config == 0x45, f"config changed while absent: {avr.config:02X}")

# --- Syntax errors ---
for text in ("SPITFIRE FOO", "SPITFIRE JOYSTICK MAYBE", "SPITFIRE JOYSTICK ON X",
             "SPITFIRE JOYSTICKS", "SPITFIRE JOY", "SPITFIRE JOYSTICK A",
             "SPITFIRE JOYSTICK C TWIN", "SPITFIRE JOYSTICK A TWINS", "SPITFIRE JOYSTICK A TWIN X",
             "SPITFIRE JOYSTICK USE", "SPITFIRE JOYSTICK USE A 3", "SPITFIRE JOYSTICK USE A 1 2",
             "SPITFIRE JOYSTICK USE 1"):
    config = avr.config
    a, out, osb, err = run(4, text)
    check(err and err.startswith("Syntax") and not osb and avr.config == config, f"*{text}: {a} {err} {osb}")

# --- Not ours ---
for text in ("SPITFIRES", "SPIT", "JOYSTICK", "HELP", "SPITFIRE.", "XSPITFIRE"):
    a, out, osb, err = run(4, text)
    check(a == 4 and not out and not osb and not err, f"*{text} claimed: {a} {out!r} {err}")

# --- *HELP ---
settings = "  Joystick {}, Port A 1\n  Ports A 3B Twin, B 3B Twin\n"
a, out, _, _ = run(9, "")
check(a == 9 and "SPItFIRE 0.01" in out and "  SPITFIRE\n" in out, f"*HELP: {out!r}")
check(out.endswith(settings.format("off")), f"*HELP settings (off): {out!r}")
joystick_byte[0] = 0x85
a, out, _, _ = run(9, "")
check(out.endswith(settings.format("on")), f"*HELP settings (on): {out!r}")
a, out, _, _ = run(9, "SPITFIRE JOYSTICK")
check(out.endswith(settings.format("on")), f"*HELP SPITFIRE JOYSTICK settings: {out!r}")
joystick_byte[0] = 0x05
a, out, _, _ = run(9, "SPITFIRE")
check(a == 9 and "SPITFIRE JOYSTICK USE A|B [1|2]" in out and "  SPITFIRE\n" in out, f"*HELP SPITFIRE: {out!r}")
a, out, _, _ = run(9, "spitfire joystick")
check(a == 9 and "SPITFIRE JOYSTICK A|B <type>" in out and "  SPITFIRE\n" not in out,
      f"*HELP SPITFIRE JOYSTICK: {out!r}")
check(max(len(l) for l in out.split("\n")) <= 40, f"*HELP wider than MODE 7: {out!r}")
for text in ("JOYSTICK", "MOS", "SPITFIRE MOUSE"):
    a, out, _, _ = run(9, text)
    check(a == 9 and (not out or text == "SPITFIRE MOUSE"), f"*HELP {text}: {out!r}")
check(avr.eeprom_writes == writes + 1, "*HELP or a failed command wrote the EEPROM")
check(not avr.y0, "Y0 was driven")

print("FAILURES:", fails)
sys.exit(1 if fails else 0)
