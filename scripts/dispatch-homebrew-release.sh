#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "usage: dispatch-homebrew-release.sh <tap-repository> <source-repository> <tag> <version> <source-commit> <correlation-id>" >&2
  exit 64
fi

tap_repository="$1"
source_repository="$2"
tag="$3"
version="$4"
source_commit="$5"
correlation_id="$6"
poll_attempts="${POLL_ATTEMPTS:-160}"
poll_interval="${POLL_INTERVAL_SECONDS:-15}"

if [[ "$tap_repository" != "SijanC147/homebrew-hextap" ]]; then
  echo "refusing to dispatch outside the canonical private tap" >&2
  exit 1
fi
if [[ "$source_repository" != "SijanC147/claude-rc-proxy" ]]; then
  echo "refusing to dispatch from a non-canonical source repository" >&2
  exit 1
fi
if [[ ! "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "Homebrew dispatch requires a stable SemVer tag" >&2
  exit 1
fi
if [[ "$version" != "${tag#v}" ]]; then
  echo "release version does not match tag" >&2
  exit 1
fi
if [[ ! "$source_commit" =~ ^[0-9a-f]{40}$ ]]; then
  echo "invalid source commit" >&2
  exit 1
fi
if [[ ! "$correlation_id" =~ ^[A-Za-z0-9._:-]+$ ]]; then
  echo "invalid correlation ID" >&2
  exit 1
fi
if [[ ! "$poll_attempts" =~ ^[1-9][0-9]*$ || ! "$poll_interval" =~ ^[0-9]+$ ]]; then
  echo "invalid polling bounds" >&2
  exit 1
fi

state_dir="$(mktemp -d)"
cleanup() {
  rm -rf -- "$state_dir"
}
trap cleanup EXIT

ruby -rjson -e '
  payload = {
    event_type: "claude-rc-proxy-release",
    client_payload: {
      correlation_id: ARGV.fetch(0),
      tag: ARGV.fetch(1),
      version: ARGV.fetch(2),
      source_commit: ARGV.fetch(3),
      source_repository: ARGV.fetch(4),
    },
  }
  File.write(ARGV.fetch(5), JSON.generate(payload))
' "$correlation_id" "$tag" "$version" "$source_commit" "$source_repository" "$state_dir/dispatch.json"

gh api --method POST "repos/$tap_repository/dispatches" \
  --input "$state_dir/dispatch.json" >/dev/null

run_id=""
for ((attempt = 1; attempt <= poll_attempts; attempt++)); do
  gh api "repos/$tap_repository/actions/workflows/claude-rc-proxy-release.yml/runs?event=repository_dispatch&per_page=100" \
    > "$state_dir/runs.json"
  run_id="$(ruby -rjson -e '
    correlation = ARGV.fetch(0)
    runs = JSON.parse(File.read(ARGV.fetch(1))).fetch("workflow_runs", [])
    match = runs.select { |run| run.fetch("display_title", "").include?("[#{correlation}]") }
                .max_by { |run| run.fetch("id", 0) }
    puts match.fetch("id") if match
  ' "$correlation_id" "$state_dir/runs.json")"
  [[ -z "$run_id" ]] || break
  sleep "$poll_interval"
done

if [[ -z "$run_id" ]]; then
  echo "timed out waiting for correlated private-tap workflow run" >&2
  exit 1
fi

for ((attempt = 1; attempt <= poll_attempts; attempt++)); do
  gh api "repos/$tap_repository/actions/runs/$run_id" > "$state_dir/run.json"
  run_state="$(ruby -rjson -e '
    run = JSON.parse(File.read(ARGV.fetch(0)))
    puts [run.fetch("status"), run["conclusion"], run.fetch("html_url")].join("\t")
  ' "$state_dir/run.json")"
  IFS=$'\t' read -r status conclusion run_url <<< "$run_state"
  if [[ "$status" == "completed" ]]; then
    if [[ "$conclusion" != "success" ]]; then
      echo "private-tap workflow failed: $run_url" >&2
      exit 1
    fi
    echo "private-tap workflow succeeded: $run_url"
    cleanup
    trap - EXIT
    exit 0
  fi
  sleep "$poll_interval"
done

echo "timed out waiting for private-tap workflow completion" >&2
exit 1
