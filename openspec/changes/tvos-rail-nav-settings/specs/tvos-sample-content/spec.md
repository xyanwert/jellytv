## MODIFIED Requirements

### Requirement: Typed content models
`JellyTVKit` SHALL define typed, `Equatable`, `Sendable` value models for the content the screens render — at minimum a media item, library (with a display-ready item count), hero feature, continue-watching item, user profile, server status, and settings category — independent of any networking layer.

#### Scenario: Views bind to shared models
- **WHEN** the Home and Settings views are constructed
- **THEN** they are initialized from these `JellyTVKit` model types (not inline ad-hoc structs), so a future data source can supply the same types

### Requirement: Sample catalog reproducing the design data
`JellyTVKit` SHALL provide a `SampleCatalog` of demo data matching the reference design: the hero feature ("The Deep Signal"), the Continue Watching list, the Recommended posters, the library list (including the two adult libraries, each with an item count), the user profile ("Marina", administrator), the server status ("reef.local", connected), the seven settings categories, and the Playback category's sample options (streaming quality, playback method, toggle rows).

#### Scenario: Sample catalog is complete and stable
- **WHEN** `SampleCatalog` is accessed
- **THEN** it returns non-empty collections for hero, continue-watching, recommended, libraries (each with an item count), settings categories, and Playback sample options, plus a profile and server status, with values matching the design reference

#### Scenario: Catalog is unit-tested
- **WHEN** `swift test` runs in `Packages/JellyTVKit`
- **THEN** tests covering the sample catalog's shape (expected counts, adult-library flag, library item counts, hero/profile/server fields, settings category count) pass
