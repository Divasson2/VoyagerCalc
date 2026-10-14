#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 José González Divassón
#
# Box-side preview of the calculator face: a Pillow port of CalculatorFace / LCDView /
# KeyView (same geometry, colours and model data, parsed from the Swift sources), with
# display contents from the real C core. Used when no Mac is at hand; the Xcode snapshot
# test (Tests/AppTests/SnapshotTests.swift) renders the real SwiftUI views.
#   python3 app/tools/preview.py LCD.json MODEL(12|15|16) landscape|portrait|photo W H OUT.png [pressed codes] [turbo]
# "photo" is a port of PhotoCalculatorFace (PhotoFaceView.swift): the photo face from
# Resources/Faces, the live display over the empty glass, pressed keys sunk and darkened,
# geometry parsed from Sources/Models/PhotoFaceGeometry.swift.
import json, os, re, sys
from PIL import Image, ImageDraw, ImageFont

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

def model(mid):
    src = open(os.path.join(APP, f"Sources/Models/Model{mid}C.swift"), encoding="utf-8").read()
    keys = []
    for m in re.finditer(r'KeySpec\((\d+), "((?:[^"\\]|\\.)*)"(.*?)\),?\n', src):
        code, name, rest = int(m.group(1)), m.group(2), m.group(3)
        def opt(k):
            mm = re.search(k + r': "((?:[^"\\]|\\.)*)"', rest)
            return mm.group(1) if mm else ""
        style = re.search(r"style: \.(\w+)", rest)
        keys.append(dict(code=code, name=name, face=opt("face") or name, f=opt("f"), g=opt("g"),
                         style=style.group(1) if style else "normal",
                         shortcuts=re.findall(r'\.char\("(.)"\)|\.special\(\.(\w+)\)', rest)))
    anns = [dict(label=a, bit=int(b), cell=float(c)) for a, b, c in re.findall(r'Annunciator\(label: "([^"]+)", bit: (\d+), cell: ([\d.]+)\)', src)]
    br = [dict(label=a, fr=int(b), to=int(c)) for a, b, c in re.findall(r'LegendBracket\(label: "([^"]+)", fromCode: (\d+), toCode: (\d+)\)', src)]
    band = int(re.search(r"\.voyager\(band: 0x([0-9A-Fa-f]+)\)", src).group(1), 16)
    name = re.search(r'name: "([^"]+)", subtitle: "([^"]+)"', src)
    return dict(id=mid, keys=keys, anns=anns, brackets=br, band=band, name=name.group(1), subtitle=name.group(2))

C = dict(body=0x3B302A, bezel=0x2A221E, f=0xE3A63A, g=0x5DA9E8, cap=0x2B2725, front=0x45403C, lcd=0xA9AE99, seg=0x22241E)
def rgb(v, a=255): return ((v >> 16) & 255, (v >> 8) & 255, v & 255, a)

def font(sz, bold=True): return ImageFont.truetype(FONT_B if bold else FONT, max(6, int(sz)))

def text_center(d, box, s, sz, color, bold=True):
    f = font(sz, bold)
    while sz > 6 and d.textlength(s, font=f) > (box[2] - box[0]):
        sz *= 0.9; f = font(sz, bold)
    w = d.textlength(s, font=f); a, b = f.getbbox("Hg")[1], f.getbbox("Hg")[3]
    d.text(((box[0] + box[2] - w) / 2, (box[1] + box[3] - (b - a)) / 2 - a), s, font=f, fill=color)

def place(k, layout):
    r, c = k["code"] // 10, k["code"] % 10
    return (r, c) if layout == "landscape" else (r + (4 if c >= 5 else 0), c % 5)

def segment_poly(s, r):
    x0, y0, w, h = r
    t = w * 0.17; g = t * 0.18; mid = h / 2; slant = 0.10
    def p(x, y): return (x0 + x + (h - y) * slant, y0 + y)
    def hor(y): return [p(t/2+g, y), p(t+g, y-t/2), p(w-t-g, y-t/2), p(w-t/2-g, y), p(w-t-g, y+t/2), p(t+g, y+t/2)]
    def ver(x, a, b): return [p(x, a+g), p(x+t/2, a+t/2+g), p(x+t/2, b-t/2-g), p(x, b-g), p(x-t/2, b-t/2-g), p(x-t/2, a+t/2+g)]
    return [hor(t/2), ver(w-t/2, t/2, mid), ver(w-t/2, mid, h-t/2), hor(h-t/2), ver(t/2, mid, h-t/2), ver(t/2, t/2, mid), hor(mid)][s]

def draw_lcd(img, box, lcd, m, over_photo=False):
    d = ImageDraw.Draw(img, "RGBA")
    x0, y0, x1, y1 = box; W, H = x1 - x0, y1 - y0
    if not over_photo:
        d.rounded_rectangle(box, radius=4, fill=rgb(C["lcd"]), outline=(0, 0, 0, 90))
    cellW = W / 11.2
    digitH = H * (0.39 if over_photo else 0.62); top = y0 + H * (0.22 if over_photo else 0.10)
    left = x0 + cellW * (-0.13 if over_photo else 0.35)
    ink, faint = (rgb(0x101410, 235), rgb(C["seg"], 6)) if over_photo else (rgb(C["seg"]), rgb(C["seg"], 12))
    for i in range(10):
        x = left + (i + 1) * cellW
        r = (x + cellW * 0.14, top, cellW * 0.62, digitH)
        for s in range(7):
            d.polygon(segment_poly(s, r), fill=ink if lcd["seg"][i] >> s & 1 else faint)
        ds = cellW * 0.13
        dot = (r[0] + r[2] + cellW * 0.06, r[1] + r[3] - ds)
        if lcd["dot"][i] or lcd["comma"][i]:
            d.rectangle((dot[0], dot[1], dot[0] + ds, dot[1] + ds), fill=ink)
        if lcd["comma"][i]:
            d.polygon([(dot[0] + ds, dot[1] + ds), (dot[0] + ds * 0.8, dot[1] + ds * 2.6), (dot[0] - ds * 0.5, dot[1] + ds * 2.6), (dot[0], dot[1] + ds)], fill=ink)
    d.polygon(segment_poly(6, (left + cellW * 0.15, top, cellW * 0.62, digitH)), fill=ink if lcd["minus"] else faint)
    annY = top + digitH + H * 0.08
    f = font(max(6, H * 0.15))
    for a in m["anns"]:
        on = lcd["ann"] >> a["bit"] & 1
        bg, k = rgb(C["lcd"]), rgb(C["seg"])
        faint_t = tuple(int(bg[j] * 0.94 + k[j] * 0.06) for j in range(3))
        if over_photo:
            if on: d.text((left + (a["cell"] + 1) * cellW, annY), a["label"], font=f, fill=ink)
        else:
            d.text((left + (a["cell"] + 1) * cellW, annY), a["label"], font=f, fill=ink[:3] if on else faint_t)

def render(lcd, mid, layout, W, H, out, pressed=(), turbo=False):
    m = model(mid)
    img = Image.new("RGB", (W, H), rgb(0x1C1714)[:3])
    d = ImageDraw.Draw(img, "RGBA")
    pad = min(W, H) * 0.035
    topH = H * (0.30 if layout == "landscape" else 0.235)
    d.rounded_rectangle((0, 0, W - 1, H - 1), radius=pad * 1.2, fill=rgb(C["body"]))
    # bezel + LCD
    lcdW = W * 0.52 if layout == "landscape" else W - pad * 4
    lcdH = topH * 0.48 if layout == "landscape" else min(topH * 0.48, lcdW * 0.22)
    lcdX = W * 0.14 if layout == "landscape" else pad * 2
    lcdY = (topH - lcdH) / 2 + pad * 0.3
    d.rounded_rectangle((lcdX - pad * 0.8, lcdY - pad * 0.7, lcdX + lcdW + pad * 0.8, lcdY + lcdH + pad * 0.7), radius=pad * 0.6, fill=rgb(C["bezel"]))
    draw_lcd(img, (lcdX, lcdY, lcdX + lcdW, lcdY + lcdH), lcd, m)
    d = ImageDraw.Draw(img, "RGBA")
    nx = W * 0.95 if layout == "landscape" else W - pad * 2
    ny = lcdY if layout == "landscape" else lcdY + lcdH + pad * 0.9
    ls = layout == "landscape"
    f1, f2 = font(max(10, topH * (0.20 if ls else 0.13))), font(max(7, topH * (0.075 if ls else 0.05)))
    d.text((nx - d.textlength(m["name"], font=f1), ny), m["name"], font=f1, fill=rgb(m["band"]))
    st = " ".join(m["subtitle"].upper())
    d.text((nx - d.textlength(st, font=f2), ny + topH * (0.24 if ls else 0.16)), st, font=f2, fill=rgb(m["band"], 200))
    if turbo:
        f3 = font(max(7, topH * 0.07)); tw = d.textlength("TURBO", font=f3)
        d.rounded_rectangle((nx - tw - 8, ny + topH * 0.36, nx, ny + topH * 0.36 + topH * 0.1), radius=6, outline=rgb(C["f"]))
        d.text((nx - tw - 4, ny + topH * 0.36), "TURBO", font=f3, fill=rgb(C["f"]))
    # keyboard
    kb = (pad * 1.4, topH + pad * 0.8, W - pad * 1.4, H - pad * 1.2)
    cols, rows = (10, 4) if layout == "landscape" else (5, 8)
    cw = (kb[2] - kb[0]) / cols; rh = (kb[3] - kb[1]) / rows
    legH, keyH, keyW = rh * 0.27, rh * 0.64, cw * 0.80
    lw = max(2, int(pad * 0.22))
    d.rounded_rectangle((kb[0] - pad * 0.45, kb[1] - pad * 0.35, kb[2] + pad * 0.45, kb[3] + pad * 0.35), radius=pad * 0.5, outline=rgb(m["band"]), width=lw)
    inbr = {k["code"] for b in m["brackets"] for k in m["keys"] if b["fr"] <= k["code"] <= b["to"]}
    for k in m["keys"]:
        r, c = place(k, layout)
        lx, ly = kb[0] + c * cw, kb[1] + r * rh
        if k["f"]:
            if k["code"] in inbr: text_center(d, (lx + cw * 0.02, ly + legH * 0.45, lx + cw * 0.98, ly + legH), k["f"], legH * 0.5 * 0.85, rgb(C["f"]))
            else: text_center(d, (lx + cw * 0.02, ly, lx + cw * 0.98, ly + legH), k["f"], legH * 0.5, rgb(C["f"]))
        x = lx + (cw - keyW) / 2; y = ly + legH
        h = rh + keyH if k["style"] == "enter" else keyH
        down = k["code"] in pressed
        oy = h * 0.025 if down else 0
        frontH = min(h * 0.16, keyH * 0.30) if k["style"] == "enter" else h * 0.30
        d.rounded_rectangle((x + 1, y + 2 + oy, x + keyW + 1, y + h + 2 + oy), radius=keyW * 0.08, fill=(0, 0, 0, 110))
        d.rounded_rectangle((x, y + oy, x + keyW, y + h + oy), radius=keyW * 0.08, fill=rgb(C["front"]))
        cap = C["f"] if k["style"] == "fShift" else C["g"] if k["style"] == "gShift" else C["cap"]
        capc = rgb(cap) if not down else tuple(int(v * 0.85) for v in rgb(cap)[:3]) + (255,)
        d.rounded_rectangle((x, y + oy, x + keyW, y + h - frontH + oy), radius=keyW * 0.07, fill=capc)
        facec = (30, 26, 23, 255) if k["style"] in ("fShift", "gShift") else (255, 255, 255, 255)
        fs = min((h - frontH) * 0.48, keyH * 0.40)
        if len(k["face"]) > 3: fs *= 0.72
        text_center(d, (x + keyW * 0.06, y + oy, x + keyW * 0.94, y + h - frontH + oy), k["face"], fs, facec)
        if k["g"]:
            text_center(d, (x + keyW * 0.02, y + h - frontH + oy, x + keyW * 0.98, y + h + oy), k["g"], keyH * 0.22, rgb(C["g"]), bold=False)
    for b in m["brackets"]:
        ks = [k for k in m["keys"] if b["fr"] <= k["code"] <= b["to"]]
        byrow = {}
        for k in ks: byrow.setdefault(place(k, layout)[0], []).append(place(k, layout)[1])
        for r, cs in byrow.items():
            x0 = kb[0] + min(cs) * cw + cw * 0.12; x1 = kb[0] + (max(cs) + 1) * cw - cw * 0.12
            y0 = kb[1] + r * rh + legH * 0.22; y1 = y0 + legH * 0.40
            d.line([(x0, y1), (x0, y0), (x1, y0), (x1, y1)], fill=rgb(C["f"]), width=1)
            f = font(legH * 0.5 * 0.8); tw = d.textlength(b["label"], font=f)
            cx = (x0 + x1) / 2
            d.rectangle((cx - tw / 2 - 3, y0 - legH * 0.2, cx + tw / 2 + 3, y0 + legH * 0.2), fill=rgb(C["body"]))
            text_center(d, (cx - tw / 2 - 3, y0 - legH * 0.25, cx + tw / 2 + 3, y0 + legH * 0.2), b["label"], legH * 0.5 * 0.8, rgb(C["f"]))
    img.convert("RGB").save(out)
    print("wrote", out)

def photo_face(mid):
    src = open(os.path.join(APP, "Sources/Models/PhotoFaceGeometry.swift"), encoding="utf-8").read()
    blk = re.search(r"static let hp%dc = PhotoFace\((.*?)\]\)" % mid, src, re.S).group(1)
    num = r"([\d.]+)"
    rect = lambda t: tuple(float(v) for v in re.search(r"CGRect\(x: %s, y: %s, width: %s, height: %s\)" % (num, num, num, num), t).groups())
    lcd = rect(re.search(r"lcd: (CGRect\([^)]*\))", blk).group(1))
    keys = {int(k): rect(r) for k, r in re.findall(r"(\d+): (CGRect\([^)]*\))", blk)}
    name = re.search(r'emptyLCDImageName: "([^"]+)"', blk).group(1)
    return dict(lcd=lcd, keys=keys, image=os.path.join(APP, "Resources/Faces", name + ".png"))

def render_photo(lcd, mid, W, H, out, pressed=(), turbo=False):
    m = model(mid); face = photo_face(mid)
    src = Image.open(face["image"]).convert("RGBA")
    aspect = src.width / src.height
    sc = min(W / aspect, H); fw, fh = int(round(sc * aspect)), int(round(sc))
    ox, oy = (W - fw) // 2, (H - fh) // 2
    photo = src.resize((fw, fh), Image.LANCZOS)
    canvas = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    canvas.alpha_composite(photo)
    R = lambda r: (r[0] * fw, r[1] * fh, (r[0] + r[2]) * fw, (r[1] + r[3]) * fh)
    for code in sorted(set(25 if c == 35 else c for c in pressed)):
        if code not in face["keys"]: continue
        x0, y0, x1, y1 = R(face["keys"][code]); h = y1 - y0
        dy = max(1, int(round(h * 0.045))); rad = min(x1 - x0, h) * 0.08
        d = ImageDraw.Draw(canvas, "RGBA")
        d.rounded_rectangle((x0, y0, x1, y1), radius=rad, fill=(0, 0, 0, 140))
        # the cap shifted down by dy and darkened, clipped to the moved cap
        mask = Image.new("L", (fw, fh), 0)
        ImageDraw.Draw(mask).rounded_rectangle((x0, y0 + dy, x1, y1), radius=rad, fill=255)
        shifted = Image.new("RGBA", (fw, fh), (0, 0, 0, 0)); shifted.alpha_composite(photo, (0, dy))
        dark = Image.eval(shifted.convert("RGB"), lambda v: int(v * 0.80)).convert("RGBA")
        canvas.paste(dark, (0, 0), mask)
    # flatten on the window background (RGB, so the translucent segments blend)
    img = Image.new("RGBA", (W, H), rgb(0x1C1714))
    img.alpha_composite(canvas, (ox, oy))
    img = img.convert("RGB")
    lx0, ly0, lx1, ly1 = R(face["lcd"])
    lx0, lx1, ly0, ly1 = lx0 + ox, lx1 + ox, ly0 + oy, ly1 + oy
    draw_lcd(img, (lx0, ly0, lx1, ly1), lcd, m, over_photo=True)
    if turbo:
        d = ImageDraw.Draw(img, "RGBA")
        f3 = font(max(7, fh * 0.022)); tw = d.textlength("TURBO", font=f3)
        ty = ly1 + fh * 0.012
        d.rounded_rectangle((lx0, ty, lx0 + tw + 8, ty + fh * 0.03), radius=6, outline=rgb(C["f"]))
        d.text((lx0 + 4, ty), "TURBO", font=f3, fill=rgb(C["f"]))
    img.save(out)
    print("wrote", out, f"{W}x{H}")

if __name__ == "__main__":
    lcd = json.load(open(sys.argv[1]))
    pressed = [int(x) for x in sys.argv[7].split(",")] if len(sys.argv) > 7 and sys.argv[7] else []
    if sys.argv[3] == "photo":
        render_photo(lcd, int(sys.argv[2]), int(sys.argv[4]), int(sys.argv[5]), sys.argv[6], pressed, turbo=len(sys.argv) > 8)
    else:
        render(lcd, int(sys.argv[2]), sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), sys.argv[6], pressed, turbo=len(sys.argv) > 8)
