# tvos-sample-content

## ADDED Requirements

### Requirement: Typed content models
`JellyTVKit` SHALL define typed, `Equatable`, `Sendable` value models for the content the screens render — at minimum a media item, library, hero feature, continue-watching item, user profile, server status, and settings entry — independent of any networking layer.

#### Scenario: Views bind to shared models
- **WHEN** the Home and Settings views are constructed
- **THEN** they are initialized from these `JellyTVKit` model types (not inline ad-hoc structs), so a future data source can supply the same types

### Requirement: Sample catalog reproducing the design data
`JellyTVKit` SHALL provide a `SampleCatalog` of demo data matching the reference design: the hero feature ("The Deep Signal"), the Continue Watching list, the Recommended posters, the library list (including the two adult libraries), the user profile ("Marina", administrator), and the server status ("reef.local", connected).

#### Scenario: Sample catalog is complete and stable
- **WHEN** `SampleCatalog` is accessed
- **THEN** it returns non-empty collections for hero, continue-watching, recommended, and libraries, plus a profile and server status, with values matching the design reference

#### Scenario: Catalog is unit-tested
- **WHEN** `swift test` runs in `Packages/JellyTVKit`
- **THEN** tests covering the sample catalog's shape (expected counts, adult-library flag, hero/profile/server fields) pass
