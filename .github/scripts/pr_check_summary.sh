#!/usr/bin/env bash
# Decides the "PR Check Summary" result, the only required check. Every job
# must succeed, except these skips:
#   - sonarqube and e2e-tests on a PR from a fork, which gets no secrets;
#   - dependency-review on a push to main, where there is nothing to compare.
#
# Inputs (environment):
#   NEEDS_JSON   toJSON(needs) of the summary job.
#   EVENT_NAME   github.event_name.
#   IS_FORK_PR   "true" for a PR whose head lives in another repository.
#
# Exits 0 only if every job succeeded or was an allowed skip. Writes a table of
# results to $GITHUB_STEP_SUMMARY when it is set.
# Tests: .github/scripts/pr_check_summary_test.sh
set -euo pipefail

allowed=" "
if [ "${EVENT_NAME:-}" = "pull_request" ] && [ "${IS_FORK_PR:-}" = "true" ]; then
  allowed+="sonarqube e2e-tests "
fi
if [ "${EVENT_NAME:-}" = "push" ]; then
  allowed+="dependency-review "
fi
step_summary=${GITHUB_STEP_SUMMARY:-/dev/null}

if ! rows=$(jq -er 'to_entries | if length == 0 then error("no jobs") else .[] | [.key, .value.result] | @tsv end' <<<"${NEEDS_JSON:-}"); then
  echo "::error::Could not read job results from NEEDS_JSON."
  exit 1
fi

{
  echo "| Job | Result |"
  echo "| --- | --- |"
} >>"$step_summary"

failed=0
while IFS=$'\t' read -r job result; do
  label=$result
  if [ "$result" = "skipped" ] && [[ "$allowed" == *" $job "* ]]; then
    label="skipped (allowed)"
  elif [ "$result" != "success" ]; then
    echo "::error::$job: $result"
    failed=1
  fi
  echo "| $job | $label |" >>"$step_summary"
done <<<"$rows"

exit "$failed"
