#!/usr/bin/env python3
"""Read (and optionally write to) the AVR's USART0 at 115200 8N1.

Usage: serread.py PORT [SECONDS] [TEXT_TO_SEND]
Example: serread.py /dev/cu.usbserial-0001 2 3   # set Port A to 14B, read 2 s

Uses only the standard library (termios), no pyserial needed.
"""
import os, sys, termios, time, select
if len(sys.argv) < 2:
    sys.exit(__doc__)
port=sys.argv[1]; secs=float(sys.argv[2]) if len(sys.argv)>2 else 3
fd=os.open(port, os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK)
a=termios.tcgetattr(fd)
a[0]=0; a[1]=0; a[2]=termios.CS8|termios.CREAD|termios.CLOCAL; a[3]=0
a[4]=a[5]=termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, a)
termios.tcflush(fd, termios.TCIFLUSH)
if len(sys.argv)>3:
    os.write(fd, sys.argv[3].encode())
buf=b''; end=time.time()+secs
while time.time()<end:
    r,_,_=select.select([fd],[],[],0.1)
    if r:
        try: buf+=os.read(fd,4096)
        except BlockingIOError: pass
os.close(fd)
sys.stdout.write(buf.decode('latin-1'))
