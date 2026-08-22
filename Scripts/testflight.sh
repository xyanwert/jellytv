#!/usr/bin/env bash
#
# testflight.sh — build + upload JellyTV (tvOS + iPad) to TestFlight via fastlane.
#
#   Scripts/testflight.sh
#
# Wraps two existing fastlane lanes:
#   1. `fastlane ios bump`  — increments the shared build number in project.yml
#      (Apple rejects re-uploading a build number that's already been used).
#   2. `fastlane ios beta`  — archives + uploads both targets to TestFlight.
#
# tv + ipad only, for now: the Remote target is iPad-only (TARGETED_DEVICE_FAMILY
# "2" in project.yml) until iPhone layout support lands, so `fastlane ios beta`
# already covers exactly these two platforms — nothing to select here.
#
# Requires fastlane/.env (copy fastlane/.env.example) with an App Store Connect
# API key. See the "Release" section in README.md for first-time setup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v fastlane >/dev/null 2>&1 || die "fastlane not found — see https://docs.fastlane.tools/#installing-fastlane"
[ -f fastlane/.env ] || die "fastlane/.env not found — copy fastlane/.env.example and fill in your App Store Connect API key."

# Dirty tree is allowed (fastlane builds from the working tree, not HEAD) but
# worth a heads-up before shipping a beta build from it.
if [ -n "$(git status --porcelain)" ]; then
  warn "Working tree has uncommitted changes:"
  git status --short
  read -r -p "Continue anyway? [y/N] " reply
  case "${reply}" in
    y|Y|yes|YES) ;;
    *) die "Aborted." ;;
  esac
fi

info "Bumping build number…"
fastlane ios bump

info "Building + uploading tvOS and iPad to TestFlight…"
fastlane ios beta

info "Done — check App Store Connect → TestFlight for processing status."
