# Which of the 32 system registers (dump 0x70..0x16F) change with display/angle/USER modes, RAN#, program position.
from v15 import *
def sd(a, b, skip=(0, 1, 2)):
    return " ".join("%02x:%s>%s" % (k, hexreg(reg(a, k)), hexreg(reg(b, k))) for k in diff(a, b) if k < 0x20 and k not in skip)
c = Calc(150); c.keys("1 ENTER")
for keys, tag in (("f 7 2", "FIX 2"), ("f 8 3", "SCI 3"), ("f 9 4", "ENG 4"), ("f 7 4", "FIX 4"), ("g 8", "RAD"), ("g 9", "GRAD"), ("g 7", "DEG"),
                  ("f RCL", "USER on"), ("f RCL", "USER off"), (". 5 STO ENTER", "STO RAN# 0.5"), ("f ENTER", "RAN#"), ("f ENTER", "RAN# again"),
                  ("g RS f RDN f SST SQRT 1 + 2 + g GSB g RS", "program 5 lines"), ("GTO SQRT", "GTO A"), ("SST", "SST"), ("SST", "SST"),
                  ("g RS", "P/R on"), ("g RS", "P/R off"), ("12 STO TAN", "I=12"), ("4 ENTER 5 +", "LASTx")):
    a = c.mem(); c.keys(keys); b = c.mem()
    print("%-18s %s" % (tag, sd(a, b)))
c.save("v150_90_sysregs_end")
