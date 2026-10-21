# SPDX-License-Identifier: MIT
# Square badge-style icon: 12C gold / 15C silver / 16C silver, lettering from the badge (jose/w_*.png).
from PIL import Image, ImageDraw
import numpy as np
S=1024; SS=2; W=S*SS
INK=(34,34,34,255); FRAME=(34,34,34,255)
def grad(w,h,stops):
    y=np.linspace(0,1,h)[:,None]; out=np.zeros((h,w,3))
    for c in range(3): out[:,:,c]=np.interp(y,[s[0] for s in stops],[s[1][c] for s in stops])
    return Image.fromarray(np.clip(out,0,255).astype('uint8')).convert("RGBA")
silver=[(0,(226,229,222)),(0.5,(205,209,200)),(1,(218,221,212))]
gold=[(0,(216,186,100)),(0.5,(197,164,80)),(1,(209,178,92))]
# 0.6.7: the panels of the other two models. 0.6.5 had (70,70,70)..(60,60,60), too dark to read the lettering;
# they are now LIFT (18 %) of the way from that dark grey to the lit silver's mean tone (neutral grey, so no tint).
LIFT=0.18
_LIT=sum(sum(c) / 3 for _, c in silver) / len(silver)          # mean tone of the lit silver panel (about 214)
DIM=[(0,(round(70+(_LIT-70)*LIFT),)*3),(1,(round(60+(_LIT-60)*LIFT),)*3)]
def word(t):
    from PIL import ImageFilter
    m=Image.open(f"jose/w_{t}.png").convert("L").filter(ImageFilter.GaussianBlur(6))
    return m.point(lambda v: 0 if v<110 else 255 if v>146 else int((v-110)*255/36))
def panel(img,box,t,g,fill_w=0.92,fill_h=0.78,radius=0.035):
    x0,y0,x1,y1=box; w=x1-x0; h=y1-y0
    m=Image.new("L",(w,h),0); ImageDraw.Draw(m).rounded_rectangle([0,0,w-1,h-1],int(W*radius),fill=255)
    img.paste(grad(w,h,g),(x0,y0),m)
    tm=word(t); ar=tm.width/tm.height
    tw=int(w*fill_w); th=int(tw/ar)
    if th>h*fill_h: th=int(h*fill_h); tw=int(th*ar)
    tm=tm.resize((tw,th),Image.LANCZOS)
    img.paste(INK,(x0+(w-tw)//2,y0+(h-th)//2),tm)
def badge3(corner=0.04,border=0.055,gap=0.03):
    img=Image.new("RGBA",(W,W),(0,0,0,0)); d=ImageDraw.Draw(img)
    d.rounded_rectangle([0,0,W-1,W-1],int(W*corner),fill=FRAME)
    b=int(W*border); gp=int(W*gap); ph=(W-2*b-2*gp)//3
    for i,(t,g) in enumerate([("12C",gold),("15C",silver),("16C",silver)]):
        y0=b+i*(ph+gp); panel(img,(b,y0,W-b,y0+ph),t,g)
    return img.resize((S,S),Image.LANCZOS)
def badge1(t,g,corner=0.04,border=0.055):
    # single-model corner badge: square, model number in a panel filling the lower third like the original,
    # upper two thirds a plain panel in the same metal (no HP logo)
    img=Image.new("RGBA",(W,W),(0,0,0,0)); d=ImageDraw.Draw(img)
    d.rounded_rectangle([0,0,W-1,W-1],int(W*corner),fill=FRAME)
    b=int(W*border); gp=int(W*0.03); ph=(W-2*b-2*gp)//3
    for i,tt in enumerate(["12C","15C","16C"]):
        y0=b+i*(ph+gp)
        gg=g if tt==t else DIM
        panel(img,(b,y0,W-b,y0+ph),tt,gg)
    return img.resize((S,S),Image.LANCZOS)
if __name__=="__main__":
    import sys
    if "--emblems-only" in sys.argv:       # 0.6.7: only the three per-face emblems (the app icon is unchanged)
        for t,g in (("12C",gold),("15C",silver),("16C",silver)): badge1(t,g).save(f"emblem-{t.lower()}-1024.png")
        print("DIM", DIM); sys.exit(0)
    ic=badge3(); ic.save("AppIcon-square-1024.png")
    for t,g in (("12C",gold),("15C",silver),("16C",silver)): badge1(t,g).save(f"emblem-{t.lower()}-1024.png")   # 0.6.5: one lit panel per face
    for s in (512,256,128,64,32,16): ic.resize((s,s),Image.LANCZOS).save(f"AppIcon-square-{s}.png")
    pv=Image.new("RGB",(1200,560),(236,236,236)); pv.paste(Image.new("RGB",(600,560),(40,40,44)),(600,0))
    for bx in (0,600):
        for s,x,y in [(256,30,150),(128,320,214),(64,480,246)]:
            t=ic.resize((s,s),Image.LANCZOS); pv.paste(t,(bx+x,y),t)
    pv.save("icon-square-preview.png")
