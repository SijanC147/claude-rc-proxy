# Release and Homebrew Publishing

Releases are built from existing SemVer tags on the fork's canonical `main`
branch. Published assets are immutable: fix a bad release with a new patch
version rather than replacing assets under an existing tag.

The `origin` fork (`SijanC147/claude-rc-proxy`) is the only write, PR, tag, and
release target. The `dthinkr/claude-rc-proxy` parent is fetch-only: its local
push URL must remain `no_push`, and upstream synchronization branches and pull
requests always target the fork's `main`. Never push a branch or tag, open a
pull request, or publish a release against the parent repository.

## Repository setup

The release workflow needs one repository secret:

```text
OP_SERVICE_ACCOUNT_TOKEN
```

The 1Password service account must be able to read:

```text
op://CICD/HOMEBREW_TAP_ACTIONS_TOKEN/credential
```

Create that as a new 1Password item. Do not replace or modify
`op://CICD/GH_PAT/credential`; `better-ccflare` still depends on the existing
credential.

`HOMEBREW_TAP_ACTIONS_TOKEN` must be a fine-grained GitHub token restricted to
only `SijanC147/homebrew-hextap`, with exactly:

```text
Actions:  Read and write
Metadata: Read
Contents: No access
```

The source workflow uses it only to trigger `workflow_dispatch`, receive that
API call's exact workflow run ID, and poll that run. It cannot read or mutate
tap contents. The public source runner never clones or executes tap content.
Runtime proxy tokens and CA material must never be stored in GitHub Actions or
release assets.

The built-in `GITHUB_TOKEN` publishes releases in this repository. The default
workflow permission can remain read-only because only the release job requests
`contents: write`, `attestations: write`, and `id-token: write`.

Before creating `v0.1.0`, enable immutable releases in the source fork:

1. Open `SijanC147/claude-rc-proxy` on GitHub.
2. Open `Settings`.
3. Scroll to the `Releases` section.
4. Select `Enable release immutability`.

This applies only to future releases, so it must be enabled before the first
release is published. The workflow refuses to finish unless
`gh release verify <tag>` confirms the resulting immutable release attestation.
It also generates build-provenance attestations for every uploaded asset from
the canonical `.github/workflows/release.yml` workflow.

Add a repository ruleset for `refs/tags/v*` that blocks tag updates and
deletions. The workflow also resolves the remote tag again immediately before
publishing and refuses publication if it moved after validation.

## Create a stable release

Run the local quality and packaging checks:

```sh
GOTOOLCHAIN=go1.26.0 go test -count=1 ./...
GOTOOLCHAIN=go1.26.0 go test -race -count=1 ./...
GOTOOLCHAIN=go1.26.0 go vet ./...
scripts/check-go-format.sh
scripts/test-release-metadata.sh
ruby scripts/test-homebrew-formula.rb
scripts/test-publish-release.sh
scripts/test-dispatch-homebrew-release.sh
ruby scripts/test-release-workflow-graph.rb
GOTOOLCHAIN=go1.26.0 scripts/test-release-packaging.sh
scripts/check-workflows.sh
shellcheck scripts/*.sh
BREW_BIN=/opt/homebrew/bin/brew GOTOOLCHAIN=go1.26.0 scripts/test-homebrew-install.sh
```

Create and push an annotated tag from an up-to-date `main`:

```sh
git switch main
git pull --ff-only origin main
git tag -a v0.1.0 -m "claude-rc-proxy v0.1.0"
git push origin v0.1.0
```

Tag pushes are the normal full-release path. If a full release is ever started
manually, select the release tag itself in GitHub's `Use workflow from`
selector, or invoke `gh workflow run Release --ref <tag>`. Full mode refuses a
branch-context dispatch because build-provenance attestations must bind to the
exact tagged commit. `homebrew-only` recovery may still run from `main` because
it does not build or attest new assets.

Stable tags must match `vX.Y.Z`. Prereleases use strict SemVer such as
`v0.2.0-rc.1`. Prereleases publish GitHub assets but never update Homebrew.

The workflow builds these archives with `CGO_ENABLED=0`:

```text
claude-rc-proxy-darwin-arm64.tar.gz
claude-rc-proxy-darwin-amd64.tar.gz
claude-rc-proxy-linux-arm64.tar.gz
claude-rc-proxy-linux-amd64.tar.gz
SHA256SUMS
```

Each archive contains `claude-rc-proxy`, `LICENSE`, and `README.md`.

## Recovery behavior

The GitHub release remains a draft until every asset has been uploaded,
downloaded again, compared byte-for-byte, and checksum-verified. A rerun may
resume an identical partial draft. It refuses to overwrite a mismatched draft
asset or mutate an already-published release.

If the GitHub release succeeds but Homebrew publication fails, dispatch the
`Release` workflow manually with:

```text
tag:  v0.1.0
mode: homebrew-only
```

Homebrew-only recovery requires an existing published stable release. It
starts the private tap's `workflow_dispatch` workflow and polls the exact run ID
returned by GitHub. Exact-run polling is bounded to 210 minutes and the source
job to 220 minutes, covering all three bounded attempts plus queue allowance.

The private workflow independently verifies the immutable release attestation
and workflow-bound build provenance for every asset. Each attempt separates:

1. trusted tap-tool snapshotting;
2. inert Formula preparation;
3. whole-tap lint/audit without executing the public binary;
4. fresh minimal-tap runtime/service validation;
5. fresh `force: false` Git Data API publication.

Tap-side service settings, caveats, tests, and comments remain unchanged. If
tap `main` moves, the attempt refuses the update and starts again from the new
base.

The private tap's `claude-rc-proxy-release.yml` workflow must be present on its
default branch before creating the first source release tag.

The private tap owns the production Formula template, metadata updater, asset
verifier, Homebrew/service validator, and CAS publisher. Public release tags
supply only immutable archives and validated release metadata; the tap workflow
does not execute source-repository scripts. The source-side Formula tooling is
used only for local snapshot tests.

The Formula intentionally omits an explicit `version` stanza. Homebrew derives
the stable version from the two identical GitHub release URL versions, and
Homebrew 6.0.19 strict audit rejects the equivalent explicit stanza as
redundant. Stable updates therefore change exactly two URLs and two SHA-256
values while preserving all tap-owned content.

## Homebrew service configuration

After the Formula is published:

```sh
brew install sean/hextap/claude-rc-proxy
```

Create `~/.homebrew/services/claude-rc-proxy.env` with mode `0600`. The parent
directory should be `0700`. Use absolute values:

```dotenv
CLAUDE_RC_PROXY_CA=/absolute/path/to/combined-ca.pem
CLAUDE_RC_PROXY_TOKEN=<pool-token>
CLAUDE_RC_PROXY_LISTEN=127.0.0.1:9801
```

Then manage the non-root per-user service with:

```sh
brew services start claude-rc-proxy
brew services restart claude-rc-proxy
brew services info claude-rc-proxy
```

Claude Code receives only the public CA certificate through
`NODE_EXTRA_CA_CERTS`; never point it at the combined signer containing the
private key.
