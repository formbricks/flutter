#!/usr/bin/env bash
# Run the playground demo app on a simulator/emulator from one command.
#
# `flutter run` cannot boot a device by itself — with none running it falls back
# to the macOS desktop target (which the app doesn't support). This script boots
# the right device if needed, then runs the app on that exact device.
#
# Usage:  ./tool/run.sh [ios|android] [extra flutter run args...]
#           ./tool/run.sh            # iOS simulator (default)
#           ./tool/run.sh android    # Android emulator
#           ./tool/run.sh ios --profile
set -euo pipefail

platform="${1:-ios}"
case "$platform" in
  ios|android) shift || true ;;
  -*) platform="ios" ;;            # first arg was a flutter flag, default platform
  *) echo "Unknown platform '$platform' (use: ios | android)" >&2; exit 2 ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root/apps/playground"

# Prefer the fvm-pinned SDK; fall back to a plain `flutter` on PATH.
if command -v fvm >/dev/null 2>&1; then
  flutter() { fvm flutter "$@"; }
fi

run_ios() {
  booted_udid() {
    xcrun simctl list devices booted \
      | grep -ioE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
      | head -1
  }
  if [[ -z "$(booted_udid)" ]]; then
    echo "No iOS simulator running — booting one..."
    flutter emulators --launch apple_ios_simulator
    echo "Waiting for the simulator to finish booting..."
    until [[ -n "$(booted_udid)" ]]; do sleep 1; done
  fi
  open -a Simulator  # bring the simulator window to the front
  local udid; udid="$(booted_udid)"
  echo "Running on iOS simulator $udid"
  exec flutter run -d "$udid" "$@"
}

run_android() {
  local adb="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}/platform-tools/adb"
  booted_serial() { "$adb" devices 2>/dev/null | awk '/emulator-[0-9]+\tdevice/ {print $1; exit}'; }
  if [[ -z "$(booted_serial)" ]]; then
    # Pick the first Android AVD that `flutter emulators` knows about.
    local avd
    avd="$(flutter emulators 2>/dev/null | awk -F '•' '$4 ~ /android/ {gsub(/^[ \t]+|[ \t]+$/,"",$1); print $1; exit}')"
    if [[ -z "$avd" ]]; then
      echo "No Android emulator (AVD) found. Create one in Android Studio." >&2
      exit 1
    fi
    echo "No Android emulator running — booting '$avd'..."
    flutter emulators --launch "$avd"
    echo "Waiting for the emulator to come online..."
    until [[ -n "$(booted_serial)" ]]; do sleep 2; done
    echo "Waiting for the emulator to finish booting..."
    "$adb" -s "$(booted_serial)" wait-for-device shell \
      'while [[ -z $(getprop sys.boot_completed) ]]; do sleep 1; done' 2>/dev/null || true
  fi
  local serial; serial="$(booted_serial)"
  echo "Running on Android emulator $serial"
  exec flutter run -d "$serial" "$@"
}

case "$platform" in
  ios) run_ios "$@" ;;
  android) run_android "$@" ;;
esac
