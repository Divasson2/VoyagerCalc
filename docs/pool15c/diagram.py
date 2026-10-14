# diagram.py - pool-map.png: the HP-15C pool for 15.0 and 15.2, drawn from a live emulator state (Pillow only)
from PIL import Image, ImageDraw, ImageFont
from v15 import Calc
import pool15, glob
def font(sz, bold=False):
    for p in glob.glob("/usr/share/fonts/**/DejaVuSans%s.ttf" % ("-Bold" if bold else ""), recursive=True): return ImageFont.truetype(p, sz)
    return ImageFont.load_default()
F, FB, FS = font(14), font(16, True), font(12)
COL = {"scratch": "#c9b3e6", "complex": "#f2a6a6", "storage": "#9cc3e6", "A": "#ffd27f", "B": "#ffbf47", "C": "#f5a623",
       "D": "#e8912a", "E": "#d87b1f", "free": "#eeeeee", "program": "#8fd18f"}
W, H, TOP, BOT = 1500, 1000, 110, 900
img = Image.new("RGB", (W, H), "white"); d = ImageDraw.Draw(img)
d.text((20, 15), "HP-15C CE memory pool, bottom (low Nut address) to top. Example: short program, A 2x3, B 3x2, C 3x3, complex on", font=FB, fill="black")
d.text((20, 40), "Map register 0x118 (bytes 0x118..0x11E = pool/free, E, D, C, B, A, data=R2 start);  dims 0x138 (A,B,C) and 0x140 (D,E);  program end 0x120;  flag 8 = 0xC4 bit 0", font=FS, fill="black")
for col, v in enumerate((150, 152)):
    c = Calc(v)
    c.keys("g RS f RDN f SST SQRT 1 2 3 4 5 6 7 8 9 1 2 3 4 5 6 7 8 9 1 2 + g GSB g RS")
    c.keys("2 ENTER 3 f SIN SQRT 3 ENTER 2 f SIN EX 3 ENTER 3 f SIN 10X g 4 8 1 ENTER 2 f TAN")
    m = c.mem(); r = pool15.decode(m, v); g = c.gmem()
    x0 = 40 + col * 740; bw = 120
    scale = (BOT - TOP) / (0x100 - r["base"])
    y = lambda p: BOT - (p - r["base"]) * scale
    d.text((x0, 70), "%s: pool Nut %02X..FF = %d registers (+ R0, R1).  g MEM %s" % ("15.2" if v == 152 else "15.0", r["base"], 0x100 - r["base"], g), font=FB, fill="black")
    segs = []
    if r["scratch"]: segs.append(("scratch", r["base"], r["scratch"], "SOLVE/∫ workspace"))
    if r["complex"]: segs.append(("complex", r["imag_at"], 5, "imaginary LASTx, T, Z, Y, X"))
    segs.append(("storage", r["data"], r["storage"], "R2..R%d (DIM (i) = %d)" % (r["dim_i"], r["dim_i"])))
    for i, L in enumerate("ABCDE"):
        n = r["dims"][i][0] * r["dims"][i][1]
        if n: segs.append((L, r["starts"][i], n, "matrix %s %dx%d, row-major" % (L, *r["dims"][i])))
    segs.append(("free", r["pool"], r["prog_low"] - r["pool"], "free (uncommitted) %d" % r["free"]))
    segs.append(("program", r["prog_low"], r["prog_regs"], "program %d regs (7 bytes each)" % r["prog_regs"]))
    lasty = None
    for kind, start, n, text in segs:
        y1, y2 = y(start), y(start + n)
        d.rectangle([x0 + 150, y2, x0 + 150 + bw, y1], fill=COL[kind], outline="black")
        ty = (y1 + y2) / 2 - 8
        if lasty is not None and lasty - ty < 18: ty = lasty - 18
        lasty = ty
        d.line([x0 + 150 + bw, (y1 + y2) / 2, x0 + 150 + bw + 18, ty + 8], fill="gray")
        d.text((x0 + 150 + bw + 22, ty), "Nut %02X..%02X  (%d)  %s" % (start, start + n - 1, n, text), font=F, fill="black")
    for t in list(range(r["base"], 0x100, 0x10)) + [0x100]:
        d.line([x0 + 140, y(t), x0 + 150, y(t)], fill="black")
        d.text((x0, y(t) - 8), ("%02X @0x%03X" % (t, pool15.off(t))) if t < 0x100 else "top @0x7F0", font=FS, fill="black")
d.text((20, 930), "Outside the pool: X = CPU M (0x20); Y Z T = 0x70 0x78 0x80; R0 0xF0, R1 0xF8, I 0x100, LASTx 0x108. Dump offset of Nut register p = 0x70 + 8*(p - 0x10).", font=FS, fill="black")
d.text((20, 950), "15.2 right after a cold start keeps R2.. at Nut A0 (Nut 40..9F free below it) until the first reallocation, which packs everything down to Nut 40.", font=FS, fill="black")
img.save("pool-map.png"); print("saved")
