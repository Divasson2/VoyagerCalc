#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 José González Divassón
"""The Python simulator's view of the HP-16C registers, for comparison with `vcore --inspect`.

Runs the keys in voyager-sim-public's program runner (Unicorn), then reads the registers through
that simulator's own firmware-style Nut RAM mapping (runner16c.nut_ram: logical Nut addresses,
extended-memory remap), not through 2 KB-dump offsets like the C core does:
  X = CPU register M, Y/Z/T/LAST X = Nut 0..3, high bytes in Nut 7, I = Nut 0xFD (+0xFE),
  status = Nut 6, pool = logical Nut 0x4D..0xFC (Path-C) with R0 at nibble 0, program from 0xFC.
Path-C (extended-memory) firmware only.
usage: pyinspect.py FIRMWARE.bin [--load M.16c] --keys "..."   -> lines 'NAME WORDHEX'"""
import sys, os, argparse, struct
SIM = os.environ.get('VOYAGER_SIM', '/workspace/voyager-sim-public')
sys.path.insert(0, SIM)
from voyager.runner16c import Calc16C, STRUCT

ap = argparse.ArgumentParser(); ap.add_argument('fw'); ap.add_argument('--load'); ap.add_argument('--keys', action='append', default=[])
a = ap.parse_args()
c = Calc16C(a.fw)
if a.load: c.load(open(a.load, 'rb').read())
for k in a.keys: c.keys(k)
ram = c.ram
nib = lambda v, i: (v >> (4 * i)) & 15
st = ram(6)
ws = 4 * (15 - nib(st, 11)) + bin(nib(st, 10)).count('1'); flt = nib(st, 13) == 0xC
if flt: ws = 56
mask = (1 << ws) - 1
M = struct.unpack('<Q', bytes(c.u.mem_read(STRUCT + 0x18, 8)))[0] & ((1 << 56) - 1)
hi = ram(7)
def word(lo, ext): return lo if flt else ((ext << 56) | lo) & mask
ext = lambda k: nib(hi, k) | nib(hi, k + 1) << 4
print('X', f'{word(M, ext(0)):016x}')
for name, n, e in (('Y', 0, 3), ('Z', 1, 5), ('T', 2, 7), ('LAST X', 3, 9)): print(name, f'{word(ram(n), ext(e)):016x}')
print('I', f'{word(ram(0xFD), nib(ram(0xFE), 3) | nib(ram(0xFE), 4) << 4):016x}')
ext_mem = c.img[0xE000:0xE004] != b'\0\0\0\0'
first, slots = (0x4D, 176) if ext_mem else (0xE0, 29)
p = ram(0xFE); reg, pos = p & 0xFF, (p >> 8) & 15
lines = (0xFC - reg) * 7 + pos if reg else 0
size = (ws + 3) // 4; nregs = (slots - (lines + 6) // 7) * 14 // size
def pool_nibble(j): return nib(ram(first + j // 14), j % 14)
for r in range(nregs):
    v = 0
    for k in range(size): v |= pool_nibble(r * size + k) << (4 * k)
    name = f'R{r:X}' if r < 16 else f'R.{r - 16:X}' if r < 32 else f'R{r}'
    print(name, f'{v:016x}')
print('lines', lines, 'regs', nregs, 'ws', ws)
