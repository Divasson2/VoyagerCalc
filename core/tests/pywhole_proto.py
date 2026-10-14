#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 José González Divassón
"""Reference for `vcore --whole --protocol SEQS.txt`: whole-calculator model, fresh calculator per line
(turn on, BSP), then each key pressed (100 ms) and released (250 ms gap); ON as hold 150 / gap 1500.
usage: pywhole_proto.py FIRMWARE.bin SEQS.txt [--load MEM.16c]"""
import hashlib, sys
sys.path.insert(0, "/workspace/voyager-sim-public")
from voyager.wholecalc import WholeCalc, cells
fw, seqs = sys.argv[1], sys.argv[2]
mem = open(sys.argv[4], "rb").read() if len(sys.argv) > 4 else None
for seq, line in enumerate(l for l in open(seqs) if l.strip() and not l.startswith("#")):
    c = WholeCalc(fw); c.turn_on(); c.press("BSP")
    if mem: c.uc.mem_write(0x20000018, mem)
    for k, tok in enumerate(line.split()):
        if tok == "ON": c.press("ON", hold=150, gap=1500)
        else: c.press(tok)
        h = hashlib.sha256(bytes(c.uc.mem_read(0x20000018, 2048))).hexdigest()[:16]
        fr = c.last_frame() or ""
        print(f"S{seq} K{k} {tok} |{c.lcd16()}| {h} frames={len(c.painted)} last=|{fr}| ms={c.ms()} sleeps={c.sleeps}", flush=True)
