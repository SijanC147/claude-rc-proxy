#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Homebrew snapshot install test skipped outside macOS"
  exit 0
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BREW_BIN="${BREW_BIN:-$(command -v brew)}"
TEST_ROOT="$(mktemp -d)"
RELEASE_DIR="$TEST_ROOT/v1.2.3"
TAP_DIR="$TEST_ROOT/homebrew-claude-rc-proxy-snapshot"
FORMULA_PATH="$TAP_DIR/Formula/claude-rc-proxy.rb"
TEST_XDG_CONFIG_HOME="$TEST_ROOT/config"
SERVICE_CONFIG_HOME="$TEST_XDG_CONFIG_HOME/homebrew"
SERVICE_ENV="$SERVICE_CONFIG_HOME/services/claude-rc-proxy.env"
TAP_OWNER_DIR="$($BREW_BIN --repository)/Library/Taps/codex"
TAP_LINK="$TAP_OWNER_DIR/homebrew-claude-rc-proxy-snapshot"
FORMULA="codex/claude-rc-proxy-snapshot/claude-rc-proxy"
installed=false

cleanup() {
  if [[ "$installed" == "true" ]]; then
    "$BREW_BIN" uninstall --formula --force --ignore-dependencies "$FORMULA" >/dev/null 2>&1 || true
  fi
  if [[ -L "$TAP_LINK" ]]; then
    unlink "$TAP_LINK"
  fi
  rmdir "$TAP_OWNER_DIR" >/dev/null 2>&1 || true
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

if [[ -e "$TAP_LINK" || -L "$TAP_LINK" ]]; then
  echo "refusing to replace existing test tap path: $TAP_LINK" >&2
  exit 1
fi
if "$BREW_BIN" list --formula "$FORMULA" >/dev/null 2>&1; then
  echo "refusing to replace installed test Formula: $FORMULA" >&2
  exit 1
fi

mkdir -p -- "$RELEASE_DIR" "$TAP_DIR/Formula" "$TAP_OWNER_DIR" "$SERVICE_CONFIG_HOME/services"
chmod 700 "$SERVICE_CONFIG_HOME" "$SERVICE_CONFIG_HOME/services"
cat > "$SERVICE_ENV" <<'SERVICE_ENVIRONMENT'
CLAUDE_RC_PROXY_CA=/tmp/claude-rc-proxy-test-ca.pem
CLAUDE_RC_PROXY_TOKEN=service-test-token
CLAUDE_RC_PROXY_LISTEN=127.0.0.1:65432
SERVICE_ENVIRONMENT
chmod 600 "$SERVICE_ENV"
GOTOOLCHAIN="${GOTOOLCHAIN:-go1.26.0}" \
  "$SCRIPT_DIR/build-release.sh" 1.2.3 abc1234 "$RELEASE_DIR"
arm64_sha="$(awk '$2 == "claude-rc-proxy-darwin-arm64.tar.gz" { print $1 }' "$RELEASE_DIR/SHA256SUMS")"
amd64_sha="$(awk '$2 == "claude-rc-proxy-darwin-amd64.tar.gz" { print $1 }' "$RELEASE_DIR/SHA256SUMS")"

ruby "$SCRIPT_DIR/update-homebrew-formula.rb" \
  --formula "$FORMULA_PATH" \
  --template "$REPO_ROOT/packaging/homebrew/claude-rc-proxy.rb.tmpl" \
  --version 1.2.3 \
  --arm64-sha "$arm64_sha" \
  --amd64-sha "$amd64_sha"

ruby - "$FORMULA_PATH" "$RELEASE_DIR" <<'RUBY'
formula_path, release_dir = ARGV
formula = File.read(formula_path)
formula.gsub!(
  %r{https://github\.com/SijanC147/claude-rc-proxy/releases/download/v1\.2\.3/},
  "file://#{release_dir}/",
)
formula.sub!(%(  license "MIT"\n), %(  version "1.2.3"\n  license "MIT"\n))
File.write(formula_path, formula)
RUBY

ln -s "$TAP_DIR" "$TAP_LINK"
PATH="$(dirname -- "$BREW_BIN"):$PATH" "$BREW_BIN" install --formula "$FORMULA"
installed=true
PATH="$(dirname -- "$BREW_BIN"):$PATH" "$BREW_BIN" test "$FORMULA"
"$BREW_BIN" info "$FORMULA" | grep -Fq '.homebrew/services/claude-rc-proxy.env'
XDG_CONFIG_HOME="$TEST_XDG_CONFIG_HOME" \
  "$BREW_BIN" ruby -e '
    formula = Formula[ARGV.fetch(0)]
    effective = formula.service.effective_environment_variables
    expected = {
      CLAUDE_RC_PROXY_CA: "/tmp/claude-rc-proxy-test-ca.pem",
      CLAUDE_RC_PROXY_TOKEN: "service-test-token",
      CLAUDE_RC_PROXY_LISTEN: "127.0.0.1:65432",
    }
    abort "service environment override mismatch" unless effective == expected
  ' -- "$FORMULA"

cleanup
trap - EXIT
echo "Homebrew snapshot install test passed"
