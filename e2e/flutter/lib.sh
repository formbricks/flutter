#!/usr/bin/env bash
# Shared constants and functions for the Flutter side of the SDK E2E harness. Source it; do not run
# it. The server is e2e/server (copied unchanged from the js repo); the macOS hand-off is e2e/tunnel
# (copied unchanged from the ios repo). The journey is apps/playground/patrol_test.
# Dependencies: bash, jq.
# shellcheck disable=SC2034 # constants are read by the scripts that source this file

E2E_FLUTTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E_PLAYGROUND_DIR="$(cd "${E2E_FLUTTER_DIR}/../../apps/playground" && pwd)"
E2E_JOURNEY_TARGET="patrol_test/golden_journey_test.dart"
# The Flutter SDK accepts http://, and the playground's debug manifest allows cleartext, so the
# emulator reaches the server on the runner's loopback through its 10.0.2.2 alias.
E2E_ANDROID_APP_URL="${E2E_ANDROID_APP_URL:-http://10.0.2.2:3000}"
# Never committed: the dart-defines file, the simulator pick, each attempt's reports.
E2E_FLUTTER_STATE_DIR="${E2E_FLUTTER_STATE_DIR:-${E2E_FLUTTER_DIR}/.state}"

# --- pure -----------------------------------------------------------------------------------------

# dart_defines_json <appUrl> <workspaceId> <userId> <feedback>
# Prints the journey's inputs as a --dart-define-from-file JSON object. A file, because patrol's
# --dart-define splits its value on commas.
dart_defines_json() {
  local url="$1" workspace="$2" user="$3" feedback="$4"
  [[ -n "${url}" && -n "${workspace}" && -n "${user}" && -n "${feedback}" ]] || {
    echo "dart_defines_json needs appUrl, workspaceId, userId and feedback" >&2
    return 1
  }
  jq -cn --arg url "${url}" --arg ws "${workspace}" --arg user "${user}" --arg fb "${feedback}" \
    '{APP_URL: $url, WORKSPACE_ID: $ws, E2E_USER_ID: $user, E2E_FEEDBACK: $fb}'
}

# pick_simulator <xcodeVersion> < `xcrun simctl list devices available -j`
# Prints "<udid>\t<iOS version>" of an available iPhone (else any iOS device) on the newest iOS
# runtime the given Xcode can run: macos-26 carries runtimes newer than its default Xcode. Fails when
# there is none, or when the listing is not JSON (CoreSimulator still starting).
pick_simulator() {
  local rows picked
  rows="$(jq -r --arg xcode "$1" '
    def majmin: split(".") | map(tonumber) | .[0:2];
    (.devices // {}) | to_entries[]
    | select(.key | test("SimRuntime\\.iOS-[0-9-]+$"))
    | (.key | capture("iOS-(?<v>[0-9-]+)$").v | gsub("-"; ".")) as $os
    | select(($os | majmin) <= ($xcode | majmin))
    | .value[] | select(.isAvailable != false)
    | [(if (.deviceTypeIdentifier // "") | test("iPhone") then 1 else 0 end), $os, .name, .udid]
    | @tsv' 2>/dev/null)" || return 1
  picked="$(LC_ALL=C sort -t$'\t' -k1,1nr -k2,2Vr -k3,3 <<<"${rows}" | head -n 1)"
  [[ -n "${picked}" ]] || return 1
  printf '%s\t%s\n' "$(cut -f4 <<<"${picked}")" "$(cut -f2 <<<"${picked}")"
}

# --- I/O helpers ----------------------------------------------------------------------------------

log() { printf '==> %s\n' "$*" >&2; }

die() {
  printf '::error::%s\n' "$*" >&2
  exit 1
}
