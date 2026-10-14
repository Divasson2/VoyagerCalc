#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# rectify.py - find the calculator body in a shop photo, fit its four edges, correct the
# small perspective / rotation and write a straight-on, cropped RGBA image (transparent
# outside the body's rounded corners).  Step 1 of the face pipeline (see art/README.md).
import cv2, numpy as np, sys, json

def body_mask(img):
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    h, w = g.shape
    bg = int(np.median(np.concatenate([g[:8].ravel(), g[-8:].ravel(), g[:, :8].ravel(), g[:, -8:].ravel()])))
    m = (g < bg - 14).astype(np.uint8) * 255
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
    cs, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    c = max(cs, key=cv2.contourArea)
    out = np.zeros_like(m); cv2.drawContours(out, [c], -1, 255, -1)
    return out, c.reshape(-1, 2).astype(np.float64)

def fit_edges(pts):
    x0, y0 = pts.min(0); x1, y1 = pts.max(0)
    w, h = x1 - x0, y1 - y0
    band = 12
    def fit(sel, horizontal):
        p = pts[sel]
        if horizontal:   # y = a x + b
            a, b = np.polyfit(p[:, 0], p[:, 1], 1); return ('h', a, b)
        a, b = np.polyfit(p[:, 1], p[:, 0], 1); return ('v', a, b)
    midx = (pts[:, 0] > x0 + 0.15 * w) & (pts[:, 0] < x1 - 0.15 * w)
    midy = (pts[:, 1] > y0 + 0.15 * h) & (pts[:, 1] < y1 - 0.15 * h)
    # the top edge is taken from the black side rails only: the metal display panel can be
    # nearly as light as the backdrop
    rails = ((pts[:, 0] > x0 + 0.004 * w) & (pts[:, 0] < x0 + 0.035 * w)) | \
            ((pts[:, 0] < x1 - 0.004 * w) & (pts[:, 0] > x1 - 0.035 * w))
    top = fit(rails & (pts[:, 1] < y0 + band), True)
    bot = fit(midx & (pts[:, 1] > y1 - band), True)
    lef = fit(midy & (pts[:, 0] < x0 + band), False)
    rig = fit(midy & (pts[:, 0] > x1 - band), False)
    def meet(hl, vl):
        _, a, b = hl; _, c, d = vl      # y = a x + b ; x = c y + d
        y = (a * d + b) / (1 - a * c); x = c * y + d
        return [x, y]
    return np.array([meet(top, lef), meet(top, rig), meet(bot, rig), meet(bot, lef)], np.float64)

def rectify(path, out_w):
    img = cv2.imread(path)
    mask, pts = body_mask(img)
    q = fit_edges(pts)
    wtop = np.linalg.norm(q[1] - q[0]); wbot = np.linalg.norm(q[2] - q[3])
    hl = np.linalg.norm(q[3] - q[0]); hr = np.linalg.norm(q[2] - q[1])
    aspect = ((wtop + wbot) / 2) / ((hl + hr) / 2)
    out_h = int(round(out_w / aspect))
    dst = np.array([[0, 0], [out_w, 0], [out_w, out_h], [0, out_h]], np.float64)
    H = cv2.getPerspectiveTransform(q.astype(np.float32), dst.astype(np.float32))
    warped = cv2.warpPerspective(img, H, (out_w, out_h), flags=cv2.INTER_LANCZOS4, borderMode=cv2.BORDER_REPLICATE)
    am = cv2.warpPerspective(mask, H, (out_w, out_h), flags=cv2.INTER_LINEAR)
    am = cv2.GaussianBlur(am, (3, 3), 0)
    rgba = np.dstack([warped, am])
    angle = np.degrees(np.arctan2(q[1][1] - q[0][1], q[1][0] - q[0][0]))
    info = dict(corners=q.round(1).tolist(), native_width=round((wtop + wbot) / 2, 1),
                native_height=round((hl + hr) / 2, 1), top_bottom_width=[round(wtop, 1), round(wbot, 1)],
                rotation_deg=round(angle, 3), out=[out_w, out_h])
    return rgba, info

if __name__ == '__main__':
    src, dst, w = sys.argv[1], sys.argv[2], int(sys.argv[3])
    rgba, info = rectify(src, w)
    cv2.imwrite(dst, rgba)
    print(json.dumps(info))
