# SPDX-License-Identifier: MIT
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np
S=1024; SS=4; W=S*SS
FONT="/usr/share/fonts/truetype/sand-box/google/Russo One/RussoOne-Regular.ttf"
def grad(w,h,stops):
    y=np.linspace(0,1,h)[:,None]
    out=np.zeros((h,w,3))
    for c in range(3):
        xs=[s[0] for s in stops]; vs=[s[1][c] for s in stops]
        out[:,:,c]=np.interp(y,xs,vs)
    # subtle brushed noise
    rng=np.random.default_rng(1)
    n=rng.normal(0,2,(h,1,1)); out+=n
    return Image.fromarray(np.clip(out,0,255).astype('uint8'))
silver=[(0,(222,226,216)),(0.5,(200,205,194)),(1,(214,218,207))]
gold=[(0,(214,184,98)),(0.5,(196,163,78)),(1,(208,177,90))]
img=Image.new("RGBA",(W,W),(0,0,0,0))
d=ImageDraw.Draw(img)
m=int(W*0.09); r=int(W*0.16)
# outer black badge
d.rounded_rectangle([m,m,W-m,W-m],r,fill=(18,18,18,255))
inner=int(W*0.03); gap=int(W*0.026)
x0=m+inner; x1=W-m-inner; y0=m+inner; y1=W-m-inner
bh=(y1-y0-2*gap)/3
labels=[("12C",gold),("15C",silver),("16C",silver)]
font=ImageFont.truetype(FONT,int(bh*0.66))
for i,(t,g) in enumerate(labels):
    ty0=int(y0+i*(bh+gap)); ty1=int(ty0+bh)
    w=x1-x0; h=ty1-ty0
    band=grad(w,h,g).convert("RGBA")
    mask=Image.new("L",(w,h),0)
    rr=int(r*0.55) if i in (0,2) else int(W*0.02)
    md=ImageDraw.Draw(mask)
    # round only the outer corners of top/bottom bands
    md.rounded_rectangle([0,0,w-1,h-1],int(W*0.05),fill=255)
    # clip to the inner rounded window so outer corners follow the badge
    clip=Image.new("L",(W,W),0); ImageDraw.Draw(clip).rounded_rectangle([x0,y0,x1,y1],r-inner,fill=255)
    mask=Image.fromarray((np.array(mask)//255*np.array(clip.crop((x0,ty0,x0+w,ty0+h)))).astype('uint8'))
    img.paste(band,(x0,ty0),mask)
    # hand-built badge-style lettering, stretched to fill the band
    import glyphs
    tw=int(w*0.88); th=int(h*0.74)
    tm=glyphs.word_fit(t,tw/th)
    tm=tm.resize((tw,th),Image.LANCZOS)
    tx=x0+(w-tw)//2; tyy=ty0+(h-th)//2
    img.paste((18,18,18,255),(tx,tyy),tm)
# drop shadow
out=img.resize((S,S),Image.LANCZOS)
sh=Image.new("RGBA",(S,S),(0,0,0,0))
a=out.split()[3].point(lambda v:int(v*0.45))
sh.putalpha(a); sh=sh.filter(ImageFilter.GaussianBlur(14))
canvas=Image.new("RGBA",(S,S),(0,0,0,0))
canvas.alpha_composite(sh,(0,10)); canvas.alpha_composite(out)
canvas.save("AppIcon-1024.png")
for s in (512,256,128,64,32,16):
    canvas.resize((s,s),Image.LANCZOS).save(f"AppIcon-{s}.png")
# preview on light & dark backgrounds
pv=Image.new("RGB",(1200,560),(236,236,236))
pv.paste(Image.new("RGB",(600,560),(40,40,44)),(600,0))
ic=canvas.resize((256,256),Image.LANCZOS)
for bx in (0,600):
    pv.paste(ic,(bx+30,150),ic)
    sm=canvas.resize((128,128),Image.LANCZOS); pv.paste(sm,(bx+320,214),sm)
    t=canvas.resize((64,64),Image.LANCZOS); pv.paste(t,(bx+480,246),t)
pv.save("icon-preview.png")
