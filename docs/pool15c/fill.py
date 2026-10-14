# Fill the whole pool (storage + one matrix filled with 1s) to see the pool bounds in the dump; check FinancePac.
from v15 import *
FP = "/home/box/agent-data/agents/5f08829f-7c0d-47f5-a4b1-2fd9b0641143/attachments/9f657e04cb00bebf352f05cdaf32b39f3ebc4204f43144d45c2e06bcd0e2b92d.bin"
for v, dim, free in ((150, 19, 78), (152, 19, 174)):
    c = Calc(v); c.keys("g 4 8 g 5 8")       # forces the 15.2 window down to the pool bottom
    n = free
    c.keys("%d ENTER 1 f SIN SQRT" % n); print(v, "DIM A %dx1:" % n, c.display(), "g MEM", c.gmem())
    c.keys("1 STO CHS SQRT")                  # STO MATRIX A: every element = 1
    c.keys("1 STO 0 2 STO 1 3 STO 2 19 STO . 9")
    m = c.save("v%d_70_full" % v)
    nz = [k for k in range(0x20, 0xF0) if reg(m, k)]
    print("   non-zero pool idx %02x..%02x (dump 0x%03x..0x%03x), count %d; nut15 %s" % (nz[0], nz[-1], nut_off(nz[0]), nut_off(nz[-1]) + 7, len(nz), m[0x118:0x11f].hex(" ")))
    c.keys("1 ENTER 2 f SIN EX"); print("   one more (DIM B 1x2):", c.display())
m = bytearray(open(FP, "rb").read())
print("FinancePac: nut15", m[0x118:0x11f].hex(" "), "nut19", m[0x138:0x13f][::-1].hex(" "), "nut1a", hexreg(reg(m, 0x1a)), "nut16", hexreg(reg(m, 0x16)), "nut0a", hexreg(reg(m, 0x0a)))
c = Calc(152); c.load(m); c.keys("wait:500"); print("  loaded in 15.2: g MEM", c.gmem())
