#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 José González Divassón
# compare.sh FIRMWARE SEQS [MEM.16c] : run the protocol in the C core and the Python simulator, diff.
FW=$1; SEQ=$2; MEM=$3; MS=${MAXSTEPS:-300000}
HERE=$(dirname "$0"); OUT=${OUT:-/tmp/vc}; mkdir -p "$OUT"
TAG=$(basename "$SEQ" .txt)-$(basename "$FW" .bin | tail -c 5)${MEM:+-mem}
L=""; [ -n "$MEM" ] && L="--load $MEM"
"$HERE/../build/vcore" -f "$FW" --protocol "$SEQ" $L --max-steps $MS | grep "^S" > "$OUT/$TAG.c.log"
python3 "$HERE/pyref.py" "$FW" "$SEQ" $L --max-steps $MS > "$OUT/$TAG.py.log"
N=$(wc -l < "$OUT/$TAG.py.log"); S=$(cut -d' ' -f1 "$OUT/$TAG.py.log" | sort -u | wc -l)
if cmp -s "$OUT/$TAG.c.log" "$OUT/$TAG.py.log"; then echo "$TAG: IDENTICAL ($S sequences, $N key steps, display + 2 KB memory hash after every key)";
else echo "$TAG: DIFFERENT"; diff "$OUT/$TAG.c.log" "$OUT/$TAG.py.log" | head -10; fi
