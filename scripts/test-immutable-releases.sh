#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(mktemp -d)"
FAKE_BIN="$TEST_ROOT/bin"
BUILD_MARKER="$TEST_ROOT/build-started"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
test "$1" = api
shift
test "$1 $2" = '-H X-GitHub-Api-Version: 2026-03-10'
shift 2
test "$1" = 'repos/SijanC147/claude-rc-proxy/immutable-releases'
shift
test "$1 $2" = '--jq .enabled'
echo "${FAKE_IMMUTABLE_ENABLED:-true}"
FAKE_GH
chmod 755 "$FAKE_BIN/gh"

export PATH="$FAKE_BIN:$PATH"
"$SCRIPT_DIR/verify-immutable-releases.sh" SijanC147/claude-rc-proxy >/dev/null

set +e
FAKE_IMMUTABLE_ENABLED=false \
  "$SCRIPT_DIR/verify-immutable-releases.sh" SijanC147/claude-rc-proxy >/dev/null 2>&1 && \
  touch "$BUILD_MARKER"
disabled_status=$?
set -e
if [[ "$disabled_status" -eq 0 || -e "$BUILD_MARKER" ]]; then
  echo "disabled immutable releases did not stop before build" >&2
  exit 1
fi

set +e
"$SCRIPT_DIR/verify-immutable-releases.sh" other/claude-rc-proxy >/dev/null 2>&1
wrong_repository_status=$?
set -e
if [[ "$wrong_repository_status" -eq 0 ]]; then
  echo "non-canonical immutable-release preflight was accepted" >&2
  exit 1
fi

cleanup
trap - EXIT
echo "immutable-release enabled, disabled, and pre-build tests passed"
