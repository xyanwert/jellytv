# release-readiness Specification

## Purpose

Defines what "ready for the App Store" means for JellyTV: versioned metadata, a published privacy policy, a two-platform App Store Connect record, a TestFlight upload lane, placeholder screenshots, and single-source versioning shared across targets.

## Requirements

### Requirement: Versioned App Store metadata
The repo SHALL contain complete `en-US` App Store metadata under `fastlane/metadata/` — app name `JellyTV`, subtitle, full description, keywords, support URL, privacy policy URL, release notes, primary category Entertainment, and review notes — with no placeholder text remaining.

#### Scenario: Metadata passes deliver validation
- **WHEN** the fastlane metadata lane runs in verify/no-upload mode against the App Store Connect record
- **THEN** validation completes with no missing-field or invalid-value errors for the en-US locale

### Requirement: Published privacy policy
A privacy policy page SHALL be published at a public URL via GitHub Pages from this repo's `docs/` folder, stating that the app collects no data, uses no analytics or tracking, and communicates only with the user's own Jellyfin server; the same URL SHALL appear in the App Store metadata.

#### Scenario: Privacy URL is live and referenced
- **WHEN** the URL stored in `fastlane/metadata/en-US/privacy_url.txt` is fetched over HTTPS
- **THEN** it returns the JellyTV privacy policy page with HTTP 200

### Requirement: App Store Connect record with both platforms
The bundle ID `net.graficx.jellytv` SHALL be registered and a single App Store Connect app record SHALL exist with both the tvOS and iOS platforms attached (universal purchase), created via `fastlane produce` or the documented manual fallback.

#### Scenario: Both platform builds attach to one record
- **WHEN** a tvOS build and an iOS build are uploaded
- **THEN** both appear under the same App Store Connect app record for `net.graficx.jellytv`

### Requirement: TestFlight upload lane
The repo SHALL provide a fastlane lane that archives both targets and uploads them to TestFlight, authenticating with an App Store Connect API key supplied via environment variables (never committed).

#### Scenario: Beta lane uploads both platforms
- **WHEN** the `beta` lane runs with valid API-key environment variables
- **THEN** signed builds of the tvOS and iOS targets are uploaded to TestFlight and complete processing without export-compliance prompts (compliance is declared in the Info.plists)

### Requirement: Placeholder App Store screenshots
The repo SHALL contain branded placeholder screenshots in every size class App Store Connect requires for the two platforms (Apple TV 16:9; current-generation iPhone and 13" iPad), stored under `fastlane/screenshots/`.

#### Scenario: Screenshot set accepted by validation
- **WHEN** the metadata lane runs including screenshots
- **THEN** validation reports no missing-screenshot or wrong-resolution errors for either platform

### Requirement: Single-source versioning
Marketing version and build number SHALL be defined once (in `project.yml`) and shared by both targets, with a fastlane lane to increment the build number.

#### Scenario: Bump lane keeps targets in lockstep
- **WHEN** the version-bump lane runs
- **THEN** both targets' `CFBundleVersion` values increase to the same new value in a single commit-able change
