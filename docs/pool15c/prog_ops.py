# A program using matrix and complex functions: how the listing names them, and where it sits in the pool.
from v15 import *
import subprocess
PRG = ("f SST SQRT "            # LBL A
       "f SIN COS "             # DIM (i)
       "2 ENTER 3 f SIN SQRT "  # DIM A
       "f SIN EX "              # DIM B
       "f CHS 1 f CHS 0 f CHS 5 "   # MATRIX 1, MATRIX 0, MATRIX 5
       "f EEX 10X "             # RESULT C
       "RCL CHS SQRT STO CHS EX "   # RCL MATRIX A, STO MATRIX B
       "STO SQRT RCL SQRT "     # STO A, RCL A
       "STO g SQRT RCL g EX "   # STO g A, RCL g B
       "RCL f SIN SQRT "        # RCL DIM A
       "STO EEX RCL EEX "       # STO RESULT, RCL RESULT
       "f TAN f - "             # I, Re<>Im
       "g 4 8 g 6 8 g 5 8 "     # SF 8, F? 8, CF 8
       "f / SQRT f * EX "       # SOLVE A, integrate B
       "g GSB")                 # RTN
for v in (150, 152):
    c = Calc(v); b = c.mem()
    c.keys("g RS f RDN " + PRG + " g RS")
    m = c.save("v%d_50_prog_ops" % v)
    print("variant", v, "g MEM", c.gmem(), "nut15", m[0x118:0x11f].hex(" "), "nut16", hexreg(reg(m, 0x16)), "nut17", hexreg(reg(m, 0x17)))
    print("  program registers changed:", " ".join("%02x" % k for k in diff(b, m) if k >= 0x20))
    out = subprocess.run(["../../core/build/vcore", "-f", FW, "--whole", "--load", "dumps/v%d_50_prog_ops.bin" % v, "--list"], capture_output=True, text=True).stdout
    if v == 150: print(out)
