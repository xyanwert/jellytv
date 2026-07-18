# tvos-home-screen Delta Spec

## ADDED Requirements

### Requirement: Home screen hides empty sections
The Home screen SHALL hide the Continue Watching section entirely when there are no resume-able items on the server. The Recommended row SHALL always render (it falls back to random items). The hero SHALL render with however many items are available (0 means no hero backdrop).

#### Scenario: Continue Watching hidden when empty
- **WHEN** the server returns zero resume-able items (fresh install or all items fully watched)
- **THEN** the Continue Watching section is not rendered and the Recommended row moves up

#### Scenario: Hero hidden when no items available
- **WHEN** there are zero continue watching items and zero recommended items (completely empty server)
- **THEN** the hero backdrop and hero content are not rendered; the home screen still shows the nav rail and content-area readout row

### Requirement: NSFW content filtering on Home
The Home screen SHALL respect the "Hide NSFW" preference from `AppState.hideNSFW`. When enabled, the hero, Continue Watching, and Recommended sections SHALL exclude all items whose source library is classified with `MetaCategory.isNSFW == true`. The setting SHALL be controlled from Settings → Home.

#### Scenario: NSFW filter hides adult content
- **WHEN** `hideNSFW` is `true` and the server has continue-watching items from both a `movies` library and a `moviesxxx` library
- **THEN** only items from the `movies` library appear in the Continue Watching row

#### Scenario: Disabling filter shows all content
- **WHEN** `hideNSFW` is toggled to `false`
- **THEN** items from NSFW libraries immediately appear in Home sections alongside other items

## MODIFIED Requirements

### Requirement: Home screen layout
The tvOS app SHALL present a Home screen matching the reference design, composed of: the shared left navigation rail (see `tvos-nav-rail`); a content-area readout row (a "Home // Featured"-style eyebrow on the left, a clock and profile avatar on the right); a hero block (eyebrow, title, rating/meta line, synopsis, `Resume` / `Details` / `＋` actions, and the pill timer); a Continue Watching row (hidden when empty); and a Recommended for You poster row. All data SHALL be sourced from `AppState` (live Jellyfin API), not `SampleCatalog`. The `SampleCatalog` SHALL only be used for screenshot/testing hooks (`JT_SHOW_DEMO`, `JT_FOCUS`).

#### Scenario: Home renders all sections from live data
- **WHEN** the app launches, connects to a Jellyfin server, and Home appears
- **THEN** the rail, content-area readout row, hero, Continue Watching row, and Recommended row are all displayed, populated from `AppState` with data fetched from the connected Jellyfin server

#### Scenario: Adult libraries are marked
- **WHEN** the Libraries submenu (see `tvos-nav-rail`) renders a library classified as `MetaCategory.moviesxxx` or `MetaCategory.hentai` or `MetaCategory.porn`
- **THEN** that row shows the accent-tinted treatment and an `18+` badge

### Requirement: Recommended posters open the detail view
The Home Recommended row's posters SHALL be focusable and selectable; selecting a poster SHALL route by `MediaItem.Kind` — a `.movie` opens the Movie detail view (see `tvos-movie-detail`) and a `.series` opens the Show view (see `tvos-show-view`) — and dismissing it (Menu/Back) returns to the Home screen with focus restored to the browse content.

#### Scenario: Selecting a movie poster opens the Movie detail
- **WHEN** a Recommended poster with `kind == .movie` is focused and the user presses select
- **THEN** the Movie detail view opens for that movie

#### Scenario: Selecting a series poster opens the Show view
- **WHEN** a Recommended poster with `kind == .series` is focused and the user presses select
- **THEN** the Show view opens for that series, and dismissing it (Menu/Back) returns to the Home screen with focus restored
