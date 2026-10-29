#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# make_face_16c_hires.py (0.7.2): the 16C face from Jose's high-resolution 16C CE photo
# (originals/hp16c_CE_front_hires_cmyk.jpg, 5906 x 3937 CMYK; the calculator is ~3200 px wide there,
# against 815 px in the old shop photo). Steps, all reusing the 0.6.x pipeline pieces:
#   rectify (crop to the body, 2000 px wide, height scaled to the old 1233) -> measure keys
#   -> paint out the "Collector's Edition" script with the faceplate's own brushed silver
#   -> colour levels mapped to the 15C master (colour_faces.make_map) -> 16C emblem on the badge
#   -> LCD glass flat #898989 (0.6.3 rule) -> rounded corners -> faces + geometry + Swift.
# Previous faces are kept as face_16c[_nolcd]_oldN.png. Run with /workspace/.venv-faces/bin/python.
import json, os, shutil, sys, io
import numpy as np, cv2
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
import make_faces as mf, colour_faces as cf
from rectify import rectify
from measure import measure

ART = mf.ART; ROOT = mf.ROOT
SRC_CMYK = os.path.join(ART, 'originals', 'hp16c_CE_front_hires_cmyk.jpg')
SRC_RGB = os.path.join(ART, 'originals', 'hp16c_CE_front_hires_rgb.png')
W, H = 2000, 1233
LCD_PX = [349, 91, 947, 199]          # glass inside the bevel, from green-minus-blue edge profiles
TEXT_BOX = (1452, 240, 1905, 326)     # x0, y0, x1, y1 of the script on the 2000 x 1233 face

def fill_script(rgb):
    """Rebuild the script box as bare faceplate. Per row: a straight blend between the clean silver
    just left and just right of the box (keeps each brushed streak and the horizontal shading), plus
    the fine texture (high-pass) of clean silver from the same rows further left, mirrored to length.
    The edges are feathered into the real faceplate."""
    x0, y0, x1, y1 = TEXT_BOX
    a = rgb.astype(np.float64); w = x1 - x0
    L = a[y0:y1, x0 - 30:x0 - 6].mean(1); R = a[y0:y1, x1 + 4:x1 + 16].mean(1)
    k = cv2.getGaussianKernel(5, 1.2).ravel()
    sm = lambda v: np.stack([np.convolve(np.pad(v[:, c], 2, mode='edge'), k, 'valid') for c in range(3)], 1)
    L, R = sm(L), sm(R)
    t = np.linspace(0, 1, w)[None, :, None]
    base = L[:, None, :] * (1 - t) + R[:, None, :] * t
    src = a[y0:y1, 1372:x0 - 8]                                   # clean silver, same rows
    hp = src - cv2.GaussianBlur(src, (0, 0), 6)
    reps = int(np.ceil(w / (2 * hp.shape[1]))) + 1
    tex = np.concatenate([hp, hp[:, ::-1]] * reps, 1)[:, :w]
    patch = base + tex
    fy = np.clip(np.minimum(np.arange(y1 - y0), y1 - y0 - 1 - np.arange(y1 - y0)) / 4.0, 0, 1)[:, None, None]
    fx = np.clip(np.minimum(np.arange(w), w - 1 - np.arange(w)) / 4.0, 0, 1)[None, :, None]
    f = fy * fx
    a[y0:y1, x0:x1] = patch * f + a[y0:y1, x0:x1] * (1 - f)
    return np.clip(a.round(), 0, 255).astype(np.uint8)

def main():
    if not os.path.exists(SRC_RGB):
        Image.open(SRC_CMYK).convert('RGB').save(SRC_RGB)
    rgba, info = rectify(SRC_RGB, W)                               # BGRA, 2000 x 1232
    rgba = cv2.resize(rgba, (W, H), interpolation=cv2.INTER_AREA)
    work = os.path.join(ART, 'work', 'rect_16c_hires.png'); cv2.imwrite(work, rgba)
    meas = measure(work)
    rgb = np.ascontiguousarray(rgba[..., 2::-1])                  # RGB
    cv2.imwrite('/workspace/voyager16c/before.png', cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR))
    rgb = fill_script(rgb)
    alpha = mf.rounded_alpha(W, H, int(W * 0.012))
    badge = mf.measure_badge(np.ascontiguousarray(rgb[..., ::-1]))
    geo = json.load(open(os.path.join(cf.FACES, 'geometry.json')))
    g = dict(source=os.path.basename(SRC_CMYK), rectify=info, size=[W, H], badge_px=badge,
             lcd=[round(LCD_PX[0] / W, 5), round(LCD_PX[1] / H, 5), round(LCD_PX[2] / W, 5), round(LCD_PX[3] / H, 5)],
             lcd_px=LCD_PX, lcd_source='hand-checked (make_face_16c_hires.py)',
             keys_filled_from_grid=meas['filled_from_grid'], keys=meas['keys'], keys_px=meas['keys_px'],
             script_box_px=list(TEXT_BOX))
    # the photo's faceplate is blue-tinted (about 208, 218, 242): white-balance on the bare silver
    # under the LCD first, so the level map below (which keeps only low-chroma pixels) sees it as neutral
    plate = rgb[300:330, 400:1200].reshape(-1, 3).astype(np.float64).mean(0)
    rgb = np.clip(rgb * (plate.mean() / plate), 0, 255).round().astype(np.uint8)
    face = np.dstack([rgb, alpha])
    ref = cf.anchors(cf.load(os.path.join(cf.FACES, 'face_15c_nolcd.png')), geo['15c'])
    mp = cf.make_map(cf.anchors(face, g), ref)
    face = cf.apply(face, mp)
    full = cf.emblem(face, g, '16c')
    nol = full.copy()
    x, y, w, h = LCD_PX
    m = np.zeros((H, W), np.float32); m[y:y + h, x:x + w] = 1
    m = cv2.GaussianBlur(m, (0, 0), 1.2)[..., None]
    nol[..., :3] = np.clip(nol[..., :3] * (1 - m) + cf.FLAT * m, 0, 255).round().astype(np.uint8)
    for name, a in (('face_16c.png', full), ('face_16c_nolcd.png', nol)):
        p = os.path.join(cf.FACES, name); shutil.copyfile(p, cf.next_old(p)); cf.save(a, p)
    shutil.copyfile(os.path.join(cf.FACES, 'face_16c_nolcd.png'), os.path.join(ROOT, 'app', 'Resources', 'Faces', 'face_16c_nolcd.png'))
    geo['16c'] = g
    shutil.copyfile(os.path.join(cf.FACES, 'geometry.json'), cf.next_old(os.path.join(cf.FACES, 'geometry.json')))
    json.dump(geo, open(os.path.join(cf.FACES, 'geometry.json'), 'w'), indent=1, default=float)
    mf.write_swift(geo)
    print('rectify', info, '\nbadge', badge, 'map', [np.round(v, 3) for v in mp])

if __name__ == '__main__':
    main()
