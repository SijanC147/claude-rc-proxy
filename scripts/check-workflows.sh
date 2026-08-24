#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
queue_schema_lag='unexpected key "queue" for "concurrency" section'

cd -- "$REPO_ROOT"
if command -v actionlint >/dev/null 2>&1; then
  actionlint -ignore "$queue_schema_lag" .github/workflows/*.yml
else
  go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12 \
    -ignore "$queue_schema_lag" .github/workflows/*.yml
fi
