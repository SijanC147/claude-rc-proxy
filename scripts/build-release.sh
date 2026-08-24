#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: build-release.sh <version> <commit> <output-directory>" >&2
  exit 64
fi

version="$1"
commit="$2"
output_dir="$3"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

"$script_dir/release-metadata.sh" "v$version" full >/dev/null
if [[ ! "$commit" =~ ^[0-9a-f]{7,64}$ ]]; then
  echo "commit must be a 7-64 character lowercase hexadecimal revision" >&2
  exit 64
fi

mkdir -p -- "$output_dir"
if find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  echo "output directory must be empty: $output_dir" >&2
  exit 1
fi
output_dir="$(cd -- "$output_dir" && pwd)"

stage_root="$(mktemp -d)"
cleanup() {
  rm -rf -- "$stage_root"
}
trap cleanup EXIT

targets=(
  "darwin arm64"
  "darwin amd64"
  "linux arm64"
  "linux amd64"
)
archives=()
archive_tool="$stage_root/package-release"
(
  cd -- "$repo_root"
  go build -trimpath -o "$archive_tool" "$script_dir/package-release.go"
)

for target in "${targets[@]}"; do
  read -r goos goarch <<<"$target"
  target_name="${goos}-${goarch}"
  stage_dir="$stage_root/$target_name"
  archive_name="claude-rc-proxy-${target_name}.tar.gz"
  mkdir -p -- "$stage_dir"

  (
    cd -- "$repo_root"
    CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
      go build -trimpath \
      -ldflags "-s -w -X main.version=$version -X main.commit=$commit" \
      -o "$stage_dir/claude-rc-proxy" .
  )
  chmod 755 "$stage_dir/claude-rc-proxy"
  cp "$repo_root/LICENSE" "$repo_root/README.md" "$stage_dir/"
  "$archive_tool" "$output_dir/$archive_name" "$stage_dir"
  archives+=("$archive_name")
done

(
  cd -- "$output_dir"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${archives[@]}" > SHA256SUMS
  else
    shasum -a 256 "${archives[@]}" > SHA256SUMS
  fi
)

echo "built release assets in $output_dir"
