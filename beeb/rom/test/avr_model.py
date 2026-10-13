"""A model of the spijoy firmware's SPI slave, as the ROM tests see it.

Decodes the bit-banged SPI (mode 0) from the User VIA port B writes, through
the 74HC138 decoder, and answers JOY_ADVAL, JOY_MOS, JOY_CONFIG, the CFG_
commands (which save the configuration in a model EEPROM) and JOY_TYPE_.
Attach it to a py65 ObservableMemory with `attach`.
"""
import random

IORB, SR = 0xFE60, 0xFE6A
Y1 = 1
CONFIG_DEFAULT = 0x40 | 1 | 1 << 2           # Both ports 3B Twin, handset 0

class AVR:
    def __init__(self):
        self.iorb = 0xFF; self.sr = 0; self.cs = False
        self.config = CONFIG_DEFAULT
        self.type = [self.config & 3, (self.config >> 2) & 3]
        self.eeprom = self.config; self.eeprom_writes = 0
        self.adval = [[random.randrange(256) for _ in range(5)] for _ in range(4)]
        self.absent = None                       # None, "high" or "low"
        self.transactions = 0; self.commands = []
        self.y0 = False

    def attach(self, mem):
        mem.subscribe_to_write([IORB], self.write_iorb)
        mem.subscribe_to_read([IORB], self.read_iorb)
        mem.subscribe_to_read([SR], self.read_sr)

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
        if self.absent: return                   # Nothing there to act on it
        if self.burst:
            self.out = self.burst.pop(0); return
        self.commands.append(b)
        if 0x50 <= b <= 0x54:
            h = (self.config >> 4) & 3 if b == 0x54 else b - 0x50
            data = [0xA0 | self.type[h >> 1]] + self.adval[h]
            self.out = data[0]; self.burst = data[1:] + [0xFF]
        elif b == 0x58:
            self.out = self.config
        elif 0xD0 <= b <= 0xDB:
            shift = 2 * ((b >> 2) & 3)
            self.config = (self.config & ~(3 << shift)) | ((b & 3) << shift)
            self.type = [self.config & 3, (self.config >> 2) & 3]
            if self.eeprom != self.config:       # eeprom_update_block
                self.eeprom = self.config; self.eeprom_writes += 1
            self.out = b
        elif 0xE0 <= b <= 0xE7:
            self.type[(b >> 2) & 1] = b & 3; self.out = b
        else:
            self.out = 0xFF

    def read_iorb(self, addr): return self.iorb

    def read_sr(self, addr):
        if self.absent == "high": return 0xFF
        if self.absent == "low": return 0x00
        return self.sr
