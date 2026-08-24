#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(mktemp -d)"
FAKE_BIN="$TEST_ROOT/bin"
FAKE_STATE="$TEST_ROOT/state"
FORMULA="$TEST_ROOT/claude-rc-proxy.rb"
BASE_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
MOVED_SHA="ffffffffffffffffffffffffffffffffffffffff"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN" "$FAKE_STATE"
echo "formula-body" > "$FORMULA"
if command -v sha256sum >/dev/null 2>&1; then
  FORMULA_SHA="$(sha256sum "$FORMULA" | awk '{ print $1 }')"
else
  FORMULA_SHA="$(shasum -a 256 "$FORMULA" | awk '{ print $1 }')"
fi

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
    --jq) shift 2 ;;
    *) endpoint="$1"; shift ;;
  esac
done
printf '%s %s\n' "$method" "$endpoint" >> "$FAKE_GH_STATE/calls"

case "$method $endpoint" in
  "GET repos/owner/tap/git/ref/heads/main")
    count_file="$FAKE_GH_STATE/ref-count"
    count=0
    [[ ! -f "$count_file" ]] || count="$(cat "$count_file")"
    count=$((count + 1))
    echo "$count" > "$count_file"
    if [[ "${FAKE_GH_MOVE_ON_SECOND_REF:-0}" == "1" && "$count" -ge 2 ]]; then
      cat "$FAKE_GH_STATE/moved-sha"
    else
      cat "$FAKE_GH_STATE/main-sha"
    fi
    ;;
  "GET repos/owner/tap/git/commits/"*) echo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ;;
  "GET repos/owner/tap/git/trees/"*) cat "$FAKE_GH_STATE/current-blob" 2>/dev/null || true ;;
  "POST repos/owner/tap/git/blobs") echo cccccccccccccccccccccccccccccccccccccccc ;;
  "POST repos/owner/tap/git/trees") echo dddddddddddddddddddddddddddddddddddddddd ;;
  "POST repos/owner/tap/git/commits") echo eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee ;;
  "PATCH repos/owner/tap/git/refs/heads/main")
    ruby -rjson -e '
      body = JSON.parse(File.read(ARGV.fetch(0)))
      abort "force must be false" unless body["force"] == false
      abort "unexpected commit" unless body["sha"] == "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    ' "$input"
    echo eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee > "$FAKE_GH_STATE/main-sha"
    ;;
  *) echo "unsupported fake API call: $method $endpoint" >&2; exit 2 ;;
esac
FAKE_GH
chmod 755 "$FAKE_BIN/gh"

export FAKE_GH_STATE="$FAKE_STATE"
export PATH="$FAKE_BIN:$PATH"
echo "$BASE_SHA" > "$FAKE_STATE/main-sha"
echo "$MOVED_SHA" > "$FAKE_STATE/moved-sha"

bootstrap_output="$("$SCRIPT_DIR/publish-homebrew-formula.sh" \
  owner/tap "$BASE_SHA" "$FORMULA" "$FORMULA_SHA" 1.2.3)"
grep -Fq "pushed=true" <<< "$bootstrap_output"
grep -Fq "reason=published" <<< "$bootstrap_output"
test "$(cat "$FAKE_STATE/main-sha")" = eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
if grep -Fq '"force":true' "$FAKE_STATE/calls"; then
  echo "force update was requested" >&2
  exit 1
fi

echo "$MOVED_SHA" > "$FAKE_STATE/main-sha"
echo 0 > "$FAKE_STATE/ref-count"
moved_output="$("$SCRIPT_DIR/publish-homebrew-formula.sh" \
  owner/tap "$BASE_SHA" "$FORMULA" "$FORMULA_SHA" 1.2.3)"
grep -Fq "pushed=false" <<< "$moved_output"
grep -Fq "reason=moved-main" <<< "$moved_output"

echo "$BASE_SHA" > "$FAKE_STATE/main-sha"
echo 0 > "$FAKE_STATE/ref-count"
rm -f "$FAKE_STATE/current-blob"
export FAKE_GH_MOVE_ON_SECOND_REF=1
race_output="$("$SCRIPT_DIR/publish-homebrew-formula.sh" \
  owner/tap "$BASE_SHA" "$FORMULA" "$FORMULA_SHA" 1.2.3)"
unset FAKE_GH_MOVE_ON_SECOND_REF
grep -Fq "pushed=false" <<< "$race_output"
grep -Fq "reason=moved-main" <<< "$race_output"

echo "Homebrew Git Data API publication tests passed"
