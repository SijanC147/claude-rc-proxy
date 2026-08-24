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
poll_attempts="${POLL_ATTEMPTS:-840}"
poll_interval="${POLL_INTERVAL_SECONDS:-15}"
workflow="claude-rc-proxy-release.yml"
api_version="2026-03-10"

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
if [[ ! "$correlation_id" =~ ^[A-Za-z0-9._-]{1,100}$ ]]; then
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
    ref: "main",
    return_run_details: true,
    inputs: {
      correlation_id: ARGV.fetch(0),
      tag: ARGV.fetch(1),
      version: ARGV.fetch(2),
      source_commit: ARGV.fetch(3),
      source_repository: ARGV.fetch(4),
    },
  }
  File.write(ARGV.fetch(5), JSON.generate(payload))
' "$correlation_id" "$tag" "$version" "$source_commit" "$source_repository" "$state_dir/dispatch.json"

gh api --method POST \
  -H "X-GitHub-Api-Version: $api_version" \
  "repos/$tap_repository/actions/workflows/$workflow/dispatches" \
  --input "$state_dir/dispatch.json" >"$state_dir/dispatch-response.json"

IFS=$'\t' read -r run_id run_url <<<"$(ruby -rjson -e '
  response = JSON.parse(File.read(ARGV.fetch(0)))
  run_id = response.fetch("workflow_run_id")
  abort "workflow dispatch did not return a positive run ID" unless run_id.is_a?(Integer) && run_id.positive?
  puts [run_id, response.fetch("html_url")].join("\t")
' "$state_dir/dispatch-response.json")"

for ((attempt = 1; attempt <= poll_attempts; attempt++)); do
  gh api -H "X-GitHub-Api-Version: $api_version" \
    "repos/$tap_repository/actions/runs/$run_id" >"$state_dir/run.json"
  run_state="$(ruby -rjson -e '
    expected_id = Integer(ARGV.fetch(0))
    correlation = ARGV.fetch(1)
    repository = ARGV.fetch(2)
    run = JSON.parse(File.read(ARGV.fetch(3)))
    abort "workflow run ID mismatch" unless run.fetch("id") == expected_id
    abort "unexpected workflow event" unless run.fetch("event") == "workflow_dispatch"
    abort "unexpected workflow path" unless run.fetch("path") == ".github/workflows/claude-rc-proxy-release.yml"
    abort "workflow did not run from tap main" unless run.fetch("head_branch") == "main"
    abort "workflow repository mismatch" unless run.dig("repository", "full_name") == repository
    abort "workflow correlation mismatch" unless run.fetch("display_title", "").include?("[#{correlation}]")
    puts [run.fetch("status"), run["conclusion"], run.fetch("html_url")].join("\t")
  ' "$run_id" "$correlation_id" "$tap_repository" "$state_dir/run.json")"
  IFS=$'\t' read -r status conclusion current_run_url <<<"$run_state"
  if [[ "$status" == "completed" ]]; then
    if [[ "$conclusion" != "success" ]]; then
      echo "private-tap workflow failed: $current_run_url" >&2
      exit 1
    fi
    echo "private-tap workflow succeeded: $current_run_url"
    cleanup
    trap - EXIT
    exit 0
  fi
  sleep "$poll_interval"
done

echo "timed out waiting for private-tap workflow completion: $run_url" >&2
exit 1
