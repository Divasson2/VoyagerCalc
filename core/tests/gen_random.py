#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 José González Divassón
"""Make random HP-16C key sequences (one per line) for the comparison tests.
usage: gen_random.py COUNT LENGTH SEED > seqs.txt"""
import random, sys
n, length, seed = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
rnd = random.Random(seed)
digits = list("0123456789") + list("ABCDEF")
common = ["ENTER", "+", "-", "*", "/", "CHS", "BSP", "x<>y", "RDN", "STO", "RCL", "f", "g", "HEX", "DEC", "OCT", "BIN", "."]
rare = ["GSB", "GTO", "R/S", "SST", "ON", "ENT2"]
for _ in range(n):
    seq = []
    for _ in range(length):
        x = rnd.random()
        if x < 0.45: seq.append(rnd.choice(digits))
        elif x < 0.95: seq.append(rnd.choice(common))
        else: seq.append(rnd.choice(rare))
    print(" ".join(seq))
