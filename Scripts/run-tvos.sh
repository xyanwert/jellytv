#!/usr/bin/env bash
#
# run-tvos.sh — build and launch the JellyTV tvOS app on a simulator.
#
#   Scripts/run-tvos.sh              # build + run Home on an Apple TV simulator
#   Scripts/run-tvos.sh --settings   # launch straight into the Settings panel
#   JELLY_TV_SIM=<udid> Scripts/run-tvos.sh   # pick a specific simulator
#
# This is for *seeing the app run* locally. It is NOT the release path — signed
# archives + TestFlight uploads live in fastlane (see fastlane/Fastfile).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

BUNDLE_ID="net.graficx.jellytv"
DERIVED="build/DerivedData"
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m error:\033[0m %s\n' "$*" >&2; exit 1; }

# Optional flag: open the Settings panel at launch (screenshot/demo hook).
LAUNCH_ENV=()
if [ "${1:-}" = "--settings" ]; then
  LAUNCH_ENV=(SIMCTL_CHILD_JT_SHOW_SETTINGS=1)
fi

command -v xcodegen >/dev/null 2>&1 || die "XcodeGen not found — run Scripts/bootstrap.sh first."

# 1. Pick a simulator: env override → any already-booted Apple TV → first available.
udid_of() { grep -oE '[0-9A-Fa-f-]{36}' | head -1; }
SIM="${JELLY_TV_SIM:-}"
if [ -z "${SIM}" ]; then
  SIM="$(xcrun simctl list devices available | grep 'Apple TV' | grep '(Booted)' | head -1 | udid_of)"
fi
if [ -z "${SIM}" ]; then
  SIM="$(xcrun simctl list devices available | grep 'Apple TV' | head -1 | udid_of)"
fi
[ -n "${SIM}" ] || die "No Apple TV simulator found. Create one in Xcode → Settings → Platforms, or Window → Devices and Simulators."
info "Simulator: ${SIM}"

# 2. Generate the project and build for that simulator.
info "Generating project…"
xcodegen generate >/dev/null

info "Building JellyTV (Debug, tvOS Simulator)…"
xcodebuild -project JellyTV.xcodeproj -scheme JellyTV \
  -destination "id=${SIM}" -configuration Debug \
  -derivedDataPath "${DERIVED}" \
  CODE_SIGNING_ALLOWED=NO build >/dev/null

APP="$(/usr/bin/find "${DERIVED}/Build/Products" -maxdepth 3 -name 'JellyTV.app' | head -1)"
[ -n "${APP}" ] || die "Build succeeded but JellyTV.app was not found under ${DERIVED}."

# 3. Boot the simulator, bring the Simulator app forward, install, and launch.
info "Booting simulator + opening Simulator.app…"
open -a Simulator
xcrun simctl bootstatus "${SIM}" -b >/dev/null 2>&1

info "Installing + launching…"
xcrun simctl install "${SIM}" "${APP}"
xcrun simctl terminate "${SIM}" "${BUNDLE_ID}" >/dev/null 2>&1 || true
env "${LAUNCH_ENV[@]}" xcrun simctl launch "${SIM}" "${BUNDLE_ID}"

echo
info "Running. Use the Simulator's remote (Ctrl/⌘ + arrow keys) to move focus."
info "In Xcode you can also just press Run (⌘R) on the JellyTV scheme."
