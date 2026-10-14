# Complex mode: g SF 8, f I, Re<>Im, g CF 8. Diff each step, g MEM, Nut 0x15 window, flags (Nut 0x1A).
from v15 import *
def step(c, prev, keys, tag, v):
    c.keys(keys); m = c.save("v%d_%s" % (v, tag))
    print("  %-28s disp|%s| ann=%x  g MEM %-11s nut15 %s  nut1a %s" % (tag + " [" + keys + "]", c.display(), c.ann(), c.gmem(), m[0x118:0x11f].hex(" "), hexreg(reg(m, 0x1a))))
    for k in diff(prev, m):
        print("      idx %02x (Nut %02x) off %03x %s  %s" % (k, k + 0x10 if k >= 0x20 else k, nut_off(k), hexreg(reg(m, k)), bcd(reg(m, k))))
    cd = cpu_diff(prev, m)
    if cd: print("      cpu bytes changed:", " ".join("%02x:%02x>%02x" % (i, prev[i], m[i]) for i in cd))
    return m
for v in (150, 152):
    print("variant", v)
    c = Calc(v)
    c.keys("1 ENTER 2 ENTER 3 ENTER 4")            # X=4 Y=3 Z=2 T=1, fill real stack first
    m = c.save("v%d_10_cx_before" % v); print("  before: g MEM", c.gmem(), "nut15", m[0x118:0x11f].hex(" "))
    m = step(c, m, "g 4 8", "11_sf8", v)
    m = step(c, m, "f TAN", "12_fI", v)          # f I: X=re part from Y, imag from X
    m = step(c, m, "5 ENTER 6 f TAN", "13_5+6i", v)
    m = step(c, m, "7 f -", "14_ReIm", v)          # Re<>Im on 7+0i -> 0+7i
    m = step(c, m, "+", "15_plus", v)              # LASTx gets an imaginary part too
    m = step(c, m, "g 5 8", "16_cf8", v)
    # complex mode reached through f I alone (flag 8 clear before)
    c2 = Calc(v); c2.keys("1 ENTER 2"); m0 = c2.mem()
    print("  fresh: f I without SF 8")
    step(c2, m0, "f TAN", "17_fI_only", v)
