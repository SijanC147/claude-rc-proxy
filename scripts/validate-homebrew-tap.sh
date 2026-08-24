#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: validate-homebrew-tap.sh <tap-directory> <owner/tap>" >&2
  exit 64
fi

tap_dir="$(cd -- "$1" && pwd)"
tap_name="$2"
owner="${tap_name%%/*}"
repository="${tap_name#*/}"

if [[ "$owner" == "$tap_name" || -z "$owner" || -z "$repository" ]]; then
  echo "tap name must use owner/tap form" >&2
  exit 64
fi
test -f "$tap_dir/Formula/claude-rc-proxy.rb"

tap_owner_dir="$(brew --repository)/Library/Taps/$owner"
tap_link="$tap_owner_dir/homebrew-$repository"
formula="$tap_name/claude-rc-proxy"
installed=false
service_test_root=""

cleanup() {
  if [[ "$installed" == "true" ]]; then
    brew uninstall --formula --force --ignore-dependencies "$formula" >/dev/null 2>&1 || true
  fi
  if [[ -L "$tap_link" ]]; then
    unlink "$tap_link"
  fi
  rmdir "$tap_owner_dir" >/dev/null 2>&1 || true
  if [[ -n "$service_test_root" ]]; then
    rm -rf -- "$service_test_root"
  fi
}
trap cleanup EXIT

if [[ -e "$tap_link" || -L "$tap_link" ]]; then
  echo "refusing to replace existing tap path: $tap_link" >&2
  exit 1
fi
mkdir -p -- "$tap_owner_dir"
ln -s "$tap_dir" "$tap_link"

brew style "$tap_name"
brew readall --aliases --os=all --arch=all "$tap_name"
brew audit --strict "$formula"
brew audit --except=installed --tap="$tap_name"

if [[ "${HOMEBREW_FORMULA_SKIP_INSTALL:-0}" != "1" ]]; then
  if brew list --formula "$formula" >/dev/null 2>&1; then
    echo "refusing to replace an installed $formula" >&2
    exit 1
  fi
  brew install --formula "$formula"
  installed=true
  brew test "$formula"

  service_test_root="$(mktemp -d)"
  service_config_home="$service_test_root/config/homebrew"
  service_env="$service_config_home/services/claude-rc-proxy.env"
  mkdir -p "$service_config_home/services"
  chmod 700 "$service_test_root/config" "$service_config_home" "$service_config_home/services"
  cat > "$service_env" <<'SERVICE_ENVIRONMENT'
CLAUDE_RC_PROXY_CA=/tmp/claude-rc-proxy-test-ca.pem
CLAUDE_RC_PROXY_TOKEN=service-test-token
CLAUDE_RC_PROXY_LISTEN=127.0.0.1:65432
SERVICE_ENVIRONMENT
  chmod 600 "$service_env"
  XDG_CONFIG_HOME="$service_test_root/config" brew ruby -e '
    formula = Formula[ARGV.fetch(0)]
    effective = formula.service.effective_environment_variables
    expected = {
      CLAUDE_RC_PROXY_CA: "/tmp/claude-rc-proxy-test-ca.pem",
      CLAUDE_RC_PROXY_TOKEN: "service-test-token",
      CLAUDE_RC_PROXY_LISTEN: "127.0.0.1:65432",
    }
    abort "service environment override mismatch" unless effective == expected
  ' -- "$formula"
fi

cleanup
trap - EXIT
echo "Homebrew tap validation passed"
