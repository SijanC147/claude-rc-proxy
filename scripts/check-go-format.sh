#!/usr/bin/env bash

set -euo pipefail

files=()
while IFS= read -r -d '' file; do
  files+=("$file")
done < <(git ls-files -z '*.go')

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "no tracked Go files found" >&2
  exit 1
fi

unformatted="$(gofmt -l "${files[@]}")"
if [[ -n "$unformatted" ]]; then
  printf 'unformatted Go files:\n%s\n' "$unformatted" >&2
  exit 1
fi

echo "all tracked Go files are formatted"
