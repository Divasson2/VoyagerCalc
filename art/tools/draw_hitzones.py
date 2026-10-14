#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Diagram of the 0.5.5 click zones on a photo face: gold = f + key, white = key, blue = g + key.
Same math as PhotoFace.hitRect / zones (Swift), from art/faces/geometry.json + PhotoFaceLabels."""
import json, os, re, sys
from PIL import Image, ImageDraw
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
G = json.load(open(f'{ROOT}/art/faces/geometry.json'))
FR = dict(re.findall(r'"face_(\w+)": ([\d.]+)', open(f'{ROOT}/app/Sources/Models/PhotoFaceLabels.swift').read()))
SPEC = {}
for m in ('12C', '15C', '16C'):
    src = open(f'{ROOT}/app/Sources/Models/Model{m}.swift').read()
    for c, body in re.findall(r'KeySpec\((\d+), (.*?)\)\s*,?\s*\n', src):
        SPEC[(m.lower(), int(c))] = ('f: "' in body and 'f: ""' not in body, 'g: "' in body and 'g: ""' not in body)

def zones(m):
    d = G[m]; keys = {int(k): v for k, v in (d['keys'] if isinstance(d['keys'], dict) else eval(d['keys'])).items()}
    def at(n, c):
        if n < 0 or n >= 40: return None
        mm = 25 if n == 35 else n
        return None if mm == c else keys.get(mm)
    def med(v): v = sorted(v); return v[len(v)//2]
    dx = [keys[c+1][0] + keys[c+1][2]/2 - (r[0] + r[2]/2) for c, r in keys.items() if c != 25 and c+1 in keys and c % 10 != 9 and c+1 != 25]
    dy = [keys[c+10][1] - r[1] for c, r in keys.items() if c != 25 and c+10 in keys and c+10 not in (25, 35)]
    pw, ph = med(dx), med(dy)
    capH = keys[24][3]; up = 0.68; frac = float(FR[m])
    out = {}
    for c, (x, y, w, h) in keys.items():
        col = c % 10; gapX = max(0, pw - w); gapY = max(0, ph - capH)
        L = (lambda n: ((n[0]+n[2]) + x)/2 if n else x - gapX/2)(at(c-1, c)) if col > 0 else x - gapX/2
        R = (lambda n: ((x+w) + n[0])/2 if n else x + w + gapX/2)(at(c+1, c)) if col < 9 else x + w + gapX/2
        a = at(c-10, c); T = a[1]+a[3] + (y - (a[1]+a[3]))*(1-up) if a else y - gapY*up
        b = at(c+10, c) or at(c+20, c); B = (y+h) + (b[1] - (y+h))*(1-up) if b else y + h + gapY*(1-up)
        hasF, hasG = SPEC.get((m, c), (False, False))
        top = y if hasF else T; gt = (y + h - capH*frac) if hasG else B
        out[c] = {'f': (L, T, R, top) if hasF else None, 'face': (L, top, R, gt), 'g': (L, gt, R, B) if hasG else None}
    return out

for m in sys.argv[1:] or ['15c']:
    im = Image.open(f'{ROOT}/art/faces/face_{m}.png').convert('RGBA'); W, H = im.size
    ov = Image.new('RGBA', im.size, (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
    col = {'f': (227, 166, 58), 'face': (255, 255, 255), 'g': (93, 169, 232)}
    Z = zones(m)
    # fills first, then every outline on top (so no neighbour's fill hides an edge), then tags
    for c, z in Z.items():
        for p, r in z.items():
            if r: d.rectangle((r[0]*W + 3, r[1]*H + 3, r[2]*W - 3, r[3]*H - 3), fill=col[p] + (80,))
    for c, z in Z.items():
        for p, r in z.items():
            if r: d.rectangle((r[0]*W + 3, r[1]*H + 3, r[2]*W - 3, r[3]*H - 3), outline=col[p] + (255,), width=4)
    for c, z in Z.items():
        for p, r in (('f', z['f']), ('g', z['g'])):
            if r:
                d.rectangle((r[0]*W + 5, r[1]*H + 5, r[0]*W + 25, r[1]*H + 27), fill=(0, 0, 0, 200))
                d.text((r[0]*W + 10, r[1]*H + 8), p, fill=col[p] + (255,))
    out = Image.alpha_composite(im, ov)
    ImageDraw.Draw(out).text((20, H - 40), "gold = f + key   white = key   blue = g + key   (VoyagerCalc 0.5.5 click zones)", fill=(255, 255, 255, 255))
    p = f'{ROOT}/screens/hitzones-{m}.png'; out.convert('RGB').save(p); print(p, out.size)
