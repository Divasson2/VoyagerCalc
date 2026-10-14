# 0.6.2: turn the green LCD glass of a photo face into a neutral grey (keeps the glass's own shading).
import numpy as np, sys
from PIL import Image, ImageFilter
TARGET = 137.0   # mean grey level, sampled from Jose's 15C reference photo (#868D78, luma 137)
def run(src, dst, lcd):
    im = Image.open(src); a = np.array(im).astype(float)
    H, W = a.shape[:2]
    x0, y0 = int(lcd[0]*W) - 20, int(lcd[1]*H) - 20
    x1, y1 = int((lcd[0]+lcd[2])*W) + 20, int((lcd[1]+lcd[3])*H) + 20
    r = a[y0:y1, x0:x1, :3]
    R, G, B = r[..., 0], r[..., 1], r[..., 2]
    L = 0.299*R + 0.587*G + 0.114*B
    # glass = clearly tinted (green above blue) and not dark bezel
    m = ((G - B) > 6) & (L > 60)
    mi = Image.fromarray((m*255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(3))
    w = np.array(mi).astype(float)[..., None]/255
    glassL = L[m].mean()
    grey = np.clip(L * (TARGET/glassL), 0, 255)[..., None].repeat(3, 2)
    a[y0:y1, x0:x1, :3] = r*(1-w) + grey*w
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), im.mode).save(dst)
    print(src, 'glass mean', r[m].mean(0).round(1), '-> grey', TARGET, 'pixels', m.sum())
if __name__ == '__main__':
    geo = {'15c': (0.18, 0.07823, 0.47, 0.15565), '16c': (0.1745, 0.07218, 0.4755, 0.16464)}
    for m in sys.argv[1:]:
        run(f'art/faces/face_{m}_nolcd_old3.png', f'art/faces/face_{m}_nolcd.png', geo[m])
