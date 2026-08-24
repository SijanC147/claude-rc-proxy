#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(mktemp -d)"
FAKE_BIN="$TEST_ROOT/bin"
FAKE_STATE="$TEST_ROOT/state"
CORRELATION="source-123-1"
SOURCE_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN" "$FAKE_STATE"
cat > "$FAKE_BIN/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail

test "$1" = api
shift
method=GET
input=""
endpoint=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --method) method="$2"; shift 2 ;;
    --input) input="$2"; shift 2 ;;
    *) endpoint="$1"; shift ;;
  esac
done

case "$method $endpoint" in
  "POST repos/SijanC147/homebrew-hextap/dispatches")
    ruby -rjson -e '
      payload = JSON.parse(File.read(ARGV.fetch(0)))
      expected = {
        "event_type" => "claude-rc-proxy-release",
        "client_payload" => {
          "correlation_id" => "source-123-1",
          "tag" => "v1.2.3",
          "version" => "1.2.3",
          "source_commit" => "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "source_repository" => "SijanC147/claude-rc-proxy",
        },
      }
      abort "dispatch payload mismatch" unless payload == expected
    ' "$input"
    ;;
  "GET repos/SijanC147/homebrew-hextap/actions/workflows/claude-rc-proxy-release.yml/runs?event=repository_dispatch&per_page=100")
    count_file="$FAKE_GH_STATE/list-count"
    count=0
    [[ ! -f "$count_file" ]] || count="$(cat "$count_file")"
    count=$((count + 1))
    echo "$count" > "$count_file"
    if [[ "$count" -eq 1 ]]; then
      echo '{"workflow_runs":[]}'
    elif [[ "${FAKE_GH_UNRELATED:-0}" == "1" ]]; then
      echo '{"workflow_runs":[{"id":99,"display_title":"claude-rc-proxy v1.2.3 [other-run]"}]}'
    else
      echo '{"workflow_runs":[{"id":42,"display_title":"claude-rc-proxy v1.2.3 [source-123-1]"}]}'
    fi
    ;;
  "GET repos/SijanC147/homebrew-hextap/actions/runs/42")
    count_file="$FAKE_GH_STATE/run-count"
    count=0
    [[ ! -f "$count_file" ]] || count="$(cat "$count_file")"
    count=$((count + 1))
    echo "$count" > "$count_file"
    if [[ "${FAKE_GH_STUCK:-0}" == "1" || "$count" -eq 1 ]]; then
      echo '{"status":"in_progress","conclusion":null,"html_url":"https://example.invalid/run/42"}'
    elif [[ "${FAKE_GH_FAIL:-0}" == "1" ]]; then
      echo '{"status":"completed","conclusion":"failure","html_url":"https://example.invalid/run/42"}'
    else
      echo '{"status":"completed","conclusion":"success","html_url":"https://example.invalid/run/42"}'
    fi
    ;;
  *) echo "unsupported fake gh call: $method $endpoint" >&2; exit 2 ;;
esac
FAKE_GH
chmod 755 "$FAKE_BIN/gh"

export FAKE_GH_STATE="$FAKE_STATE"
export PATH="$FAKE_BIN:$PATH"
POLL_ATTEMPTS=5 POLL_INTERVAL_SECONDS=0 \
  "$SCRIPT_DIR/dispatch-homebrew-release.sh" \
  SijanC147/homebrew-hextap SijanC147/claude-rc-proxy \
  v1.2.3 1.2.3 "$SOURCE_SHA" "$CORRELATION"

echo 0 > "$FAKE_STATE/list-count"
echo 0 > "$FAKE_STATE/run-count"
if FAKE_GH_FAIL=1 POLL_ATTEMPTS=5 POLL_INTERVAL_SECONDS=0 \
  "$SCRIPT_DIR/dispatch-homebrew-release.sh" \
  SijanC147/homebrew-hextap SijanC147/claude-rc-proxy \
  v1.2.3 1.2.3 "$SOURCE_SHA" "$CORRELATION" >/dev/null 2>&1; then
  echo "failed private-tap run was accepted" >&2
  exit 1
fi

if POLL_ATTEMPTS=1 POLL_INTERVAL_SECONDS=0 \
  "$SCRIPT_DIR/dispatch-homebrew-release.sh" \
  other-owner/homebrew-hextap SijanC147/claude-rc-proxy \
  v1.2.3 1.2.3 "$SOURCE_SHA" "$CORRELATION" >/dev/null 2>&1; then
  echo "non-canonical tap target was accepted" >&2
  exit 1
fi

for invalid_case in wrong-source prerelease malformed-commit malformed-correlation
do
  args=(SijanC147/homebrew-hextap SijanC147/claude-rc-proxy v1.2.3 1.2.3 "$SOURCE_SHA" "$CORRELATION")
  case "$invalid_case" in
    wrong-source) args[1]=other/claude-rc-proxy ;;
    prerelease)
      args[2]=v1.2.3-rc.1
      args[3]=1.2.3-rc.1
      ;;
    malformed-commit) args[4]=not-a-commit ;;
    malformed-correlation) args[5]='bad correlation' ;;
    *) exit 2 ;;
  esac
  if POLL_ATTEMPTS=1 POLL_INTERVAL_SECONDS=0 \
    "$SCRIPT_DIR/dispatch-homebrew-release.sh" "${args[@]}" >/dev/null 2>&1; then
    echo "invalid dispatch accepted: $invalid_case" >&2
    exit 1
  fi
done

echo 0 > "$FAKE_STATE/list-count"
if FAKE_GH_UNRELATED=1 POLL_ATTEMPTS=2 POLL_INTERVAL_SECONDS=0 \
  "$SCRIPT_DIR/dispatch-homebrew-release.sh" \
  SijanC147/homebrew-hextap SijanC147/claude-rc-proxy \
  v1.2.3 1.2.3 "$SOURCE_SHA" "$CORRELATION" >/dev/null 2>&1; then
  echo "unrelated workflow run was accepted" >&2
  exit 1
fi

echo 1 > "$FAKE_STATE/list-count"
echo 0 > "$FAKE_STATE/run-count"
if FAKE_GH_STUCK=1 POLL_ATTEMPTS=2 POLL_INTERVAL_SECONDS=0 \
  "$SCRIPT_DIR/dispatch-homebrew-release.sh" \
  SijanC147/homebrew-hextap SijanC147/claude-rc-proxy \
  v1.2.3 1.2.3 "$SOURCE_SHA" "$CORRELATION" >/dev/null 2>&1; then
  echo "incomplete workflow run was accepted" >&2
  exit 1
fi

echo "Homebrew dispatch tests passed"
