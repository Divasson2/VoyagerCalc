#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 José González Divassón
# Registers after a run: C core (vcore --inspect, 2 KB-dump layout) vs the Python simulator's view
# (tests/pyinspect.py, firmware-style Nut RAM mapping). usage: compare_inspect.sh FW.bin MEM.16c "KEYS"
set -e
HERE=$(cd "$(dirname "$0")" && pwd); cd "$HERE/.."
FW=$1; MEM=$2; KEYS=$3; OUT=${OUT:-/tmp/vc}; mkdir -p "$OUT"
./build/vcore -f "$FW" ${MEM:+--load "$MEM"} --keys "$KEYS" --inspect | awk '/^inspect:/ {print "lines", $21, "regs", $23, "ws", $9; next} NR>2 && !/^loaded/ {n=$1; if ($1=="LAST") {n="LAST X"; print n, $3} else print n, $2}' > "$OUT/insp-c.txt"
python3 tests/pyinspect.py "$FW" ${MEM:+--load "$MEM"} --keys "$KEYS" > "$OUT/insp-py.txt"
sort "$OUT/insp-c.txt" > "$OUT/insp-c.s"; sort "$OUT/insp-py.txt" > "$OUT/insp-py.s"
if cmp -s "$OUT/insp-c.s" "$OUT/insp-py.s"; then echo "inspect: $(wc -l < "$OUT/insp-c.txt") values identical ($KEYS)"; else diff "$OUT/insp-c.s" "$OUT/insp-py.s" | head -20; echo "inspect: DIFFERENT"; exit 1; fi
