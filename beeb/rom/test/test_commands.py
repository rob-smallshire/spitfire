"""Regression test for the SPItFIRE ROM's commands, *HELP, *STATUS and OSWORD &3F,
on a 6502 emulator.

Calls the service entry on py65 for service calls &04 (unrecognised command),
&09 (*HELP), &29 (*STATUS) and &08 (OSWORD), with command lines in memory,
capturing OSASCI/OSNEWL output, OSBYTE calls and errors (the ROM copies an
error block to &0100 and jumps there). The machine keeps its memory between
calls: the ROM claims its workspace and installs its BYTEV hook at a model
reset, and *SPITFIRE ADVAL's OSBYTE &80 calls go through the hook, as the
extended vector would send them. The model AVR in avr_model.py holds the
configuration and counts its EEPROM writes.

Run from beeb/rom with `make test`, or:
    uv run --with py65 python test/test_commands.py
"""
import ast, pathlib, re, subprocess, sys, tempfile
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory
from avr_model import AVR, CONFIG_DEFAULT

ROM_DIR = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as tmp:
    image = pathlib.Path(tmp) / "SPITFIRE"
    result = subprocess.run(["beebasm", "-i", "src/main.asm", "-o", str(image), "-d"],
                            cwd=ROM_DIR, capture_output=True, text=True)
    if result.returncode or not image.exists():
        sys.exit(f"beebasm failed:\n{result.stdout}{result.stderr}")
    rom = image.read_bytes()
syms = ast.literal_eval(result.stdout.strip().replace("L,", ",").replace("L}", "}"))[0]

OSASCI, OSNEWL, OSBYTE = 0xFFE3, 0xFFE7, 0xFFF4
LINE, BLOCK = 0x0700, 0x0780
ROM_NUMBER, PAGE, XVT = 7, 0xDA, 0x0D9F
WS = 0xB6
MOS_BYTEV = 0x0600              # Stands in for the MOS's OSBYTE handler

class Machine:
    def __init__(self, avr, claim=True):
        self.avr = avr
        self.mem = mem = ObservableMemory()
        avr.attach(mem)
        self.mpu = MPU(memory=mem)
        mem[0x8000:0x8000 + len(rom)] = rom
        mem[0x0400:0x0404] = [0x20, 0x03, 0x80, 0x00]      # JSR &8003
        for v in (OSASCI, OSNEWL, OSBYTE, MOS_BYTEV):
            mem[v] = 0x60                                   # RTS; trapped below
        mem[0x020A], mem[0x020B] = MOS_BYTEV & 0xFF, MOS_BYTEV >> 8
        mem[0xF4] = ROM_NUMBER
        self.joystick_byte = 0x05
        self.column = 0
        if claim:
            self.call(0x24, y=0xDC)
            self.call(0x22, y=PAGE)
        self.call(0x27)

    def call(self, a, text="", y=0):
        """Offer service call `a`. Returns (A, output, osbyte calls, error)."""
        mem, mpu = self.mem, self.mpu
        mem[LINE:LINE + len(text) + 1] = list(text.encode()) + [13]
        mem[0xF2], mem[0xF3] = LINE & 0xFF, LINE >> 8
        mpu.a, mpu.x, mpu.y = a, ROM_NUMBER, y
        mpu.pc, mpu.sp = 0x0400, 0xFF
        out, osbytes = [], []
        for _ in range(400000):
            pc = mpu.pc
            if pc == OSASCI:
                if mpu.a == 13:
                    out.append("\n"); self.column = 0
                else:
                    out.append(chr(mpu.a)); self.column += 1
            elif pc == OSNEWL:
                out.append("\n"); self.column = 0
            elif pc == OSBYTE:
                osbytes.append((mpu.a, mpu.x, mpu.y))
                if mpu.a == 0xBE:                           # (old AND Y) EOR X
                    old = self.joystick_byte
                    self.joystick_byte = (old & mpu.y) ^ mpu.x
                    mpu.x = old
                elif mpu.a == 0xA8:
                    mpu.x, mpu.y = XVT & 0xFF, XVT >> 8
                elif mpu.a == 0x86:
                    mpu.x, mpu.y = self.column, 0
                elif mpu.a == 0x80 and mem[0x020A] | mem[0x020B] << 8 == 0xFF0F:
                    # Through the extended vector to the hook
                    hook = mem[XVT + 15] | mem[XVT + 16] << 8
                    mpu.pc = hook
                    continue
            elif pc == MOS_BYTEV and mpu.a == 0x80:         # The MOS's ADVAL(0)-(2)
                c = mpu.x
                if c == 0: mpu.x, mpu.y = mem[0x200 + WS], 0
                else:
                    base = 0x200 + WS + (1 if c & 1 else 3)
                    mpu.x, mpu.y = mem[base], mem[base + 1]
            elif pc == 0x0100:
                msg = bytes(mem[0x0102:0x0102 + 60]).split(b"\0")[0].decode()
                return None, "".join(out), osbytes, msg
            mpu.step()
            if mpu.pc == 0x0403:
                break
        else:
            raise RuntimeError("did not return")
        assert mpu.sp == 0xFF, "stack unbalanced"
        assert (mpu.x, mpu.y)[0] == ROM_NUMBER, f"{text!r}: X not preserved"
        return mpu.a, "".join(out), osbytes, None

    def star(self, text): return self.call(4, text)
    def help(self, text=""): return self.call(9, text)
    def status(self, text=""): return self.call(0x29, text)

    def poll(self):
        for _ in range(2):
            self.call(0x2C, y=WS)

    def osword(self, reason=0):
        mem = self.mem
        mem[BLOCK:BLOCK + 16] = [reason] + [0xEE] * 15
        mem[0xEF] = 0x3F
        mem[0xF0], mem[0xF1] = BLOCK & 0xFF, BLOCK >> 8
        a, out, _, err = self.call(8)
        return a, list(mem[BLOCK:BLOCK + 16])

fails = 0
def check(cond, msg):
    global fails
    if not cond:
        fails += 1
        print("FAIL:", msg)

avr = AVR()
m = Machine(avr)

# --- *SPITFIRE ---
for text in ("SPITFIRE", "spitfire", "SpitFire  "):
    a, out, _, err = m.star(text)
    check(a == 0 and "SPItFIRE 0.02" in out and "JOYSTICK" in out and "Ctrl-Break" not in out,
          f"*{text}: {a} {out!r} {err}")

# --- *SPITFIRE JOYSTICK ON|OFF and status ---
a, out, osb, err = m.star("SPITFIRE JOYSTICK OFF")
check(a == 0 and (0xBE, 0x00, 0x7F) in osb and m.joystick_byte == 0x05, f"OFF: {a} {osb} {err}")
a, out, _, _ = m.star("SPITFIRE JOYSTICK")
check(out == "Joystick off\nPort A: Standard dual joystick\n        Joysticks 1, 2\nPort B: No joystick\n",
      f"status off: {out!r}")
a, out, osb, err = m.star("spitfire  joystick  on")
check(a == 0 and (0xBE, 0x80, 0x7F) in osb and m.joystick_byte == 0x85, f"ON: {a} {osb} {err}")
a, out, _, _ = m.star("SPITFIRE JOYSTICK")
check(out.startswith("Joystick on\n"), f"status on: {out!r}")
check(avr.eeprom_writes == 0, "ON/OFF or status wrote the EEPROM")

# --- Port types ---
for text, config in (("SPITFIRE JOYSTICK PORT B SINGLE", 0x4A), ("SPITFIRE JOYSTICK PORT a 3bt", 0x4C),
                     ("SPITFIRE JOYSTICK PORT A 14b", 0x4D), ("SPITFIRE JOYSTICK PORT B QUINKEY", 0x7D),
                     ("SPITFIRE JOYSTICK PORT A NONE", 0x78), ("SPITFIRE JOYSTICK PORT B bitstik", 0x70),
                     ("SPITFIRE JOYSTICK PORT A 3BS", 0x73), ("SPITFIRE JOYSTICK PORT A DUAL", 0x72)):
    a, out, osb, err = m.star(text)
    check(a == 0 and not out and not err and avr.config == config and avr.eeprom == config,
          f"*{text}: {a} {out!r} {err} config {avr.config:02X}")

statuses = [
    (0x42, ["Port A: Standard dual joystick", "        Joysticks 1, 2", "Port B: No joystick"]),
    (0x48, ["Port A: No joystick", "Port B: Standard single joystick", "        Joystick 1"]),
    (0x4C, ["Port A: Voltmace Delta 3B Twin", "        Joysticks 1, 2", "Port B: Standard single joystick",
            "        Joystick 3"]),
    (0x6D, ["Port A: Voltmace Delta 14B", "        Joystick 1", "Port B: Voltmace Delta 14B", "        Joystick 2"]),
    (0x76, ["Port A: Acorn Bitstik", "        Channels 1, 2, 3, 4", "Port B: Acorn Bitstik",
            "        Channels 17, 18, 19, 20"]),
    (0x7B, ["Port A: Voltmace Delta 3B Single", "        Joysticks 1, 2", "Port B: Microwriter Quinkey",
            "        Channels 17, 18, 19, 20"]),
    (0x61, ["Port A: Standard single joystick", "        Joystick 1", "Port B: Voltmace Delta 3B Twin",
            "        Joysticks 2, 3"]),
]
for config, lines in statuses:
    avr.config = config
    a, out, _, _ = m.star("SPITFIRE JOYSTICK")
    check(out == "Joystick on\n" + "".join(l + "\n" for l in lines), f"status {config:02X}: {out!r}")
avr.config = 0x42

# --- The EEPROM is written only when a value changes ---
avr.config = avr.eeprom = 0x72
writes = avr.eeprom_writes
for text in ("SPITFIRE JOYSTICK PORT A DUAL", "SPITFIRE JOYSTICK PORT B BITSTIK"):
    m.star(text)
check(avr.eeprom_writes == writes, f"unchanged settings wrote the EEPROM {avr.eeprom_writes - writes} times")
m.star("SPITFIRE JOYSTICK PORT B NONE")
check(avr.eeprom_writes == writes + 1, "a change was not saved")

# --- *SPITFIRE ADVAL ---
def adval_table(text):
    a, out, _, err = m.star(text)
    check(a == 0 and not err, f"*{text}: {a} {err}")
    lines = out.split("\n")
    check(lines[0] == "Ch Use               Port Value", f"*{text} header: {lines[0]!r}")
    check(max(len(l) for l in lines) <= 40, f"*{text} wider than 40: {out!r}")
    rows = {}
    for l in lines[1:]:
        if not l or l.startswith("5-9"): continue
        rows[int(l[:2])] = (l[3:21].rstrip(), l[21:26].rstrip(), l[26:])
    return out, rows

def fmt(kind, v):
    return f"&{v:02X}" if kind == "byte" else f"&{v:04X}" if kind == "word" else str(v)

KINDS = {0: "byte", 16: "byte", 10: "word", 11: "word", 26: "word", 27: "word"}
for config, uses in [
    (0x42, {0: ("Fire 1, 2", "A"), 1: ("Joystick 1 X", "A"), 2: ("Joystick 1 Y", "A"),
            3: ("Joystick 2 X", "A"), 4: ("Joystick 2 Y", "A")}),
    (0x4C, {0: ("Fire 1, 2", "A"), 1: ("Joystick 1 X", "A"), 2: ("Joystick 1 Y", "A"),
            3: ("Joystick 2 X", "A"), 4: ("Joystick 2 Y", "A"), 16: ("Fire 3", "B"),
            17: ("Joystick 3 X", "B"), 18: ("Joystick 3 Y", "B")}),
    (0x55, {0: ("Fire 1, 2", "A"), 1: ("Joystick 1 X", "A"), 2: ("Joystick 1 Y", "A"),
            10: ("Joystick 1 keypad", "A"), 3: ("Joystick 2 X", "B"), 4: ("Joystick 2 Y", "B"),
            16: ("Fire 3", "B"), 17: ("Joystick 3 X", "B"), 18: ("Joystick 3 Y", "B")}),
    (0x7E, {0: ("Fire 1, 2", "A"), 1: ("Bitstik X", "A"), 2: ("Bitstik Y", "A"), 3: ("Bitstik twist", "A"),
            4: ("Bitstik button", "A"), 16: ("Fire 3, 4", "B"), 17: ("Quinkey 1", "B"),
            18: ("Quinkey 2", "B"), 19: ("Quinkey 3", "B"), 20: ("Quinkey 4", "B")}),
]:
    avr.config = config
    avr.type = [config & 7, (config >> 3) & 7]
    avr.randomise()
    m.poll()
    mos, ch = avr.expected()
    values = dict(ch)
    values[0] = mos[0]
    values[1] = mos[1] | mos[2] << 8
    values[2] = mos[3] | mos[4] << 8
    out, rows = adval_table("SPITFIRE ADVAL")
    check(set(rows) == set(uses), f"ADVAL {config:02X}: channels {sorted(rows)} != {sorted(uses)}")
    for c, (use, port) in uses.items():
        if c in rows:
            check(rows[c] == (use, port, fmt(KINDS.get(c), values[c])),
                  f"ADVAL {config:02X} ch {c}: {rows[c]} != {(use, port, fmt(KINDS.get(c), values[c]))}")
    out, rows = adval_table("spitfire adval all")
    check(set(rows) == {0, 1, 2, 3, 4, 10, 11, 16, 17, 18, 19, 20, 26, 27} and "5-9 Passed on (mouse)" in out,
          f"ADVAL ALL {config:02X}: {sorted(rows)}")
    for c in set(rows) - set(uses):
        check(rows[c] == ("-", "-", fmt(KINDS.get(c), 0)), f"ADVAL ALL {config:02X} ch {c}: {rows[c]}")

# --- OSWORD &3F ---
for config, want in [
    (0x42, [0x53, 1, 2, 0, 2, 0, 0x02, 0x02, 0xFF, 0xFF, 0]),
    (0x55, [0x53, 1, 5, 2, 3, 1, 0x05, 0x82, 0x82, 0xFF, 0]),
    (0x6D, [0x53, 1, 5, 5, 2, 3, 0x05, 0x85, 0xFF, 0xFF, 0]),
    (0x40, [0x53, 1, 0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF, 0]),
    (0x7E, [0x53, 1, 6, 7, 4, 0, 0x06, 0x06, 0x87, 0x87, 0]),
]:
    avr.config = config
    a, block = m.osword()
    check(a == 0 and block[:11] == want and block[11:] == [0xEE] * 5,
          f"OSWORD &3F {config:02X}: {a} {[hex(b) for b in block[:11]]}")
a, block = m.osword(reason=1)
check(a == 8 and block[0] == 1 and block[1:] == [0xEE] * 15, f"OSWORD &3F reason 1 claimed: {a} {block}")
avr.absent = "high"
a, block = m.osword()
check(a == 0 and block[:11] == [0x53, 1, 0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF, 2], f"OSWORD absent: {block}")
avr.absent = None
avr.config = 0x42

# --- *STATUS ---
a, out, _, _ = m.status()
check(a == 0x29 and out == "SPItFIRE: Joystick on\nPort A: Standard dual joystick\n        Joysticks 1, 2\n"
      "Port B: No joystick\nProportional, Switched, Stick unused\nConfigure with *SPITFIRE JOYSTICK\n",
      f"*STATUS: {a} {out!r}")
a, out2, _, _ = m.status("spitfire")
check(a == 0 and out2 == out, f"*STATUS SPITFIRE: {a} {out2!r}")
for text in ("BAUD", "SPITFIRES", "SPITFIRE X"):
    a, out, _, _ = m.status(text)
    check(a == 0x29 and not out, f"*STATUS {text}: {a} {out!r}")
m.star("SPITFIRE JOYSTICK OFF")
a, out, _, _ = m.status()
check("Joystick off" in out and "unused" not in out and "Configure with" in out, f"*STATUS off: {out!r}")
m.star("SPITFIRE JOYSTICK ON")

# --- No AVR ---
for mode in ("high", "low"):
    avr.absent = mode
    a, out, _, err = m.star("SPITFIRE JOYSTICK PORT A NONE")
    check(err == "SPItFIRE not responding", f"absent ({mode}) set: {err}")
    a, out, _, err = m.star("SPITFIRE JOYSTICK")
    check(out == "Joystick on\nSPItFIRE not responding\n", f"absent ({mode}) status: {out!r}")
    a, out, _, err = m.star("SPITFIRE ADVAL")
    check(err == "SPItFIRE not responding", f"absent ({mode}) ADVAL: {err}")
    avr.absent = None
check(avr.config == 0x42, f"config changed while absent: {avr.config:02X}")

# --- Syntax errors ---
for text in ("SPITFIRE FOO", "SPITFIRE JOYSTICK MAYBE", "SPITFIRE JOYSTICK ON X",
             "SPITFIRE JOYSTICKS", "SPITFIRE JOY", "SPITFIRE JOYSTICK A", "SPITFIRE JOYSTICK A DUAL",
             "SPITFIRE JOYSTICK PORT", "SPITFIRE JOYSTICK PORT A", "SPITFIRE JOYSTICK PORT DUAL",
             "SPITFIRE JOYSTICK PORTA DUAL", "SPITFIRE JOYSTICK PORT C DUAL", "SPITFIRE JOYSTICK PORT A TWIN",
             "SPITFIRE JOYSTICK PORT A DUAL X", "SPITFIRE JOYSTICK SETTYPE A 3BT", "SPITFIRE JOYSTICK USE A",
             "SPITFIRE ADVAL X", "SPITFIRE ADVAL ALL X", "SPITFIRE ADVALL"):
    config = avr.config
    a, out, osb, err = m.star(text)
    check(err and err.startswith("Syntax") and avr.config == config, f"*{text}: {a} {err} {osb}")

# --- Not ours ---
for text in ("SPITFIRES", "SPIT", "JOYSTICK", "HELP", "SPITFIRE.", "XSPITFIRE"):
    a, out, osb, err = m.star(text)
    check(a == 4 and not out and not err, f"*{text} claimed: {a} {out!r} {err}")

# --- *HELP ---
settings = "  Joystick {}\n  Port A: Standard dual joystick\n          Joysticks 1, 2\n  Port B: No joystick\n"
a, out, _, _ = m.help()
check(a == 9 and "SPItFIRE 0.02" in out and "  SPITFIRE\n" in out, f"*HELP: {out!r}")
check(out.endswith(settings.format("on")), f"*HELP settings: {out!r}")
a, out, _, _ = m.help("SPITFIRE")
check(a == 9 and "SPITFIRE ADVAL [ALL]" in out and "SPITFIRE JOYSTICK PORT A|B <type>" in out,
      f"*HELP SPITFIRE: {out!r}")
a, out, _, _ = m.help("spitfire joystick")
check(a == 9 and "SPITFIRE JOYSTICK PORT A|B <type>" in out and "ADVAL" not in out
      and out.endswith(settings.format("on")), f"*HELP SPITFIRE JOYSTICK: {out!r}")
check(max(len(l) for l in out.split("\n")) <= 40, f"*HELP wider than MODE 7: {out!r}")
for text in ("JOYSTICK", "MOS", "SPITFIRE MOUSE"):
    a, out, _, _ = m.help(text)
    check(a == 9 and (not out or text == "SPITFIRE MOUSE"), f"*HELP {text}: {out!r}")
check(not avr.y0, "Y0 was driven")

# --- Without workspace (after *SRLOAD ... I) ---
avr2 = AVR()
m2 = Machine(avr2, claim=False)
check(m2.mem[0x020A] | m2.mem[0x020B] << 8 == MOS_BYTEV, "hook installed without workspace")
reminder = "Press Ctrl-Break to start SPItFIRE\n"
a, out, _, _ = m2.star("SPITFIRE")
check(out.endswith(reminder), f"no ws *SPITFIRE: {out!r}")
for text in ("SPITFIRE JOYSTICK", "SPITFIRE ADVAL"):
    a, out, _, err = m2.star(text)
    check(a == 0 and out == reminder, f"no ws *{text}: {out!r} {err}")
a, out, _, _ = m2.status()
check(out == "SPItFIRE: " + reminder, f"no ws *STATUS: {out!r}")
a, out, _, _ = m2.help()
check(out.endswith("  " + reminder), f"no ws *HELP: {out!r}")
a, block = m2.osword()
check(a == 0 and block[:11] == [0x53, 1, 0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF, 1], f"no ws OSWORD: {block}")
a, out, _, err = m2.star("SPITFIRE JOYSTICK PORT B SINGLE")
check(a == 0 and not err and avr2.config == 0x4A, f"no ws PORT: {err} {avr2.config:02X}")

print("FAILURES:", fails)
sys.exit(1 if fails else 0)
