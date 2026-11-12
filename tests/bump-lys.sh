#!/usr/bin/env bash
set -euo pipefail

tool=$(cd "$(dirname "$0")/.." && pwd)/bin/bump-lys
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() {
    echo "FAIL: $1" >&2
    exit 1
}

real_nix=$(command -v nix)
mkdir "$work/bin" "$work/remotes"
for stub in go just; do
    cat > "$work/bin/$stub" << STUB
#!/usr/bin/env bash
echo "$stub \$*" >> "\$CALLS"
if [ "$stub \$1" = "just --summary" ]; then echo "check vendor-hash"; fi
if [ "$stub \$1" = "go get" ]; then echo changed >> go.sum; fi
STUB
    chmod +x "$work/bin/$stub"
done
cat > "$work/bin/nix" << 'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = eval ]; then
    exec "$REAL_NIX" "$@"
fi
echo "nix $*" >> "$CALLS"
if [ "$1" = develop ]; then
    [ "$2 $3" = "--no-update-lock-file --command" ]
    shift 3
    exec "$@"
fi
[ "$1 $2" = "flake update" ]
shift 2
while [ "$1" != --override-input ]; do
    shift
done
nodes='"root":{"inputs":{'
lock=''
separator=''
while [ "$#" -gt 0 ]; do
    [ "$1" = --override-input ]
    rev=${3##*/}
    if [ "$2" = "${STALE_INPUT-}" ]; then
        rev=0000000000000000000000000000000000000000
    fi
    nodes+="$separator\"$2\":\"$2\""
    lock+=",\"$2\":{\"locked\":{\"rev\":\"$rev\",\"type\":\"github\"}}"
    separator=,
    shift 3
done
printf '{"nodes":{%s}}%s},"root":"root","version":7}\n' "$nodes" "$lock" > flake.lock
STUB
chmod +x "$work/bin/nix"

remote() {
    git init -q -b main "$work/remotes/$1"
    git -C "$work/remotes/$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1 first"
    git -C "$work/remotes/$1" branch dev
    git -C "$work/remotes/$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1 second"
}
remote lys-ci
remote lys-d
head_ci=$(git -C "$work/remotes/lys-ci" rev-parse main)
dev_d=$(git -C "$work/remotes/lys-d" rev-parse dev)
[ "$dev_d" != "$(git -C "$work/remotes/lys-d" rev-parse main)" ] || fail "lys-d's dev and main must differ"
printf '[url "file://%s/remotes/"]\n\tinsteadOf = https://github.com/stubbedev/\n' "$work" > "$work/gitconfig"

checkout() {
    mkdir "$work/$1"
    cd "$work/$1"
    git init -q
    cat > go.mod << 'MOD'
module github.com/stubbedev/lys-a

require (
	github.com/stubbedev/lys-b v0.1.0
	github.com/stubbedev/memory-go v0.5.0
)

tool github.com/stubbedev/lys-c/cmd/tool
tool github.com/stubbedev/lys-a/cmd/own
MOD
    cat > flake.nix << 'NIX'
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    lys-ci.url = "github:stubbedev/lys-ci";
    lys-d = {
      url = "github:stubbedev/lys-d/dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lys-e.follows = "lys-d";
  };
  outputs = _: {};
}
NIX
    touch go.sum
    git add -A
    git -c user.name=t -c user.email=t@t commit -qm base
}

bump() {
    PATH="$work/bin:$PATH" CALLS="$work/$1.calls" REAL_NIX="$real_nix" STALE_INPUT="$2" \
        GIT_CONFIG_GLOBAL="$work/gitconfig" GIT_CONFIG_NOSYSTEM=1 "$tool" 2> "$work/$1.err"
}

checkout current
bump current '' || fail "bump-lys failed: $(cat "$work/current.err")"
go_env='env GOPROXY=direct GOPRIVATE=github.com/stubbedev/*'
want="nix flake update lys-ci lys-d --override-input lys-ci github:stubbedev/lys-ci/$head_ci --override-input lys-d github:stubbedev/lys-d/$dev_d
nix develop --no-update-lock-file --command $go_env go get github.com/stubbedev/lys-b@HEAD github.com/stubbedev/lys-c@HEAD
go get github.com/stubbedev/lys-b@HEAD github.com/stubbedev/lys-c@HEAD
nix develop --no-update-lock-file --command $go_env go mod tidy
go mod tidy
just --summary
just vendor-hash"
got=$(cat "$work/current.calls")
[ "$got" = "$want" ] || fail "calls were:
$got"

checkout stale
if bump stale lys-d; then
    fail "bump-lys succeeded although lys-d was locked at a stale revision"
fi
grep -qxF "bump-lys: flake input lys-d is locked at 0000000000000000000000000000000000000000, not at its head $dev_d" "$work/stale.err" ||
    fail "the stale lock's error does not name lys-d: $(cat "$work/stale.err")"
if grep -q '^go ' "$work/stale.calls"; then
    fail "bump-lys moved the Go modules after a stale lock"
fi
