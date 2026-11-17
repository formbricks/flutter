#!/usr/bin/env bash
# Tests for pr_check_summary.sh. Run: .github/scripts/pr_check_summary_test.sh
set -uo pipefail

script="$(cd "$(dirname "$0")" && pwd)/pr_check_summary.sh"
failures=0

summary_file=$(mktemp)
trap 'rm -f "$summary_file"' EXIT

# run <needs-json> <event-name> <is-fork-pr>: sets $status, $output and $summary.
run() {
  : >"$summary_file"
  output=$(NEEDS_JSON="$1" EVENT_NAME="$2" IS_FORK_PR="$3" GITHUB_STEP_SUMMARY="$summary_file" bash "$script" 2>&1)
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

skipped_secrets='{"lint":{"result":"success"},"sonarqube":{"result":"skipped"},"e2e-tests":{"result":"skipped"}}'
skipped_review='{"lint":{"result":"success"},"dependency-review":{"result":"skipped"}}'

run '{"lint":{"result":"success"},"build":{"result":"success"}}' pull_request false
expect_status "all jobs succeeded passes" 0

run '{"lint":{"result":"success"},"build":{"result":"failure"}}' pull_request false
expect_status "a failed job fails" 1

run '{"lint":{"result":"cancelled"}}' push false
expect_status "a cancelled job fails" 1

# sonarqube and e2e-tests need secrets, which only fork PRs lack.
run "$skipped_secrets" pull_request true
expect_status "sonarqube and e2e-tests may skip on a fork PR" 0

run "$skipped_secrets" pull_request false
expect_status "sonarqube and e2e-tests may not skip on a same-repo PR (Dependabot included)" 1

run "$skipped_secrets" merge_group false
expect_status "sonarqube and e2e-tests may not skip in the merge queue" 1

run "$skipped_secrets" push true
expect_status "the fork flag only counts on pull_request" 1

# dependency-review has nothing to compare on a push to main.
run "$skipped_review" push false
expect_status "dependency-review may skip on push" 0

run "$skipped_review" pull_request false
expect_status "dependency-review may not skip on a PR" 1

run "$skipped_review" pull_request true
expect_status "dependency-review may not skip on a fork PR" 1

run "$skipped_review" merge_group false
expect_status "dependency-review may not skip in the merge queue" 1

run '{"lint":{"result":"skipped"}}' pull_request true
expect_status "any other skip fails, even on a fork PR" 1

run '{"lint":{"result":"skipped"}}' push false
expect_status "any other skip fails on push" 1

run '{}' pull_request false
expect_status "no jobs at all fails" 1

run 'not json' pull_request false
expect_status "unreadable needs fails" 1

run '{"lint":{"result":"success"},"build":{"result":"failure"}}' pull_request false
expect_contains "the log names the failed job" "$output" "::error::build: failure"
expect_contains "the step summary lists every job" "$summary" "| lint | success |"
expect_contains "the step summary marks the failed job" "$summary" "| build | failure |"

run '{"sonarqube":{"result":"skipped"}}' pull_request true
expect_contains "the step summary marks an allowed skip" "$summary" "| sonarqube | skipped (allowed) |"

if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
