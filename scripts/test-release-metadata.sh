#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
METADATA_SCRIPT="$SCRIPT_DIR/release-metadata.sh"

assert_metadata() {
  local tag="$1"
  local mode="$2"
  local expected="$3"
  local actual

  actual="$($METADATA_SCRIPT "$tag" "$mode")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'metadata mismatch for %s %s\nexpected:\n%s\nactual:\n%s\n' \
      "$tag" "$mode" "$expected" "$actual" >&2
    return 1
  fi
}

assert_invalid() {
  local tag="$1"
  local mode="${2:-full}"

  if "$METADATA_SCRIPT" "$tag" "$mode" >/dev/null 2>&1; then
    printf 'expected rejection for tag=%s mode=%s\n' "$tag" "$mode" >&2
    return 1
  fi
}

assert_metadata "v0.1.0" "full" $'tag=v0.1.0\nversion=0.1.0\nstable=true\nprerelease=false\nmode=full'
assert_metadata "v12.34.56-rc.1" "full" $'tag=v12.34.56-rc.1\nversion=12.34.56-rc.1\nstable=false\nprerelease=true\nmode=full'
assert_metadata "v2.0.0" "homebrew-only" $'tag=v2.0.0\nversion=2.0.0\nstable=true\nprerelease=false\nmode=homebrew-only'

for invalid_tag in \
  "0.1.0" \
  "v1.2" \
  "v1.2.3.4" \
  "v01.2.3" \
  "v1.02.3" \
  "v1.2.03" \
  "v1.2.3-01" \
  "v1.2.3-" \
  "v1.2.3+build" \
  "v1.2.3-rc_1"; do
  assert_invalid "$invalid_tag"
done

assert_invalid "v1.2.3" "unsupported-mode"

echo "release metadata tests passed"
