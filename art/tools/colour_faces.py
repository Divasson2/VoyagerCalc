#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# colour_faces.py (0.6.5): finish the photo faces after make_faces.py / grey_lcd.py / flat_lcd.py.
#   1. g: neutralise the colour cast of the 15C and 16C photos and give both the same black point,
#      white point and gamma, measured with the LCD glass and the badge masked out. (The three source
#      photos have different white balances; the pipeline itself never changed colours.)
#   2. a: the badge at the top right shows only the running model (art/icon/emblem-<m>-1024.png:
#      the model's panel lit, the other two dark), painted with make_faces.replace_badge.
#   3. the LCD glass is painted flat #898989 again (0.6.3 rule) so the correction never touches it.
# The previous faces are kept as face_<m>[_nolcd]_oldN.png in art/faces (never in app/Resources).
# Run with the venv that has opencv-python-headless, numpy, pillow:
#   /workspace/.venv-faces/bin/python art/tools/colour_faces.py [--check]
import json, os, shutil, sys
import numpy as np
from PIL import Image, ImageFilter
sys.path.insert(0, os.path.dirname(__file__))
import make_faces as mf

ART = mf.ART; ROOT = mf.ROOT
FACES = os.path.join(ART, 'faces')
FLAT = 0x89
GLASS = {'15c': (0.18, 0.07823, 0.47, 0.15565), '16c': (0.1745, 0.07218, 0.4755, 0.16464)}   # as flat_lcd.py
GAMMA = 1.0                                  # the same gamma for the 15C and 16C (linear)
LUMA = np.array([0.2126, 0.7152, 0.0722])

def next_old(path):
    base, ext = os.path.splitext(path)
    n = 1
    while True:
        cand = f'{base}_old{"" if n == 1 else n}{ext}'
        if not os.path.exists(cand): return cand
        n += 1

def stat_mask(rgba, geo):
    a = rgba[..., 3] > 250
    x, y, w, h = geo['lcd_px']; a[max(0, y - 6):y + h + 6, max(0, x - 6):x + w + 6] = False
    x, y, w, h = geo['badge_px']; a[max(0, y - 10):y + h + 10, max(0, x - 10):x + w + 10] = False
    return a

def measure(rgba, geo):
    m = stat_mask(rgba, geo); rgb = rgba[..., :3][m].astype(float); L = rgb @ LUMA
    c = rgb.max(1) - rgb.min(1)
    p99 = np.percentile(L, 99)                      # thresholds relative to the photo's own white
    bright = rgb[(L > 0.75 * p99) & (c < 25)]; dark = rgb[L < 0.25 * p99]
    return dict(mean=rgb.mean(0), bright=bright.mean(0), dark=dark.mean(0), p=np.percentile(L, [1, 50, 99]))

def anchors(rgba, geo):
    """Per-channel anchors of one photo: the mean of the dark body / key pixels (L < 0.25 p99) and of the bright
    neutral faceplate pixels (L > 0.75 p99, low chroma), LCD and badge masked."""
    s = measure(rgba, geo)
    return s['dark'], s['bright']

def make_map(src_anchors, ref_anchors):
    """Linear map per channel taking this photo's dark / bright anchors to the reference ones, with the
    reference anchors made grey (R = G = B = their luma mean). All faces therefore end with the same black
    point and white point, neutral at both ends. (Gamma is the same for all: 1.0, linear.)"""
    d, w = src_anchors
    rd, rw = ref_anchors
    bt, wt = float(rd.mean()), float(rw.mean())
    gain = (wt - bt) / (w - d)
    return d, gain, bt

def apply(rgba, mp):
    d, gain, bt = mp
    out = rgba.astype(float)
    x = bt + (out[..., :3] - d) * gain
    t = np.clip(x, 0, 255) / 255.0
    out[..., :3] = 255.0 * t ** GAMMA
    return np.clip(out.round(), 0, 255).astype(np.uint8)

def glass_weight(flat_rgba, g):
    """The 0.6.3 flat_lcd.py glass mask, computed on the existing (already flat) face."""
    a = flat_rgba.astype(float); H, W = a.shape[:2]
    x0, y0 = int(g[0] * W) - 20, int(g[1] * H) - 20; x1, y1 = int((g[0] + g[2]) * W) + 20, int((g[1] + g[3]) * H) + 20
    r = a[y0:y1, x0:x1, :3]; L = r.mean(2); sat = r.max(2) - r.min(2)
    m = ((L > 60) & (L < 200) & (sat < 4)).astype(np.uint8) * 255
    mi = Image.fromarray(m).filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))
    rows = np.where(np.array(mi).mean(1) > 127)[0]; cols = np.where(np.array(mi).mean(0) > 127)[0]
    box = np.zeros_like(m); box[rows[0]:rows[-1] + 1, cols[0]:cols[-1] + 1] = 255
    w = np.array(Image.fromarray(box).filter(ImageFilter.GaussianBlur(1.5))).astype(float)[..., None] / 255
    return (x0, y0, x1, y1), w

def emblem(rgba, geo, model):
    import cv2
    mf.LOGO = os.path.join(ART, 'icon', f'emblem-{model}-1024.png')
    bgr = np.ascontiguousarray(rgba[..., 2::-1])
    out = mf.replace_badge(bgr, geo['badge_px'])
    res = rgba.copy(); res[..., :3] = out[..., ::-1]
    return res

def load(p): return np.array(Image.open(p).convert('RGBA'))
def save(a, p): Image.fromarray(a, 'RGBA').save(p, optimize=True)

def main():
    check = '--check' in sys.argv
    geo = json.load(open(os.path.join(FACES, 'geometry.json')))
    report = {}
    ref = anchors(load(os.path.join(FACES, 'face_15c_nolcd.png')), geo['15c'])   # the 15C is the master: its levels, made neutral
    # parameters come from the empty-LCD face (the LCD is masked there anyway)
    for m in ('12c', '15c', '16c'):
        nol_p, full_p = [os.path.join(FACES, f'face_{m}{s}.png') for s in ('_nolcd', '')]
        nol = load(nol_p); full = load(full_p)
        before = measure(nol, geo[m])
        if m == '12c':
            nol2, full2 = nol, full                         # the 12C keeps its photo colours
            params = None
        else:
            mp = make_map(anchors(nol, geo[m]), ref); params = mp
            nol2 = apply(nol, mp); full2 = apply(full, mp)
            w_box, w = glass_weight(nol, GLASS[m])          # glass from the old flat face
            x0, y0, x1, y1 = w_box
            reg = nol2[y0:y1, x0:x1, :3].astype(float)
            nol2[y0:y1, x0:x1, :3] = np.clip(reg * (1 - w) + FLAT * w, 0, 255).round().astype(np.uint8)
        nol2 = emblem(nol2, geo[m], m); full2 = emblem(full2, geo[m], m)
        after = measure(nol2, geo[m])
        report[m] = dict(before=before, after=after, params=params)
        if not check:
            for p, a in ((nol_p, nol2), (full_p, full2)):
                shutil.copyfile(p, next_old(p)); save(a, p)
            res = os.path.join(ROOT, 'app', 'Resources', 'Faces', f'face_{m}_nolcd.png')
            shutil.copyfile(nol_p, res)
    for m, r in report.items():
        b, a = r['before'], r['after']
        print(m, 'before: bright', b['bright'].round(1), 'dark', b['dark'].round(1), 'luma p1/50/99', b['p'].round(1))
        print(m, 'after : bright', a['bright'].round(1), 'dark', a['dark'].round(1), 'luma p1/50/99', a['p'].round(1))
        if r['params']: print(m, 'dark anchor', r['params'][0].round(1), 'gain', r['params'][1].round(4), 'black ->', round(r['params'][2], 1), 'gamma', GAMMA)

if __name__ == '__main__':
    main()
