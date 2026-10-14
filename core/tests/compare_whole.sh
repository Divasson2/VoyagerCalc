#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 José González Divassón
# compare_whole.sh FIRMWARE SEQS [MEM.16c] : whole-calculator engine, C core vs Python model.
FW=$1; SEQ=$2; MEM=$3; HERE=$(dirname "$0"); OUT=${OUT:-/tmp/vc}; mkdir -p "$OUT"
TAG=whole-$(basename "$SEQ" .txt)-$(basename "$FW" .bin | tail -c 5)${MEM:+-mem}
L=""; [ -n "$MEM" ] && L="--load $MEM"
"$HERE/../build/vcore" -f "$FW" --whole --protocol "$SEQ" $L | grep "^S" > "$OUT/$TAG.c.log"
python3 "$HERE/pywhole_proto.py" "$FW" "$SEQ" $L > "$OUT/$TAG.py.log"
N=$(wc -l < "$OUT/$TAG.py.log"); S=$(cut -d' ' -f1 "$OUT/$TAG.py.log" | sort -u | wc -l)
if cmp -s "$OUT/$TAG.c.log" "$OUT/$TAG.py.log"; then echo "$TAG: IDENTICAL ($S sequences, $N key steps: display, memory hash, painted frames, simulated ms, sleeps)";
else echo "$TAG: DIFFERENT"; diff "$OUT/$TAG.c.log" "$OUT/$TAG.py.log" | head -10; fi
