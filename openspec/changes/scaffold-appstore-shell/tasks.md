# Tasks: scaffold-appstore-shell

## 1. Repo hygiene & foundations

- [x] 1.1 Add Swift/Xcode `.gitignore` (excludes `*.xcodeproj`, DerivedData, build artifacts, `fastlane/.env`, `*.p8`, `fastlane/report.xml`, `fastlane/test_output`)
- [x] 1.2 Add `LICENSE` (MIT, Francisco Berridi) and initial `README.md` (project intent, bootstrap/build/release workflow — finalize in 7.3)
- [x] 1.3 Rename local default branch `master` → `main` and make the initial commit of existing files (`openspec/`, `.claude/`, `.mcp.json`)
- [ ] 1.4 Restart-verify XcodeBuildMCP: confirm the `.mcp.json` server is approved and its tools respond (list simulators)

## 2. Xcode project skeleton (XcodeGen)

- [x] 2.1 Read the Apple Developer Team ID (`security find-identity -v -p codesigning`, fall back to Xcode → Settings → Accounts) for use in `project.yml`
- [x] 2.2 Write `project.yml`: project `JellyTV`; shared settings `MARKETING_VERSION=0.1.0`, `CURRENT_PROJECT_VERSION=1`, automatic signing with the Team ID; tvOS target `JellyTV` (min tvOS 17.0) and iOS target `Remote` (min iOS 17.0, iPhone+iPad), both with `PRODUCT_BUNDLE_IDENTIFIER=net.graficx.jellytv`, display name `JellyTV`, `ITSAppUsesNonExemptEncryption=NO`, `LSApplicationCategoryType=public.app-category.entertainment`; iOS adds `NSLocalNetworkUsageDescription` and `NSBonjourServices=[_jellytv._tcp]`
- [x] 2.3 Create app sources: `Apps/JellyTV/Sources` (SwiftUI `App` + branded placeholder `RootView`) and `Apps/Remote/Sources` (SwiftUI `App` + "Remote for JellyTV" placeholder `RootView`)
- [x] 2.4 Create `Packages/JellyTVKit` (library + test target, one placeholder symbol e.g. `JellyTVKit.version`), link it from both app targets, consume the symbol in both root views; `swift test` passes
- [x] 2.5 Add `PrivacyInfo.xcprivacy` to both targets (no data collected; UserDefaults required-reason `CA92.1`)
- [x] 2.6 Run `xcodegen generate`; build both schemes and launch each on a tvOS / iPhone / iPad simulator via XcodeBuildMCP; verify built Info.plists match the identity spec (bundle ID, name, versions identical across platforms)

## 3. Branding assets

- [x] 3.1 Write `Scripts/generate-icons.swift` (CoreGraphics-only): gradient background + jellyfish/play glyph, emitting PNGs and asset-catalog JSON for the tvOS brand assets (layered App Store icon 1280×768; home icon 400×240 @1x / 800×480 @2x; Top Shelf Wide 2320×720 @1x / 4640×1440 @2x; Top Shelf 1920×720 @1x / 3840×1440 @2x) and iOS `AppIcon` 1024×1024 (no alpha), plus shared `AccentColor`
- [x] 3.2 Run the generator, regenerate the project, and rebuild both targets; verify `actool` output has zero icon/top-shelf warnings and the script is idempotent (second run produces identical files)

## 4. Bootstrap script

- [x] 4.1 Write `Scripts/bootstrap.sh`: check/install XcodeGen + fastlane via Homebrew, run icon generation, run `xcodegen generate`; exit non-zero with a clear message on missing Xcode
- [x] 4.2 Verify bootstrap from a pristine state: `git clean -xdf` dry-run inspection, then run the script in a temp clone and confirm one command yields an openable, buildable project

## 5. GitHub + privacy policy

- [x] 5.1 Create the GitHub repo and push `main` (`gh repo create` — confirm desired visibility with Francisco), set it as `origin`
- [x] 5.2 Write `docs/privacy/index.html` (no data collected, no analytics, traffic only to the user's own Jellyfin server) and enable GitHub Pages from `main` `/docs` (`gh api`); verify the privacy URL returns HTTP 200
- [x] 5.3 Record the live URL in `fastlane/metadata/en-US/privacy_url.txt` and the repo URL in `support_url` metadata

## 6. fastlane & App Store Connect

- [x] 6.1 Install fastlane (`brew install fastlane`); create `fastlane/Appfile`, `Fastfile` (lanes: `bump`, `build_tvos`, `build_ios`, `beta`, `metadata`, `release_check`), `Deliverfile`, and `.env.example` documenting the App Store Connect API key variables
- [x] 6.2 Write full `fastlane/metadata/en-US/` content per design D8: name `JellyTV`, subtitle `Client for Jellyfin servers`, description, keywords, release notes, review notes, categories (Entertainment), age-rating answers (all None → 4+), App Privacy = Data Not Collected
- [x] 6.3 **(Francisco, in browser)** Create an App Store Connect API key (App Manager role), download the `.p8`, store it outside the repo, fill in `fastlane/.env`
- [x] 6.4 Register bundle ID `net.graficx.jellytv` and create the single app record with **both** tvOS and iOS platforms via `fastlane produce` (manual App Store Connect fallback documented in README); check "JellyTV" name availability, fall back per design if taken
- [x] 6.5 Generate placeholder screenshots from the running simulators (Apple TV 1920×1080; current iPhone and 13" iPad sizes) into `fastlane/screenshots/`
- [ ] 6.6 Run the `metadata` lane in verify mode (`release_check`) and fix every validation error until clean

## 7. First uploads & final verification

- [ ] 7.1 Run the `beta` lane: archive both targets (Release, automatic signing) and upload to TestFlight; confirm both builds finish processing under one universal-purchase app record with no export-compliance prompt
- [ ] 7.2 Walk every spec scenario in `specs/**` and check it passes (build/launch, identity match, asset validation, privacy URL live, versions in lockstep, clean `git status` after builds/lanes)
- [x] 7.3 Finalize `README.md` (bootstrap, xcodegen workflow, icon regeneration, release lanes, TestFlight status, guideline-4.2 note on public release) and commit everything
