# SOLVE / integrate scratch: sample the pool window (Nut 0x15) while they run, and after.
from v15 import *
for v in (150, 152):
    c = Calc(v)
    c.keys("g RS f RDN f SST SQRT g SQRT 2 - g GSB f SST EX g SQRT g GSB g RS")   # LBL A x^2 2 - RTN ; LBL B x^2 RTN
    c.keys("f SIN SQRT 5 STO 2")   # nothing; (f SIN SQRT without numbers would DIM A from stack: avoid) -> undo below
    c.keys("0 ENTER 0 f SIN SQRT")  # A back to 0x0
    m0 = c.save("v%d_60_scratch_before" % v); print("variant", v, "before: g MEM", c.gmem(), "nut15", m0[0x118:0x11f].hex(" "))
    for keys, tag in (("1 ENTER 2 f / SQRT", "SOLVE A"), ("0 ENTER 1 f * EX", "integrate B"), ("g 4 8 1 ENTER 2 f / SQRT", "SOLVE A in complex mode")):
        for k in keys.split()[:-1]: c.keys(k)
        lib.vc_press_key(c.c, CODE[keys.split()[-1]]); lib.vc_run_ms(c.c, 80); lib.vc_release_key(c.c, CODE[keys.split()[-1]])
        seen = {}; peak = None
        for i in range(3000):
            lib.vc_run_ms(c.c, 10); m = c.mem(); w = m[0x118:0x11f].hex(" ")
            if w not in seen: seen[w] = i * 10; peak = m
            d = c.display()
            if i > 30 and "running" not in d and d.strip() and w == m0[0x118:0x11f].hex(" ") and len(seen) > 1: break
        lib.vc_run_ms(c.c, 3000); m = c.mem()
        print("  %-24s windows seen (ms): %s" % (tag, seen))
        print("     result |%s| after: g MEM %s nut15 %s" % (c.display(), c.gmem(), m[0x118:0x11f].hex(" ")))
        if len(seen) > 1:
            pk = list(seen)[1]; open("dumps/v%d_61_scratch_%s.bin" % (v, tag.split()[0].lower()), "wb").write(peak)
        m0 = m
