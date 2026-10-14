# Largest matrix accepted (n x 1, and square), empty program, DIM (i) 19.
from v15 import *
def ok(c, r, k):
    c.keys("%d ENTER %d f SIN SQRT" % (r, k)); e = "Error" in c.display()
    if e: c.keys("BSP")
    c.keys("0 ENTER 0 f SIN SQRT"); return not e
for v in (150, 152):
    c = Calc(v); c.keys("g 4 8 g 5 8")
    lo, hi = 1, 300
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if ok(c, mid, 1): lo = mid
        else: hi = mid - 1
    sq = max(n for n in range(1, 20) if ok(c, n, n))
    c.keys("%d ENTER 1 f SIN SQRT" % lo); m = c.mem()
    print(v, "max n x 1 =", lo, " max square =", sq, " at max n x 1: nut15", m[0x118:0x11f].hex(" "), "g MEM", c.gmem())
    c.keys("0 ENTER 0 f SIN SQRT 1 ENTER 99 f SIN EX"); print("   1x99 B:", c.display(), c.gmem(), "  ", end="")
    c.keys("0 ENTER 0 f SIN EX 99 ENTER 1 f SIN EX"); print("99x1:", c.display(), c.gmem(), c.mem()[0x138:0x13f][::-1].hex(" "))
