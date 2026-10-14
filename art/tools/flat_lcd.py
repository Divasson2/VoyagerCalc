# 0.6.3: one flat grey on the LCD glass of the 15C / 16C photo faces (no gradient inside the glass).
import numpy as np, sys
from PIL import Image, ImageFilter
FLAT = 0x89   # 137: the 16C glass mean after grey_lcd.py (136.6)
GEO = {'15c': (0.18, 0.07823, 0.47, 0.15565), '16c': (0.1745, 0.07218, 0.4755, 0.16464)}
def run(src, dst, g):
    im = Image.open(src); a = np.array(im).astype(float); H, W = a.shape[:2]
    x0, y0 = int(g[0]*W)-20, int(g[1]*H)-20; x1, y1 = int((g[0]+g[2])*W)+20, int((g[1]+g[3])*H)+20
    r = a[y0:y1, x0:x1, :3]; L = r.mean(2); sat = r.max(2)-r.min(2)
    m = ((L > 60) & (L < 200) & (sat < 4)).astype(np.uint8)*255
    # fill holes / dark corners inside the glass, then a 1.5 px soft edge
    mi = Image.fromarray(m).filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))
    rows = np.where(np.array(mi).mean(1) > 127)[0]; cols = np.where(np.array(mi).mean(0) > 127)[0]
    box = np.zeros_like(m); box[rows[0]:rows[-1]+1, cols[0]:cols[-1]+1] = 255
    w = np.array(Image.fromarray(box).filter(ImageFilter.GaussianBlur(1.5))).astype(float)[..., None]/255
    a[y0:y1, x0:x1, :3] = r*(1-w) + FLAT*w
    Image.fromarray(np.clip(a, 0, 255).round().astype(np.uint8), im.mode).save(dst)
    print(src, 'glass', x0+cols[0], y0+rows[0], x0+cols[-1], y0+rows[-1])
if __name__ == '__main__':
    for m in sys.argv[1:]:
        run(f'art/faces/face_{m}_nolcd_old4.png', f'art/faces/face_{m}_nolcd.png', GEO[m])
