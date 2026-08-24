#!/usr/bin/env bash

set -euo pipefail

secret_assignment='(^|[[:space:]])(GH_PAT|GH_TOKEN|OP_SERVICE_ACCOUNT_TOKEN)='
pid="$$"
stop_pid="${SECRET_ANCESTOR_STOP_PID:-1}"

while [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]]; do
  if ps eww -p "$pid" 2>/dev/null | grep -Eq "$secret_assignment"; then
    echo "secret-bearing process detected in validation ancestry" >&2
    exit 1
  fi
  if [[ "$pid" == "$stop_pid" ]]; then
    break
  fi
  pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]')"
done

echo "validation ancestry contains no scoped release secrets"
