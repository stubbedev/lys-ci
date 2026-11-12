#!/usr/bin/env bash
set -euo pipefail

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() {
    echo "FAIL: $1" >&2
    exit 1
}

mkdir "$work/tool" "$work/bin" "$work/state"
cp "$(cd "$(dirname "$0")/.." && pwd)/bin/train" "$work/tool/train"
tool=$work/tool/train

cat > "$work/tool/bump-lys" << 'STUB'
#!/usr/bin/env bash
set -euo pipefail
name=$(basename "$PWD")
if [ -f "$STATE/bumps-$name" ]; then
    echo "$(git -C "$WORK/$(cat "$STATE/bumps-$name")" rev-parse HEAD)" > pinned
    echo "github.com/stubbedev/$(cat "$STATE/bumps-$name") v0.0.0-$(date +%s)" >> go.mod
fi
echo "$name" >> "$STATE/bump-order"
if [ -f "$STATE/moves-$name" ]; then
    git clone --quiet "$WORK/$name.git" "$STATE/elsewhere"
    git -C "$STATE/elsewhere" commit --quiet --allow-empty -m elsewhere
    git -C "$STATE/elsewhere" push --quiet origin HEAD:main
fi
STUB
cat > "$work/bin/go" << 'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat > "$work/bin/just" << 'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = release-patch ]
tag=v0.0.$(($(git tag -l 'v*' | wc -l) + 1))
git tag -a "$tag" -m "$tag"
git push --quiet origin "$tag"
STUB
cat > "$work/bin/gh" << 'STUB'
#!/usr/bin/env bash
set -euo pipefail
name=$(basename "$PWD")
printf '%s %s\n' "$name" "$*" >> "$STATE/gh.log"
case "$*" in
    "run list --workflow ci.yml"*)
        if [ -f "$STATE/stuck-$name" ] && ! grep -q "^$name workflow run ci.yml --ref main" "$STATE/gh.log"; then
            echo "queued  12"
            exit 0
        fi
        states=$(cat "$STATE/ci-$name" 2> /dev/null || echo "completed success 1")
        calls=$(grep -c "^$name run list --workflow" "$STATE/gh.log")
        sed -n "${calls}p" <<< "$states" | grep . || tail -n 1 <<< "$states"
        ;;
    "run list --commit"*)
        runs='[{"workflowName":"ci","status":"completed","conclusion":"cancelled","createdAt":"2026-01-01T00:00:00Z"},{"workflowName":"ci","status":"completed","conclusion":"success","createdAt":"2026-01-01T00:01:00Z"}'
        polls=$(grep -c "^$name run list --commit" "$STATE/gh.log")
        if [ ! -f "$STATE/late-release-$name" ] || [ "$polls" -gt 3 ]; then
            runs+=',{"workflowName":"release","status":"completed","conclusion":"success","createdAt":"2026-01-01T00:00:30Z"}'
        elif [ "$polls" -gt 1 ]; then
            runs+=',{"workflowName":"release","status":"queued","conclusion":"","createdAt":"2026-01-01T00:00:30Z"}'
        fi
        jq -r "${*: -1}" <<< "$runs]"
        ;;
esac
STUB
chmod +x "$work/tool/"* "$work/bin/"*
export PATH="$work/bin:$PATH" STATE="$work/state" WORK="$work" TRAIN_CI_POLL=1 TRAIN_CI_LIMIT=5 TRAIN_CI_STALL=2
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

repo() {
    local name=$1 requires=$2 input=$3
    git init --quiet --bare --initial-branch=main "$work/$name.git"
    git clone --quiet "$work/$name.git" "$work/$name" 2> /dev/null
    cd "$work/$name"
    git checkout --quiet -b main
    printf 'module github.com/stubbedev/%s\n' "$name" > go.mod
    if [ -n "$requires" ]; then printf 'require github.com/stubbedev/%s v0.0.0\n' "$requires" >> go.mod; fi
    printf '{"nodes":{"root":{"inputs":{"nixpkgs":"nixpkgs"%s}}}}\n' "${input:+,\"$input\":\"$input\"}" > flake.lock
    git add -A
    git commit --quiet -m one
    git push --quiet origin HEAD:main
    git remote set-head origin main
    cd "$work"
}
repo lys-c "" lys-b
repo lys-b lys-a ""
repo lys-a "" ""
echo lys-a > "$STATE/bumps-lys-b"
echo lys-b > "$STATE/bumps-lys-c"

touch "$work/lys-b/dirty"
if out=$("$tool" "$work/lys-a" "$work/lys-b" "$work/lys-c" 2>&1); then fail "a dirty tree went out: $out"; fi
[[ $out == *"lys-b has uncommitted changes"* ]] || fail "the dirty tree was not named: $out"
rm "$work/lys-b/dirty"
[ ! -e "$STATE/bump-order" ] || fail "a refused train bumped something"

printf 'completed failure 7\ncompleted failure 8\n' > "$STATE/ci-lys-c"
if out=$("$tool" "$work/lys-a" "$work/lys-b" "$work/lys-c" 2>&1); then fail "red CI went out: $out"; fi
[[ $out == *"tiers: [lys-a] [lys-b] [lys-c]"* ]] || fail "the tiers: $out"
[ "$(paste -sd' ' "$STATE/bump-order")" = "lys-a lys-b lys-c" ] || fail "bumped out of order: $(cat "$STATE/bump-order")"
[ "$(git -C "$work/lys-c" show origin/main:pinned)" = "$(git -C "$work/lys-b" rev-parse origin/main)" ] || fail "lys-c did not pin lys-b's bumped head"
[[ $(git -C "$work/lys-b" log -1 --format=%s origin/main) == "deps: lys-a v0.0.0-"* ]] || fail "the deps commit message: $(git -C "$work/lys-b" log -1 --format=%s)"
grep -qF "lys-c run rerun 7 --failed" "$STATE/gh.log" || fail "the failed jobs were not rerun"
[[ $out == *"lys-c: NOT released: ci.yml on"* ]] || fail "lys-c was not reported: $out"
git -C "$work/lys-c" ls-remote --exit-code origin refs/tags/v0.0.1 > /dev/null && fail "red lys-c was tagged"
git -C "$work/lys-a" ls-remote --exit-code origin refs/tags/v0.0.1 > /dev/null || fail "lys-a was not tagged"
git -C "$work/lys-b" ls-remote --exit-code origin refs/tags/v0.0.1 > /dev/null || fail "lys-b was not tagged"

rm "$STATE/ci-lys-c" "$STATE/bumps-lys-c" "$STATE/bump-order"
printf 'completed failure 9\ncompleted success 9\n' > "$STATE/ci-lys-b"
git -C "$work/lys-a" commit --quiet --allow-empty -m two
git -C "$work/lys-a" push --quiet origin HEAD:main
: > "$STATE/gh.log"
"$tool" "$work/lys-a" "$work/lys-b" "$work/lys-c" > "$work/out" 2>&1 || fail "a train with one flake: $(cat "$work/out")"
grep -qF "lys-b run rerun 9 --failed" "$STATE/gh.log" || fail "the flake was not rerun"
grep -qF "lys-a: v0.0.2 at" "$work/out" || fail "lys-a's new commit was not released: $(cat "$work/out")"
grep -qF "lys-b: v0.0.2 at" "$work/out" || fail "lys-b's bump was not released: $(cat "$work/out")"
grep -qF "lys-c: v0.0.1 at" "$work/out" || fail "lys-c was not released: $(cat "$work/out")"
grep -qF "ci=success, release=success" "$work/out" || fail "the workflows were not reported: $(cat "$work/out")"

git -C "$work/lys-a" commit --quiet --allow-empty -m three
git -C "$work/lys-a" push --quiet origin HEAD:main
: > "$STATE/gh.log"
touch "$STATE/moves-lys-a"
printf 'completed failure 11\n' > "$STATE/ci-lys-a"
if out=$("$tool" "$work/lys-a" 2>&1); then fail "a moved head went out: $out"; fi
[[ $out == *"origin has moved on since"* ]] || fail "the moved head was not named: $out"
if grep -qF "run rerun" "$STATE/gh.log"; then fail "a stale run was rerun, which cancels the new head's run"; fi

rm -f "$STATE/moves-lys-a" "$STATE/ci-lys-a"
git -C "$work/lys-a" pull --quiet
git -C "$work/lys-a" commit --quiet --allow-empty -m four
git -C "$work/lys-a" push --quiet origin HEAD:main
: > "$STATE/gh.log"
touch "$STATE/stuck-lys-a"
"$tool" "$work/lys-a" > "$work/out" 2>&1 || fail "a run that never started was not dispatched again: $(cat "$work/out")"
[ "$(grep -c "workflow run ci.yml" "$STATE/gh.log")" = 1 ] || fail "dispatched $(grep -c "workflow run ci.yml" "$STATE/gh.log") times"
grep -qF "lys-a: unchanged, head" "$work/out" || fail "an unchanged repository was not called so: $(cat "$work/out")"

rm -f "$STATE/stuck-lys-a"
git -C "$work/lys-a" commit --quiet --allow-empty -m five
git -C "$work/lys-a" push --quiet origin HEAD:main
: > "$STATE/gh.log"
touch "$STATE/late-release-lys-a"
"$tool" "$work/lys-a" > "$work/out" 2>&1 || fail "a release run that appeared late: $(cat "$work/out")"
grep -qF "ci=success, release=success" "$work/out" || fail "the late release run was not waited for: $(cat "$work/out")"
