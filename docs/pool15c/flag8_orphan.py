import sys; sys.path.insert(0,'.')
from v15 import *
for v in (152,150):
    src=Calc(v); src.keys("1 ENTER 2 ENTER 3 ENTER 4 g 4 8"); S=src.mem()
    dst=Calc(v); D=dst.mem(); print(v,'empty gmem',dst.gmem())
    M=bytearray(D); M[0x70:0x7F0]=S[0x70:0x7F0]; dst.load(M); lib.vc_run_ms(dst.c,300)
    dst.keys("5"); m=dst.mem(); print(' bad state b6=%02x S03=%s gmem=%s'%(m[0x11E],m[0x88:0x8f].hex(),dst.gmem()))
    dst.keys("g 4 8"); m=dst.mem(); print(' after SF8 b6=%02x c4=%02x 4c=%02x gmem=%s'%(m[0x11E],m[0xC4],m[0x4c],dst.gmem()))
    dst.keys("g 5 8"); m=dst.mem(); print(' after CF8 b6=%02x gmem=%s'%(m[0x11E],dst.gmem()))
    dst2=Calc(v); dst2.load(M); lib.vc_run_ms(dst2.c,300); dst2.keys("5")
    dst2.keys("1 g 2 2 ENTER"); m=dst2.mem(); print(' after 1 DIM(i)? b6=%02x gmem=%s'%(m[0x11E],dst2.gmem()))
