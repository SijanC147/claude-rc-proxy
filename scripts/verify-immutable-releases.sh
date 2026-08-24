#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: verify-immutable-releases.sh <repository>" >&2
  exit 64
fi

repository="$1"
api_version="2026-03-10"

if [[ "$repository" != "SijanC147/claude-rc-proxy" ]]; then
  echo "immutable-release preflight repository is not canonical" >&2
  exit 1
fi

enabled="$(gh api \
  -H "X-GitHub-Api-Version: $api_version" \
  "repos/$repository/immutable-releases" \
  --jq '.enabled')"
if [[ "$enabled" != "true" ]]; then
  echo "immutable releases must be enabled before building or publishing" >&2
  exit 1
fi

echo "immutable releases are enabled for the canonical source fork"
