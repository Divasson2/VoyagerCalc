import numpy as np, sys
from PIL import Image
def run(src,dst,box=(1455,250,1900,326)):
  im=np.array(Image.open(src)).astype(float)
  x0,y0,x1,y1=box
  top=im[y0-4:y0,x0:x1,:3].mean(0); bot=im[y1:y1+4,x0:x1,:3].mean(0)
  # texture: residual of clean strip just left of the label (same rows), tiled
  ref=im[y0:y1,1350:1450,:3]
  res=ref-ref.mean(1,keepdims=True)
  rng=np.random.default_rng(7)
  out=im.copy()
  for i,y in enumerate(range(y0,y1)):
    t=(i+0.5)/(y1-y0)
    base=top*(1-t)+bot*t
    # horizontally-smoothed base to avoid column stripes
    k=np.ones(15)/15
    base=np.stack([np.convolve(np.pad(base[:,c],7,mode='edge'),k,'valid') for c in range(3)],1)
    tex=np.tile(res[i],( (x1-x0)//res.shape[1]+1,1))[:x1-x0]
    tex=np.roll(tex,rng.integers(0,100),0)
    out[y,x0:x1,:3]=base+tex
  # feather the left/right 12 px into the original
  for j in range(12):
    a=(j+1)/13
    for x in (x0+j, x1-1-j):
      out[y0:y1,x,:3]=im[y0:y1,x,:3]*(1-a)+out[y0:y1,x,:3]*a
  Image.fromarray(np.clip(out,0,255).astype(np.uint8),Image.open(src).mode).save(dst)
for m in sys.argv[1:]:
  run(f'app/Resources/Faces/face_{m}_nolcd.png',f'/tmp/{m}_new.png')
  Image.open(f'/tmp/{m}_new.png').convert('RGB').crop((1300,180,1990,400)).save(f'/tmp/{m}_newlab.png')
