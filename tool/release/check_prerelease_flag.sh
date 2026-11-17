#!/usr/bin/env bash
# Usage: check_prerelease_flag.sh <tag> <is-prerelease>
#
# Fails the release when the GitHub release's "Set as a pre-release" flag
# (<is-prerelease>, from `gh release view --json isPrerelease`: "true" or
# "false") disagrees with the tag: a tag with a SemVer prerelease suffix
# (1.4.0-rc.1) must be a pre-release, and a plain version (1.4.0) must not be.
# Build metadata (+build-5) is not a prerelease suffix.
#
# The tag's format is checked by set_version_from_tag.sh. Any other
# <is-prerelease> value, for example when there is no GitHub release for the
# tag, fails too.
set -euo pipefail

tag="${1:-}"
is_prerelease="${2:-}"

core="${tag%%+*}"
if [[ $core == *-* ]]; then
  want=true
else
  want=false
fi

case "$is_prerelease" in
  true | false) ;;
  *)
    echo "::error::Could not read the pre-release flag of the GitHub release for $tag (got '$is_prerelease'). Publish a GitHub release to create the tag." >&2
    exit 1
    ;;
esac

if [[ $is_prerelease != "$want" ]]; then
  if [[ $want == true ]]; then
    echo "::error::$tag has a prerelease suffix, but its GitHub release is not marked as a pre-release. Tick \"Set as a pre-release\" and re-run." >&2
  else
    echo "::error::$tag is a stable version, but its GitHub release is marked as a pre-release. Untick \"Set as a pre-release\" and re-run." >&2
  fi
  exit 1
fi

echo "The GitHub release for $tag is correctly marked as $([[ $want == true ]] && echo "a pre-release" || echo "a stable release")."
