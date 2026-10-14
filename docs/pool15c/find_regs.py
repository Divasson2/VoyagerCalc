# Step 0: where R0..R.9, I, LASTx, X..T live (distinct values keyed in), both variants.
from v15 import *
for v in (150, 152):
    c = Calc(v); base = c.mem()
    seq = []
    for n in range(10): seq.append("%d STO %d" % (100 + n, n))
    for n in range(10): seq.append("%d STO . %d" % (200 + n, n))
    c.keys(" ".join(seq)); c.keys("300 STO TAN")    # STO I  (I = TAN key position, unshifted after STO)
    c.keys("11 ENTER 12 ENTER 13 ENTER 14 ENTER 15 +")   # LASTx = 15, X = 29, Y = 13, Z = 12, T = 12? (stack lift)
    m = c.save("v%d_01_regs" % v)
    print("variant", v, c.gmem(), "display", c.display())
    for k in diff(base, m): print("  idx %02x off %03x %s  %s" % (k, nut_off(k), hexreg(reg(m, k)), bcd(reg(m, k))))
    print("  X(M @0x20)", bcd(int.from_bytes(m[0x20:0x27], "little")))
