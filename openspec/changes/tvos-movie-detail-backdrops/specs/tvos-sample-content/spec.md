## ADDED Requirements

### Requirement: Movie content model
`JellyTVKit` SHALL define a typed, `Equatable`, `Sendable` `Movie` value model carrying the fields a movie detail needs — title, studio/eyebrow line, rating, certification, runtime, director, year, genre label, synopsis, key-art reference, artwork, resume progress/remaining, starring, audio line, and a "more like this" list — independent of any networking layer.

#### Scenario: Movie detail binds to the shared model
- **WHEN** the Movie detail is constructed
- **THEN** it is initialized from the `JellyTVKit` `Movie` type (not an inline ad-hoc struct)

### Requirement: Media item kind
`JellyTVKit` SHALL expose whether a `MediaItem` represents a movie or a series (a `kind`, or a derivation from its metadata) so the Home Recommended row can route a selection to the Movie detail or the Show view.

#### Scenario: Kind is available for routing
- **WHEN** a Recommended `MediaItem` is inspected
- **THEN** it reports whether it is a movie or a series

### Requirement: Sample movie data
`JellyTVKit` SHALL provide sample movie data — a demo movie with spec-sheet metadata, a synopsis, a resume point, cast/credits, and a "more like this" list — plus a builder that produces a `Movie` for a given media item (carrying that item's title and key art). The sample `Show` SHALL also carry a synopsis.

#### Scenario: Sample movie is complete and unit-tested
- **WHEN** the sample movie (or a movie built for a media item) is accessed, and `swift test` runs in `Packages/JellyTVKit`
- **THEN** it returns populated spec-sheet, synopsis, resume, cast, and non-empty more-like-this fields, and tests covering the sample movie and the `movie(for:)` builder (carrying the item's title) pass
