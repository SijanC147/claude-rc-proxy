#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$(mktemp -d)"

cleanup() {
  rm -rf -- "$TEST_DIR"
}
trap cleanup EXIT

GOTOOLCHAIN="${GOTOOLCHAIN:-go1.26.0}" \
  "$SCRIPT_DIR/build-release.sh" "1.2.3" "abc1234" "$TEST_DIR/dist-one"
GOTOOLCHAIN="${GOTOOLCHAIN:-go1.26.0}" \
  "$SCRIPT_DIR/build-release.sh" "1.2.3" "abc1234" "$TEST_DIR/dist-two"
"$SCRIPT_DIR/verify-release-assets.sh" "$TEST_DIR/dist-one" "1.2.3" "abc1234"
"$SCRIPT_DIR/verify-release-assets.sh" "$TEST_DIR/dist-two" "1.2.3" "abc1234"

for name in \
  SHA256SUMS \
  claude-rc-proxy-darwin-amd64.tar.gz \
  claude-rc-proxy-darwin-arm64.tar.gz \
  claude-rc-proxy-linux-amd64.tar.gz \
  claude-rc-proxy-linux-arm64.tar.gz; do
  cmp "$TEST_DIR/dist-one/$name" "$TEST_DIR/dist-two/$name"
done

expected_files=$'SHA256SUMS\nclaude-rc-proxy-darwin-amd64.tar.gz\nclaude-rc-proxy-darwin-arm64.tar.gz\nclaude-rc-proxy-linux-amd64.tar.gz\nclaude-rc-proxy-linux-arm64.tar.gz'
actual_files="$(find "$TEST_DIR/dist-one" -maxdepth 1 -type f -exec basename {} \; | LC_ALL=C sort)"
if [[ "$actual_files" != "$expected_files" ]]; then
  printf 'unexpected release files:\n%s\n' "$actual_files" >&2
  exit 1
fi

if [[ -e "$REPO_ROOT/dist" ]]; then
  echo "release test polluted the repository dist directory" >&2
  exit 1
fi

PUBLISH_TEST_ASSET_DIR="$TEST_DIR/dist-two" \
PUBLISH_TEST_EXISTING_ASSET_DIR="$TEST_DIR/dist-one" \
  "$SCRIPT_DIR/test-publish-release.sh"

echo "release packaging tests passed"
