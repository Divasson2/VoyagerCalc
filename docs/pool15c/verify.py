# verify.py - checks pool15.decode() against the live calculator in many states (both variants):
#   g MEM (all 4 fields), matrix elements (RCL g X with row/col), imaginary stack (Re<>Im), flags.
from v15 import *
import pool15
fails = checks = 0
def check(cond, msg):
    global fails, checks
    checks += 1
    if not cond: fails += 1; print("   FAIL", msg)
def state(c, tag):
    m = c.mem(); r = pool15.decode(m, c.variant())
    g = " ".join(c.gmem().replace("-", " - ").split()).replace(" - ", "-")
    want = r["gmem"]
    # g MEM shows "19174 00-0" (no space when the 2nd field has 3 digits): compare digits only
    check(g.replace(" ", "") == want.replace(" ", ""), "%s: g MEM %s vs decoded %s" % (tag, g, want))
    # matrix elements against RCL g <matrix> (row in Y, col in X), first and last element of each
    for i, L in enumerate("ABCDE"):
        rr, cc = r["dims"][i]
        for (a, b) in {(1, 1), (rr, cc)} if rr * cc else ():
            c.keys("%d ENTER %d RCL g %s" % (a, b, ["SQRT", "EX", "10X", "YX", "1/X"][i]))
            live = c.display().strip().rstrip("0").rstrip(".") or "0"
            k = (a - 1) * cc + (b - 1)
            dec = pool15.bcd(pool15.rd(c.mem(), r["starts"][i] + k))
            check(abs(float(dec) - float(c.display().replace(" ", "") or 0)) < 1e-6 * max(1, abs(float(dec))), "%s: %s(%d,%d) live %s dump %s" % (tag, L, a, b, live, dec))
    print("  ok %-34s g MEM %-12s %s" % (tag, want, " ".join("%s%dx%d" % (L, *r["dims"][i]) for i, L in enumerate("ABCDE") if r["dims"][i][0])))
    return r
for v in (150, 152):
    print("variant", v)
    c = Calc(v)
    state(c, "cold")
    c.keys("22 STO 2 2 ENTER 3 f SIN SQRT f CHS 1 f RCL 11 STO SQRT 12 STO SQRT 13 STO SQRT 21 STO SQRT 22 STO SQRT 23 STO SQRT f RCL"); state(c, "A 2x3 filled")
    c.keys("3 ENTER 2 f SIN EX 7 STO CHS EX"); state(c, "B 3x2 = 7")
    c.keys("f EEX 10X RCL CHS EX RCL CHS SQRT *"); state(c, "C = B x A (RESULT C)")
    c.keys("4 ENTER 4 f SIN YX 9 STO CHS YX 1 ENTER 5 f SIN 1/X 3 STO CHS 1/X"); state(c, "D 4x4, E 1x5")
    c.keys("g 4 8"); r = state(c, "SF 8 with matrices"); check(r["complex"], "complex flag")
    c.keys("1 ENTER 2 f TAN 3 ENTER 4 f TAN")
    m = c.mem(); r = pool15.decode(m, v); im = [pool15.bcd(pool15.rd(m, r["imag_at"] + i)) for i in range(5)]
    check(im[4] == "4" and im[3] == "2", "imag X/Y %s" % im); print("  ok imaginary block (LASTx T Z Y X):", im)
    c.keys("30 f SIN COS"); state(c, "DIM (i) 30 + complex + matrices")
    c.keys("g RS f RDN f SST SQRT 1 2 3 4 5 6 7 8 9 + g GSB g RS"); state(c, "program 12 lines")
    c.keys("2 ENTER 2 f SIN SQRT"); state(c, "redim A 2x2")
    c.keys("g 5 8"); r = state(c, "CF 8"); check(not r["complex"] and r["imag_at"] is None, "complex off")
    c.keys("f CHS 0"); state(c, "MATRIX 0")
    c.keys("g 4 3 g 4 9 g 5 9"); r = pool15.decode(c.mem(), v); check(r["flags"][3] and not r["flags"][9], "flags %s" % r["flags"])
print("%d checks, %d failed -> %s" % (checks, fails, "VERIFY: FAIL" if fails else "VERIFY: OK"))
