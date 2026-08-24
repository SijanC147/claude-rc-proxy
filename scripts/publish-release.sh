#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: publish-release.sh <owner/repository> <tag> <asset-directory> <true|false-prerelease>" >&2
  exit 64
fi

repository="$1"
tag="$2"
asset_dir="$(cd -- "$3" && pwd)"
prerelease="$4"

if [[ "$prerelease" != "true" && "$prerelease" != "false" ]]; then
  echo "prerelease must be true or false" >&2
  exit 64
fi

expected_assets=(
  "SHA256SUMS"
  "claude-rc-proxy-darwin-amd64.tar.gz"
  "claude-rc-proxy-darwin-arm64.tar.gz"
  "claude-rc-proxy-linux-amd64.tar.gz"
  "claude-rc-proxy-linux-arm64.tar.gz"
)

for name in "${expected_assets[@]}"; do
  test -f "$asset_dir/$name" || {
    echo "missing release asset: $name" >&2
    exit 1
  }
done

release_exists=false
if gh release view "$tag" --repo "$repository" >/dev/null 2>&1; then
  release_exists=true
fi

if [[ "$release_exists" == "true" ]]; then
  is_draft="$(gh release view "$tag" --repo "$repository" --json isDraft --jq '.isDraft')"
  is_prerelease="$(gh release view "$tag" --repo "$repository" --json isPrerelease --jq '.isPrerelease')"
  if [[ "$is_draft" != "true" ]]; then
    echo "release $tag is already published; refusing to mutate it" >&2
    exit 1
  fi
  if [[ "$is_prerelease" != "$prerelease" ]]; then
    echo "existing draft prerelease state does not match requested state" >&2
    exit 1
  fi
else
  create_args=("$tag" "--repo" "$repository" "--verify-tag" "--draft" "--generate-notes")
  if [[ "$prerelease" == "true" ]]; then
    create_args+=("--prerelease")
  fi
  gh release create "${create_args[@]}"
fi

existing_names="$(gh release view "$tag" --repo "$repository" --json assets --jq '.assets[].name')"
comparison_root="$(mktemp -d)"
verification_root="$(mktemp -d)"
cleanup() {
  rm -rf -- "$comparison_root" "$verification_root"
}
trap cleanup EXIT

for name in "${expected_assets[@]}"; do
  if grep -Fxq "$name" <<<"$existing_names"; then
    existing_dir="$comparison_root/$name"
    mkdir -p -- "$existing_dir"
    gh release download "$tag" --repo "$repository" --pattern "$name" --dir "$existing_dir"
    if ! cmp "$asset_dir/$name" "$existing_dir/$name"; then
      echo "existing draft asset differs from local asset: $name" >&2
      exit 1
    fi
    continue
  fi
  gh release upload "$tag" "$asset_dir/$name" --repo "$repository"
done

actual_names="$(gh release view "$tag" --repo "$repository" --json assets --jq '.assets[].name' | LC_ALL=C sort)"
expected_names="$(printf '%s\n' "${expected_assets[@]}" | LC_ALL=C sort)"
if [[ "$actual_names" != "$expected_names" ]]; then
  printf 'release asset set mismatch\nexpected:\n%s\nactual:\n%s\n' \
    "$expected_names" "$actual_names" >&2
  exit 1
fi

gh release download "$tag" --repo "$repository" --dir "$verification_root"
for name in "${expected_assets[@]}"; do
  cmp "$asset_dir/$name" "$verification_root/$name"
done
(
  cd -- "$verification_root"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum --check SHA256SUMS
  else
    shasum -a 256 --check SHA256SUMS
  fi
)

gh release edit "$tag" --repo "$repository" --draft=false
echo "published $repository release $tag"
