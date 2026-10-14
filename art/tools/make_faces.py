#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# make_faces.py - the whole photo-face pipeline:
#   originals/*  -> rectify (perspective / rotation) -> measure keys + LCD
#   -> faces/face_<model>.png          (photo face, transparent outside the body)
#   -> faces/face_<model>_nolcd.png    (same, LCD glass replaced by clean empty glass;
#                                       the app draws the live display there)
#   (the HP badge top right is covered by the three-panel logo, icon/AppIcon-square-1024.png)
#   -> faces/geometry.json             (normalised key / LCD rectangles)
#   -> ../app/Sources/Models/PhotoFaceGeometry.swift (the same numbers, for the app)
#   -> ../app/Resources/Faces/face_<model>_nolcd.png (copied; the app bundles these)
# Run with a Python that has opencv-python-headless, numpy and pillow:
#   python3 art/tools/make_faces.py
import cv2, numpy as np, json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from rectify import rectify
from measure import measure

ART = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
ROOT = os.path.dirname(ART)
WIDTH = 2000
MODELS = {'12c': 'hp12c_P1040477.JPG', '15c': 'hp15c_HP15c-front-300dpi.jpg', '16c': 'hp16c_HP16c-front-web.jpg'}

def rounded_alpha(w, h, r):
    s = 4  # supersample for a smooth edge
    m = np.zeros((h * s, w * s), np.uint8)
    R = r * s
    cv2.rectangle(m, (R, 0), (w * s - R, h * s), 255, -1)
    cv2.rectangle(m, (0, R), (w * s, h * s - R), 255, -1)
    for cx, cy in ((R, R), (w * s - R, R), (R, h * s - R), (w * s - R, h * s - R)):
        cv2.circle(m, (cx, cy), R, 255, -1)
    return cv2.resize(m, (w, h), interpolation=cv2.INTER_AREA)

def clean_lcd(bgr, box):
    """Replace the LCD glass with empty glass: fit a smooth (cubic in x, quadratic in y)
    surface per channel to the background pixels (not the segments) and paint it in."""
    x, y, w, h = [int(round(v)) for v in box]
    win = bgr[y:y + h, x:x + w].astype(np.float64)
    gray = win.mean(2)
    bgest = cv2.medianBlur(gray.astype(np.uint8), 61).astype(np.float64)
    bgmask = gray > bgest - 12
    # keep away from the frame shading in the outer 4 %
    my, mx = int(h * 0.06), int(w * 0.02)
    inner = np.zeros_like(bgmask); inner[my:h - my, mx:w - mx] = True
    yy, xx = np.mgrid[0:h, 0:w]
    u, v = xx / w - 0.5, yy / h - 0.5
    terms = [np.ones_like(u), u, v, u * u, u * v, v * v, u ** 3, u * u * v]
    A = np.stack([t[bgmask & inner] for t in terms], 1)
    out = np.empty_like(win)
    for c in range(3):
        coef, *_ = np.linalg.lstsq(A, win[:, :, c][bgmask & inner], rcond=None)
        out[:, :, c] = sum(k * t for k, t in zip(coef, terms))
    # darken towards the frame a little (the glass is recessed), like the photo does
    edge = np.minimum.reduce([xx, w - 1 - xx, yy, h - 1 - yy]).astype(np.float64)
    out *= (0.86 + 0.14 * np.clip(edge / (h * 0.08), 0, 1))[..., None]
    res = bgr.copy()
    res[y:y + h, x:x + w] = np.clip(out, 0, 255).astype(np.uint8)
    return res

LOGO = os.path.join(ART, 'icon', 'AppIcon-square-1024.png')

def measure_badge(bgr):
    """The HP badge: the dark square in the top-right corner of the faceplate (x, y, w, h)."""
    H, W = bgr.shape[:2]; x0, x1, y1 = int(W * 0.75), int(W * 0.97), int(H * 0.25)
    g = cv2.cvtColor(bgr[:y1, x0:x1], cv2.COLOR_BGR2GRAY)
    mask = cv2.morphologyEx((g < np.median(g) - 55).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    n, _, st, _ = cv2.connectedComponentsWithStats(mask)
    c = [(st[i, 4], i) for i in range(1, n) if 0.75 < st[i, 2] / max(1, st[i, 3]) < 1.3 and st[i, 2] > 80]
    x, y, w, h = st[max(c)[1], :4]
    return [int(x + x0), int(y), int(w), int(h)]

def replace_badge(bgr, box, margin=7):
    """Cover the HP badge with the three-panel logo, same square. First the badge and a margin
    around it are rebuilt as bare faceplate: the brushed metal of the same rows just left of
    the badge, shifted per row so it meets the real faceplate on both sides; then the logo
    (its transparent rounded corners show that faceplate) goes exactly on the old square."""
    x, y, w, h = box
    px, py, pw, ph = x - margin, y - margin, w + 2 * margin, h + 2 * margin
    img = bgr.astype(np.float64)
    src = img[py:py + ph, px - pw - 4:px - 4].copy()                  # same rows, left of the badge
    band = 4
    left = img[py:py + ph, px - band:px].mean(1)                       # real faceplate either side
    right = img[py:py + ph, px + pw:px + pw + band].mean(1)
    sl, sr = src[:, :band].mean(1), src[:, -band:].mean(1)
    k = cv2.getGaussianKernel(15, 4).ravel()
    sm = lambda a: np.stack([np.convolve(np.pad(a[:, c], 7, mode='edge'), k, 'valid') for c in range(3)], 1)
    dl, dr = sm(left - sl), sm(right - sr)
    t = np.linspace(0, 1, pw)[None, :, None]
    patch = src + dl[:, None, :] * (1 - t) + dr[:, None, :] * t
    # top and bottom rows: feather into the real faceplate above and below
    fy = np.clip(np.minimum(np.arange(ph), ph - 1 - np.arange(ph)) / 3.0, 0, 1)[:, None, None]
    out = img.copy()
    out[py:py + ph, px:px + pw] = patch * fy + img[py:py + ph, px:px + pw] * (1 - fy)
    # rows inside the badge must be all patch (the feather only touches the margin rows)
    out[y:y + h, px:px + pw] = patch[margin:margin + h]
    from PIL import Image
    logo = Image.open(LOGO).convert('RGBA').resize((w * 4, h * 4), Image.LANCZOS).resize((w, h), Image.LANCZOS)
    la = np.asarray(logo).astype(np.float64)
    a = la[:, :, 3:4] / 255.0
    rgb = la[:, :, 2::-1]                                              # RGB -> BGR
    out[y:y + h, x:x + w] = rgb * a + out[y:y + h, x:x + w] * (1 - a)
    return np.clip(out, 0, 255).astype(np.uint8)

def main():
    os.makedirs(os.path.join(ART, 'faces'), exist_ok=True)
    os.makedirs(os.path.join(ART, 'work'), exist_ok=True)
    overrides = json.load(open(os.path.join(ART, 'tools', 'lcd_windows.json')))
    badges = json.load(open(os.path.join(ART, 'tools', 'badges.json')))
    geo = {}
    for m, fn in MODELS.items():
        src = os.path.join(ART, 'originals', fn)
        rgba, info = rectify(src, WIDTH)
        work = os.path.join(ART, 'work', f'rect_{m}.png')
        cv2.imwrite(work, rgba)
        meas = measure(work)
        H, W = rgba.shape[:2]
        if m in overrides:
            lx, ly, lw, lh = overrides[m]
            meas['lcd_px'] = [lx, ly, lw, lh]
            meas['lcd'] = [round(lx / W, 5), round(ly / H, 5), round(lw / W, 5), round(lh / H, 5)]
            meas['lcd_source'] = 'hand-checked (tools/lcd_windows.json)'
        else:
            meas['lcd_source'] = 'automatic'
        alpha = rounded_alpha(W, H, int(W * 0.012))
        bgr = rgba[:, :, :3]
        found = measure_badge(bgr)
        if m in badges and max(abs(a - b) for a, b in zip(found, badges[m])) > 3:
            print(m, 'badge measured at', found, 'but badges.json says', badges[m], '- using badges.json')
        badge = badges.get(m, found)
        bgr = replace_badge(np.ascontiguousarray(bgr), badge)
        face = np.dstack([bgr, alpha])
        cv2.imwrite(os.path.join(ART, 'faces', f'face_{m}.png'), face, [cv2.IMWRITE_PNG_COMPRESSION, 9])
        nol = clean_lcd(bgr, meas['lcd_px'])
        cv2.imwrite(os.path.join(ART, 'faces', f'face_{m}_nolcd.png'), np.dstack([nol, alpha]), [cv2.IMWRITE_PNG_COMPRESSION, 9])
        geo[m] = dict(source=fn, rectify=info, size=[W, H], badge_px=badge, lcd=meas['lcd'], lcd_px=meas['lcd_px'],
                      lcd_source=meas['lcd_source'], keys_filled_from_grid=meas['filled_from_grid'],
                      keys=meas['keys'], keys_px=meas['keys_px'])
        print(m, 'size', W, 'x', H, 'native', info['native_width'], 'x', info['native_height'],
              'rot', info['rotation_deg'], 'filled', meas['filled_from_grid'])
    json.dump(geo, open(os.path.join(ART, 'faces', 'geometry.json'), 'w'), indent=1)
    write_swift(geo)
    # the app ships only the empty-LCD faces
    import shutil
    res = os.path.join(ROOT, 'app', 'Resources', 'Faces'); os.makedirs(res, exist_ok=True)
    for m in MODELS:
        shutil.copyfile(os.path.join(ART, 'faces', f'face_{m}_nolcd.png'), os.path.join(res, f'face_{m}_nolcd.png'))
    print('copied empty-LCD faces to', res, '- rerun app/tools/genproj.py if the file set changed')

def write_swift(geo):
    names = {'12c': 'hp12c', '15c': 'hp15c', '16c': 'hp16c'}
    L = ['// SPDX-License-Identifier: MIT', '// Copyright (c) 2026 José González Divassón', '//',
         '// PhotoFaceGeometry.swift - GENERATED by art/tools/make_faces.py; do not edit by hand.',
         '// Key and LCD rectangles measured on the photo faces (art/faces/face_<model>.png), as',
         '// fractions of the face width / height (x, y, w, h; origin top-left).', '',
         'import Foundation', '', 'extension PhotoFace {']
    for m, g in geo.items():
        W, H = g['size']
        L.append(f'    public static let {names[m]} = PhotoFace(')
        L.append(f'        imageName: "face_{m}", emptyLCDImageName: "face_{m}_nolcd",')
        L.append(f'        pixelSize: CGSize(width: {W}, height: {H}),')
        lx, ly, lw, lh = g['lcd']
        L.append(f'        lcd: CGRect(x: {lx}, y: {ly}, width: {lw}, height: {lh}),')
        L.append('        keys: [')
        for k, (x, y, w, h) in sorted(g['keys'].items(), key=lambda t: int(t[0])):
            L.append(f'            {int(k)}: CGRect(x: {x}, y: {y}, width: {w}, height: {h}),')
        L.append('        ])')
    L.append('}')
    out = os.path.join(ROOT, 'app', 'Sources', 'Models', 'PhotoFaceGeometry.swift')
    open(out, 'w').write('\n'.join(L) + '\n')
    print('wrote', out)

if __name__ == '__main__':
    main()
