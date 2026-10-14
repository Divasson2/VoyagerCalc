#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# overlay.py - draw the measured key / LCD rectangles on a face for checking.
import cv2, json, sys
img = cv2.imread(sys.argv[1], cv2.IMREAD_UNCHANGED)[:, :, :3].copy()
d = json.load(open(sys.argv[2])); H, W = img.shape[:2]
def box(r, col):
    x, y, w, h = r
    cv2.rectangle(img, (int(x * W), int(y * H)), (int((x + w) * W), int((y + h) * H)), col, 2)
for k, r in d['keys'].items():
    box(r, (0, 0, 255)); cv2.putText(img, k, (int(r[0] * W) + 4, int(r[1] * H) + 22), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)
box(d['lcd'], (255, 0, 255))
cv2.imwrite(sys.argv[3], cv2.resize(img, (W // 2, H // 2), interpolation=cv2.INTER_AREA) if len(sys.argv) < 5 else img)
