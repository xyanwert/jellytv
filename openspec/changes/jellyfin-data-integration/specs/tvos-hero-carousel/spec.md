# tvos-hero-carousel Delta Spec

## MODIFIED Requirements

### Requirement: Multi-item auto-rotating hero
The Home hero SHALL rotate through up to 6 featured items assembled by `AppState` (3 from Continue Watching and 3 from Recommended, capped at whatever is available), auto-advancing to the next item after the configured rotation interval and wrapping at the end. The number of hero items SHALL be dynamic based on available data rather than a fixed sample set.

#### Scenario: Hero auto-advances with dynamic item count
- **WHEN** the Home screen is shown with 4 hero items (2 from continue watching, 2 from recommended) and the rotation interval elapses
- **THEN** the hero advances to the next item (wrapping after the 4th), updating the backdrop, title, and metadata

#### Scenario: Single item does not rotate
- **WHEN** there is only one hero item
- **THEN** no auto-advance occurs and the pill timer is hidden

#### Scenario: Zero hero items
- **WHEN** there are zero hero items (completely empty server)
- **THEN** the hero backdrop and content are not rendered

### Requirement: Horizontal pill timer
The hero SHALL display a horizontal row of pills as the rotation indicator when there are 2 or more hero items: one pill per item, the active pill wider than the rest, filling from top-to-bottom over the rotation interval as a visible countdown to the next advance. When there is only 1 or 0 hero items, the pill timer SHALL be hidden.

#### Scenario: Pill count matches dynamic hero count
- **WHEN** `appState.heroes` contains 4 items
- **THEN** exactly 4 pills are displayed, with the one corresponding to the active index filling

#### Scenario: Single hero hides pills
- **WHEN** there is only 1 hero item
- **THEN** the pill timer is not rendered

### Requirement: Configurable rotation interval
The rotation interval SHALL be user-selectable among 5s, 15s (default), and 30s, persisted across launches, and applied live to both the auto-advance and the pill fill rate. The interval control SHALL be in Settings → Home.

#### Scenario: Changing the interval takes effect
- **WHEN** the user selects a different rotation interval in Settings → Home
- **THEN** subsequent slides use the new interval for both the auto-advance timing and the pill fill, and the choice survives relaunch
