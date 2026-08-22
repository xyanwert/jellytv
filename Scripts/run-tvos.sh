#!/usr/bin/env bash
#
# run-tvos.sh — build and launch JellyTV on one or more simulators.
#
#   Scripts/run-tvos.sh                    # tv only (default)
#   Scripts/run-tvos.sh tv                 # Apple TV simulator (JellyTV scheme)
#   Scripts/run-tvos.sh ipad               # iPad simulator (Remote scheme)
#   Scripts/run-tvos.sh iphone             # iPhone simulator (Remote scheme)
#   Scripts/run-tvos.sh ipad,iphone        # both, no tv
#   Scripts/run-tvos.sh tv,ipad,iphone     # all three
#   Scripts/run-tvos.sh tv --settings      # tv, straight into the Settings panel
#   Scripts/run-tvos.sh tv --mock          # tv, mock Jellyfin server — skips login/setup
#
#   JELLY_TV_SIM=<udid>     Scripts/run-tvos.sh tv       # pick a specific Apple TV sim
#   JELLY_IPAD_SIM=<udid>   Scripts/run-tvos.sh ipad     # pick a specific iPad sim
#   JELLY_IPHONE_SIM=<udid> Scripts/run-tvos.sh iphone   # pick a specific iPhone sim
#
# With a single platform, the app's console is attached (Ctrl-C to stop), same
# as before. With more than one, each is installed + launched and left
# running — there's no single console to block on, so check each Simulator
# window.
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

# Parse args: an optional comma-separated platform list (default "tv"), plus
# optional --settings / --mock flags in any position. JT_SHOW_SETTINGS only
# exists in the tvOS RootView, so it only affects the tv launch; JT_MOCK_SERVER
# (ServerConnection.swift) is shared by both apps, so it applies to all of them.
PLATFORMS_ARG="tv"
SHOW_SETTINGS=0
MOCK=0
for arg in "$@"; do
  case "${arg}" in
    --settings) SHOW_SETTINGS=1 ;;
    --mock)     MOCK=1 ;;
    *) PLATFORMS_ARG="${arg}" ;;
  esac
done

IFS=',' read -r -a PLATFORMS <<< "${PLATFORMS_ARG}"
WANT_TV=0 WANT_IPAD=0 WANT_IPHONE=0
for p in "${PLATFORMS[@]}"; do
  case "${p}" in
    tv)     WANT_TV=1 ;;
    ipad)   WANT_IPAD=1 ;;
    iphone) WANT_IPHONE=1 ;;
    "")     ;;
    *) die "Unknown platform '${p}' — expected a comma-separated mix of tv, ipad, iphone." ;;
  esac
done
TARGET_COUNT=$((WANT_TV + WANT_IPAD + WANT_IPHONE))
[ "${TARGET_COUNT}" -gt 0 ] || die "No platforms selected."

command -v xcodegen >/dev/null 2>&1 || die "XcodeGen not found — run Scripts/bootstrap.sh first."

# Pick a simulator: env override → any already-booted matching device → first available.
udid_of() { grep -oE '[0-9A-Fa-f-]{36}' | head -1; }
find_sim() {
  local pattern="$1" override="$2" sim
  sim="${override}"
  if [ -z "${sim}" ]; then
    # grep exits 1 on no match (e.g. nothing booted yet) — under `set -e` that
    # would silently kill the whole script right here, before any output, so
    # these lookups must not be allowed to trip errexit.
    sim="$(xcrun simctl list devices available | grep "${pattern}" | grep '(Booted)' | head -1 | udid_of || true)"
  fi
  if [ -z "${sim}" ]; then
    sim="$(xcrun simctl list devices available | grep "${pattern}" | head -1 | udid_of || true)"
  fi
  echo "${sim}"
}

TV_SIM="" IPAD_SIM="" IPHONE_SIM=""
if [ "${WANT_TV}" = 1 ]; then
  TV_SIM="$(find_sim 'Apple TV' "${JELLY_TV_SIM:-}")"
  [ -n "${TV_SIM}" ] || die "No Apple TV simulator found. Create one in Xcode → Settings → Platforms, or Window → Devices and Simulators."
  info "tv simulator: ${TV_SIM}"
fi
if [ "${WANT_IPAD}" = 1 ]; then
  IPAD_SIM="$(find_sim 'iPad' "${JELLY_IPAD_SIM:-}")"
  [ -n "${IPAD_SIM}" ] || die "No iPad simulator found."
  info "ipad simulator: ${IPAD_SIM}"
fi
if [ "${WANT_IPHONE}" = 1 ]; then
  IPHONE_SIM="$(find_sim 'iPhone' "${JELLY_IPHONE_SIM:-}")"
  [ -n "${IPHONE_SIM}" ] || die "No iPhone simulator found."
  info "iphone simulator: ${IPHONE_SIM}"
fi

info "Generating project…"
xcodegen generate

# Prefer a pretty formatter for readable per-file progress; fall back to raw
# xcodebuild output (which still streams) when none is installed. pipefail (set
# at the top) makes a build failure propagate through the pipe.
BEAUTIFY=(cat)
if command -v xcbeautify >/dev/null 2>&1; then BEAUTIFY=(xcbeautify)
elif command -v xcpretty >/dev/null 2>&1; then BEAUTIFY=(xcpretty)
fi

build() {
  local scheme="$1" sim="$2"
  info "Building ${scheme} (Debug, destination ${sim})…"
  xcodebuild -project JellyTV.xcodeproj -scheme "${scheme}" \
    -destination "id=${sim}" -configuration Debug \
    -derivedDataPath "${DERIVED}" \
    CODE_SIGNING_ALLOWED=NO build | "${BEAUTIFY[@]}"
}

[ "${WANT_TV}" = 1 ] && build JellyTV "${TV_SIM}"
# ipad and iphone both build from the Remote scheme — one build covers both.
if [ "${WANT_IPAD}" = 1 ] || [ "${WANT_IPHONE}" = 1 ]; then
  build Remote "${IPAD_SIM:-${IPHONE_SIM}}"
fi

APP_TV="$(/usr/bin/find "${DERIVED}/Build/Products" -maxdepth 3 -path '*appletvsimulator*' -name 'JellyTV.app' | head -1)"
APP_IOS="$(/usr/bin/find "${DERIVED}/Build/Products" -maxdepth 3 -path '*iphonesimulator*' -name 'JellyTV.app' | head -1)"
[ "${WANT_TV}" = 1 ] && [ -z "${APP_TV}" ] && die "Build succeeded but JellyTV.app (tvOS) was not found under ${DERIVED}."
{ [ "${WANT_IPAD}" = 1 ] || [ "${WANT_IPHONE}" = 1 ]; } && [ -z "${APP_IOS}" ] && die "Build succeeded but JellyTV.app (iOS) was not found under ${DERIVED}."

info "Booting simulator(s) + opening Simulator.app…"
open -a Simulator

LAUNCHED_SIMS=()
cleanup() {
  echo
  info "Stopping app(s)…"
  # ${#arr[@]} is safe on an empty array under `set -u` even on bash 3.2;
  # "${arr[@]}" itself is not (see the install_and_launch note below) — so
  # guard the loop instead of iterating directly.
  if [ "${#LAUNCHED_SIMS[@]}" -gt 0 ]; then
    for sim in "${LAUNCHED_SIMS[@]}"; do
      xcrun simctl terminate "${sim}" "${BUNDLE_ID}" >/dev/null 2>&1 || true
    done
  fi
}
trap cleanup INT TERM

# Installs + launches on one simulator. With a single overall target, attaches
# to the app's console and blocks (Ctrl-C to stop) — same as the original
# single-target behavior. Otherwise launches detached so the next target can
# start right away.
#
# Any extra args become env assignments passed to `env`. They're forwarded via
# "$@" (never a declared bash array) — macOS's stock bash is old enough that
# expanding "${arr[@]}" on a *declared-but-empty* array throws "unbound
# variable" under `set -u`, which silently killed the script right at launch
# (app got installed, never opened). "$@" doesn't have that problem even when
# empty.
install_and_launch() {
  local label="$1" sim="$2" app="$3"; shift 3
  xcrun simctl bootstatus "${sim}" -b
  info "Installing on ${label}…"
  xcrun simctl install "${sim}" "${app}"
  xcrun simctl terminate "${sim}" "${BUNDLE_ID}" >/dev/null 2>&1 || true
  LAUNCHED_SIMS+=("${sim}")
  if [ "${TARGET_COUNT}" = 1 ]; then
    info "Launching on ${label} (attached — press Ctrl-C to stop)…"
    # --console-pty attaches to the app's stdout/stderr and blocks until the
    # app exits, so the script keeps running and shows live output instead of
    # returning the instant the app is spawned.
    env "$@" xcrun simctl launch --console-pty "${sim}" "${BUNDLE_ID}"
  else
    info "Launching on ${label}…"
    env "$@" xcrun simctl launch "${sim}" "${BUNDLE_ID}" >/dev/null
  fi
}

# Build each target's extra env as a plain (non-array) string of KEY=VAL
# tokens, then splice it into the call *unquoted* so it word-splits into zero
# or more separate args — same reasoning as the "$@" note above: a scalar
# variable that happens to be empty expands to nothing under `set -u`
# without error, unlike an empty declared array.
MOCK_ENV=""
[ "${MOCK}" = 1 ] && MOCK_ENV="SIMCTL_CHILD_JT_MOCK_SERVER=1"

if [ "${WANT_TV}" = 1 ]; then
  TV_ENV="${MOCK_ENV}"
  [ "${SHOW_SETTINGS}" = 1 ] && TV_ENV="${TV_ENV} SIMCTL_CHILD_JT_SHOW_SETTINGS=1"
  # shellcheck disable=SC2086
  install_and_launch "tv" "${TV_SIM}" "${APP_TV}" ${TV_ENV}
fi
# shellcheck disable=SC2086
[ "${WANT_IPAD}" = 1 ]   && install_and_launch "ipad" "${IPAD_SIM}" "${APP_IOS}" ${MOCK_ENV}
# shellcheck disable=SC2086
[ "${WANT_IPHONE}" = 1 ] && install_and_launch "iphone" "${IPHONE_SIM}" "${APP_IOS}" ${MOCK_ENV}

[ "${TARGET_COUNT}" -gt 1 ] && info "All requested targets launched. Check each Simulator window."
