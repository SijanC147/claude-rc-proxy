#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: release-metadata.sh <v-semver-tag> <full|homebrew-only>" >&2
  exit 64
fi

tag="$1"
mode="$2"

if [[ "$mode" != "full" && "$mode" != "homebrew-only" ]]; then
  echo "unsupported release mode: $mode" >&2
  exit 64
fi

core='(0|[1-9][0-9]*)'
prerelease_identifier='(0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)'
semver_regex="^v${core}\.${core}\.${core}(-${prerelease_identifier}(\.${prerelease_identifier})*)?$"

if [[ ! "$tag" =~ $semver_regex ]]; then
  echo "tag is not an accepted SemVer release tag: $tag" >&2
  exit 64
fi

version="${tag#v}"
stable=true
prerelease=false
if [[ "$version" == *-* ]]; then
  stable=false
  prerelease=true
fi

printf 'tag=%s\n' "$tag"
printf 'version=%s\n' "$version"
printf 'stable=%s\n' "$stable"
printf 'prerelease=%s\n' "$prerelease"
printf 'mode=%s\n' "$mode"
