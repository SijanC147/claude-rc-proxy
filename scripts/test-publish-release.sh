#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(mktemp -d)"
ASSET_DIR="$TEST_ROOT/assets"
FAKE_BIN="$TEST_ROOT/bin"
FAKE_STATE="$TEST_ROOT/state"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p -- "$ASSET_DIR" "$FAKE_BIN" "$FAKE_STATE"
if [[ -n "${PUBLISH_TEST_ASSET_DIR:-}" ]]; then
  cp "$PUBLISH_TEST_ASSET_DIR"/SHA256SUMS "$PUBLISH_TEST_ASSET_DIR"/claude-rc-proxy-*.tar.gz "$ASSET_DIR/"
else
  for target in darwin-amd64 darwin-arm64 linux-amd64 linux-arm64; do
    printf 'asset-%s\n' "$target" > "$ASSET_DIR/claude-rc-proxy-$target.tar.gz"
  done
  (
    cd -- "$ASSET_DIR"
    shasum -a 256 claude-rc-proxy-*.tar.gz > SHA256SUMS
  )
fi

cat > "$FAKE_BIN/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail

test "$1" = release
operation="$2"
tag="$3"
shift 3
release_dir="$FAKE_GH_STATE/$tag"
assets_dir="$release_dir/assets"

case "$operation" in
  view)
    test -f "$release_dir/draft" || exit 1
    query=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --jq) query="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    case "$query" in
      .isDraft) cat "$release_dir/draft" ;;
      .isPrerelease) cat "$release_dir/prerelease" ;;
      '.assets[].name') find "$assets_dir" -maxdepth 1 -type f -exec basename {} \; | LC_ALL=C sort ;;
      "") echo '{}' ;;
      *) echo "unsupported fake gh query: $query" >&2; exit 2 ;;
    esac
    ;;
  create)
    mkdir -p -- "$assets_dir"
    echo true > "$release_dir/draft"
    echo false > "$release_dir/prerelease"
    for argument in "$@"; do
      [[ "$argument" != "--prerelease" ]] || echo true > "$release_dir/prerelease"
    done
    ;;
  upload)
    asset="$1"
    mkdir -p -- "$assets_dir"
    cp "$asset" "$assets_dir/"
    ;;
  download)
    pattern=""
    destination=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --pattern) pattern="$2"; shift 2 ;;
        --dir) destination="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    mkdir -p -- "$destination"
    if [[ -n "$pattern" ]]; then
      cp "$assets_dir/$pattern" "$destination/"
    else
      cp "$assets_dir"/* "$destination/"
    fi
    ;;
  edit)
    echo false > "$release_dir/draft"
    ;;
  *)
    echo "unsupported fake gh operation: $operation" >&2
    exit 2
    ;;
esac
FAKE_GH
chmod 755 "$FAKE_BIN/gh"

export FAKE_GH_STATE="$FAKE_STATE"
export PATH="$FAKE_BIN:$PATH"

"$SCRIPT_DIR/publish-release.sh" owner/repository v1.0.0 "$ASSET_DIR" false
test "$(cat "$FAKE_STATE/v1.0.0/draft")" = false
test "$(find "$FAKE_STATE/v1.0.0/assets" -type f | wc -l | tr -d ' ')" = 5
if "$SCRIPT_DIR/publish-release.sh" owner/repository v1.0.0 "$ASSET_DIR" false >/dev/null 2>&1; then
  echo "published release was mutated" >&2
  exit 1
fi

mkdir -p "$FAKE_STATE/v1.1.0/assets"
echo true > "$FAKE_STATE/v1.1.0/draft"
echo false > "$FAKE_STATE/v1.1.0/prerelease"
existing_asset_dir="${PUBLISH_TEST_EXISTING_ASSET_DIR:-$ASSET_DIR}"
cp "$existing_asset_dir/SHA256SUMS" "$FAKE_STATE/v1.1.0/assets/"
"$SCRIPT_DIR/publish-release.sh" owner/repository v1.1.0 "$ASSET_DIR" false
test "$(cat "$FAKE_STATE/v1.1.0/draft")" = false
test "$(find "$FAKE_STATE/v1.1.0/assets" -type f | wc -l | tr -d ' ')" = 5

mkdir -p "$FAKE_STATE/v1.2.0/assets"
echo true > "$FAKE_STATE/v1.2.0/draft"
echo false > "$FAKE_STATE/v1.2.0/prerelease"
echo mismatched > "$FAKE_STATE/v1.2.0/assets/SHA256SUMS"
if "$SCRIPT_DIR/publish-release.sh" owner/repository v1.2.0 "$ASSET_DIR" false >/dev/null 2>&1; then
  echo "mismatched draft asset was replaced" >&2
  exit 1
fi
test "$(cat "$FAKE_STATE/v1.2.0/draft")" = true
test "$(cat "$FAKE_STATE/v1.2.0/assets/SHA256SUMS")" = mismatched

echo "release publication tests passed"
