#!/usr/bin/env bash
# Usage: pub_version.sh status|wait <package> <version>
#
# Asks the pub.dev API whether <package> <version> is published. pub.dev files
# a version with a -suffix under prereleases on its own, so the version itself
# is the channel.
#
#   status  prints "published" or "missing". Exits 2 on any other answer, so
#           a pub.dev outage fails the run instead of looking like "missing".
#           The release workflow skips the publish when it prints "published".
#   wait    polls until pub.dev serves the version, riding out errors, and
#           exits 1 after PUB_WAIT_TIMEOUT seconds (default 900), polling every
#           PUB_WAIT_INTERVAL seconds (default 15). The verify job runs it.
#
# PUB_HOSTED_URL overrides the registry (default https://pub.dev), as it does
# for `dart pub`.
set -euo pipefail

command="${1:-}"
package="${2:-}"
version="${3:-}"
registry="${PUB_HOSTED_URL:-https://pub.dev}"

# Prints published, missing or error for one request.
check() {
  local body status
  body="$(mktemp)"
  status="$(curl --silent --show-error --max-time 30 --output "$body" --write-out '%{http_code}' \
    "$registry/api/packages/$package/versions/${version//+/%2B}")" || status="000"
  if [[ $status == "200" ]] && [[ "$(jq -r '.version // empty' "$body" 2> /dev/null)" == "$version" ]]; then
    echo published
  elif [[ $status == "404" ]]; then
    echo missing
  else
    echo "pub.dev answered HTTP $status for $package $version." >&2
    echo error
  fi
  rm -f "$body"
}

case "$command" in
  status)
    result="$(check)"
    [[ $result == "error" ]] && exit 2
    echo "$result"
    ;;
  wait)
    timeout="${PUB_WAIT_TIMEOUT:-900}"
    interval="${PUB_WAIT_INTERVAL:-15}"
    deadline=$((SECONDS + timeout))
    while true; do
      if [[ "$(check)" == "published" ]]; then
        echo "pub.dev serves $package $version."
        exit 0
      fi
      if ((SECONDS + interval > deadline)); then
        echo "::error::pub.dev did not serve $package $version within ${timeout}s." >&2
        exit 1
      fi
      echo "pub.dev does not serve $package $version yet; checking again in ${interval}s."
      sleep "$interval"
    done
    ;;
  *)
    echo "usage: pub_version.sh status|wait <package> <version>" >&2
    exit 64
    ;;
esac
