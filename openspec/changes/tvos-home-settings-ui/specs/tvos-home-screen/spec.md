# tvos-home-screen

## ADDED Requirements

### Requirement: Home screen layout
The tvOS app SHALL present a Home screen matching the reference design, composed of: a top bar (logo + `jelly·tv` wordmark, a centered navigation pill with `Home` (active) / `Movies` / `Shows` / `Search`, a clock, and a profile avatar); a horizontally-scrolling library-chips row; a hero block (eyebrow, title, rating/meta line, synopsis, `Resume` / `Details` / `＋` actions, and pager dots); a Continue Watching row; and a Recommended for You poster row.

#### Scenario: Home renders all sections from the sample catalog
- **WHEN** the app launches and Home appears
- **THEN** the top bar, library chips, hero, Continue Watching row, and Recommended row are all displayed, populated from `SampleCatalog`

#### Scenario: Adult libraries are marked
- **WHEN** the library-chips row renders a library flagged adult
- **THEN** that chip shows the accent-tinted treatment and an `18+` badge

### Requirement: Remote-navigable focus
The Home screen SHALL be navigable with the Apple TV remote via the tvOS focus engine: the hero actions, library chips, Continue Watching cards, Recommended posters, and nav pill tabs are focusable, focus is visually indicated, and horizontal rows scroll to keep the focused item visible.

#### Scenario: Focus moves and rows scroll
- **WHEN** the app launches on a tvOS simulator and directional focus moves are issued
- **THEN** an element is focused at launch (e.g. the hero Resume action), focus moves between actions/rows/cards, the focused element shows the focus effect, and focusing an off-screen card in a row scrolls it into view

### Requirement: Continue Watching progress
Each Continue Watching card SHALL show artwork, title, an accent progress bar reflecting watched fraction, a remaining-indicator, and an episode/label line.

#### Scenario: Progress reflects the model
- **WHEN** a Continue Watching card renders an item with a given watched fraction
- **THEN** its progress bar fill and remaining indicator correspond to that fraction

### Requirement: Secondary nav destinations are non-blocking
Selecting a nav tab other than `Home` (Movies/Shows/Search) SHALL not crash or dead-end; these destinations are out of scope for this change and MAY render a lightweight placeholder.

#### Scenario: Non-Home tab is safe
- **WHEN** a Movies/Shows/Search tab is focused and selected
- **THEN** the app remains responsive (e.g. shows a "coming soon" placeholder) and the user can return to Home
