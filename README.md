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
