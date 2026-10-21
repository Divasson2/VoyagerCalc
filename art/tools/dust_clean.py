# SPDX-License-Identifier: MIT
# Copyright (c) 2026 José González Divassón
"""dust_clean.py - find and inpaint dust specks on a photo face (0.6.9 plan, sample tool).

Usage: python3 dust_clean.py face_15c_nolcd.png OUT_DIR [--thr 7] [--max-area 80]

Writes into OUT_DIR (never touches the input): <name>_clean.png, <name>_mask.png,
<name>_detections.png (scaled overview, specks circled), <name>_strip.png (before / after / difference x8 for the 8 strongest specks)
and <name>_report.json. Needs numpy + opencv-python-headless (the faces venv).

Method (all numbers are for the 2000 px wide faces):
 1. residual = luminance - median9(luminance): a speck is a small blob the median removes.
 2. protected zones: strong structure (legends, key edges, bezels: Gaussian-6 gradient, dilated),
    textured zones (the leather-look side rails: local mean |residual| high), alpha < 255.
 3. keep blobs 2..max-area px whose |residual| > thr, bbox <= 16 px; grow them 2 px.
 4. cv2.inpaint (Telea, radius 3) on the colour image, alpha untouched.
"""
import argparse, json, os, sys
import cv2
import numpy as np


def detect(bgr, alpha, thr=7.0, max_area=80, lcd=None, badge=None, ring_std_max=2.5):
    g = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    h, w = g.shape
    res = g.astype(np.float32) - cv2.medianBlur(g, 9).astype(np.float32)
    big = cv2.GaussianBlur(g.astype(np.float32), (0, 0), 6)
    grad = np.hypot(cv2.Sobel(big, cv2.CV_32F, 1, 0), cv2.Sobel(big, cv2.CV_32F, 0, 1))
    structure = cv2.dilate((grad > 6).astype(np.uint8), np.ones((13, 13), np.uint8)) > 0
    texture = cv2.blur(np.abs(res), (61, 61)) > 3.0
    protect = structure | texture | (alpha < 255)
    for r in (lcd, badge):
        if r:
            x, y, rw, rh = r
            protect[max(0, y - 6):y + rh + 6, max(0, x - 6):x + rw + 6] = True
    cand = ((np.abs(res) > thr) & ~protect).astype(np.uint8)
    n, lab, st, cen = cv2.connectedComponentsWithStats(cand, 8)
    mask = np.zeros_like(cand)
    specks = []
    for i in range(1, n):
        x, y, bw, bh, area = st[i]
        if 2 <= area <= max_area and max(bw, bh) <= 16:
            # isolation test: the ring 4..9 px around the blob must be quiet (a speck sits on flat ground;
            # key corners, hairlines and bezel edges have a busy ring).
            x0, y0 = max(0, x - 10), max(0, y - 10)
            sub = (lab[y0:y + bh + 10, x0:x + bw + 10] == i).astype(np.uint8)
            near = cv2.dilate(sub, np.ones((9, 9), np.uint8)) > 0
            far = cv2.dilate(sub, np.ones((19, 19), np.uint8)) > 0
            ring = far & ~near
            gl = g[y0:y + bh + 10, x0:x + bw + 10].astype(np.float32)
            if ring.sum() < 20 or gl[ring].std() > ring_std_max or protect[y0:y + bh + 10, x0:x + bw + 10][ring].mean() > 0.2:
                continue
            specks.append({"_i": i, "x": int(cen[i][0]), "y": int(cen[i][1]), "area": int(area),
                           "contrast": round(float(np.abs(res[lab == i]).max()), 1)})
    # real dust is isolated; a row of tiny dots (JPEG / print texture) is not: drop specks with 2+ neighbours within 40 px
    keep = [s for s in specks if sum(1 for t in specks if t is not s and abs(t["x"] - s["x"]) < 40 and abs(t["y"] - s["y"]) < 40) < 2]
    for s in keep:
        mask[lab == s.pop("_i")] = 255
    mask = cv2.dilate(mask, np.ones((5, 5), np.uint8))
    return mask, keep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("face"); ap.add_argument("out")
    ap.add_argument("--thr", type=float, default=6.0)
    ap.add_argument("--max-area", type=int, default=80)
    ap.add_argument("--ring-std", type=float, default=3.0)
    ap.add_argument("--geometry", default=os.path.join(os.path.dirname(__file__), "..", "faces", "geometry.json"))
    a = ap.parse_args()
    im = cv2.imread(a.face, cv2.IMREAD_UNCHANGED)
    bgr = im[:, :, :3]
    alpha = im[:, :, 3] if im.shape[2] == 4 else np.full(im.shape[:2], 255, np.uint8)
    key = os.path.basename(a.face).split("_")[1]
    geo = json.load(open(a.geometry)).get(key, {})
    mask, specks = detect(bgr, alpha, a.thr, a.max_area, geo.get("lcd_px"), geo.get("badge_px"), a.ring_std)
    clean = cv2.inpaint(bgr, mask, 3, cv2.INPAINT_TELEA)
    os.makedirs(a.out, exist_ok=True)
    base = os.path.splitext(os.path.basename(a.face))[0]
    out = clean if im.shape[2] == 3 else np.dstack([clean, alpha])
    cv2.imwrite(os.path.join(a.out, base + "_clean.png"), out)
    cv2.imwrite(os.path.join(a.out, base + "_mask.png"), mask)
    over = bgr.copy()
    for s in specks:
        cv2.circle(over, (s["x"], s["y"]), 12, (0, 0, 255), 2)
    cv2.imwrite(os.path.join(a.out, base + "_detections.png"),
                cv2.resize(over, (1400, int(1400 * over.shape[0] / over.shape[1])), interpolation=cv2.INTER_AREA))
    tiles_b, tiles_a, tiles_d = [], [], []
    hh, ww = bgr.shape[:2]
    lift = lambda im: (np.power(im.astype(np.float32) / 255, 0.5) * 255).astype(np.uint8)   # gamma 0.5: dark dust becomes visible
    R, S = 20, 8                                   # 40 x 40 px around a speck, shown at 8x
    for s in sorted(specks, key=lambda s: -s["contrast"])[:8]:
        x = min(max(s["x"], R), ww - R); y = min(max(s["y"], R), hh - R)
        b = bgr[y - R:y + R, x - R:x + R]; c = clean[y - R:y + R, x - R:x + R]
        d = np.clip(np.abs(b.astype(np.int16) - c.astype(np.int16)) * 8, 0, 255).astype(np.uint8)
        for src, dst in ((lift(b), tiles_b), (lift(c), tiles_a), (d, tiles_d)):
            t = cv2.resize(src, (2 * R * S, 2 * R * S), interpolation=cv2.INTER_NEAREST)
            cv2.putText(t, f"{s['x']},{s['y']}", (4, 14), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 255, 255), 1, cv2.LINE_AA)
            dst.append(t)
    if tiles_b:   # rows: before, after, difference x8 (before / after lifted with gamma 0.5 so dark dust shows)
        strip = np.vstack([np.hstack(tiles_b), np.hstack(tiles_a), np.hstack(tiles_d)])
        label = np.full((strip.shape[0], 150, 3), 32, np.uint8)
        th = 2 * R * S
        for i, text in enumerate(("BEFORE", "AFTER", "DIFFERENCE x8")):
            cv2.putText(label, text, (8, i * th + th // 2), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1, cv2.LINE_AA)
        cv2.imwrite(os.path.join(a.out, base + "_strip.png"), np.hstack([label, strip]))
    json.dump({"face": os.path.basename(a.face), "threshold": a.thr, "specks": len(specks),
               "masked_pixels": int((mask > 0).sum()), "list": specks},
              open(os.path.join(a.out, base + "_report.json"), "w"), indent=1)
    print(base, "specks:", len(specks), "masked px:", int((mask > 0).sum()))


if __name__ == "__main__":
    sys.exit(main())
