# ios-companion-shell

## ADDED Requirements

### Requirement: Buildable, launchable iOS companion app
The repo SHALL contain an iOS/iPadOS app target `Remote` (SwiftUI lifecycle, minimum deployment iOS 17.0, device families iPhone and iPad) that builds and launches to a branded placeholder screen identifying itself as the remote companion for JellyTV.

#### Scenario: Clean build and launch on iPhone and iPad simulators
- **WHEN** the `Remote` scheme is built and run on an iPhone Simulator and an iPad Simulator destination
- **THEN** both builds succeed and the app launches to the branded companion placeholder screen on each

### Requirement: Shared identity for universal purchase
The iOS target SHALL use the same bundle ID `net.graficx.jellytv`, display name `JellyTV`, and marketing/build version values as the tvOS target, so both binaries attach to one App Store Connect record as a universal purchase.

#### Scenario: Version and identity match the tvOS target
- **WHEN** the built iOS and tvOS app bundles' Info.plists are compared
- **THEN** bundle ID, display name, `CFBundleShortVersionString`, and `CFBundleVersion` are identical across the two

### Requirement: iOS brand assets
The iOS target SHALL include a 1024×1024 single-size app icon without an alpha channel and a shared accent color consistent with the tvOS branding.

#### Scenario: Icon validates at build time
- **WHEN** the target is built and `actool` compiles the asset catalog
- **THEN** the build log contains no warnings or errors about the app icon, and the compiled icon has no alpha channel

### Requirement: Companion networking declarations
The iOS target SHALL declare, in advance of the remote-control feature, `NSLocalNetworkUsageDescription` with an honest user-facing string and `NSBonjourServices` containing `_jellytv._tcp`, plus a `PrivacyInfo.xcprivacy` declaring no data collection.

#### Scenario: Networking and privacy declarations present in built product
- **WHEN** the built app bundle's Info.plist and privacy manifest are inspected
- **THEN** the local-network usage description, the `_jellytv._tcp` Bonjour service, and the no-data-collected privacy manifest are all present
