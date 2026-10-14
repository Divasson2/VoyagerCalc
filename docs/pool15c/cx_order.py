# Complex stack order check (distinct imaginary parts in X Y Z T LASTx) and that R2.. move with the window.
from v15 import *
for v in (150, 152):
    c = Calc(v); c.keys("22 STO 2 99 STO . 9 1 STO 0")
    m0 = c.mem(); w = m0[0x118:0x11f]; print(v, "before: window", w.hex(" "), "R2 at Nut %02x" % w[6])
    # build T=1+2i, Z=3+4i, Y=5+6i, X=7+8i, then LASTx = imag 8 after a unary op? use ENTER-free building:
    c.keys("1 ENTER 2 f TAN 3 ENTER 4 f TAN 5 ENTER 6 f TAN 7 ENTER 8 f TAN")
    c.keys("9 ENTER 10 f TAN g SQRT")   # x^2 of 9+10i: LASTx = 9+10i, X = -19+180i, stack lifted: drops 1+2i
    m = c.save("v%d_18_cx_order" % v); w = m[0x118:0x11f]
    b = w[6] - 5
    print("   window", w.hex(" "), "imag block Nut %02x..%02x:" % (b, b + 4), [bcd(reg(m, b + i - 0x10)) for i in range(5)])
    print("   real X Y Z T LASTx:", bcd(int.from_bytes(m[0x20:0x27], "little")), bcd(reg(m, 0)), bcd(reg(m, 1)), bcd(reg(m, 2)), bcd(reg(m, 0x13)))
    print("   R2 now at Nut %02x = %s ; R.9 = %s ; R0 = %s" % (w[6], bcd(reg(m, w[6] - 0x10)), bcd(reg(m, w[6] - 0x10 + 17)), bcd(reg(m, 0x10))))
