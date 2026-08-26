#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(mktemp -d)"
TARGET_OS="$(go env GOOS)"
TARGET_ARCH="$(go env GOARCH)"
COMMIT="abc1234"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

case "$TARGET_OS" in
  darwin | linux) ;;
  *)
    echo "unsupported test host OS: $TARGET_OS" >&2
    exit 1
    ;;
esac
case "$TARGET_ARCH" in
  arm64 | amd64) ;;
  *)
    echo "unsupported test host architecture: $TARGET_ARCH" >&2
    exit 1
    ;;
esac

build() {
  local version="$1"
  local output="$2"
  local target_os="${3:-$TARGET_OS}"
  local target_arch="${4:-$TARGET_ARCH}"
  local commit="${5:-$COMMIT}"

  HEXTAP_TARGET_OS="$target_os" \
    HEXTAP_TARGET_ARCH="$target_arch" \
    HEXTAP_OUTPUT="$output" \
    HEXTAP_VERSION="$version" \
    HEXTAP_COMMIT="$commit" \
    "$BASH" "$SCRIPT_DIR/hextap-build"
}

assert_version() {
  local binary="$1"
  local version="$2"
  local expected="claude-rc-proxy $version (commit $COMMIT)"
  local actual

  actual="$("$binary" --version)"
  if [[ "$actual" != "$expected" ]]; then
    printf 'version output mismatch\nexpected: %s\nactual: %s\n' \
      "$expected" "$actual" >&2
    return 1
  fi
}

assert_rejected() {
  local label="$1"
  shift

  if "$@" >/dev/null 2>&1; then
    echo "expected rejection: $label" >&2
    return 1
  fi
}

mkdir -p "$TEST_ROOT/stable" "$TEST_ROOT/prerelease-one" "$TEST_ROOT/prerelease-two" "$TEST_ROOT/invalid"

stable_binary="$TEST_ROOT/stable/claude-rc-proxy"
build "1.2.3" "$stable_binary"
assert_version "$stable_binary" "1.2.3"

prerelease_one="$TEST_ROOT/prerelease-one/claude-rc-proxy"
prerelease_two="$TEST_ROOT/prerelease-two/claude-rc-proxy"
build "1.2.3-rc.1" "$prerelease_one"
build "1.2.3-rc.1" "$prerelease_two"
assert_version "$prerelease_one" "1.2.3-rc.1"
cmp "$prerelease_one" "$prerelease_two"

for invalid_version in \
  "v1.2.3" \
  "01.2.3" \
  "1.02.3" \
  "1.2.03" \
  "1.2.3-01" \
  "1.2.3-" \
  "1.2.3+build" \
  "1.2.3-rc_1"; do
  assert_rejected "version $invalid_version" \
    build "$invalid_version" "$TEST_ROOT/invalid/claude-rc-proxy"
done

assert_rejected "target OS" \
  build "1.2.3" "$TEST_ROOT/invalid/claude-rc-proxy" windows "$TARGET_ARCH"
assert_rejected "target architecture" \
  build "1.2.3" "$TEST_ROOT/invalid/claude-rc-proxy" "$TARGET_OS" ppc64
assert_rejected "short commit" \
  build "1.2.3" "$TEST_ROOT/invalid/claude-rc-proxy" "$TARGET_OS" "$TARGET_ARCH" abc123
assert_rejected "uppercase commit" \
  build "1.2.3" "$TEST_ROOT/invalid/claude-rc-proxy" "$TARGET_OS" "$TARGET_ARCH" ABC1234

echo "Hextap build adapter tests passed"
