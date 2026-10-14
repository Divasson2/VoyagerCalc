# Matrices: DIM A/B/C, fill, RESULT, multiply, redimension, MATRIX 0. Diff each step.
from v15 import *
import sys
def X(m): return int.from_bytes(m[0x20:0x27], "little")
def step(c, prev, keys, tag, v, quiet=False):
    c.keys(keys); m = c.save("v%d_%s" % (v, tag))
    print("  %-34s disp|%s| gMEM %-11s nut15 %s  X=%s" % (tag + " [" + keys + "]", c.display(), c.gmem(), m[0x118:0x11f].hex(" "), hexreg(X(m))))
    if not quiet:
        for k in diff(prev, m):
            if k in (4, 9): continue
            print("      idx %02x (Nut %02x) off %03x %s  %s" % (k, k + 0x10 if k >= 0x20 else k, nut_off(k), hexreg(reg(m, k)), bcd(reg(m, k))))
    return m
v = int(sys.argv[1]) if len(sys.argv) > 1 else 150
print("variant", v)
c = Calc(v)
c.keys("22 STO 2 99 STO . 9")
m = c.save("v%d_20_mx_base" % v); print("  base nut15", m[0x118:0x11f].hex(" "), "gMEM", c.gmem())
m = step(c, m, "2 ENTER 3 f SIN SQRT", "21_dimA_2x3", v)
m = step(c, m, "1 ENTER 2 f SIN EX", "22_dimB_1x2", v)
m = step(c, m, "f CHS 1 f RCL", "23_matrix1_user", v)            # MATRIX 1 (R0=R1=1), USER on
m = step(c, m, "11 STO SQRT 12 STO SQRT 13 STO SQRT 21 STO SQRT 22 STO SQRT 23 STO SQRT", "24_fillA", v)
m = step(c, m, "5 STO EX 6 STO EX", "25_fillB", v)
m = step(c, m, "f RCL 3 ENTER 1 f SIN 10X", "26_dimC_3x1_userOff", v)
m = step(c, m, "f EEX 10X", "27_result_C", v)
m = step(c, m, "RCL CHS EX", "28_rclmat_B", v)
m = step(c, m, "RCL CHS SQRT", "29_rclmat_A", v)
m = step(c, m, "*", "30_BxA_into_C", v)
m = step(c, m, "1 ENTER 2 RCL g SQRT", "31_rcl_gA_1_2", v)     # RCL g A: element (Y=row 1, X=col 2) of A
m = step(c, m, "3 ENTER 3 f SIN SQRT", "32_redimA_3x3", v)
m = step(c, m, "2 ENTER 2 f SIN SQRT", "33_redimA_2x2", v)
m = step(c, m, "g 4 8", "34_sf8_with_matrices", v)
m = step(c, m, "f CHS 0", "35_matrix0", v)
m = step(c, m, "g 5 8", "36_cf8", v)
