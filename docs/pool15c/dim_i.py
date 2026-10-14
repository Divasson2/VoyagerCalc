# DIM (i): where R20.. land, how Nut 0x15 (dump 0x118) changes, and g MEM. Both variants.
from v15 import *
def show(c, m, base, tag):
    print(" ", tag, "g MEM", c.gmem(), " nut15 =", m[0x118:0x11f].hex(" "))
    for k in diff(base, m):
        if k not in (0, 1, 2, 4, 9, 0x0a, 0x13): print("    idx %02x off %03x %s  %s" % (k, nut_off(k), hexreg(reg(m, k)), bcd(reg(m, k))))
for v, n in ((150, 50), (152, 150)):
    print("variant", v)
    c = Calc(v); base = c.mem()
    c.keys("%d f SIN COS" % n); m1 = c.save("v%d_02_dim%d" % (v, n)); show(c, m1, base, "DIM (i)=%d" % n)
    c.keys("%d STO TAN 777 STO COS 20 STO TAN 555 STO COS" % n)
    m2 = c.save("v%d_03_dim%d_R%d" % (v, n, n)); show(c, m2, base, "R%d=777 R20=555" % n)
    c.keys("999 f SIN COS"); print("   999 DIM(i) ->", c.display(), "| after ->", c.keys("BSP").gmem(), c.mem()[0x118:0x11f].hex(" "))
    c.keys("0 f SIN COS"); m3 = c.mem(); print("   DIM(i)=0:", c.gmem(), m3[0x118:0x11f].hex(" "))
    c.keys("1 f SIN COS"); m3 = c.mem(); print("   DIM(i)=1:", c.gmem(), m3[0x118:0x11f].hex(" "))
