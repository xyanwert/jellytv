# tvos-sample-content Specification

## Purpose

Defines the typed content models and the demo sample catalog that power the Home and Settings screens ahead of a real data source.

## Requirements

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

### Requirement: Series content models
`JellyTVKit` SHALL define typed, `Equatable`, `Sendable` value models for a collection and its contents — a `Show` (title, studio/eyebrow line, rating, certification, run summary, creator, years, genre label, technical line, key-art reference, resume episode label/progress/remaining, and its seasons), a `Season` (number, name, episodes), and an `Episode` (number, title, runtime, current flag, artwork) — independent of any networking layer.

#### Scenario: Show view binds to shared models
- **WHEN** the Show view is constructed
- **THEN** it is initialized from these `JellyTVKit` model types (not inline ad-hoc structs)

### Requirement: Sample series data
`JellyTVKit` SHALL provide sample series data: a demo multi-season show with per-season episodes (one marked current), spec-sheet metadata, and a resume point, plus a builder that produces a `Show` for a given media item (carrying that item's title and key art) so the Recommended row can open any poster as a show.

#### Scenario: Sample show is complete
- **WHEN** the sample show (or a show built for a media item) is accessed
- **THEN** it returns non-empty seasons each with non-empty episodes, exactly one episode flagged current, and populated spec-sheet + resume fields

#### Scenario: Series sample data is unit-tested
- **WHEN** `swift test` runs in `Packages/JellyTVKit`
- **THEN** tests covering the sample series (season/episode counts, a single current episode, resume fields, and the `show(for:)` builder carrying the item's title) pass
