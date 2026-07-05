# tvos-app-shell

## ADDED Requirements

### Requirement: Buildable, launchable tvOS app
The repo SHALL contain a tvOS app target `JellyTV` (SwiftUI lifecycle, minimum deployment tvOS 17.0) that builds without warnings-as-errors and launches to a branded placeholder screen showing the app mark and name.

#### Scenario: Clean build and launch on simulator
- **WHEN** `xcodegen generate` is run followed by an `xcodebuild build` (or XcodeBuildMCP build) for the `JellyTV` scheme against a tvOS Simulator destination
- **THEN** the build succeeds and the installed app launches to the branded placeholder screen without crashing

### Requirement: App identity and release metadata
The tvOS target SHALL carry all identity metadata required for App Store submission: bundle ID `net.graficx.jellytv`, display name `JellyTV`, marketing version `0.1.0`, integer build number ≥ 1, application category `public.app-category.entertainment`, and `ITSAppUsesNonExemptEncryption = NO`.

#### Scenario: Built product exposes complete identity metadata
- **WHEN** the built app bundle's Info.plist is inspected
- **THEN** it contains exactly the bundle ID `net.graficx.jellytv`, display name `JellyTV`, `CFBundleShortVersionString` `0.1.0`, a numeric `CFBundleVersion`, and `ITSAppUsesNonExemptEncryption` set to false

### Requirement: Complete tvOS brand assets
The tvOS target SHALL include a fully populated `App Icon & Top Shelf Image` brand-assets catalog: layered App Store icon (1280×768), layered home-screen icon (400×240 @1x, 800×480 @2x), Top Shelf Image Wide (2320×720 @1x, 4640×1440 @2x), and Top Shelf Image (1920×720 @1x, 3840×1440 @2x), each icon stack having at least two layers for parallax.

#### Scenario: Asset catalog compiles with no missing brand assets
- **WHEN** the target is built and `actool` compiles the asset catalog
- **THEN** the build log contains no warnings or errors about missing, mis-sized, or invalid app icon / top shelf assets

### Requirement: Privacy manifest
The tvOS target SHALL bundle a `PrivacyInfo.xcprivacy` declaring that no data is collected and listing required-reason API usage (at minimum UserDefaults, reason `CA92.1`).

#### Scenario: Privacy manifest present in built product
- **WHEN** the built app bundle is inspected
- **THEN** `PrivacyInfo.xcprivacy` is present and declares an empty collected-data list

### Requirement: Archivable with automatic signing
The tvOS target SHALL be configured with automatic signing (`CODE_SIGN_STYLE = Automatic`) and the owner's `DEVELOPMENT_TEAM`, such that a distribution archive can be produced.

#### Scenario: Release archive succeeds
- **WHEN** `xcodebuild archive` (or the fastlane `build_tvos` lane) runs for the Release configuration
- **THEN** an `.xcarchive` is produced signed with the configured team, with no signing errors
