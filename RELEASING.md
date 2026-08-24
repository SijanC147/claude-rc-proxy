# Release and Homebrew Publishing

Releases are built from existing SemVer tags on the fork's canonical `main`
branch. Published assets are immutable: fix a bad release with a new patch
version rather than replacing assets under an existing tag.

## Repository setup

The release workflow needs one repository secret:

```text
OP_SERVICE_ACCOUNT_TOKEN
```

The 1Password service account must be able to read:

```text
op://CICD/GH_PAT/credential
```

That item contains the separate GitHub credential used only for a bare read of
`SijanC147/homebrew-hextap` and an atomic Git Data API update. It needs
repository contents read/write access to that private repository. Runtime proxy
tokens and CA material must never be stored in GitHub Actions or release assets.

The built-in `GITHUB_TOKEN` publishes releases in this repository. The default
workflow permission can remain read-only because only the release job requests
`contents: write`.

Add a repository ruleset for `refs/tags/v*` that blocks tag updates and
deletions. The workflow also resolves the remote tag again immediately before
publishing and refuses publication if it moved after validation.

## Create a stable release

Run the local quality and packaging checks:

```sh
GOTOOLCHAIN=go1.26.0 go test -count=1 ./...
GOTOOLCHAIN=go1.26.0 go test -race -count=1 ./...
GOTOOLCHAIN=go1.26.0 go vet ./...
scripts/test-release-metadata.sh
ruby scripts/test-homebrew-formula.rb
scripts/test-publish-release.sh
scripts/test-publish-homebrew-formula.sh
scripts/test-secret-ancestry.sh
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
downloads and re-verifies release assets and makes up to three isolated
publication attempts. Each attempt uses one fresh runner to construct and fully
validate a Formula against an exact tap base commit, then a second fresh runner
to compare-and-swap that one validated Formula with GitHub's Git Data API.
Tap-side service settings, caveats, tests, and comments remain unchanged. If
tap `main` moves, the attempt refuses the update and starts again from the new
base. The ref update always uses `force: false`.

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
