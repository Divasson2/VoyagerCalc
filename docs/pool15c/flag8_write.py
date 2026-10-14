import sys; sys.path.insert(0,'.')
from v15 import *
def st(c,tag):
    m=c.mem(); print("  %-34s C-ann=%d  0xC4=%02x 0x4C=%02x map.b6=%02x disp|%s|"%(tag,(c.ann()>>2)&1,m[0xC4],m[0x4C],m[0x11E],c.display()))
    return m
for v in (152,150):
    print("variant",v)
    src=Calc(v); src.keys("1 ENTER 2 ENTER 3 ENTER 4 g 4 8"); S=st(src,"source after SF 8")
    for case in ("write-as-0.6.3 (CPU kept)","+ 0x4C bit3 set","only 0x4C bit3 (no C4)"):
        dst=Calc(v); D=st(dst,"target empty")
        M=bytearray(D); M[0x70:0x7F0]=S[0x70:0x7F0]
        if case.startswith("+"): M[0x4C]|=8
        if case.startswith("only"): M[0x4C]|=8; M[0xC4]&=~1
        dst.load(M); lib.vc_run_ms(dst.c,300)
        st(dst,case+": loaded")
        dst.keys("5"); st(dst,"  after key 5")
        dst.keys("ENTER"); st(dst,"  after ENTER")
        # F? 8 test: g ×(x=0)? use g CHS? simpler: Re<>Im f - ; show X imaginary
        dst.keys("ON wait:800 ON wait:1500"); st(dst,"  after OFF/ON")
