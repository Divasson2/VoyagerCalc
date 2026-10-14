# SOLVE scratch together with the complex stack: which comes first at the pool bottom; Nut 0x14 after each.
from v15 import *
for v in (150, 152):
    c = Calc(v); pb = 0xA0 if v == 150 else 0x40
    c.keys("g RS f RDN f SST SQRT g SQRT 2 - g GSB g RS")
    c.keys("g 4 8 77 ENTER 88 f TAN 1 ENTER 2 f / SQRT wait:3000")
    m = c.save("v%d_64_cx_plus_solve" % v); w = m[0x118:0x11f]
    print(v, "nut15", w.hex(" "), "nut14", hexreg(reg(m, 0x14)), "nut0a", hexreg(reg(m, 0x0a)))
    print("   pool bottom Nut %02x.. :" % pb, [bcd(reg(m, pb - 0x10 + i)) for i in range(w[6] - pb)])
    c.keys("g RCL wait:2500"); m = c.mem(); w = m[0x118:0x11f]
    print("   after g MEM: nut15", w.hex(" "), "nut14", hexreg(reg(m, 0x14)), [bcd(reg(m, pb - 0x10 + i)) for i in range(w[6] - pb)])
