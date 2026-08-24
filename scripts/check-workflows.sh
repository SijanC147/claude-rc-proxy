#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

cd -- "$REPO_ROOT"
if command -v actionlint >/dev/null 2>&1; then
  actionlint .github/workflows/*.yml
else
  go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12 .github/workflows/*.yml
fi
