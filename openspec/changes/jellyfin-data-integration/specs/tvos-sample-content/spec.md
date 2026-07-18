# tvos-sample-content Delta Spec

## ADDED Requirements

### Requirement: Sample catalog retained for screenshot hooks
`SampleCatalog` SHALL remain in `JellyTVKit` as the data source for design-system screenshot and testing environment variables (`JT_SHOW_DEMO`, `JT_FOCUS`, `JT_SETUP_DEMO`, `JT_SCAN_DEMO`). These hooks SHALL continue to function with sample data so design screenshots and manual testing of layout states remain reproducible.

#### Scenario: Screenshot hooks still use sample data
- **WHEN** the app is launched with `JT_SHOW_DEMO=1`
- **THEN** the show or movie detail screen renders using sample catalog data, not live Jellyfin data

#### Scenario: Sample catalog is still unit-tested
- **WHEN** `swift test` runs in `Packages/JellyTVKit`
- **THEN** tests covering the sample catalog's shape pass

## MODIFIED Requirements

### Requirement: Typed content models
`JellyTVKit` SHALL define typed, `Equatable`, `Sendable` value models for the content the screens render — at minimum a media item, library (with a display-ready item count), hero feature, continue-watching item, user profile, server status, and settings category — independent of any networking layer. It SHALL also provide conversion helpers that construct these UI models from `JellyfinItem` and `JellyfinUserView` DTOs (e.g. `JellyfinItem.toContinueWatchingItem()`, `JellyfinItem.toMediaItem()`, `JellyfinItem.toHeroFeature()`).

#### Scenario: Views bind to shared models
- **WHEN** the Home and Settings views are constructed
- **THEN** they are initialized from these `JellyTVKit` model types (not inline ad-hoc structs), so both `SampleCatalog` and `AppState` can supply the same types

#### Scenario: Conversion helpers produce correct UI models
- **WHEN** a `JellyfinItem` with `type = "Movie"` is converted via `toMediaItem()`
- **THEN** the resulting `MediaItem` has `kind == .movie`, its `title` matches the Jellyfin `name`, and its `meta` line is derived from the genre list

### Requirement: Sample catalog reproducing the design data
`JellyTVKit` SHALL provide a `SampleCatalog` of demo data matching the reference design. At runtime, `AppState` SHALL be the primary data source when a Jellyfin server is connected; `SampleCatalog` SHALL be used only for screenshot/testing hooks via environment variables. When no server is connected (setup/disconnected state), no home screen data is shown.

#### Scenario: Sample catalog is not the runtime data source
- **WHEN** the app is launched normally with a connected Jellyfin server (no `JT_*` environment variables set)
- **THEN** all Home screen data comes from `AppState` (live Jellyfin API), and `SampleCatalog` is not accessed for content display

#### Scenario: Catalog values still match the design reference
- **WHEN** `SampleCatalog` is accessed (e.g. by screenshot hooks)
- **THEN** it returns non-empty collections matching the design reference, as before
