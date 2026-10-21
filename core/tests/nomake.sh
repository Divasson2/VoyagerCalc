#!/bin/sh
# Build the core and the C tests without make (gcc or clang). Usage: tests/nomake.sh [builddir]  (default /tmp/vcbuild)
set -e
HERE=$(cd "$(dirname "$0")" && pwd); cd "$HERE/.."
B=${1:-/tmp/vcbuild}; CC=${CC:-$(command -v clang || command -v gcc)}
mkdir -p "$B"
F="-std=c11 -O2 -Wall -Wextra -Wpedantic -Iinclude -D_POSIX_C_SOURCE=200809L"
for s in cpu machine sha256 inspect; do $CC $F -c src/$s.c -o "$B/$s.o"; done
ar rcs "$B/libvoyagercore.a" "$B"/cpu.o "$B"/machine.o "$B"/sha256.o "$B"/inspect.o
for t in test_multi test_firmware test_lcd; do $CC $F tests/$t.c "$B/libvoyagercore.a" -o "$B/$t"; done
for t in test_inspect test_pool15 test_mem16 test_matrix15; do [ -f tests/$t.c ] && $CC $F tests/$t.c "$B/libvoyagercore.a" -lm -o "$B/$t"; done
$CC $F tools/vcore.c "$B/libvoyagercore.a" -o "$B/vcore"
echo "built in $B"
