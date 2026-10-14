# largest DIM (i) accepted (empty program, no matrices), and the window bytes at that size
from v15 import *
for v in (150, 152):
    c = Calc(v); lo, hi = 1, 400
    while lo < hi:
        mid = (lo + hi + 1) // 2
        c.keys("%d f SIN COS" % mid)
        if "Error" in c.display(): hi = mid - 1; c.keys("BSP")
        else: lo = mid
    c.keys("%d f SIN COS" % lo); m = c.mem()
    print(v, "max DIM(i) =", lo, "g MEM", c.gmem(), "nut15", m[0x118:0x11f].hex(" "))
    c.keys("19 f SIN COS"); m = c.save("v%d_04_dim19_after_max" % v); print("   back to 19:", c.gmem(), m[0x118:0x11f].hex(" "))
