#!/usr/bin/env bash
# Tests for pr_check_summary.sh. Run: .github/scripts/pr_check_summary_test.sh
set -uo pipefail

script="$(cd "$(dirname "$0")" && pwd)/pr_check_summary.sh"
failures=0

summary_file=$(mktemp)
trap 'rm -f "$summary_file"' EXIT

# run <needs-json> <allowed-skips>: sets $status, $output and $summary.
run() {
  : >"$summary_file"
  output=$(NEEDS_JSON="$1" ALLOWED_SKIPS="$2" GITHUB_STEP_SUMMARY="$summary_file" bash "$script" 2>&1)
  status=$?
  summary=$(cat "$summary_file")
}

expect_contains() {
  local name=$1 haystack=$2 needle=$3
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: $name: missing '$needle' in:"
    printf '    %s\n' "$haystack"
    failures=$((failures + 1))
  else
    echo "ok: $name"
  fi
}

expect_status() {
  local name=$1 want=$2
  if [ "$status" -ne "$want" ]; then
    echo "FAIL: $name: exit $status, want $want"
    printf '    %s\n' "$output"
    failures=$((failures + 1))
  else
    echo "ok: $name"
  fi
}

run '{"lint":{"result":"success"},"build":{"result":"success"}}' ''
expect_status "all jobs succeeded passes" 0

run '{"lint":{"result":"success"},"build":{"result":"failure"}}' ''
expect_status "a failed job fails" 1

run '{"lint":{"result":"success"},"sonarqube":{"result":"skipped"}}' 'sonarqube e2e-tests'
expect_status "an allowed skip passes" 0

run '{"lint":{"result":"skipped"}}' 'sonarqube e2e-tests'
expect_status "a skip that is not allowed fails" 1

run '{"lint":{"result":"cancelled"}}' ''
expect_status "a cancelled job fails" 1

run '{}' ''
expect_status "no jobs at all fails" 1

run 'not json' ''
expect_status "unreadable needs fails" 1

run '{"lint":{"result":"success"},"build":{"result":"failure"}}' ''
expect_contains "the log names the failed job" "$output" "::error::build: failure"
expect_contains "the step summary lists every job" "$summary" "| lint | success |"
expect_contains "the step summary marks the failed job" "$summary" "| build | failure |"

run '{"sonarqube":{"result":"skipped"}}' 'sonarqube'
expect_contains "the step summary marks an allowed skip" "$summary" "| sonarqube | skipped (allowed) |"

if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
