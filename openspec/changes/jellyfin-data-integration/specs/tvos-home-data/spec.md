# tvos-home-data Specification

## Purpose

Defines the home screen data pipeline: the `AppState` orchestrator that fetches libraries and items from the Jellyfin API, computes the Continue Watching, Recommended, and Hero datasets, applies the NSFW filter, and refreshes on a timer and on reconnection.

## ADDED Requirements

### Requirement: AppState data orchestrator
The tvOS app SHALL provide an `AppState: ObservableObject` owned by `RootView` and injected as an `@EnvironmentObject`. `AppState` SHALL own the live home screen data — libraries, continue watching items, recommended items, and hero features — and SHALL expose them as `@Published` properties. It SHALL be initialized with the credentials from `ServerConnection` after a successful connection.

#### Scenario: AppState loads libraries on refresh
- **WHEN** `appState.refresh()` is called after a successful server connection
- **THEN** `appState.libraries` is populated with `JellyfinUserView` instances fetched from the server, filtered to exclude music/books/mixed libraries

#### Scenario: AppState loads home data on refresh
- **WHEN** `appState.refresh()` completes successfully
- **THEN** `appState.continueWatching`, `appState.recommended`, and `appState.heroes` are populated with non-empty arrays (or empty if the server has no relevant content)

### Requirement: Continue Watching from Jellyfin
`AppState` SHALL fetch Continue Watching items from the Jellyfin server by querying each library with `filters=IsResumable&sortBy=DatePlayed&sortOrder=Descending&limit=10`, pooling results, sorting client-side by `lastPlayedDate` descending, converting the top 6 to `ContinueWatchingItem` models, and applying the NSFW filter. If no items exist (fresh install), the Continue Watching section SHALL be hidden.

#### Scenario: Continue Watching populated from server
- **WHEN** the server has 5 resume-able items across two libraries
- **THEN** `appState.continueWatching` contains exactly those 5 items sorted by most-recently-played first

#### Scenario: Empty Continue Watching hides the row
- **WHEN** the server returns zero resume-able items
- **THEN** `appState.continueWatching` is empty and the Home screen does not render the Continue Watching section

### Requirement: Recommended computation
`AppState` SHALL compute the Recommended row by: (1) identifying up to 3 items from the same `MetaCategory` as the user's most-recently-watched items, (2) identifying up to 3 items the user has not watched recently from any library, (3) if fewer than 6 items are found, filling with random items from available libraries. All items SHALL be converted to `MediaItem` models with their `kind` derived from Jellyfin's `type` field.

#### Scenario: Affinity picks from same meta-category
- **WHEN** the user's most recently watched item is from a `MetaCategory.shows` library
- **THEN** at least some recommended items come from libraries also classified as `MetaCategory.shows`

#### Scenario: Fallback fills to 6 items
- **WHEN** the server has at least 6 items total but the affinity + recency picks yield fewer than 6
- **THEN** the remaining slots are filled with random items from any available library, up to 6 total

### Requirement: Hero assembly
`AppState` SHALL assemble the hero carousel by converting up to 3 `ContinueWatchingItem`s to `HeroFeature`s and up to 3 `MediaItem`s from Recommended to `HeroFeature`s, for a total of up to 6. On a completely fresh install (0 continue watching and 0 recommended), up to 3 random items SHALL be picked as hero slides.

#### Scenario: Hero includes both continue watching and recommended
- **WHEN** there are 2 continue watching items and 5 recommended items
- **THEN** `appState.heroes` contains 2 heroes from continue watching and 3 from recommended, for a total of 5

#### Scenario: Fresh install uses random items
- **WHEN** the server has items but no resume-able or recently-watched items (fresh install)
- **THEN** `appState.heroes` contains up to 3 heroes from random items on the server

### Requirement: NSFW filtering
`AppState` SHALL expose a `hideNSFW: Bool` preference (default `true`, persisted to `UserDefaults`). When `true`, all three Home sections (hero, Continue Watching, Recommended) SHALL exclude items whose library's `MetaCategory.isNSFW == true`. Toggling this preference SHALL immediately re-filter the displayed data without re-fetching from the server.

#### Scenario: NSFW items excluded when filter is on
- **WHEN** `hideNSFW` is `true` and a continue-watching item comes from a library classified as `MetaCategory.hentai`
- **THEN** that item does not appear in the Continue Watching row

#### Scenario: NSFW items shown when filter is off
- **WHEN** `hideNSFW` is `false`
- **THEN** items from NSFW libraries appear in all Home sections alongside other items

### Requirement: Periodic refresh
`AppState` SHALL run a refresh timer that re-fetches all home data at a fixed interval (default 5 minutes) while the server is connected. The timer SHALL cancel on disconnect and restart on reconnect.

#### Scenario: Timer refreshes data periodically
- **WHEN** the server is connected and 5 minutes elapse
- **THEN** `appState.refresh()` is called automatically and the home sections update with fresh data

### Requirement: Reconnection triggers refresh
`AppState` SHALL expose a `refresh()` method; `RootView` SHALL call `appState.refresh()` after `server.status` transitions to `.connected`, so the home screen is populated immediately after a successful connection or reconnection.

#### Scenario: Refresh runs after initial connection
- **WHEN** the user completes the setup wizard and `server.status` becomes `.connected`
- **THEN** `appState.refresh()` is called and the home screen shows real content from the connected server
