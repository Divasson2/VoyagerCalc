#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 José González Divassón
# Run every comparison against the Python simulator. Needs the firmware files (not included)
# and /workspace/voyager-sim-public. Takes about 10-15 minutes, mostly in the Python side.
set -e
HERE=$(cd "$(dirname "$0")" && pwd); cd "$HERE/.."
B7=${B7:-/workspace/Firmware/Voyager16-ext-path-c-trim4-show-B7B7.bin}
B5=${B5:-/workspace/Firmware/Voyager16-ext-path-c-B5B5.bin}
M=${M:-/workspace/voyager-sim-public/samples/miller-rabin-ext-ready.16c}
M5=${M5:-/workspace/blog-prime/downloads/miller-rabin-B5B5-ready.16c}
OUT=${OUT:-/tmp/vc}; export OUT; mkdir -p "$OUT"; rm -f "$OUT"/acc-*.16c
make -s
echo "== acceptance: 2147483647 GSB A"
for P in "$B7:$M:b7" "$B5:$M5:b5"; do
  FW=${P%%:*}; R=${P#*:}; MEM=${R%%:*}; T=${R#*:}
  ./build/vcore -f "$FW" --load "$MEM" --fmem --keys "2147483647 GSB A" --show --save "$OUT/acc-c-$T.16c" | grep -E "f MEM|display"
  (cd /workspace/voyager-sim-public && python3 voyagersim.py -f "$FW" --load "$MEM" --fmem --keys "2147483647 GSB A" --show --save "$OUT/acc-py-$T.16c" | grep -E "f MEM|display")
  cmp "$OUT/acc-c-$T.16c" "$OUT/acc-py-$T.16c" && echo "$T: 2 KB memory byte-identical"
done
echo "== program runner: fixed and random sequences"
python3 tests/gen_random.py 300 25 1 > "$OUT/rand1.txt"
python3 tests/gen_random.py 100 25 2 > "$OUT/rand2.txt"
python3 tests/gen_random.py 100 25 3 > "$OUT/rand3.txt"
tests/compare.sh "$B7" tests/fixed.txt
tests/compare.sh "$B7" tests/fixed.txt "$M"
tests/compare.sh "$B7" "$OUT/rand1.txt"
tests/compare.sh "$B7" "$OUT/rand2.txt" "$M"
tests/compare.sh "$B5" "$OUT/rand3.txt" "$M5"
echo "== whole calculator: fixed and random sequences"
printf '1 ENTER 1 +\nf 0\nDEC 7 ENTER 3 / 2 * HEX 5 CHS g x<>y\n' > "$OUT/wfixed.txt"
python3 tests/gen_random.py 60 15 11 > "$OUT/wrand1.txt"
python3 tests/gen_random.py 40 15 12 > "$OUT/wrand2.txt"
tests/compare_whole.sh "$B7" "$OUT/wfixed.txt"
tests/compare_whole.sh "$B7" "$OUT/wrand1.txt"
tests/compare_whole.sh "$B5" "$OUT/wrand2.txt" "$M5"
echo "== LCD-drawn display vs Nut registers"
./build/test_lcd /workspace/Firmware/Voyager16-ext-path-c-trim4-show-B7B7.bin 60
echo "== HP-12C CE multi: model switch"
[ -f /workspace/HP12c-multi.bin ] && ./build/test_multi /workspace/HP12c-multi.bin || true
echo "== inspection API (registers, modes, listings, pointer, read-only)"
./build/test_inspect
echo "== registers: C core vs the Python simulator's view"
tests/compare_inspect.sh "$B7" "$M" "2147483647 GSB A"
tests/compare_inspect.sh "$B5" "$M5" "2147483647 GSB A"
tests/compare_inspect.sh "$B7" "" "HEX 4 0 f STO F E D C B A 9 8 7 6 5 4 3 2 1 0 ENTER 1 2 3 + 7 STO SST 5 CHS STO 3 1 0 f STO 2 6 7 STO SST 7 7 7 7 STO R/S 9 STO 0"
tests/compare_inspect.sh "$B7" "" "DEC 7 f STO 1 2 3 STO 5 f 1 9 9 CHS STO 6 f RCL 4 2 ENTER 3 / STO 1"
echo "ALL DONE"
