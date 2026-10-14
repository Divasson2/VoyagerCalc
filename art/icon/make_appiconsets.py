#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 José González Divassón
# AppIcon-square-1024.png (Jose's approved square logo, made by make_icon_square.py) -> the asset
# catalogs of the Xcode project (the earlier source, AppIcon-1024.png, is kept; make_appiconsets_old.py):
#   app/Resources/macOS/Assets.xcassets/AppIcon.appiconset  (16..512 @1x/@2x, used as is: square,
#        its own slightly rounded corners and transparency, no squircle mask, no padding)
#   app/Resources/iOS/Assets.xcassets/AppIcon.appiconset    (one 1024 opaque universal image: iOS
#        applies its own mask, so no transparency; the corners are filled with the frame colour)
import json, os
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__)); APP = os.path.join(HERE, "..", "..", "app", "Resources")
SRC = "AppIcon-square-1024.png"
src = Image.open(os.path.join(HERE, SRC)).convert("RGBA")
BLACK = src.getpixel((src.width // 2, 12))[:3]     # the dark frame colour
def catalog(plat):
    d = os.path.join(APP, plat, "Assets.xcassets"); s = os.path.join(d, "AppIcon.appiconset")
    os.makedirs(s, exist_ok=True)
    json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(d, "Contents.json"), "w"), indent=2)
    return s
mac = catalog("macOS"); imgs = []
for pt in (16, 32, 128, 256, 512):
    for sc in (1, 2):
        px = pt * sc; name = f"icon_{pt}x{pt}{'@2x' if sc == 2 else ''}.png"
        src.resize((px, px), Image.LANCZOS).save(os.path.join(mac, name))
        imgs.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{sc}x", "filename": name})
json.dump({"images": imgs, "info": {"author": "xcode", "version": 1}}, open(os.path.join(mac, "Contents.json"), "w"), indent=2)
ios = catalog("iOS")
flat = Image.new("RGB", src.size, BLACK); flat.paste(src, mask=src.split()[3])
assert src.size == (1024, 1024)
flat.save(os.path.join(ios, "AppIcon-1024.png"))
json.dump({"images": [{"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "AppIcon-1024.png"}],
           "info": {"author": "xcode", "version": 1}}, open(os.path.join(ios, "Contents.json"), "w"), indent=2)
print("wrote", mac, "and", ios)
