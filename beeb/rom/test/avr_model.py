"""A model of the spijoy firmware's SPI slave, as the ROM tests see it.

Decodes the bit-banged SPI (mode 0) from the User VIA port B writes, through
the 74HC138 decoder, and answers JOY_ALL, JOY_CONFIG, the CFG_PORT_ commands
(which save the configuration in a model EEPROM) and JOY_PORT_, building the
JOY_ALL burst as firmware/src/spijoy.cpp does. Attach it to a py65
ObservableMemory with `attach`.
"""
import random

IORB, SR = 0xFE60, 0xFE6A
Y1 = 1
NONE, SINGLE, DUAL, D3BS, D3BT, D14B, BITSTIK, QUINKEY = range(8)
JOYSTICKS = [0, 1, 2, 2, 2, 1, 2, 2]
CONFIG_DEFAULT = 0x40 | DUAL | NONE << 3          # Port A Dual, Port B None
KEY_FIRE_14B = 1 << 10

def adval_value(v):
    return ((v << 6) | (v >> 4)) & 0xFFFF

class AVR:
    def __init__(self):
        self.iorb = 0xFF; self.sr = 0; self.cs = False
        self.config = CONFIG_DEFAULT
        self.type = [self.config & 7, (self.config >> 3) & 7]
        self.eeprom = self.config; self.eeprom_writes = 0
        self.randomise()
        self.absent = None                       # None, "high" or "low"
        self.transactions = 0; self.commands = []
        self.y0 = False

    def randomise(self):
        """New readings: 10-bit channels CH0-CH3, fire inputs (b0 pin 13,
        b1 pin 10) and 14B keys, per port."""
        self.channels = [[random.randrange(1024) for _ in range(4)] for _ in range(2)]
        self.fire = [random.randrange(4) for _ in range(2)]
        self.keys = [random.randrange(4096) for _ in range(2)]

    def sticks(self):
        """The allocated joysticks, Port A's first, as the firmware sees them."""
        out = []
        for p in range(2):
            t = self.type[p]
            for j in range(JOYSTICKS[t]):
                x, y = self.channels[p][2 * j], self.channels[p][2 * j + 1]
                keypad = self.keys[p] if t == D14B else None
                if t == D14B: fire = bool(self.keys[p] & KEY_FIRE_14B)
                elif t == QUINKEY: fire = False
                else: fire = bool((self.fire[p] >> j) & 1)
                out.append(dict(x=x, y=y, fire=fire, dirs=t != QUINKEY, keypad=keypad))
        return out

    @staticmethod
    def directions(s):
        if not s["dirs"]: return 0
        d = 0
        if s["x"] >= 768: d |= 0x10
        if s["x"] < 256: d |= 0x80
        if s["y"] >= 768: d |= 0x40
        if s["y"] < 256: d |= 0x20
        return d

    @classmethod
    def switch(cls, s):
        """A joystick's switch byte: fire in b0, directions in b4-7."""
        return 0 if s is None else cls.directions(s) | int(s["fire"])

    def burst(self):
        sticks = self.sticks()
        n = len(sticks)
        k = sum(1 << i for i, s in enumerate(sticks) if s["keypad"] is not None)
        out = [0xA0 | n, 0x50 | k]
        def value(v): out.extend([adval_value(v) & 0xFF, adval_value(v) >> 8])
        for i in range(max(n, 1)):                 # J1's record is always sent
            s = sticks[i] if i < n else None
            out.append(self.switch(s)); value(s["x"] if s else 0); value(s["y"] if s else 0)
        for s in sticks:
            if s["keypad"] is not None:
                out.extend([s["keypad"] & 0xFF, s["keypad"] >> 8])
        return out

    def expected(self):
        """What the ROM should hold afterwards: ADVAL(0)-(2) as the MOS's five
        bytes, and every hooked channel's 16-bit value (0 if unallocated)."""
        sticks = self.sticks()
        n = len(sticks)
        def sw(i):
            return self.switch(sticks[i]) if i < n else 0
        def pair(first):                          # ADVAL(0) and (16): fire bits
            return sw(first) | (sw(first + 1) & 1) << 1
        def xy(i, axis):
            return adval_value(sticks[i]["xy"[axis]]) if i < n else 0
        mos = [pair(0), xy(0, 0) & 0xFF, xy(0, 0) >> 8, xy(0, 1) & 0xFF, xy(0, 1) >> 8]
        ch = {3: xy(1, 0), 4: xy(1, 1), 12: sw(0) | sw(1) << 8,
              16: pair(2), 17: xy(2, 0), 18: xy(2, 1), 19: xy(3, 0), 20: xy(3, 1),
              28: sw(2) | sw(3) << 8}
        for c, i in ((10, 0), (11, 1), (26, 2), (27, 3)):
            ch[c] = sticks[i]["keypad"] if i < n and sticks[i]["keypad"] is not None else 0
        return mos, ch

    def attach(self, mem):
        mem.subscribe_to_write([IORB], self.write_iorb)
        mem.subscribe_to_read([IORB], self.read_iorb)
        mem.subscribe_to_read([SR], self.read_sr)

    def write_iorb(self, addr, v):
        prev, self.iorb = self.iorb, v
        dev = (v >> 2) & 7
        if dev == 0: self.y0 = True
        if dev != Y1:
            if self.cs: self.pending = []        # SS rising ends a burst
            self.cs = False; return
        if not self.cs:
            assert not (v & 2), "AVR selected with SCK high"
            self.cs = True; self.bits = 0; self.rx = 0; self.pending = []
            self.out = 0xFF; self.transactions += 1
        if (v & 2) and not (prev & 2):           # Rising edge
            if self.bits == 0: self.tx = self.out
            self.rx = ((self.rx << 1) | (v & 1)) & 0xFF
            self.bits += 1
            if self.bits == 8:
                self.bits = 0; self.sr = self.tx; self.isr(self.rx)

    def isr(self, b):
        if self.absent: return                   # Nothing there to act on it
        if self.pending:
            self.out = self.pending.pop(0); return
        self.commands.append(b)
        if b == 0x55:
            data = self.burst()
            self.out = data[0]; self.pending = data[1:] + [0xFF]
        elif b == 0x58:
            self.out = self.config
        elif 0xD0 <= b <= 0xDF:
            shift = 3 * ((b >> 3) & 1)
            self.config = (self.config & ~(7 << shift)) | ((b & 7) << shift)
            self.type = [self.config & 7, (self.config >> 3) & 7]
            if self.eeprom != self.config:       # eeprom_update_block
                self.eeprom = self.config; self.eeprom_writes += 1
            self.out = b
        elif 0xE0 <= b <= 0xEF:
            self.type[(b >> 3) & 1] = b & 7; self.out = b
        else:
            self.out = 0xFF

    def read_iorb(self, addr): return self.iorb

    def read_sr(self, addr):
        if self.absent == "high": return 0xFF
        if self.absent == "low": return 0x00
        return self.sr
