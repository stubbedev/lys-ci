#!/usr/bin/env bash
set -euo pipefail

tool=$(cd "$(dirname "$0")/.." && pwd)/bin/release
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() {
    echo "FAIL: $1" >&2
    exit 1
}

mkdir "$work/bin"
cat > "$work/bin/gh" << 'GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_LOG"
if [ "$1" = run ]; then
    printf '%s\n' "$GH_STATE"
fi
GH
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" GH_LOG="$work/gh.log" GH_STATE="completed success"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
: > "$GH_LOG"

git init --quiet --bare --initial-branch=main "$work/origin.git"
git clone --quiet "$work/origin.git" "$work/repo" 2> /dev/null
cd "$work/repo"
git checkout --quiet -b main
commit() {
    git commit --quiet --allow-empty -m "$1"
    git push --quiet origin HEAD:main
}
commit one
git remote set-head origin main
refused() {
    if out=$("$tool" "$1" 2>&1); then
        fail "$2 was released: $out"
    fi
    grep -qF "$3" <<< "$out" || fail "$2 did not say '$3': $out"
}

refused sideways "an unknown bump" usage
[ "$("$tool" patch)" = "v0.0.1 at $(git rev-parse --short=7 HEAD)" ] || fail "the first patch"
git rev-parse -q --verify refs/tags/v0.0.1 > /dev/null || fail "no local tag"
git ls-remote --exit-code origin refs/tags/v0.0.1 > /dev/null || fail "no pushed tag"
[ "$(git cat-file -t v0.0.1)" = tag ] || fail "the tag is not annotated"
grep -qF 'release create v0.0.1 --verify-tag' "$GH_LOG" || fail "no release without a workflow"
refused patch "a released commit" "already released as v0.0.1"

commit two
GH_STATE="completed failure" refused patch "red CI" "completed failure"
GH_STATE="in_progress " refused patch "CI in flight" "in_progress"
GH_STATE="" refused patch "no CI run" "not started"

touch dirty
refused patch "a dirty tree" dirty
rm dirty

git commit --quiet --allow-empty -m unpushed
refused patch "an unpushed commit" "is not origin/main"
git reset --quiet --hard origin/main

git checkout --quiet -b other
refused patch "another branch" "not the default branch"
git checkout --quiet main

mkdir -p .github/workflows
touch .github/workflows/release.yml
git add .github
commit three
: > "$GH_LOG"
"$tool" minor > /dev/null
git rev-parse -q --verify refs/tags/v0.1.0 > /dev/null || fail "the minor"
if grep -qF 'release create' "$GH_LOG"; then
    fail "a release workflow's release was created twice"
fi
commit four
"$tool" major > /dev/null
git rev-parse -q --verify refs/tags/v1.0.0 > /dev/null || fail "the major"
git tag v1.0.10 HEAD~1
commit five
"$tool" patch > /dev/null
git rev-parse -q --verify refs/tags/v1.0.11 > /dev/null || fail "tags are not ordered by version"
