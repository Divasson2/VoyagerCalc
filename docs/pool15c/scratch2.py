# What records the SOLVE / integrate scratch size, and what releases it.
from v15 import *
def sysdiff(a, b):
    return " ".join("%02x:%s>%s" % (k, hexreg(reg(a, k)), hexreg(reg(b, k))) for k in diff(a, b) if k < 0x20 and k not in (0, 1, 2, 4, 9, 0x13))
for v in (150,):
    c = Calc(v)
    c.keys("g RS f RDN f SST SQRT g SQRT 2 - g GSB f SST EX g SQRT g GSB g RS")
    a = c.mem()
    c.keys("1 ENTER 2 f / SQRT wait:3000"); b = c.save("v150_62_after_solve")
    print("SOLVE:", b[0x118:0x11f].hex(" "), "|", sysdiff(a, b))
    c.keys("0 ENTER 1 f * EX wait:5000"); d = c.save("v150_63_after_integrate")
    print("INT  :", d[0x118:0x11f].hex(" "), "|", sysdiff(b, d))
    print("  scratch block idx 90..a6:", [bcd(reg(d, k)) for k in range(0x90, 0xa7)])
    for keys, tag in (("g RCL", "g MEM"), ("1 ENTER 1 f SIN SQRT", "DIM A 1x1"), ("0 ENTER 0 f SIN SQRT", "DIM A 0x0"),
                      ("19 f SIN COS", "DIM (i) 19"), ("f CHS 0", "MATRIX 0"), ("g 4 8", "SF 8"), ("g 5 8", "CF 8")):
        e = c.mem(); c.keys(keys + " wait:2500"); f = c.mem()
        print("  %-12s -> nut15 %s  g MEM %s | %s" % (tag, f[0x118:0x11f].hex(" "), c.gmem(), sysdiff(e, f)))
