# Design: scaffold-appstore-shell

## Context

Greenfield repo (only `openspec/` and `.claude/` exist). Target environment: macOS with Xcode 26.6 (tvOS 26 / iOS 26 SDKs), XcodeGen 2.45.4, Node 24 (for MCP servers). Owner has a paid Apple Developer account (`francisco.berridi@gmail.com`); the Team ID must be read from Xcode/Keychain during implementation. Decisions already made with the user:

- App name **JellyTV**, bundle ID **`net.graficx.jellytv`** on both platforms (universal purchase).
- Project defined with **XcodeGen**; iOS companion shell scaffolded **now**; metadata managed with **fastlane in-repo**; **generated placeholder icons**; privacy policy on **GitHub Pages**.

## Goals / Non-Goals

**Goals:**
- An empty-but-branded tvOS app and iOS companion shell that build, run, archive, and are mechanically submittable to App Store Connect (TestFlight-ready).
- Every release detail resolved now: identity, versioning, icons, metadata, privacy policy, privacy manifests, export compliance, signing.
- Deterministic, CLI-drivable project workflow (XcodeGen + fastlane + XcodeBuildMCP).

**Non-Goals:**
- Any actual Jellyfin functionality (server connect, browsing, playback) — future changes.
- The remote-control protocol between companion and TV app — future change (only its Info.plist/network prerequisites are laid down).
- CI (GitHub Actions / Xcode Cloud), localization beyond `en-US`, final artwork, public App Store release (blocked by guideline 4.2 until a real feature ships).

## Decisions

### D1 — Repo layout
```
project.yml                    # XcodeGen source of truth
Apps/
  JellyTV/                     # tvOS app target
    Sources/                   #   JellyTVApp.swift, RootView.swift
    Resources/Assets.xcassets  #   Brand assets (layered icon, top shelf), AccentColor
    Support/                   #   PrivacyInfo.xcprivacy; Info.plist keys live in project.yml
  Remote/                      # iOS/iPadOS companion target
    Sources/
    Resources/Assets.xcassets  #   AppIcon (1024 single-size), AccentColor
    Support/
Packages/JellyTVKit/           # shared local SwiftPM package (+ its test target)
fastlane/                      # Fastfile, Appfile, Deliverfile, metadata/en-US/*, screenshots/
Scripts/                       # bootstrap.sh, generate-icons.swift
docs/privacy/index.html        # GitHub Pages privacy policy
.gitignore  README.md  LICENSE  .mcp.json
```

### D2 — XcodeGen with gitignored `.xcodeproj`
`project.yml` is the single source of truth; `JellyTV.xcodeproj` is generated and **gitignored**. `Scripts/bootstrap.sh` regenerates it on a fresh clone. Rationale: no pbxproj merge conflicts, target/settings changes are reviewable YAML, and Claude Code can maintain the project without touching pbxproj. Trade-off (must re-run `xcodegen` after structural changes) is mitigated by the bootstrap script and a README note. *Alternative rejected:* checked-in `.xcodeproj` with synchronized folders — more familiar but machine-unfriendly; Tuist — heavier than a 2-target project warrants.

### D3 — Same bundle ID on both targets → universal purchase
Both targets use `PRODUCT_BUNDLE_IDENTIFIER = net.graficx.jellytv`. In App Store Connect this creates **one app record** with two platforms (universal purchase). This is deliberate and effectively irreversible, per user decision. Both targets share one `MARKETING_VERSION` (start `0.1.0`) and integer `CURRENT_PROJECT_VERSION` (start `1`), set once at project level in `project.yml` so they cannot drift. `CFBundleDisplayName` is **"JellyTV" on both platforms** — a shared record shares one store name, and divergent on-device names invite review friction; the companion's remote-control purpose is expressed in its UI and the store description instead.

### D4 — Minimum deployment targets: tvOS 17.0 / iOS 17.0
Covers every Apple TV that runs tvOS 13+ hardware still supported (HD 2015 and all 4K models) while enabling modern SwiftUI + Observation. *Alternative rejected:* min 26 (needlessly excludes devices for an app shipping features months from now); min 15 (drags compatibility cost with zero current users).

### D5 — SwiftUI app lifecycle, empty branded root views
Each target is a plain SwiftUI `App` whose root view shows the app mark + name (and "Remote for your JellyTV" on iOS). No launch storyboards (not used on modern tvOS; iOS uses `UILaunchScreen` dict with background color only). `JellyTVKit` is linked by both targets and exposes one placeholder symbol (e.g. `JellyTVKit.version`) so the dependency edge is real and tested from day one.

### D6 — Icon pipeline: scripted CoreGraphics generation
`Scripts/generate-icons.swift` (run via `swift Scripts/generate-icons.swift`, macOS-only, zero external deps) draws the placeholder artwork — deep-indigo gradient background layer + jellyfish/play glyph foreground layer — and writes PNGs **plus the asset-catalog JSON** for:
- tvOS `App Icon & Top Shelf Image.brandassets`: App Icon – App Store `.imagestack` (1280×768, 2 layers), App Icon `.imagestack` (400×240 @1x, 800×480 @2x, 2 layers), Top Shelf Image Wide (2320×720 @1x / 4640×1440 @2x), Top Shelf Image (1920×720 @1x / 3840×1440 @2x).
- iOS `AppIcon.appiconset`: single-size 1024×1024 (no alpha).
Keeping the generator in-repo makes the placeholder swappable by re-running one script with final artwork later. Validation is delegated to `actool` via the build (see specs). *Alternative rejected:* hand-exported PNGs (not reproducible); Python/Pillow (extra dependency).

### D7 — fastlane via Homebrew, App Store Connect API key auth
fastlane installed with `brew install fastlane` (solo dev; Gemfile/bundler deferred to a CI change). Lanes: `bump` (build number), `build_tvos` / `build_ios` (archive + export), `beta` (upload both to TestFlight), `metadata` (deliver `--skip_binary_upload`), `release_check` (deliver verify/precheck). Auth uses an **App Store Connect API key** (p8 stored outside the repo, referenced via `APP_STORE_CONNECT_API_KEY_*` env vars in untracked `fastlane/.env`) — avoids Apple-ID 2FA breakage. App record + bundle ID created with `fastlane produce` (both platforms) with a documented manual fallback.

### D8 — Metadata content decisions (resolved now, versioned in `fastlane/metadata/en-US/`)
- **name**: `JellyTV` · **subtitle**: `Client for Jellyfin servers`
- **primary category**: Entertainment; secondary: none
- **privacy_url**: GitHub Pages URL (D9) · **support_url**: repo GitHub URL
- **description/keywords**: honest "native Apple TV client for your own Jellyfin media server, with iPhone/iPad remote companion" copy; "Jellyfin" used descriptively only (trademark-safe), never in the app name.
- **Age rating**: all questionnaire answers "None" → 4+ (revisit when playback of arbitrary server media ships).
- **App Privacy**: "Data Not Collected" (matches privacy manifests); export compliance `ITSAppUsesNonExemptEncryption = NO` (HTTPS only — exempt).
- **Review notes**: state the app is a self-hosted-media client shell distributed via TestFlight until feature-complete.

### D9 — Privacy policy on GitHub Pages from `docs/`
`docs/privacy/index.html`: app collects nothing, no analytics/tracking, all traffic goes solely to the user's own Jellyfin server. Requires the repo to be pushed to GitHub with Pages enabled (branch `main`, `/docs` folder) — the local default branch gets renamed `master` → `main` as part of repo hygiene. URL lands in `fastlane/metadata/en-US/privacy_url.txt`.

### D10 — Companion networking prerequisites now, protocol later
The iOS target's Info.plist (via `project.yml`) declares `NSLocalNetworkUsageDescription` ("JellyTV Remote finds and controls your Apple TV and Jellyfin server on your local network.") and `NSBonjourServices` = [`_jellytv._tcp`] reserving the service name the future remote protocol will use. Both targets ship `PrivacyInfo.xcprivacy` (no collected data; required-reason declaration for UserDefaults `CA92.1`). These are inert in an empty app (prompts trigger only on use) but mean zero release-plumbing work when the feature lands.

### D11 — Signing
Automatic signing (`CODE_SIGN_STYLE = Automatic`) with `DEVELOPMENT_TEAM` set in `project.yml` (team IDs are not secrets). The Team ID is read during implementation from `security find-identity -v -p codesigning` or Xcode → Settings → Accounts. *Alternative rejected:* fastlane match — solo developer, no cert-sharing need yet.

### D12 — Developer tooling / MCP
XcodeBuildMCP registered at project scope in `.mcp.json` (**already done**) — provides build/test/simulator/device tools so Claude Code can drive Xcode workflows. No other MCP server adds value for this project today; revisit when CI or design tooling appears.

## Risks / Trade-offs

- [App Review 4.2 — minimum functionality rejects empty apps] → Deliverable is "mechanically submittable"; distribute via TestFlight (no 4.2 bar) and hold public submission until the first real feature. Documented in review notes and README.
- [Layered `.imagestack`/brandassets JSON is finicky and fails late at archive time] → Generator script emits catalog JSON from known-good templates; spec requires a clean `xcodebuild` run whose `actool` step must emit no missing/invalid brand-asset warnings.
- [Same-bundle-ID universal purchase cannot be undone] → Explicit user decision (D3); recorded here and in the spec so no future change accidentally forks the IDs.
- [fastlane Apple-ID auth breaks on 2FA] → API-key auth from the start (D7); key material never enters the repo.
- ["Jellyfin" trademark in metadata] → Descriptive use only in subtitle/description; name stays "JellyTV".
- [XcodeGen regeneration forgotten after editing project.yml / adding files] → bootstrap script, README instructions, and gitignored `.xcodeproj` make "generate" the only path to a project.
- [GitHub Pages URL unknown until repo is pushed] → Privacy URL task ordered before metadata verification; placeholder fails `deliver` validation, making the gap loud, not silent.

## Migration Plan

Greenfield — nothing to migrate. Rollback = delete generated files; the only external state created (bundle ID registration, App Store Connect record) is harmless to leave and reusable.

## Open Questions

- Final icon/artwork direction (placeholder is deliberately generic).
- Whether the companion will ever do playback itself (would expand it beyond "chrome" and reopen the age-rating/privacy answers).
- Exact App Store Connect app-record name availability ("JellyTV" could be taken; fallback e.g. "JellyTV — Media Client"). Checked at `produce` time.
