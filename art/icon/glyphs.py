# SPDX-License-Identifier: MIT
# Wide, heavy glyphs with closed terminals, in the style of the Voyager model badges.
from PIL import Image, ImageDraw
X=1.0
H=1000; S=int(H*0.225); h=S/2
R=H*0.30            # centre-line corner radius
TURN=S*0.55         # length of the curled-in terminals
class P:
    def __init__(s,w): s.w=w; s.im=Image.new("L",(int(w),H),0); s.d=ImageDraw.Draw(s.im)
    def v(s,x,y0,y1): y0,y1=sorted((y0,y1)); s.d.rectangle([x-h,y0,x+h,y1],fill=255)
    def hz(s,y,x0,x1): x0,x1=sorted((x0,x1)); s.d.rectangle([x0,y-h,x1,y+h],fill=255)
    def a(s,cx,cy,r,st,en): s.d.arc([cx-r-h,cy-r-h,cx+r+h,cy+r+h],st,en,fill=255,width=int(S))
def box(w):
    return h,w-h,h,H-h   # centre-line extents L,Rt,T,B
def gC():
    w=H*1.02*X; p=P(w); L,Rt,T,B=box(w); r=H*0.26
    p.a(Rt-r,T+r,r,270,360); p.hz(T,L+r,Rt-r); p.a(L+r,T+r,r,180,270)
    p.v(L,T+r,B-r); p.a(L+r,B-r,r,90,180); p.hz(B,L+r,Rt-r); p.a(Rt-r,B-r,r,0,90)
    return p.im
def g5():
    w=H*0.98*X; p=P(w); L,Rt,T,B=box(w); mid=H*0.47; r=(B-mid)/2
    p.hz(T,L-h,Rt+h)                      # top bar
    p.v(L,T,mid+h)                        # stem
    p.hz(mid,L,Rt-r); p.a(Rt-r,mid+r,r,270,360)
    p.a(Rt-r,B-r,r,0,90); p.hz(B,L+r,Rt-r); p.a(L+r,B-r,r,90,180)
    p.v(L,B-r,B-r-TURN*0.35)
    return p.im
def g2():
    w=H*0.98*X; p=P(w); L,Rt,T,B=box(w); mid=H*0.53; r=(mid-T)/2
    p.v(L,T+r,T+r+TURN*0.35); p.a(L+r,T+r,r,180,270); p.hz(T,L+r,Rt-r)
    p.a(Rt-r,T+r,r,270,360); p.a(Rt-r,mid-r,r,0,90)
    r2=S*0.6
    p.hz(mid,L+r2,Rt-r); p.a(L+r2,mid+r2,r2,180,270)
    p.v(L,mid+r2,B+h); p.hz(B,L,Rt+h)
    return p.im
def g6():
    w=H*0.98*X; p=P(w); L,Rt,T,B=box(w); mid=H*0.50; r=R; r2=(B-mid)/2
    p.a(Rt-r,T+r,r,270,345); p.hz(T,L+r,Rt-r); p.a(L+r,T+r,r,180,270)
    p.v(L,T+r,B-r2); p.a(L+r2,B-r2,r2,90,180); p.hz(B,L+r2,Rt-r2); p.a(Rt-r2,B-r2,r2,0,90)
    p.a(Rt-r2,mid+r2,r2,270,360); p.hz(mid,L,Rt-r2)
    return p.im
def g1():
    w=H*0.55*(1+(X-1)*0.4); p=P(w); x=w-h-H*0.02
    p.v(x,0,H)
    p.d.polygon([(0,H*0.12),(x-h,0),(x-h,S*0.95),(H*0.09,H*0.12+S*0.9)],fill=255)
    return p.im
G={"1":g1,"2":g2,"5":g5,"6":g6,"C":gC}
def word_fit(t,ratio):
    global X
    lo,hi=0.6,4.0
    for _ in range(30):
        X=(lo+hi)/2; im=word(t)
        if im.width/im.height<ratio: lo=X
        else: hi=X
    return word(t)
def word(t,track=int(H*0.11)):
    gl=[G[c]() for c in t]
    W=sum(g.width for g in gl)+track*(len(gl)-1)
    out=Image.new("L",(W,H),0); x=0
    for g in gl: out.paste(g,(x,0)); x+=g.width+track
    return out
if __name__=="__main__":
    im=Image.new("L",(3500,3400),0)
    for i,t in enumerate(["12C","15C","16C"]):
        im.paste(word(t),(50,50+i*1120))
    im.resize((1050,1020),Image.LANCZOS).save("glyphs-test.png")
