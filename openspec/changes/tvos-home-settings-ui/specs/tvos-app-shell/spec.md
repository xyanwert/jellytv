# tvos-app-shell

## MODIFIED Requirements

### Requirement: Buildable, launchable tvOS app
The repo SHALL contain a tvOS app target `JellyTV` (SwiftUI lifecycle, minimum deployment tvOS 17.0) that builds without warnings-as-errors and launches to the **Home screen** (top bar, hero, and content rows), navigable with the Apple TV remote.

#### Scenario: Clean build and launch on simulator
- **WHEN** `xcodegen generate` is run followed by an `xcodebuild build` (or XcodeBuildMCP build) for the `JellyTV` scheme against a tvOS Simulator destination
- **THEN** the build succeeds and the installed app launches to the Home screen (top bar + hero + rows) without crashing
