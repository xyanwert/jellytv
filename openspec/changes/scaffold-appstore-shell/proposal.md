# Proposal: scaffold-appstore-shell

## Why

JellyTV will be a new native tvOS client for Jellyfin with a better UI than the existing options, plus an iOS/iPadOS companion app that acts as a pure remote control ("the chrome only"). Before any feature work starts, we want the entire release apparatus — project structure, bundle identities, icons, App Store metadata, privacy policy, signing — completed up front, so that an **empty but App Store–submittable app** exists from day one and release logistics never block feature development later.

## What Changes

- **New Xcode project (XcodeGen-defined)** at the repo root: a `project.yml` generates `JellyTV.xcodeproj` with two app targets:
  - `JellyTV` — tvOS app (SwiftUI, empty branded launch screen), bundle ID `net.graficx.jellytv`.
  - `JellyTV Remote` — iOS/iPadOS companion app (SwiftUI, empty branded shell), **same bundle ID** `net.graficx.jellytv` to enable universal purchase (one App Store product across tvOS + iOS).
- **Shared local Swift package** `JellyTVKit` (empty placeholder) that both targets link, establishing where future shared code (Jellyfin API client, models, remote-control protocol) will live.
- **Complete branding placeholders**: layered tvOS parallax App Icon (App Store 1280×768 + Home Screen 400×240), Top Shelf image (wide + standard), iOS 1024pt icon, accent color — generated programmatically, valid for submission, swappable later.
- **All Info.plist / build-setting metadata needed for release**: display name, category (`public.app-category.entertainment`), version/build scheme (`0.1.0` / auto-incrementing build), export compliance (`ITSAppUsesNonExemptEncryption = NO`), local-network usage description (companion will discover/control the TV app and Jellyfin servers), automatic signing wired to Francisco's Apple Developer team.
- **fastlane release plumbing in-repo**: `fastlane/metadata` (name, subtitle, description, keywords, support URL, privacy URL, review notes), `Fastfile` lanes for building and uploading to TestFlight/App Store, `Deliverfile`.
- **Privacy policy published via GitHub Pages** from this repo (`docs/privacy.html` or equivalent): honest, minimal policy — the app talks only to the user's own Jellyfin server, collects nothing.
- **Repo hygiene**: Swift/Xcode `.gitignore`, `README.md`, MIT (or chosen) license placeholder.
- **Developer tooling**: XcodeBuildMCP registered at project scope (`.mcp.json`) so build/run/simulator work can be driven from Claude Code — *already installed as part of this proposal*.

## Capabilities

### New Capabilities

- `tvos-app-shell`: The JellyTV tvOS app target — builds, launches to a branded empty screen, carries all identity/metadata/icon assets required for App Store submission.
- `ios-companion-shell`: The JellyTV Remote iOS/iPadOS app target — an empty branded shell sharing the tvOS app's bundle ID (universal purchase), declared as a remote-control companion in its metadata.
- `release-readiness`: Everything required to submit both shells to the App Store — fastlane metadata, privacy policy URL, export compliance, versioning, signing, App Store Connect record checklist.
- `project-tooling`: Deterministic project generation via XcodeGen (`project.yml` is the source of truth), shared `JellyTVKit` package, repo hygiene, and MCP-assisted build workflow.

### Modified Capabilities

_None — this is a greenfield repo with no existing specs._

## Impact

- **Code**: entirely new files at repo root (`project.yml`, `Apps/`, `Packages/JellyTVKit/`, `fastlane/`, `docs/`, `Scripts/`, `.gitignore`, `README.md`). No existing code is touched (repo currently contains only `openspec/` and `.claude/`).
- **External systems**: Apple Developer account (team `francisco.berridi@gmail.com`) — bundle ID registration + App Store Connect app record; GitHub Pages enabled on this repo for the privacy policy URL.
- **Dependencies/tools**: XcodeGen (installed, 2.45.4), fastlane (to be installed via Homebrew or bundler), XcodeBuildMCP (installed via `.mcp.json`), Xcode 26.6 SDKs.
- **Constraints to note**: App Review guideline 4.2 (minimum functionality) means a *truly* empty app can reach TestFlight but would likely be rejected from public App Store release — the deliverable here is "submission-ready in every mechanical respect," with actual submission expected once the first real feature lands. The Jellyfin name is used only descriptively (subtitle/description), respecting Jellyfin trademark guidance.
