# Where are the D and E dimensions? Dimension byte encoding (binary or BCD) with sizes > 9.
from v15 import *
for v in (150, 152):
    c = Calc(v); print("variant", v)
    for keys, tag in (("1 ENTER 1 f SIN SQRT", "A1x1"), ("2 ENTER 1 f SIN EX", "B2x1"), ("3 ENTER 1 f SIN 10X", "C3x1"),
                      ("4 ENTER 1 f SIN YX", "D4x1"), ("5 ENTER 1 f SIN 1/X", "E5x1"), ("1 ENTER 2 f SIN 1/X", "E1x2"),
                      ("1 ENTER 12 f SIN 1/X", "E1x12"), ("12 ENTER 1 f SIN YX", "D12x1"), ("1 ENTER 11 f SIN YX", "D1x11")):
        b = c.mem(); c.keys(keys); m = c.mem()
        ch = [k for k in diff(b, m) if k not in (0, 1, 2, 4, 9, 0x0a, 0x15, 0x19) and k < 0x20]
        print("  %-6s disp|%s| gMEM %-10s nut15 %s nut19(b6..b0) %s ; other: %s" % (tag, c.display(), c.gmem(), m[0x118:0x11f].hex(" "),
              m[0x138:0x13f][::-1].hex(" "), " ".join("%02x=%s" % (k, hexreg(reg(m, k))) for k in ch)))
    c.save("v%d_40_dims_ABCDE" % v)
