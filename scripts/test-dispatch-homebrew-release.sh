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
cat >"$FAKE_BIN/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail

test "$1" = api
shift
method=GET
input=""
endpoint=""
api_version_seen=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --method) method="$2"; shift 2 ;;
    --input) input="$2"; shift 2 ;;
    -H)
      test "$2" = "X-GitHub-Api-Version: 2026-03-10"
      api_version_seen=true
      shift 2
      ;;
    *) endpoint="$1"; shift ;;
  esac
done
[[ "$api_version_seen" == true ]]
printf '%s %s\n' "$method" "$endpoint" >>"$FAKE_GH_STATE/calls"

case "$method $endpoint" in
  "POST repos/SijanC147/homebrew-hextap/actions/workflows/claude-rc-proxy-release.yml/dispatches")
    ruby -rjson -e '
      payload = JSON.parse(File.read(ARGV.fetch(0)))
      expected = {
        "ref" => "main",
        "return_run_details" => true,
        "inputs" => {
          "correlation_id" => "source-123-1",
          "tag" => "v1.2.3",
          "version" => "1.2.3",
          "source_commit" => "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "source_repository" => "SijanC147/claude-rc-proxy",
        },
      }
      abort "workflow dispatch payload mismatch" unless payload == expected
    ' "$input"
    if [[ "${FAKE_GH_NO_RUN_ID:-0}" == 1 ]]; then
      echo '{}'
    else
      echo '{"workflow_run_id":42,"run_url":"https://api.example.invalid/runs/42","html_url":"https://example.invalid/run/42"}'
    fi
    ;;
  "GET repos/SijanC147/homebrew-hextap/actions/runs/42")
    count_file="$FAKE_GH_STATE/run-count"
    count=0
    [[ ! -f "$count_file" ]] || count="$(cat "$count_file")"
    count=$((count + 1))
    echo "$count" >"$count_file"
    run_id=42
    event=workflow_dispatch
    path='.github/workflows/claude-rc-proxy-release.yml@refs/heads/main'
    branch=main
    repository=SijanC147/homebrew-hextap
    title='claude-rc-proxy v1.2.3 [source-123-1]'
    if [[ "${FAKE_GH_WRONG_RUN:-0}" == 1 ]]; then run_id=99; fi
    if [[ "$count" -eq 1 || "${FAKE_GH_STUCK:-0}" == 1 ]]; then
      status=in_progress
      conclusion=null
    elif [[ "${FAKE_GH_FAIL:-0}" == 1 ]]; then
      status=completed
      conclusion='"failure"'
    else
      status=completed
      conclusion='"success"'
    fi
    printf '{"id":%s,"event":"%s","path":"%s","head_branch":"%s","repository":{"full_name":"%s"},"display_title":"%s","status":"%s","conclusion":%s,"html_url":"https://example.invalid/run/42"}\n' \
      "$run_id" "$event" "$path" "$branch" "$repository" "$title" "$status" "$conclusion"
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

if grep -Eq '/contents|/git/|repos/SijanC147/homebrew-hextap/dispatches' "$FAKE_STATE/calls"; then
  echo "Actions-only credential path attempted repository contents mutation" >&2
  exit 1
fi
expected_calls=$'POST repos/SijanC147/homebrew-hextap/actions/workflows/claude-rc-proxy-release.yml/dispatches\nGET repos/SijanC147/homebrew-hextap/actions/runs/42\nGET repos/SijanC147/homebrew-hextap/actions/runs/42'
actual_calls="$(cat "$FAKE_STATE/calls")"
if [[ "$actual_calls" != "$expected_calls" ]]; then
  printf 'unexpected API call set:\n%s\n' "$actual_calls" >&2
  exit 1
fi

for failure_case in failed-run incomplete-run wrong-run missing-run-id; do
  rm -f "$FAKE_STATE/calls" "$FAKE_STATE/run-count"
  unset FAKE_GH_FAIL FAKE_GH_STUCK FAKE_GH_WRONG_RUN FAKE_GH_NO_RUN_ID
  case "$failure_case" in
    failed-run) export FAKE_GH_FAIL=1 ;;
    incomplete-run) export FAKE_GH_STUCK=1 ;;
    wrong-run) export FAKE_GH_WRONG_RUN=1 ;;
    missing-run-id) export FAKE_GH_NO_RUN_ID=1 ;;
    *) exit 2 ;;
  esac
  set +e
  POLL_ATTEMPTS=2 POLL_INTERVAL_SECONDS=0 \
    "$SCRIPT_DIR/dispatch-homebrew-release.sh" \
    SijanC147/homebrew-hextap SijanC147/claude-rc-proxy \
    v1.2.3 1.2.3 "$SOURCE_SHA" "$CORRELATION" >/dev/null 2>&1
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "dispatch failure accepted: $failure_case" >&2
    exit 1
  fi
done
unset FAKE_GH_FAIL FAKE_GH_STUCK FAKE_GH_WRONG_RUN FAKE_GH_NO_RUN_ID

for invalid_case in wrong-tap wrong-source prerelease malformed-commit malformed-correlation unsafe-correlation long-correlation; do
  args=(SijanC147/homebrew-hextap SijanC147/claude-rc-proxy v1.2.3 1.2.3 "$SOURCE_SHA" "$CORRELATION")
  case "$invalid_case" in
    wrong-tap) args[0]=other/homebrew-hextap ;;
    wrong-source) args[1]=other/claude-rc-proxy ;;
    prerelease)
      args[2]=v1.2.3-rc.1
      args[3]=1.2.3-rc.1
      ;;
    malformed-commit) args[4]=not-a-commit ;;
    malformed-correlation) args[5]='bad correlation' ;;
    unsafe-correlation) args[5]='source:123' ;;
    long-correlation) args[5]="$(printf 'a%.0s' {1..101})" ;;
    *) exit 2 ;;
  esac
  set +e
  POLL_ATTEMPTS=1 POLL_INTERVAL_SECONDS=0 \
    "$SCRIPT_DIR/dispatch-homebrew-release.sh" "${args[@]}" >/dev/null 2>&1
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "invalid dispatch accepted: $invalid_case" >&2
    exit 1
  fi
done

cleanup
trap - EXIT
echo "Actions-only workflow dispatch and exact-run polling tests passed"
