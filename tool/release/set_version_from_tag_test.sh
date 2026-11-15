#!/usr/bin/env bash
# Tests for set_version_from_tag.sh. Run: bash tool/release/set_version_from_tag_test.sh
set -uo pipefail

script="$(cd "$(dirname "$0")" && pwd)/set_version_from_tag.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

# A pubspec shaped like packages/formbricks/pubspec.yaml on main.
new_pubspec() {
  cat > "$work/pubspec.yaml" <<'YAML'
name: formbricks
description: >-
  Formbricks Flutter SDK.
version: 0.0.0-dev
homepage: https://formbricks.com

environment:
  sdk: ^3.6.0
YAML
}

expect_written() {
  local tag="$1"
  new_pubspec
  if ! out="$(bash "$script" "$tag" "$work/pubspec.yaml" 2>&1)"; then
    fail "expected tag '$tag' to be accepted, got: $out"
    return
  fi
  local versions
  versions="$(grep -c '^version: ' "$work/pubspec.yaml")"
  if [[ "$versions" != "1" ]]; then
    fail "tag '$tag': expected exactly one version line, found $versions"
  fi
  if ! grep -qx "version: $tag" "$work/pubspec.yaml"; then
    fail "tag '$tag': pubspec version not set, got: $(grep '^version:' "$work/pubspec.yaml")"
  fi
  # Every other line is left alone.
  if ! grep -qx 'homepage: https://formbricks.com' "$work/pubspec.yaml" ||
    ! grep -qx '  sdk: ^3.6.0' "$work/pubspec.yaml"; then
    fail "tag '$tag': other pubspec lines changed"
  fi
}

expect_rejected() {
  local tag="$1"
  new_pubspec
  local before
  before="$(cat "$work/pubspec.yaml")"
  if out="$(bash "$script" "$tag" "$work/pubspec.yaml" 2>&1)"; then
    fail "expected tag '$tag' to be rejected, got: $out"
  fi
  if [[ "$(cat "$work/pubspec.yaml")" != "$before" ]]; then
    fail "tag '$tag' was rejected but the pubspec changed"
  fi
}

# Stable and prerelease versions ship; pub.dev treats a -suffix as a prerelease.
expect_written "1.4.0"
expect_written "0.0.1"
expect_written "10.20.30"
expect_written "1.4.0-rc.1"
expect_written "1.4.0-beta"
expect_written "1.4.0-alpha.0.valid"
expect_written "1.4.0+build.5"

# Anything else fails the release run before the pubspec is touched.
expect_rejected "v1.4.0"
expect_rejected ""
expect_rejected "1.4"
expect_rejected "1.4.0.1"
expect_rejected "01.4.0"
expect_rejected "1.04.0"
expect_rejected "1.4.0-"
expect_rejected "1.4.0-rc..1"
expect_rejected "1.4.0-01"
expect_rejected "1.4.0 "
expect_rejected "release-1.4.0"
expect_rejected $'1.4.0\n2.0.0'

# A pubspec without a top-level version line is an error, not a silent no-op.
printf 'name: formbricks\n  version: nested\n' > "$work/pubspec.yaml"
if out="$(bash "$script" "1.4.0" "$work/pubspec.yaml" 2>&1)"; then
  fail "expected a pubspec without a version line to be rejected, got: $out"
fi

# A missing pubspec is an error.
if out="$(bash "$script" "1.4.0" "$work/missing.yaml" 2>&1)"; then
  fail "expected a missing pubspec to be rejected, got: $out"
fi

if [[ $failures -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "set_version_from_tag: all tests passed"
