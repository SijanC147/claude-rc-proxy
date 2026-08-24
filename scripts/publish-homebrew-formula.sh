#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: publish-homebrew-formula.sh <owner/repository> <base-sha> <formula-file> <formula-sha256> <version>" >&2
  exit 64
fi

repository="$1"
base_sha="$2"
formula_file="$(cd -- "$(dirname -- "$3")" && pwd)/$(basename -- "$3")"
formula_sha256="$4"
version="$5"
formula_path="Formula/claude-rc-proxy.rb"

[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]
[[ "$base_sha" =~ ^[0-9a-f]{40}$ ]]
[[ "$formula_sha256" =~ ^[0-9a-f]{64}$ ]]
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
test -f "$formula_file"

if command -v sha256sum >/dev/null 2>&1; then
  actual_sha256="$(sha256sum "$formula_file" | awk '{ print $1 }')"
else
  actual_sha256="$(shasum -a 256 "$formula_file" | awk '{ print $1 }')"
fi
[[ "$actual_sha256" == "$formula_sha256" ]]

write_output() {
  local key="$1"
  local value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
  else
    printf '%s=%s\n' "$key" "$value"
  fi
}

api="repos/$repository"
current_main="$(gh api "$api/git/ref/heads/main" --jq '.object.sha')"
if [[ "$current_main" != "$base_sha" ]]; then
  write_output pushed false
  write_output reason moved-main
  exit 0
fi

base_tree="$(gh api "$api/git/commits/$base_sha" --jq '.tree.sha')"
current_blob="$(gh api "$api/git/trees/$base_tree?recursive=1" \
  --jq ".tree[] | select(.path == \"$formula_path\") | .sha")"
proposed_blob_local="$(git hash-object "$formula_file")"
if [[ "$current_blob" == "$proposed_blob_local" ]]; then
  write_output pushed true
  write_output reason already-current
  exit 0
fi

request_dir="$(mktemp -d)"
cleanup() {
  rm -rf -- "$request_dir"
}
trap cleanup EXIT

ruby -rbase64 -rjson -e '
  content = Base64.strict_encode64(File.binread(ARGV.fetch(0)))
  File.write(ARGV.fetch(1), JSON.generate(content: content, encoding: "base64"))
' "$formula_file" "$request_dir/blob.json"
new_blob="$(gh api --method POST "$api/git/blobs" \
  --input "$request_dir/blob.json" --jq '.sha')"

ruby -rjson -e '
  body = {
    base_tree: ARGV.fetch(0),
    tree: [{ path: "Formula/claude-rc-proxy.rb", mode: "100644", type: "blob", sha: ARGV.fetch(1) }],
  }
  File.write(ARGV.fetch(2), JSON.generate(body))
' "$base_tree" "$new_blob" "$request_dir/tree.json"
new_tree="$(gh api --method POST "$api/git/trees" \
  --input "$request_dir/tree.json" --jq '.sha')"

ruby -rjson -e '
  body = { message: "Update claude-rc-proxy to #{ARGV.fetch(0)}", tree: ARGV.fetch(1), parents: [ARGV.fetch(2)] }
  File.write(ARGV.fetch(3), JSON.generate(body))
' "$version" "$new_tree" "$base_sha" "$request_dir/commit.json"
new_commit="$(gh api --method POST "$api/git/commits" \
  --input "$request_dir/commit.json" --jq '.sha')"

current_main="$(gh api "$api/git/ref/heads/main" --jq '.object.sha')"
if [[ "$current_main" != "$base_sha" ]]; then
  write_output pushed false
  write_output reason moved-main
  exit 0
fi

ruby -rjson -e '
  File.write(ARGV.fetch(1), JSON.generate(sha: ARGV.fetch(0), force: false))
' "$new_commit" "$request_dir/ref.json"

set +e
gh api --method PATCH "$api/git/refs/heads/main" \
  --input "$request_dir/ref.json" >/dev/null 2>&1
update_status=$?
set -e
if [[ "$update_status" -ne 0 ]]; then
  current_main="$(gh api "$api/git/ref/heads/main" --jq '.object.sha')"
  if [[ "$current_main" != "$base_sha" ]]; then
    write_output pushed false
    write_output reason moved-main
    exit 0
  fi
  echo "atomic ref update failed while main still matched the validated base" >&2
  exit 1
fi

write_output pushed true
write_output reason published
cleanup
trap - EXIT
