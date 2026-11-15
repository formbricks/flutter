#!/usr/bin/env bash
# Decides the "PR Check Summary" result, the only required check.
#
# Inputs (environment):
#   NEEDS_JSON     toJSON(needs) of the summary job.
#   ALLOWED_SKIPS  space-separated job ids that may be skipped on this run
#                  (e.g. "sonarqube" on fork PRs). Every other job must succeed.
#
# Exits 0 only if every job succeeded or was an allowed skip. Writes a table of
# results to $GITHUB_STEP_SUMMARY when it is set.
# Tests: .github/scripts/pr-check-summary.test.sh
set -euo pipefail

allowed=" ${ALLOWED_SKIPS:-} "
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
