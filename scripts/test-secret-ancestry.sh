#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/assert-no-secret-ancestors.sh"

SECRET_ANCESTOR_STOP_PID="$$" \
  env -u GH_PAT -u GH_TOKEN -u OP_SERVICE_ACCOUNT_TOKEN "$CHECK" >/dev/null
if SECRET_ANCESTOR_STOP_PID="$$" GH_PAT=ancestor-test-value "$CHECK" >/dev/null 2>&1; then
  echo "secret-bearing ancestry was not rejected" >&2
  exit 1
fi
if GH_TOKEN=ancestor-test-value bash -c \
  'SECRET_ANCESTOR_STOP_PID="$$" env -u GH_TOKEN "$1"; child_rc=$?; :; exit "$child_rc"' \
  _ "$CHECK" >/dev/null 2>&1; then
  echo "clean child under a secret-bearing parent was not rejected" >&2
  exit 1
fi

echo "secret ancestry tests passed"
