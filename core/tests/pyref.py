#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 José González Divassón
"""Reference side of the comparison tests: run the same key-sequence protocol as
`vcore --protocol` with our Python simulator (voyager-sim-public, program runner)
and print the same per-key log. Test tool only; it imports the Python simulator,
it does not copy any of its code into the C core.

usage: pyref.py FIRMWARE.bin SEQS.txt [--load MEM.16c] [--max-steps N]
"""
import hashlib, sys, argparse
sys.path.insert(0, "/workspace/voyager-sim-public")
from voyager.runner16c import Calc16C
from voyager.firmware import Firmware

ap = argparse.ArgumentParser()
ap.add_argument("firmware"); ap.add_argument("seqs")
ap.add_argument("--load"); ap.add_argument("--max-steps", type=int, default=0)
a = ap.parse_args()
fw = Firmware(a.firmware)
mem = open(a.load, "rb").read() if a.load else None
seq = 0
for line in open(a.seqs):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    c = Calc16C(fw)
    if mem:
        c.load(mem)
    for k, tok in enumerate(line.split()):
        n = len(c.held)
        try:
            r = c.press(tok, max_steps=a.max_steps or None)
            if r == "done" and len(c.held) > n:
                r = "held"
        except RuntimeError:
            r = "hold-error"
        h = hashlib.sha256(c.dump()).hexdigest()[:16]
        print(f"S{seq} K{k} {tok} {r} |{c.lcd()}| {h}", flush=True)
        if r in ("hold-error", "limit"):
            break
    seq += 1
