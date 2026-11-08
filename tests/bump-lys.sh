#!/usr/bin/env bash
set -euo pipefail

tool=$(cd "$(dirname "$0")/.." && pwd)/bin/bump-lys
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/repo"
for stub in go nix just; do
    cat > "$work/bin/$stub" <<STUB
#!/usr/bin/env bash
echo "$stub \$*" >> "$work/calls"
if [ "$stub \$1" = "just --summary" ]; then echo "check vendor-hash"; fi
if [ "$stub \$1" = "go get" ]; then echo changed >> go.sum; fi
STUB
    chmod +x "$work/bin/$stub"
done
cd "$work/repo"
git init -q
cat > go.mod <<'MOD'
module github.com/stubbedev/lys-a

require (
	github.com/stubbedev/lys-b v0.1.0
	github.com/stubbedev/memory-go v0.5.0
)

tool github.com/stubbedev/lys-c/cmd/tool
tool github.com/stubbedev/lys-a/cmd/own
MOD
cat > flake.nix <<'NIX'
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    lys-ci.url = "github:stubbedev/lys-ci";
    lys-d = {
      url = "github:stubbedev/lys-d";
    };
  };
}
NIX
touch go.sum
git add -A
git -c user.name=t -c user.email=t@t commit -qm base
PATH="$work/bin:$PATH" "$tool"
want="go get github.com/stubbedev/lys-b@HEAD github.com/stubbedev/lys-c@HEAD
go mod tidy
nix flake update lys-ci lys-d
just --summary
just vendor-hash"
got=$(cat "$work/calls")
[ "$got" = "$want" ] || { echo "calls were:"; echo "$got"; exit 1; }
