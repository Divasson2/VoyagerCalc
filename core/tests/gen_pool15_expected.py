#!/usr/bin/env python3
"""Expected HP-15C pool fields for every dump in docs/pool15c/dumps, from the reference decoder
docs/pool15c/pool15.py (test_pool15.c compares the C port against this file).
The 15.2 cold-start gap below R2 is reported as 'gap', not as workspace (pool15.py calls it scratch)."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, "../../docs/pool15c")
sys.path.insert(0, REF)
import pool15
out = []
for f in sorted(os.listdir(os.path.join(REF, "dumps"))):
    if not f.endswith(".bin"): continue
    d = bytearray(open(os.path.join(REF, "dumps", f), "rb").read())
    v = 152 if f.startswith("v152") else 150
    r = pool15.decode(d, v)
    below = r["data"] - r["base"] - (5 if r["complex"] else 0)
    scratch = below if below in (5, 23, 28) else 0
    gap = below if below > 0 and not scratch else 0
    dims = " ".join("%dx%d" % rc for rc in r["dims"])
    imag = " ".join("%014x" % pool15.rd(d, r["imag_at"] + i) for i in range(5)) if r["complex"] else "-"
    # first and last element of every dimensioned matrix
    mx = []
    for i, (rr, cc) in enumerate(r["dims"]):
        if rr * cc:
            mx.append("%s:%014x:%014x" % ("ABCDE"[i], pool15.rd(d, r["starts"][i]), pool15.rd(d, r["starts"][i] + rr * cc - 1)))
    flags = sum(1 << i for i, x in enumerate(r["flags"]) if x)
    out.append("|".join([f, str(v), "%02x" % r["data"], " ".join("%02x" % s for s in r["starts"]), "%x" % r["pool"], dims,
                         "ABCDE"[0] if r["result"] == "?" else r["result"], str(int(r["complex"])), str(scratch), str(gap),
                         str(r["dim_i"]), str(r["matrices"]), str(r["prog_regs"]), str(r["prog_bytes"]), str(r["free"]), r["gmem"],
                         "%x" % flags, imag, " ".join(mx) or "-"]))
open(os.path.join(HERE, "pool15_expected.txt"), "w").write("\n".join(out) + "\n")
print(len(out), "dumps")
