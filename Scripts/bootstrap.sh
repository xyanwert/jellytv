#!/usr/bin/env bash
#
# bootstrap.sh — one-command setup for a fresh clone of JellyTV.
#
# Verifies (and where possible installs) the required tooling, regenerates the
# branding assets, and generates the Xcode project from project.yml.
#
#   Scripts/bootstrap.sh
#   open JellyTV.xcodeproj
#
set -euo pipefail

# Always operate from the repo root (the parent of this script's directory).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m warning:\033[0m %s\n' "$*"; }
die()   { printf '\033[1;31m error:\033[0m %s\n' "$*" >&2; exit 1; }

installed=()

# 1. Xcode is mandatory and cannot be auto-installed.
if ! xcodebuild -version >/dev/null 2>&1; then
  die "Xcode is required but 'xcodebuild' was not found. Install Xcode from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"
fi
info "Xcode: $(xcodebuild -version | head -1)"

# 2. Homebrew is needed to install the remaining CLI tools.
if ! command -v brew >/dev/null 2>&1; then
  die "Homebrew is required to install XcodeGen/fastlane. Install it from https://brew.sh and re-run."
fi

# 3. XcodeGen — generates the .xcodeproj from project.yml.
if ! command -v xcodegen >/dev/null 2>&1; then
  info "Installing XcodeGen..."
  brew install xcodegen
  installed+=("xcodegen")
fi
info "XcodeGen: $(xcodegen --version)"

# 4. fastlane — release metadata + upload lanes (not needed just to build,
#    but part of a complete setup).
if ! command -v fastlane >/dev/null 2>&1; then
  info "Installing fastlane..."
  brew install fastlane
  installed+=("fastlane")
fi

# 5. Regenerate branding assets (deterministic; safe to run every time).
info "Generating branding assets..."
swift Scripts/generate-icons.swift

# 6. Generate the Xcode project.
info "Generating JellyTV.xcodeproj..."
xcodegen generate

echo
info "Done. Open the project with:  open JellyTV.xcodeproj"
if [ "${#installed[@]}" -gt 0 ]; then
  info "Installed this run: ${installed[*]}"
fi
