## ADDED Requirements

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
