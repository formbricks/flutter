#!/usr/bin/env bash
# Tests for check_prerelease_flag.sh. Run: bash tool/release/check_prerelease_flag_test.sh
set -uo pipefail

script="$(cd "$(dirname "$0")" && pwd)/check_prerelease_flag.sh"
failures=0

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

expect_pass() {
  local tag="$1" flag="$2" out
  if ! out="$(bash "$script" "$tag" "$flag" 2>&1)"; then
    fail "tag '$tag' with isPrerelease '$flag' should pass, got: $out"
  fi
}

expect_fail() {
  local tag="$1" flag="$2" out
  if out="$(bash "$script" "$tag" "$flag" 2>&1)"; then
    fail "tag '$tag' with isPrerelease '$flag' should fail, got: $out"
  elif [[ "$out" != *"::error::"* ]]; then
    fail "tag '$tag' with isPrerelease '$flag' failed without a GitHub error annotation: $out"
  fi
}

# A plain version is a stable release.
expect_pass 1.4.0 false
expect_fail 1.4.0 true

# A -suffix is a prerelease.
expect_pass 1.4.0-rc.1 true
expect_fail 1.4.0-rc.1 false

# Build metadata is not a prerelease suffix, even when it holds a hyphen.
expect_pass 1.4.0+build.5 false
expect_pass 1.4.0+build-5 false
expect_fail 1.4.0+build-5 true
expect_pass 1.4.0-rc.1+build.5 true
expect_fail 1.4.0-rc.1+build.5 false

# Anything but "true" or "false" (for example no GitHub release) fails.
expect_fail 1.4.0 ""
expect_fail 1.4.0 null
expect_fail 1.4.0-rc.1 TRUE

if [[ $failures -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "check_prerelease_flag: all tests passed"
