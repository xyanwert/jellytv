# tvos-library-classification Specification

## Purpose

Defines the meta-category system that classifies each user library returned by a Jellyfin server into one of 8 categories based on the Jellyfin collection type and library name, with derived NSFW and Anime flags. This classification is the foundation for content filtering and personalized recommendations.

## ADDED Requirements

### Requirement: Meta-category enumeration
`JellyTVKit` SHALL define a `MetaCategory` enum with exactly 8 cases: `movies`, `moviesxxx`, `animefilm`, `shows`, `anime`, `hentai`, `videos`, `porn`. Each case SHALL expose `isNSFW: Bool`, `isAnime: Bool`, and `collectionType: String` (the Jellyfin `CollectionType` value: `"movies"`, `"tvshows"`, or `"homevideos"`) as computed properties.

#### Scenario: NSFW flag is correct per category
- **WHEN** `MetaCategory.moviesxxx.isNSFW` is accessed
- **THEN** it returns `true`
- **WHEN** `MetaCategory.movies.isNSFW` is accessed
- **THEN** it returns `false`

#### Scenario: Anime flag is correct per category
- **WHEN** `MetaCategory.animefilm.isAnime` is accessed
- **THEN** it returns `true`
- **WHEN** `MetaCategory.shows.isAnime` is accessed
- **THEN** it returns `false`

#### Scenario: Collection type maps correctly
- **WHEN** `MetaCategory.movies.collectionType` is accessed
- **THEN** it returns `"movies"`
- **WHEN** `MetaCategory.hentai.collectionType` is accessed
- **THEN** it returns `"tvshows"`

### Requirement: Library classifier
`JellyTVKit` SHALL provide a `LibraryClassifier` that, given a Jellyfin library's `collectionType: String?` and `name: String`, returns a `MetaCategory`. Classification SHALL use name-based regex heuristics (Anime: `/anime|アニメ|hentai/i`; NSFW: `/xxx|nsfw|adult|porn|jav/i`) combined with the `CollectionType` to determine the exact category according to the mapping table.

#### Scenario: Standard movie library
- **WHEN** a library has `collectionType = "movies"` and `name = "Movies"`
- **THEN** `LibraryClassifier.classify` returns `MetaCategory.movies`

#### Scenario: NSFW movie library
- **WHEN** a library has `collectionType = "movies"` and `name = "Movies XXX"`
- **THEN** `LibraryClassifier.classify` returns `MetaCategory.moviesxxx`

#### Scenario: Anime movie library
- **WHEN** a library has `collectionType = "movies"` and `name = "Anime Films"`
- **THEN** `LibraryClassifier.classify` returns `MetaCategory.animefilm`

#### Scenario: Standard TV show library
- **WHEN** a library has `collectionType = "tvshows"` and `name = "TV Shows"`
- **THEN** `LibraryClassifier.classify` returns `MetaCategory.shows`

#### Scenario: Anime TV library
- **WHEN** a library has `collectionType = "tvshows"` and `name = "Anime"`
- **THEN** `LibraryClassifier.classify` returns `MetaCategory.anime`

#### Scenario: Hentai library (NSFW + Anime on TV shows)
- **WHEN** a library has `collectionType = "tvshows"` and `name = "Hentai"`
- **THEN** `LibraryClassifier.classify` returns `MetaCategory.hentai`

#### Scenario: Standard home videos library
- **WHEN** a library has `collectionType = "homevideos"` and `name = "Videos"`
- **THEN** `LibraryClassifier.classify` returns `MetaCategory.videos`

#### Scenario: NSFW home videos library
- **WHEN** a library has `collectionType = "homevideos"` and `name = "Porn"`
- **THEN** `LibraryClassifier.classify` returns `MetaCategory.porn`

#### Scenario: Unknown collection type defaults gracefully
- **WHEN** a library has `collectionType = "music"` or `nil` (music/books/unknown libraries)
- **THEN** `LibraryClassifier.classify` returns `nil` (the library SHALL be filtered out and not shown)

### Requirement: All meta-categories filterable
The tvOS app SHALL be able to filter items by their library's `MetaCategory`, specifically: when the "Hide NSFW" preference is enabled, no item from a library whose `MetaCategory.isNSFW == true` SHALL appear in the Home screen's hero, Continue Watching, or Recommended sections.

#### Scenario: NSFW items hidden when filter is on
- **WHEN** "Hide NSFW" is enabled and a recommended item's library resolves to `MetaCategory.moviesxxx`
- **THEN** that item is excluded from the Recommended row
