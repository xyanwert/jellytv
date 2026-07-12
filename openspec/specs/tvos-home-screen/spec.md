# tvos-home-screen Specification

## Purpose

Defines the tvOS Home screen: layout, sample-data-driven content, and remote-navigable focus behavior.

## Requirements

### Requirement: Home screen layout
The tvOS app SHALL present a Home screen matching the reference design, composed of: the shared left navigation rail (see `tvos-nav-rail`); a content-area readout row (a "Home // Featured"-style eyebrow on the left, a clock and profile avatar on the right); a hero block (eyebrow, title, rating/meta line, synopsis, `Resume` / `Details` / `＋` actions, and the pill timer); a Continue Watching row; and a Recommended for You poster row.

#### Scenario: Home renders all sections from the sample catalog
- **WHEN** the app launches and Home appears
- **THEN** the rail, content-area readout row, hero, Continue Watching row, and Recommended row are all displayed, populated from `SampleCatalog`

#### Scenario: Adult libraries are marked
- **WHEN** the Libraries submenu (see `tvos-nav-rail`) renders a library flagged adult
- **THEN** that row shows the accent-tinted treatment and an `18+` badge

### Requirement: Remote-navigable focus
The Home screen SHALL be navigable with the Apple TV remote via the tvOS focus engine: the rail icons, hero actions, Continue Watching cards, and Recommended posters are focusable, focus is visually indicated, and horizontal rows scroll to keep the focused item visible.

#### Scenario: Focus moves and rows scroll
- **WHEN** the app launches on a tvOS simulator and directional focus moves are issued
- **THEN** an element is focused at launch (e.g. the hero Resume action), focus moves between the rail/actions/rows/cards, the focused element shows the focus effect, and focusing an off-screen card in a row scrolls it into view

### Requirement: Continue Watching progress
Each Continue Watching card SHALL show artwork, title, an accent progress bar reflecting watched fraction, a remaining-indicator, and an episode/label line.

#### Scenario: Progress reflects the model
- **WHEN** a Continue Watching card renders an item with a given watched fraction
- **THEN** its progress bar fill and remaining indicator correspond to that fraction

### Requirement: Recommended posters open the Show view
The Home Recommended row's posters SHALL be focusable and selectable; selecting a poster SHALL open the Show view (see `tvos-show-view`) for a series derived from that poster.

#### Scenario: Selecting a poster opens a show
- **WHEN** a Recommended poster is focused and the user presses select
- **THEN** the Show view opens for that poster's series, and dismissing it (Menu/Back) returns to the Home screen with focus restored to the browse content
