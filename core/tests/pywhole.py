#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 José González Divassón
"""Reference for the whole-calculator engine: same flow as `vcore --whole --keys ... --show --count --bench`.
usage: pywhole.py FIRMWARE.bin "KEYS" [--load MEM.16c]"""
import hashlib, sys
sys.path.insert(0, "/workspace/voyager-sim-public")
from voyager.wholecalc import WholeCalc
fw, script = sys.argv[1], sys.argv[2]
c = WholeCalc(fw); c.turn_on(); c.press("BSP")
if len(sys.argv) > 4 and sys.argv[3] == "--load":
    c.uc.mem_write(0x20000018, open(sys.argv[4], "rb").read())
for tok in script.split():
    if tok.lower().startswith("wait:"): c.wait(int(tok[5:]))
    elif "+" in tok and tok != "+": c.chord(tok.split("+"))
    elif tok.isdigit() and len(tok) > 1:
        for d in tok: c.press(d)
    elif tok == "ON": c.press("ON", hold=150, gap=1500)
    else: c.press(tok)
mem = bytes(c.uc.mem_read(0x20000018, 2048))
print(f"display: {c.lcd16()}   (last painted frame: {c.last_frame()})")
print(f"memory hash {hashlib.sha256(mem).hexdigest()[:16]}  simulated {c.ms()} ms, {c.sleeps} sleeps, frames {len(c.painted)}")
