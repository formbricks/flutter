#!/usr/bin/env bash
# Builds and runs the Patrol golden journey (apps/playground/patrol_test/golden_journey_test.dart).
#   e2e/flutter/run-journey.sh android-build   build the app and test APKs (no emulator, no server)
#   e2e/flutter/run-journey.sh android         run on the booted emulator against http://10.0.2.2:3000
#   e2e/flutter/run-journey.sh ios-build       pick and boot a simulator, warm the build (no server)
#   e2e/flutter/run-journey.sh ios             run on that simulator against E2E_APP_URL (https)
# Env: E2E_USER_ID and E2E_FEEDBACK (the same values assert-response.sh checks); E2E_APP_URL for ios.
# The journey is retried once inside this step: the merge queue drops a PR before anyone could re-run
# the job. Each attempt's output, test results and device log go to $E2E_REPORT_DIR.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# The workspace id lives in the server harness; read it in a subshell so the two libs stay apart.
# shellcheck source-path=SCRIPTDIR source=../server/lib.sh
E2E_WORKSPACE_ID="$(source "${E2E_FLUTTER_DIR}/../server/lib.sh" && printf '%s' "${E2E_WORKSPACE_ID}")"

: "${E2E_USER_ID:?set E2E_USER_ID to the userId the journey identifies as}"
: "${E2E_FEEDBACK:?set E2E_FEEDBACK to the open-text answer the journey types}"
report_dir="${E2E_REPORT_DIR:-${E2E_FLUTTER_DIR}/reports}"
defines_file="${E2E_FLUTTER_STATE_DIR}/dart-defines.json"
simulator_file="${E2E_FLUTTER_STATE_DIR}/simulator"
export PATROL_ANALYTICS_ENABLED=false
mkdir -p "${E2E_FLUTTER_STATE_DIR}" "${report_dir}"

write_defines() {
  dart_defines_json "$1" "${E2E_WORKSPACE_ID}" "${E2E_USER_ID}" "${E2E_FEEDBACK}" >"${defines_file}"
}

patrol_in_playground() {
  (cd "${E2E_PLAYGROUND_DIR}" && patrol "$@" --target "${E2E_JOURNEY_TARGET}" \
    --dart-define-from-file="${defines_file}" --no-label)
}

android_device_log() { adb logcat -d -v threadtime; }
ios_device_log() {
  xcrun simctl spawn "$(cut -f1 "${simulator_file}")" log show --last 15m --style compact \
    --predicate 'process == "Runner" OR process == "RunnerUITests-Runner"'
}

# attempt <n> <android|ios> <patrol args...>
attempt() {
  local n="$1" platform="$2" status=0 dir
  shift 2
  dir="${report_dir}/attempt-${n}"
  mkdir -p "${dir}"
  log "Golden journey, attempt ${n}"
  patrol_in_playground "$@" 2>&1 | tee "${dir}/patrol.log" || status=$?
  "${platform}_device_log" >"${dir}/device.log" 2>&1 || true
  for results in build/app/outputs/androidTest-results build/ios_results; do
    [[ -e "${E2E_PLAYGROUND_DIR}/${results}" ]] && cp -R "${E2E_PLAYGROUND_DIR}/${results}" "${dir}/" || true
  done
  return "${status}"
}

run_with_one_retry() {
  if attempt 1 "$@"; then
    return 0
  fi
  printf '::warning::%s\n' "The golden journey failed on the first attempt; retrying once."
  attempt 2 "$@"
}

pick_and_boot_simulator() {
  local xcode try picked udid
  xcode="$(xcodebuild -version | sed -n 's/^Xcode //p')"
  # On a fresh macos-26 runner CoreSimulator can still be starting and list nothing.
  for try in 1 2 3 4 5 6; do
    if picked="$(xcrun simctl list devices available -j 2>/dev/null | pick_simulator "${xcode}")"; then
      break
    fi
    log "No iOS simulator listed yet (attempt ${try}), retrying"
    sleep 10
  done
  [[ -n "${picked:-}" ]] || die "no iOS simulator available for Xcode ${xcode}"
  printf '%s\n' "${picked}" >"${simulator_file}"
  udid="$(cut -f1 <<<"${picked}")"
  log "Booting simulator ${udid} (iOS $(cut -f2 <<<"${picked}"))"
  xcrun simctl boot "${udid}" 2>/dev/null || true
  xcrun simctl bootstatus "${udid}" -b >/dev/null
}

case "${1:-}" in
  android-build)
    write_defines "${E2E_ANDROID_APP_URL}"
    patrol_in_playground build android
    ;;
  android)
    write_defines "${E2E_ANDROID_APP_URL}"
    adb logcat -c || true
    run_with_one_retry android test
    ;;
  ios-build)
    pick_and_boot_simulator
    # The tunnel URL is not known yet. This build resolves the Swift packages and fills Xcode's
    # build cache, so the build inside `ios` mostly recompiles the Dart the URL changes.
    write_defines "https://tunnel.invalid"
    patrol_in_playground build ios --simulator
    ;;
  ios)
    : "${E2E_APP_URL:?set E2E_APP_URL to the server https URL (the tunnel)}"
    [[ -s "${simulator_file}" ]] || die "run '$0 ios-build' first"
    udid="$(cut -f1 "${simulator_file}")"
    os="$(cut -f2 "${simulator_file}")"
    write_defines "${E2E_APP_URL}"
    run_with_one_retry ios test --device "${udid}" --ios "${os}"
    ;;
  *)
    echo "usage: $0 android-build|android|ios-build|ios" >&2
    exit 2
    ;;
esac
