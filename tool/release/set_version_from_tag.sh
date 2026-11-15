#!/usr/bin/env bash
# Usage: set_version_from_tag.sh <tag> <pubspec.yaml>
#
# Checks that <tag> is a plain SemVer 2.0.0 version (https://semver.org), for
# example 1.4.0 or 1.4.0-rc.1, and writes it as the `version:` of <pubspec.yaml>.
# pub.dev treats a version with a -suffix as a prerelease.
#
# The release workflow runs this in its checkout only. On main the pubspec keeps
# the 0.0.0-dev placeholder; the tag is the single source of the version.
#
# Exits 1, leaving the pubspec untouched, when the tag is not a version (a "v"
# prefix included: the pub.dev tag pattern is the bare {{version}}) or when the
# pubspec has no top-level `version:` line.
set -euo pipefail

tag="${1:-}"
pubspec="${2:-}"

# The SemVer 2.0.0 grammar, written as a POSIX extended regex.
num='(0|[1-9][0-9]*)'
ident='(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)'
semver="^${num}\.${num}\.${num}(-${ident}(\.${ident})*)?(\+[0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*)?$"

if [[ ! $tag =~ $semver ]]; then
  echo "::error::Tag '$tag' is not a plain semver version (expected MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD], no 'v' prefix)." >&2
  exit 1
fi

if [[ ! -f $pubspec ]]; then
  echo "::error::Pubspec '$pubspec' not found." >&2
  exit 1
fi

if ! grep -q '^version: ' "$pubspec"; then
  echo "::error::Pubspec '$pubspec' has no top-level 'version:' line." >&2
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
awk -v version="$tag" '
  !done && /^version: / { print "version: " version; done = 1; next }
  { print }
' "$pubspec" > "$tmp"
cat "$tmp" > "$pubspec"

echo "Set $pubspec version to $tag."
