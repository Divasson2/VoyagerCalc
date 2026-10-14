#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# measure.py - measure the LCD window and the 39 key rectangles on a rectified face
# (rectify.py output).  The f and g keys are found by colour; they give the key size and the
# column pitch.  Every other key is then located by snapping a rectangle of that size to the
# strongest outline (Sobel edges) near its grid position.  Output: normalised rectangles
# (x, y, w, h as fractions of the face width / height), JSON on stdout.
import cv2, numpy as np, sys, json

def color_box(hsv, region, hue, sat, val=120):
    x0, y0, x1, y1 = region
    sub = hsv[y0:y1, x0:x1]
    m = ((sub[:, :, 0] >= hue[0]) & (sub[:, :, 0] <= hue[1]) & (sub[:, :, 1] >= sat) & (sub[:, :, 2] >= val)).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    i = 1 + int(np.argmax(st[1:, 4]))
    x, y, w, h, _ = st[i]
    return np.array([x + x0, y + y0, w, h], float)

def lcd_box(img):
    H, W = img.shape[:2]
    top = img[: int(H * 0.27)].astype(int)
    b, g, r = top[:, :, 0], top[:, :, 1], top[:, :, 2]
    m = ((g >= r - 4) & (g - b > 10) & (g > 50)).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((45, 45), np.uint8))
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((9, 9), np.uint8))
    m[: int(H * 0.03)] = 0
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    wide = [j for j in range(1, n) if st[j, 2] > 0.3 * W]
    i = max(wide, key=lambda j: st[j, 4])
    x, y, w, h, _ = st[i]
    # trim rows / columns that are less than 60 % LCD (rounded corners, bevel shading)
    comp = (lab[y:y + h, x:x + w] == i)
    rows = np.where(comp.mean(1) > 0.6)[0]; cols = np.where(comp.mean(0) > 0.6)[0]
    return np.array([x + cols[0], y + rows[0], cols[-1] - cols[0] + 1, rows[-1] - rows[0] + 1], float)

class Edges:
    def __init__(self, gray):
        g = cv2.GaussianBlur(gray, (3, 3), 0).astype(np.float32)
        self.gx = np.abs(cv2.Sobel(g, cv2.CV_32F, 1, 0, ksize=3))
        self.gy = np.abs(cv2.Sobel(g, cv2.CV_32F, 0, 1, ksize=3))
        self.ix = cv2.integral(self.gx); self.iy = cv2.integral(self.gy)
    @staticmethod
    def _sum(ii, x0, y0, x1, y1):
        return ii[y1, x1] - ii[y0, x1] - ii[y1, x0] + ii[y0, x0]
    def score(self, x, y, w, h, t=2):
        x, y, w, h = int(x), int(y), int(w), int(h)
        # inset the strip ends so corners (rounded) do not dominate
        ix, iy = int(w * 0.15), int(h * 0.15)
        l = self._sum(self.ix, x - t, y + iy, x + t, y + h - iy)
        r = self._sum(self.ix, x + w - t, y + iy, x + w + t, y + h - iy)
        tp = self._sum(self.iy, x + ix, y - t, x + w - ix, y + t)
        bt = self._sum(self.iy, x + ix, y + h - t, x + w - ix, y + h + t)
        # require all four sides (geometric-ish mean via min + mean)
        sides = np.array([l / (h - 2 * iy), r / (h - 2 * iy), tp / (w - 2 * ix), bt / (w - 2 * ix)])
        return sides.mean() + sides.min()

def snap(E, x, y, w, h, rx, ry, rs=6):
    best = (-1, x, y, w, h)
    for dw in range(-rs, rs + 1, 2):
        for dh in range(-rs, rs + 1, 2):
            for dy in range(-ry, ry + 1, 2):
                for dx in range(-rx, rx + 1, 2):
                    s = E.score(x + dx, y + dy, w + dw, h + dh)
                    if s > best[0]: best = (s, x + dx, y + dy, w + dw, h + dh)
    # fine pass at 1 px
    s0, bx, by, bw, bh = best
    for dw in (-1, 0, 1):
        for dh in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    s = E.score(bx + dx, by + dy, bw + dw, bh + dh)
                    if s > best[0]: best = (s, bx + dx, by + dy, bw + dw, bh + dh)
    return best

def clusters(vals, gap):
    vals = sorted(vals); out = [[vals[0]]]
    for v in vals[1:]:
        if v - out[-1][-1] > gap: out.append([v])
        else: out[-1].append(v)
    return [float(np.median(c)) for c in out]

def measure(path):
    img = cv2.imread(path, cv2.IMREAD_UNCHANGED)[:, :, :3]
    H, W = img.shape[:2]
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    # Key caps are lighter than the black keyboard plate.  Threshold at a range of levels,
    # keep blobs of key size (and the tall ENTER), and pool them.
    found = []      # (cx, cy, x, y, w, h, tall)
    for t in range(30, 80, 3):
        m = (blur > t).astype(np.uint8)
        m[: int(H * 0.33)] = 0
        m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
        n, lab, st, cen = cv2.connectedComponentsWithStats(m)
        for (x, y, w, h, a), (cx, cy) in zip(st[1:], cen[1:]):
            if 0.05 * W < w < 0.08 * W and 0.07 * H < h < 0.115 * H and a > 0.75 * w * h:
                found.append((x + w / 2, y + h / 2, x, y, w, h, False))
            elif 0.05 * W < w < 0.08 * W and 0.2 * H < h < 0.3 * H and a > 0.75 * w * h:
                found.append((x + w / 2, y + h / 2, x, y, w, h, True))
    normal = [f for f in found if not f[6]]
    tall = [f for f in found if f[6]]
    cols = clusters([f[0] for f in normal], 0.03 * W)
    rows = clusters([f[1] for f in normal], 0.04 * H)
    if len(cols) != 10 or len(rows) != 4:
        raise SystemExit(f"grid not found: {len(cols)} columns, {len(rows)} rows")
    near = lambda v, arr: int(np.argmin([abs(v - a) for a in arr]))
    slots = {}
    for f in normal:
        r, c = near(f[1], rows), near(f[0], cols)
        slots.setdefault(10 * r + c, []).append(f[2:6])
    keys, missing = {}, []
    for r in range(4):
        for c in range(10):
            code = 10 * r + c
            if code in (25, 35): continue
            if code in slots and len(slots[code]) >= 2:
                keys[code] = [float(np.median([s[i] for s in slots[code]])) for i in range(4)]
            else:
                missing.append(code)
    # fill gaps from the row (y, h) and column (x, w) medians
    for code in missing:
        r, c = divmod(code, 10)
        rr = [keys[k] for k in keys if k // 10 == r]; cc = [keys[k] for k in keys if k % 10 == c]
        keys[code] = [float(np.median([k[0] for k in cc])), float(np.median([k[1] for k in rr])),
                      float(np.median([k[2] for k in cc])), float(np.median([k[3] for k in rr]))]
    if tall:
        keys[25] = [float(np.median([t[i] for t in tall])) for i in (2, 3, 4, 5)]
    else:
        missing.append(25)
        k5r2 = [keys[k] for k in keys if k // 10 == 2]; k5r3 = [keys[k] for k in keys if k // 10 == 3]
        cc = [keys[k] for k in keys if k % 10 == 5]
        y0 = np.median([k[1] for k in k5r2]); y1 = np.median([k[1] + k[3] for k in k5r3])
        keys[25] = [float(np.median([k[0] for k in cc])), float(y0), float(np.median([k[2] for k in cc])), float(y1 - y0)]
    # regularise: the caps are all the same size, keys in a row share a centre line and
    # keys in a column share a centre column (the photo is rectified), so use the medians
    normal = [k for k in keys if k != 25]
    kw = float(np.median([keys[k][2] for k in normal])); kh = float(np.median([keys[k][3] for k in normal]))
    cy = {r: float(np.median([keys[k][1] + keys[k][3] / 2 for k in normal if k // 10 == r])) for r in range(4)}
    cx = {c: float(np.median([keys[k][0] + keys[k][2] / 2 for k in normal if k % 10 == c])) for c in range(10)}
    for k in normal:
        keys[k] = [cx[k % 10] - kw / 2, cy[k // 10] - kh / 2, kw, kh]
    e = keys[25]
    keys[25] = [cx[5] - kw / 2, e[1], kw, e[3]]
    lcd = lcd_box(img)
    norm = lambda r: [round(r[0] / W, 5), round(r[1] / H, 5), round(r[2] / W, 5), round(r[3] / H, 5)]
    return dict(size=[W, H], filled_from_grid=sorted(missing),
                lcd_px=[float(v) for v in lcd], lcd=norm(lcd),
                keys_px={k: [round(v, 1) for v in keys[k]] for k in sorted(keys)},
                keys={k: norm(keys[k]) for k in sorted(keys)})

if __name__ == '__main__':
    print(json.dumps(measure(sys.argv[1])))
