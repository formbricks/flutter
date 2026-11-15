#!/usr/bin/env bash
# Unit tests for the pure functions in e2e/flutter/lib.sh. Needs bash and jq only.
# Run: e2e/flutter/test/lib.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=../lib.sh
source "${HERE}/../lib.sh"

failures=0
passes=0

pass() { passes=$((passes + 1)); }
fail() {
  failures=$((failures + 1))
  printf 'FAIL: %s\n' "$1" >&2
  [[ $# -gt 1 ]] && printf '  %s\n' "${@:2}" >&2
  return 0
}

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass; else fail "$1" "expected: $3" "actual:   $2"; fi
}

assert_json_eq() {
  if jq -e --argjson a "$2" --argjson b "$3" -n '$a == $b' >/dev/null 2>&1; then
    pass
  else
    fail "$1" "expected: $3" "actual:   $2"
  fi
}

# --- dart-defines file ----------------------------------------------------------------------------

assert_json_eq "dart defines carry the app URL, workspace, user and feedback" \
  "$(dart_defines_json https://abc.trycloudflare.com clsdkqaws00000000000000001 qa-user-1-1 'Golden journey feedback 1')" \
  '{"APP_URL":"https://abc.trycloudflare.com","WORKSPACE_ID":"clsdkqaws00000000000000001","E2E_USER_ID":"qa-user-1-1","E2E_FEEDBACK":"Golden journey feedback 1"}'

# patrol's --dart-define splits its value on commas; the file must keep them.
assert_json_eq "commas, quotes and backslashes survive" \
  "$(dart_defines_json http://10.0.2.2:3000 ws u 'a, "b" \c')" \
  '{"APP_URL":"http://10.0.2.2:3000","WORKSPACE_ID":"ws","E2E_USER_ID":"u","E2E_FEEDBACK":"a, \"b\" \\c"}'

if dart_defines_json http://10.0.2.2:3000 ws u '' >/dev/null 2>&1; then
  fail "an empty feedback is rejected"
else
  pass
fi

if dart_defines_json '' ws u f >/dev/null 2>&1; then
  fail "an empty app URL is rejected"
else
  pass
fi

# --- simulator pick -------------------------------------------------------------------------------

simctl_json='{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
      {"name": "iPhone 17", "udid": "NEWER-RUNTIME", "isAvailable": true,
       "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17"}
    ],
    "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
      {"name": "iPad Pro 13-inch (M5)", "udid": "IPAD-26-2", "isAvailable": true,
       "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5"},
      {"name": "iPhone 17 Pro", "udid": "IPHONE-26-2", "isAvailable": true,
       "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"},
      {"name": "iPhone Air", "udid": "BROKEN", "isAvailable": false,
       "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-Air"}
    ],
    "com.apple.CoreSimulator.SimRuntime.iOS-18-6": [
      {"name": "iPhone 16", "udid": "IPHONE-18-6", "isAvailable": true,
       "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16"}
    ],
    "com.apple.CoreSimulator.SimRuntime.watchOS-26-2": [
      {"name": "Apple Watch", "udid": "WATCH", "isAvailable": true,
       "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.Apple-Watch"}
    ]
  }
}'

assert_eq "picks an available iPhone on the newest runtime the Xcode can run" \
  "$(pick_simulator 26.3 <<<"${simctl_json}")" $'IPHONE-26-2\t26.2'

assert_eq "an older Xcode falls back to its own runtime" \
  "$(pick_simulator 18.6 <<<"${simctl_json}")" $'IPHONE-18-6\t18.6'

assert_eq "takes an iPad when there is no iPhone" \
  "$(pick_simulator 26.3 <<<'{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-2":[{"name":"iPad","udid":"IPAD","isAvailable":true,"deviceTypeIdentifier":"x.iPad"}]}}')" \
  $'IPAD\t26.2'

if pick_simulator 26.3 <<<'{"devices":{}}' >/dev/null 2>&1; then
  fail "no simulator is a failure"
else
  pass
fi

if pick_simulator 26.3 <<<'CoreSimulator is starting' >/dev/null 2>&1; then
  fail "a listing that is not JSON is a failure"
else
  pass
fi

printf '%d passed, %d failed\n' "${passes}" "${failures}"
[[ ${failures} -eq 0 ]]
