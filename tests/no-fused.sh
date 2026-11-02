#!/usr/bin/env bash
set -euo pipefail

tool=$(cd "$(dirname "$0")/.." && pwd)/bin/no-fused
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
export GOCACHE="$work/cache" GOFLAGS=-mod=mod
printf 'module fused\n\ngo 1.21\n' > go.mod
stderr="$work/stderr"
fail() {
    echo "FAIL: $1" >&2
    exit 1
}
write_source() {
    printf 'package fused\n\nfunc F(x, y, z float64) float64 {\n\t%s\n}\n' "$1" > fused.go
}

write_source 'return x*y + z'
if "$tool" 2> "$stderr"; then
    fail "a product added to a term passed"
fi
grep -qE 'FMADDD' "$stderr" || fail "the fused add was not named: $(cat "$stderr")"

write_source 'return z - x*y'
if "$tool" 2> "$stderr"; then
    fail "a product subtracted from a term passed"
fi
grep -qE 'FN?MSUBD' "$stderr" || fail "the fused subtract was not named: $(cat "$stderr")"

write_source 'return float64(x*y) + z'
"$tool" 2> "$stderr" || fail "a rounded product failed: $(cat "$stderr")"

write_source 'return nope'
if "$tool" 2> "$stderr"; then
    fail "code that does not build passed"
fi
grep -qF 'the arm64 build failed' "$stderr" || fail "the build failure was not reported: $(cat "$stderr")"
grep -qF 'nope' "$stderr" || fail "the compiler's error was lost: $(cat "$stderr")"

echo "no-fused: ok"
