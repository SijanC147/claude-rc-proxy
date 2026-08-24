#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: verify-release-assets.sh <asset-directory> <version> <commit>" >&2
  exit 64
fi

asset_dir="$(cd -- "$1" && pwd)"
version="$2"
commit="$3"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
verify_root="$(mktemp -d)"

cleanup() {
  rm -rf -- "$verify_root"
}
trap cleanup EXIT

targets=(
  "darwin arm64"
  "darwin amd64"
  "linux arm64"
  "linux amd64"
)
expected_files=("SHA256SUMS")
for target in "${targets[@]}"; do
  read -r goos goarch <<<"$target"
  expected_files+=("claude-rc-proxy-${goos}-${goarch}.tar.gz")
done

actual_files="$(find "$asset_dir" -mindepth 1 -maxdepth 1 -type f -exec basename {} \; | LC_ALL=C sort)"
expected_listing="$(printf '%s\n' "${expected_files[@]}" | LC_ALL=C sort)"
if [[ "$actual_files" != "$expected_listing" ]]; then
  printf 'release asset set mismatch\nexpected:\n%s\nactual:\n%s\n' \
    "$expected_listing" "$actual_files" >&2
  exit 1
fi

(
  cd -- "$asset_dir"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum --check SHA256SUMS
  else
    shasum -a 256 --check SHA256SUMS
  fi
)

host_os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$(uname -m)" in
  arm64 | aarch64) host_arch="arm64" ;;
  x86_64 | amd64) host_arch="amd64" ;;
  *) host_arch="unsupported" ;;
esac

for target in "${targets[@]}"; do
  read -r goos goarch <<<"$target"
  target_name="${goos}-${goarch}"
  archive="$asset_dir/claude-rc-proxy-${target_name}.tar.gz"
  extract_dir="$verify_root/$target_name"
  mkdir -p -- "$extract_dir"

  listing="$(tar -tzf "$archive" | sed 's#^\./##' | LC_ALL=C sort)"
  if [[ "$listing" != $'LICENSE\nREADME.md\nclaude-rc-proxy' ]]; then
    printf 'unexpected archive contents in %s:\n%s\n' "$archive" "$listing" >&2
    exit 1
  fi

  tar -xzf "$archive" -C "$extract_dir"
  test -x "$extract_dir/claude-rc-proxy"
  cmp "$repo_root/LICENSE" "$extract_dir/LICENSE"
  cmp "$repo_root/README.md" "$extract_dir/README.md"

  file_output="$(file "$extract_dir/claude-rc-proxy")"
  case "$target_name" in
    darwin-arm64) [[ "$file_output" == *"Mach-O 64-bit executable arm64"* ]] ;;
    darwin-amd64) [[ "$file_output" == *"Mach-O 64-bit executable x86_64"* ]] ;;
    linux-arm64) [[ "$file_output" == *"ELF 64-bit LSB executable"*"ARM aarch64"*"statically linked"* ]] ;;
    linux-amd64) [[ "$file_output" == *"ELF 64-bit LSB executable"*"x86-64"*"statically linked"* ]] ;;
  esac

  if [[ "$goos" == "$host_os" && "$goarch" == "$host_arch" ]]; then
    output="$("$extract_dir/claude-rc-proxy" --version)"
    expected="claude-rc-proxy $version (commit $commit)"
    if [[ "$output" != "$expected" ]]; then
      printf 'version output mismatch\nexpected: %s\nactual: %s\n' "$expected" "$output" >&2
      exit 1
    fi
  fi
done

echo "release assets verified"
