import sys; sys.path.insert(0,'.')
from v15 import *
def st(c,t):
    m=c.mem(); print("  %-28s C=%d c4=%02x 4c=%02x 30=%02x |%s|"%(t,(c.ann()>>2)&1,m[0xC4],m[0x4C],m[0x30],c.display())); return m
for v in (152,):
    src=Calc(v); src.keys("1 ENTER 2 g 4 8"); S=src.mem()
    # turn target off first, then load (like an image written while the calc is idle), then ON
    dst=Calc(v); dst.keys("ON wait:1000"); D=st(dst,"target off")
    M=bytearray(D); M[0x70:0x7F0]=S[0x70:0x7F0]; dst.load(M); lib.vc_run_ms(dst.c,300)
    st(dst,"loaded while off"); dst.keys("ON wait:1500"); st(dst,"after ON")
    dst.keys("5"); st(dst,"after 5")
