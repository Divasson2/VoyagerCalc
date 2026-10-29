#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# make_face_16c_phone.py (0.7.2 v2): the 16C face from Jose's phone photo of his real 16C CE
# (originals/hp16c_CE_phone.jpg, 4075 x 2591). Replaces make_face_16c_hires.py (rejected: over-sharpened
# labels, magenta fringes). Rules: no sharpening anywhere (Lanczos warp, area downscale only), no global
# colour cast (one neutral white balance + a luma-only level), purple/magenta chroma removed (defringe).
#   1. perspective: 4-point homography from the keyboard plate's inner edges (lines fitted to sub-pixel
#      edge points, residuals < 2.5 px), plate mapped to a rectangle; body cropped at its outer edges
#   2. dust: small isolated low-chroma bright (and on the bezel also dark) specks inpainted, at native size
#   3. defringe: chroma of purple / magenta pixels (G below both R and B) pulled to grey
#   4. downscale to 2000 x 1233 (INTER_AREA)  5. "Collector's Edition" painted out with brushed silver
#   6. 16C emblem on the badge  7. LCD glass flat #898989  8. rounded corners; geometry + Swift
# Previous files are kept as face_16c[_nolcd]_old8.png / geometry_old3.json. venv: /workspace/.venv-faces
import json, os, shutil, sys
import numpy as np, cv2
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
import make_faces as mf, colour_faces as cf
from measure import measure

ART = mf.ART; ROOT = mf.ROOT
SRC = os.path.join(ART, 'originals', 'hp16c_CE_phone.jpg')
OUT = '/workspace/voyager16c/v2'
W, H = 2000, 1233
# plate inner edges in the photo: x = a*y + b (left, right), y = a*x + b (top, bottom); see edge_lines()
BODY_PAD = None
LCD_PX = [355, 90, 952, 200]
TEXT_BOX = (1462, 238, 1908, 326)

def edge_lines(g):
    def scan(axis, lo, hi, rng, sign):
        pts = []
        for t in rng:
            prof = g[t, lo:hi] if axis == 'x' else g[lo:hi, t]
            d = np.diff(prof) * sign; i = int(np.argmax(d))
            if d[i] > 8 and 0 < i < len(d) - 1:
                a, b, c = d[i - 1], d[i], d[i + 1]; den = a - 2 * b + c
                pts.append((t, lo + i + 0.5 + (0.5 * (a - c) / den if den else 0)))
        return np.array(pts)
    def fit(p):
        for _ in range(3):
            a, b = np.polyfit(p[:, 0], p[:, 1], 1); r = p[:, 1] - (a * p[:, 0] + b)
            keep = abs(r) < np.median(abs(r)) * 3 + 0.5; p = p[keep]
        a, b = np.polyfit(p[:, 0], p[:, 1], 1)
        return (a, b), float(np.abs(p[:, 1] - (a * p[:, 0] + b)).max()), len(p)
    L = fit(scan('x', 345, 420, range(1000, 2250, 10), -1)); R = fit(scan('x', 3715, 3775, range(1000, 2250, 10), 1))
    T = fit(scan('y', 820, 960, range(500, 3600, 10), -1)); B = fit(scan('y', 2230, 2420, range(500, 3600, 10), 1))
    return L, R, T, B

def rectify_phone(bgr):
    g = cv2.GaussianBlur(cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY).astype(np.float32), (0, 0), 1.5)
    (L, eL, _), (R, eR, _), (T, eT, _), (B, eB, _) = edge_lines(g)
    def meet(V, Hh):
        a, b = V; c, d = Hh; y = (c * b + d) / (1 - c * a); return [a * y + b, y]
    C = np.float32([meet(L, T), meet(R, T), meet(R, B), meet(L, B)])
    w = (np.linalg.norm(C[1] - C[0]) + np.linalg.norm(C[2] - C[3])) / 2
    h = (np.linalg.norm(C[3] - C[0]) + np.linalg.norm(C[2] - C[1])) / 2
    ox, oy = 400.0, 1000.0
    D = np.float32([[ox, oy], [ox + w, oy], [ox + w, oy + h], [ox, oy + h]])
    Hm = cv2.getPerspectiveTransform(C, D)
    big = cv2.warpPerspective(bgr, Hm, (int(2 * ox + w), int(oy + h + 400)), flags=cv2.INTER_LANCZOS4, borderMode=cv2.BORDER_REPLICATE)
    # body outer edges: black rails / body against the light table
    gg = cv2.cvtColor(big, cv2.COLOR_BGR2GRAY).astype(float)
    first = lambda p: int(np.argmax(p < 100))
    rows = range(600, 2400, 50)
    x0 = int(np.median([first(gg[y, :600]) for y in rows]))
    x1 = int(np.median([gg.shape[1] - first(gg[y, ::-1][:600]) for y in rows]))
    y0 = int(np.median([first(gg[:600, x]) for x in list(range(x0 + 30, x0 + 130, 10)) + list(range(x1 - 100, x1 - 20, 10))]))
    y1 = int(np.median([gg.shape[0] - first(gg[::-1, x][:600]) for x in range(x0 + 200, x1 - 200, 100)]))
    info = dict(plate_corners_photo=C.round(2).tolist(), plate_rect=[round(float(w), 1), round(float(h), 1)],
                edge_fit_max_residual_px=dict(left=round(eL, 2), right=round(eR, 2), top=round(eT, 2), bottom=round(eB, 2)),
                body_crop_on_warp=[x0, y0, x1, y1], native=[x1 - x0, y1 - y0])
    return big[y0:y1, x0:x1].copy(), info, Hm

def despeck(bgr):
    """Small isolated specks: white top-hat (on the bezel also black-hat) above a threshold, low chroma, small
    and compact, and not part of any larger structure (label / legend strokes, bracket lines, key edges): those
    are pieces of a looser threshold with >= 150 px or >= 25 coloured px; they and 6 px around them are protected.
    Inpainted (Telea, radius 3) at native resolution."""
    g = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    sat = (bgr.max(2).astype(int) - bgr.min(2).astype(int))      # absolute chroma (HSV S is noisy on black)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    disc = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    bg = cv2.medianBlur(g, 31).astype(int)
    mask = np.zeros(g.shape, np.uint8)
    def pick(hat, strong, loose, region, maxarea, maxside, sign=1, stroke=150):
        raw = ((hat > loose) & region).astype(np.uint8)
        n0, lab0, st0, _ = cv2.connectedComponentsWithStats(raw, 8)
        satn = np.bincount(lab0[raw.astype(bool) & (sat > 55)], minlength=n0)          # coloured pixels per piece (gold / blue legends)
        strokes = np.where((st0[:, 4] >= stroke) | (satn >= 3))[0]; strokes = strokes[strokes > 0]
        seed = np.isin(lab0, strokes)                                                  # real strokes (glyphs, lines)
        # whole glyphs by plain contrast against the local median (the top-hat splits wide strokes)
        con = (sign * (g.astype(int) - bg) > 30).astype(np.uint8)      # same polarity as the specks
        n1, lab1, st1, _ = cv2.connectedComponentsWithStats(con, 8)
        big1 = np.where(st1[:, 4] >= stroke)[0]; big1 = big1[big1 > 0]
        seed |= np.isin(lab1, big1)
        protected = cv2.dilate(seed.astype(np.uint8), disc, iterations=2) > 0            # strokes + 6 px around
        cand = ((hat > strong) & (sat < 45) & region & ~protected).astype(np.uint8)
        n, lab, st, _ = cv2.connectedComponentsWithStats(cand, 8)
        for i in range(1, n):
            x, y, w, h = st[i, :4]
            if st[i, 4] <= maxarea and max(w, h) <= maxside:
                mask[y:y + h, x:x + w][lab[y:y + h, x:x + w] == i] = 255
    th = cv2.morphologyEx(g, cv2.MORPH_TOPHAT, k).astype(int)
    bh = cv2.morphologyEx(g, cv2.MORPH_BLACKHAT, k).astype(int)
    pick(th, 20, 9, np.ones(g.shape, bool), 150, 18)            # bright specks anywhere
    pick(th, 11, 7, bg < 60, 260, 26, 1, 320)                            # fainter specks on the black plate (e.g. left of SR)
    pick(bh, 14, 8, bg > 140, 100, 14, -1)                           # dark specks on the silver bezel
    mask = cv2.dilate(mask, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
    return cv2.inpaint(bgr, mask, 3, cv2.INPAINT_TELEA), mask

def defringe(rgb):
    """Purple / magenta chroma (G below both R and B) pulled to grey, more strongly the more magenta it is.
    Nothing on the calculator is legitimately purple (labels are gold, blue, orange, cyan)."""
    a = rgb.astype(np.float32); R, G, B = a[..., 0], a[..., 1], a[..., 2]
    Y = 0.299 * R + 0.587 * G + 0.114 * B
    mag = np.minimum(R, B) - G                           # > 0 = magenta/purple
    w = np.clip((mag - 1.0) / 6.0, 0, 1)[..., None]
    out = a * (1 - w) + Y[..., None] * w
    return np.clip(out.round(), 0, 255).astype(np.uint8), float((w > 0).mean())

def fill_script(rgb):
    x0, y0, x1, y1 = TEXT_BOX
    a = rgb.astype(np.float64); w = x1 - x0
    L = a[y0:y1, x0 - 30:x0 - 6].mean(1); R = a[y0:y1, x1 + 4:x1 + 14].mean(1)
    k = cv2.getGaussianKernel(5, 1.2).ravel()
    sm = lambda v: np.stack([np.convolve(np.pad(v[:, c], 2, mode='edge'), k, 'valid') for c in range(3)], 1)
    L, R = sm(L), sm(R)
    t = np.linspace(0, 1, w)[None, :, None]
    base = L[:, None, :] * (1 - t) + R[:, None, :] * t
    src = a[y0:y1, 1368:x0 - 8]
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
    os.makedirs(OUT, exist_ok=True)
    from PIL import ImageOps
    rgb0 = np.array(ImageOps.exif_transpose(Image.open(SRC)).convert('RGB'))
    body, info, Hm = rectify_phone(np.ascontiguousarray(rgb0[..., ::-1]))     # BGR, native size
    cv2.imwrite(os.path.join(ART, 'work', 'rect_16c_phone_native.png'), body)
    before = cv2.resize(body, (W, H), interpolation=cv2.INTER_AREA)
    cv2.imwrite(os.path.join(OUT, 'before.png'), before)
    clean, mask = despeck(body)
    info['specks_inpainted_px_native'] = int((mask > 0).sum())
    cv2.imwrite(os.path.join(ART, 'work', 'rect_16c_phone_speckmask.png'), mask)
    rgb = np.ascontiguousarray(clean[..., ::-1])
    rgb, frac = defringe(rgb); info['defringed_fraction'] = round(frac, 4)
    rgb = cv2.resize(rgb, (W, H), interpolation=cv2.INTER_AREA)
    # neutral greys stay neutral: one per-channel affine map taking the black keyboard plate (dark pixels of the
    # keyboard area) and the bare silver under the LCD to grey (their own luma; silver lifted to the previous faces'
    # 226), then a soft highlight knee on luma only (no clipping of the white legends), then defringe again.
    f = rgb.astype(np.float64)
    kb = f[400:1150, 100:1900].reshape(-1, 3); dark = kb[kb.mean(1) < 25].mean(0)
    silver = f[300:330, 400:1200].reshape(-1, 3).mean(0)
    dt, st_ = float(dark.mean()), 226.0
    A = (st_ - dt) / (silver - dark); Bc = dt - A * dark
    f = np.clip(f * A + Bc, 0, None)
    Y = f @ np.array([0.299, 0.587, 0.114])
    wd = (np.clip((40.0 - Y) / 30.0, 0, 1) * 0.9)[..., None]       # the black plate is black: no tint in deep shadows
    f = f * (1 - wd) + Y[..., None] * wd
    knee = 205.0
    Yn = np.where(Y < knee, Y, knee + 50.0 * (1 - np.exp(-(Y - knee) / 50.0)))
    f = f * np.where(Y > knee, Yn / np.maximum(Y, 1.0), 1.0)[..., None]
    rgb = np.clip(f.round(), 0, 255).astype(np.uint8)
    rgb, frac2 = defringe(rgb)
    info['neutral_map'] = dict(gain=A.round(4).tolist(), offset=Bc.round(2).tolist(), dark_anchor=dark.round(1).tolist(),
                               silver_anchor=silver.round(1).tolist(), knee=knee, defringed_fraction_2000=round(frac2, 4))
    rgb = fill_script(rgb)
    work = os.path.join(ART, 'work', 'rect_16c_phone.png'); cv2.imwrite(work, rgb[..., ::-1])
    meas = measure(work)
    badge = mf.measure_badge(np.ascontiguousarray(rgb[..., ::-1]))
    alpha = mf.rounded_alpha(W, H, int(W * 0.012))
    geo = json.load(open(os.path.join(cf.FACES, 'geometry.json')))
    g = dict(source=os.path.basename(SRC), rectify=info, size=[W, H], badge_px=badge,
             lcd=[round(LCD_PX[0] / W, 5), round(LCD_PX[1] / H, 5), round(LCD_PX[2] / W, 5), round(LCD_PX[3] / H, 5)],
             lcd_px=LCD_PX, lcd_source='hand-checked (make_face_16c_phone.py)',
             keys_filled_from_grid=meas['filled_from_grid'], keys=meas['keys'], keys_px=meas['keys_px'],
             script_box_px=list(TEXT_BOX))
    full = cf.emblem(np.dstack([rgb, alpha]), g, '16c')
    nol = full.copy()
    x, y, w, h = LCD_PX
    m = np.zeros((H, W), np.float32); m[y:y + h, x:x + w] = 1
    m = cv2.GaussianBlur(m, (0, 0), 1.2)[..., None]
    nol[..., :3] = np.clip(nol[..., :3] * (1 - m) + cf.FLAT * m, 0, 255).round().astype(np.uint8)
    if '--dry' not in sys.argv:
        for name, a in (('face_16c.png', full), ('face_16c_nolcd.png', nol)):
            p = os.path.join(cf.FACES, name); bk = p.replace('.png', '_old8.png')
            if not os.path.exists(bk): shutil.copyfile(p, bk)
            cf.save(a, p)
        shutil.copyfile(os.path.join(cf.FACES, 'face_16c_nolcd.png'), os.path.join(ROOT, 'app', 'Resources', 'Faces', 'face_16c_nolcd.png'))
        gp = os.path.join(cf.FACES, 'geometry.json'); bk = os.path.join(cf.FACES, 'geometry_old3.json')
        if not os.path.exists(bk): shutil.copyfile(gp, bk)
        geo['16c'] = g
        json.dump(geo, open(gp, 'w'), indent=1, default=float)
        mf.write_swift(geo)
    else:
        cf.save(nol, '/tmp/dry_nolcd.png')
    print(json.dumps(info, default=float, indent=1)); print('badge', badge, 'keys', len(meas['keys']), 'filled', meas['filled_from_grid'])

if __name__ == '__main__':
    main()
