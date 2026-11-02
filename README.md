# lys-ci

The CI every lys repository shares, so a change lands in one place. It holds
only what is about the repositories' builds; the documentation sites share
[lys-docs-theme](https://github.com/stubbedev/lys-docs-theme).

## vendorHash on Dependabot's Go pull requests

Dependabot rewrites `go.mod` and `go.sum` but not `vendorHash`, so the
fixed-output vendor derivation fails every Nix build of its pull request. The
`vendor-hash` workflow recomputes the hash with the repository's
`just vendor-hash` and pushes the commit to the pull request. A build failing
for any other reason than the hash fails the job, and a pull request whose
code does not build against the bump still fails its own CI.

A repository needs three things.

The recipe, naming the file that holds `vendorHash` and the vendor derivation:

```just
vendor-hash:
    nix run github:stubbedev/lys-ci#vendor-hash -- nix/package.nix .#default.goModules
```

The workflow, in `.github/workflows/vendor-hash.yml`, pinned to a commit of
this repository:

```yaml
name: vendor-hash

on:
  pull_request:
    paths:
      - go.mod
      - go.sum

permissions:
  contents: read

jobs:
  vendor-hash:
    uses: stubbedev/lys-ci/.github/workflows/vendor-hash.yml@<commit>
    secrets:
      VENDOR_HASH_DEPLOY_KEY: ${{ secrets.VENDOR_HASH_DEPLOY_KEY }}
```

### A repository's deploy key

The push needs a key of its own because a `GITHUB_TOKEN` push starts no CI run
on the new head. Without one, a pull request with a stale hash fails this job
naming the secret. Each repository holds its own, as a Dependabot secret so
only Dependabot's runs can read it:

```sh
repo=stubbedev/<repository>
dir=$(mktemp -d)
ssh-keygen -q -t ed25519 -N '' -C 'vendor-hash workflow' -f "$dir/key"
gh repo deploy-key add "$dir/key.pub" -R "$repo" --allow-write --title 'vendor-hash workflow'
gh secret set VENDOR_HASH_DEPLOY_KEY --app dependabot -R "$repo" < "$dir/key"
rm -rf "$dir"
```

The check runs only when a hash is stale, because the run that the key's own
push starts belongs to no Dependabot actor, sees no Dependabot secret, and
finds the hash current.

## Nix and Go caches

`.github/actions/nix-setup` installs Nix with the xilo substituter and restores
the job's Nix store and Go's compile cache, keyed by runner, job and
`flake.lock`. A job then starts from what the last run fetched and built rather
than downloading its whole closure again. Go test results are never reused:
the action sets `GOFLAGS=-count=1`, so only compilation is cached. Use it after
checkout, pinned to a commit of this repository:

```yaml
- uses: stubbedev/lys-ci/.github/actions/nix-setup@<commit>
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## The fused-multiply gate

`bin/no-fused` compiles the module in the current directory for arm64 and fails
on any FMA instruction, which the Go spec lets the compiler fuse from `x*y + z`
and which would make arm64's floats differ from amd64's. It runs the `go` on
`PATH`, the repository's own.

A repository takes this repository as a flake input, pinned by its `flake.lock`
like any other, and puts it in its dev shell, which puts `bin/no-fused` on `PATH`:

```nix
inputs.lys-ci.url = "github:stubbedev/lys-ci";
# in the dev shell, as a string, since mkShell takes no flake for a package
packages = ["${inputs.lys-ci}"];
```

```just
no-fused:
    no-fused
```

It is a dev shell tool rather than a `nix run`, unlike `vendor-hash`, because it
is a gate: the repositories' `just docker` containers run the dev shell's store
paths with no `nix` and no daemon socket to run it with.

## Cutting a release

`release <major|minor|patch>` tags the current commit as the next version and
pushes the tag. It refuses anything but a clean default branch at
`origin`'s head whose `ci.yml` run succeeded, and a commit already released. A
repository with `.github/workflows/release.yml` publishes from the tag; for one
without, the tool creates the GitHub release itself.

```just
release-patch:
    nix run github:stubbedev/lys-ci#release -- patch
```

A repository whose version lives in its source needs a commit before the tag,
so lys-shell keeps its own recipes.
