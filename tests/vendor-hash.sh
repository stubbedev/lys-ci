#!/usr/bin/env bash
set -euo pipefail

tool=$(cd "$(dirname "$0")/.." && pwd)/vendor-hash
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
cat > "$work/bin/nix" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$NIX_ARGS"
printf '%s\n' "$NIX_OUTPUT"
exit "$NIX_STATUS"
FAKE
chmod +x "$work/bin/nix"
export PATH="$work/bin:$PATH"
export NIX_ARGS="$work/args"

current=sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
fresh=sha256-CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=
file="$work/package.nix"
stderr="$work/stderr"
reset() {
    printf '  # vendorHash pins go.sum\n  vendorHash = "%s";\n  pname = "x";\n' "$current" > "$file"
}
fail() {
    echo "FAIL: $1" >&2
    exit 1
}
holds() {
    grep -qF "vendorHash = \"$1\";" "$file" || fail "$2: $(cat "$file")"
}
refuses() {
    local name=$1
    shift
    if "$tool" "$@" 2> "$stderr"; then
        fail "$name: succeeded"
    fi
}
says() {
    grep -qF -- "$1" "$stderr" || fail "stderr lacks '$1': $(cat "$stderr")"
}

reset
NIX_OUTPUT="error: hash mismatch
         specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
            got:    $current" NIX_STATUS=1 "$tool" "$file" .#x.goModules > /dev/null
cp "$file" "$work/after"
reset
cmp -s "$file" "$work/after" || fail "a current hash changed the file"
grep -qx 'build --no-link .#x.goModules' "$NIX_ARGS" || fail "built $(cat "$NIX_ARGS")"

reset
NIX_OUTPUT="   got:    $fresh" NIX_STATUS=1 "$tool" "$file" .#x.goModules > /dev/null
holds "$fresh" "a stale hash was not corrected"
grep -qF 'pname = "x";' "$file" || fail "the rest of the file was lost"

reset
NIX_OUTPUT="error: go.sum is broken" NIX_STATUS=1 refuses "another build failure" "$file" .#x.goModules
says "error: go.sum is broken"
says ".#x.goModules failed without reporting its hash"
holds "$current" "another build failure left the file changed"

reset
NIX_OUTPUT="   got:    sha256-short=" NIX_STATUS=1 refuses "a malformed hash" "$file" .#x.goModules
says "failed without reporting its hash"
holds "$current" "a malformed hash left the file changed"

reset
NIX_OUTPUT="" NIX_STATUS=0 refuses "a build that ignores the hash" "$file" .#x.goModules
says "built with the fake hash"
holds "$current" "a build that ignores the hash left the file changed"

printf 'pname = "x";\n' > "$file"
NIX_OUTPUT="" NIX_STATUS=1 refuses "no vendorHash" "$file" .#x.goModules
says "found 0"

reset
printf '  vendorHash = "%s";\n' "$current" >> "$file"
NIX_OUTPUT="" NIX_STATUS=1 refuses "two vendorHashes" "$file" .#x.goModules
says "found 2"

refuses "no arguments"
says "usage: vendor-hash"

echo "vendor-hash: all cases pass"
