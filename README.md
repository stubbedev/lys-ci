# lys-ci

The CI tools every lys repository shares. Documentation sites use
[lys-docs-theme](https://github.com/stubbedev/lys-docs-theme) instead.

Pin the reusable workflow and the action to a commit of this repository.

## vendorHash on Dependabot's Go pull requests

Dependabot updates `go.mod` and `go.sum` but not `vendorHash`, so every Nix build
of its pull request fails. The `vendor-hash` workflow runs `just vendor-hash` and
pushes the result to the pull request.

It runs only on Dependabot pull requests from the same repository. A current hash
needs no commit. The job fails when the build fails for another reason, when
`just vendor-hash` changes other than exactly one file, or when the hash is stale
and `VENDOR_HASH_DEPLOY_KEY` is missing.

### Setup

The recipe passes the file holding `vendorHash` and the flake attribute of the
vendor derivation:

```just
vendor-hash:
    nix run github:stubbedev/lys-ci#vendor-hash -- nix/package.nix .#default.goModules
```

The file must contain exactly one `vendorHash = "sha256-...";` line.

`.github/workflows/vendor-hash.yml`:

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

| Secret | Required | Purpose |
| --- | --- | --- |
| `VENDOR_HASH_DEPLOY_KEY` | Only when a hash is stale | Private key of a write deploy key; the push uses it so the new head gets a CI run |

### A repository's deploy key

Store the key as a Dependabot secret, so only Dependabot's runs can read it:

```sh
repo=stubbedev/<repository>
dir=$(mktemp -d)
ssh-keygen -q -t ed25519 -N '' -C 'vendor-hash workflow' -f "$dir/key"
gh repo deploy-key add "$dir/key.pub" -R "$repo" --allow-write --title 'vendor-hash workflow'
gh secret set VENDOR_HASH_DEPLOY_KEY --app dependabot -R "$repo" < "$dir/key"
rm -rf "$dir"
```

The run that the key's push starts has no Dependabot actor and cannot read the
secret; it finds the hash current and succeeds.

## Security scanning

The `security` workflow runs CodeQL over Go and the workflows, Grype and
govulncheck with SARIF uploaded to code scanning, and dependency review with the
licence allow-list on pull requests.

The caller owns the triggers and the concurrency group, and grants the jobs'
permissions:

```yaml
jobs:
  security:
    permissions:
      actions: read
      contents: read
      pull-requests: read
      security-events: write
    uses: stubbedev/lys-ci/.github/workflows/security.yml@<commit>
```

| Input | Default | Purpose |
| --- | --- | --- |
| `go-toolchain` | `stable` | `stable`: the latest Go. `go.mod`: the version `go.mod` names, with `CGO_ENABLED=0`. `nix`: the dev shell, and a reachable vulnerability fails the job |
| `bounded-timeouts` | `false` | Bound each job to 10-30 minutes instead of GitHub's six hours |

## Publishing a release

The `publish-release` workflow downloads every artifact of the run, writes
`SHA256SUMS` and creates the release for the pushed tag with generated notes. Run
it after the jobs that upload the `.tar.gz`, `.deb` and `.rpm` files:

```yaml
publish:
  needs: package
  permissions:
    contents: write
  uses: stubbedev/lys-ci/.github/workflows/publish-release.yml@<commit>
```

| Input | Default | Purpose |
| --- | --- | --- |
| `timeout-minutes` | `360` | The job's timeout |

## Nix and Go caches

`.github/actions/nix-setup`:

- installs Nix with flakes and the `nix.stubbe.dev` substituter;
- restores the Nix store, keyed by OS, architecture, job and `flake.lock`;
- restores Go's build and module caches, refreshed daily and on a change to
  `flake.lock` or `go.sum`, so `go test` reruns only what a commit can affect;
- on a `schedule` event sets `GOFLAGS=-count=1` and leaves `LYS_TEST_ARGS` unset,
  so the weekly run repeats everything with the repository's own default flags.

A test recipe takes its uncacheable flags from `LYS_TEST_ARGS`, with its local
default after the dash: `go test ${LYS_TEST_ARGS--shuffle=on} ./...`. Other runs
set it empty, because `-shuffle` and `-count` turn Go's test cache off.

| Input | Required | Purpose |
| --- | --- | --- |
| `github-token` | Yes | Token for Nix fetches from GitHub |

Use it after checkout:

```yaml
- uses: stubbedev/lys-ci/.github/actions/nix-setup@<commit>
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## The fused-multiply gate

`no-fused` builds the module in the current directory for linux/arm64 with the
`go` on `PATH` and fails on any `FMADD`, `FMSUB`, `FNMADD` or `FNMSUB`
instruction. Go may fuse `x*y + z` on arm64, which rounds differently from amd64.

Add this repository as a flake input and put it in the dev shell, which puts
`bin/no-fused` on `PATH`:

```nix
inputs.lys-ci.url = "github:stubbedev/lys-ci";
# in mkShell
packages = ["${inputs.lys-ci}"];
```

```just
no-fused:
    no-fused
```

On `PATH`, it also runs in containers that have the dev shell's store paths but no
`nix`. `nix run github:stubbedev/lys-ci#no-fused` works too.

## Cutting a release

`release <major|minor|patch>` tags the current commit as the next
`vMAJOR.MINOR.PATCH` (from `v0.0.0` when there is no tag) and pushes the tag.

It refuses unless the working tree is clean, on `origin`'s default branch, at
`origin/<default>`, not yet tagged, and its latest `ci.yml` run succeeded.

A repository with `.github/workflows/release.yml` publishes from the tag. For one
without, `release` creates the GitHub release with generated notes.

```just
release-patch:
    nix run github:stubbedev/lys-ci#release -- patch
```

`release` makes no commit: a repository whose version is stored in its source must
commit the new version first.
