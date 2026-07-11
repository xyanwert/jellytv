# tvos-hero-carousel Specification

## Purpose

Defines the Home hero's multi-item auto-rotating carousel behavior: rotation timing, the horizontal pill timer indicator, clock reset on index change, the configurable rotation interval, and the pills' non-focusable status.

## Requirements

### Requirement: Multi-item auto-rotating hero
The Home hero SHALL rotate through a list of featured items (from `SampleCatalog.heroes`), auto-advancing to the next item after the configured rotation interval and wrapping at the end.

#### Scenario: Hero auto-advances
- **WHEN** the Home screen is shown with more than one hero item and the rotation interval elapses
- **THEN** the hero advances to the next item (wrapping after the last), updating the backdrop, title, and metadata

#### Scenario: Single item does not rotate
- **WHEN** there is only one hero item
- **THEN** no auto-advance occurs and the pill timer is hidden

### Requirement: Horizontal pill timer
The hero SHALL display a horizontal row of pills as the rotation indicator: one pill per item, the active pill wider than the rest, filling left→right over the rotation interval as a visible countdown to the next advance, after a brief "hold full" lead-in.

#### Scenario: Active pill fills over the interval
- **WHEN** a hero item becomes active
- **THEN** its pill is the widened/active pill and its fill progresses from empty to full across the interval (after a short lead-in), reaching full just as the hero auto-advances

#### Scenario: Pills reflect the current index
- **WHEN** the hero index changes (auto or manual)
- **THEN** exactly the pill for the new index is shown as active and its fill restarts from the beginning

### Requirement: Clock reset on index change
Changing the hero item (auto-advance or manual jump) SHALL reset the timer clock so each slide gets a full interval, and a manual change SHALL cancel any in-flight auto-advance so it cannot double-advance.

#### Scenario: Manual change restarts the timer cleanly
- **WHEN** the hero index is changed manually before the interval elapses
- **THEN** the new slide's pill fill starts from zero, the previous pending auto-advance does not fire early, and the next auto-advance is a full interval later

### Requirement: Configurable rotation interval
The rotation interval SHALL be user-selectable among 5s, 15s (default), and 30s, persisted across launches, and applied live to both the auto-advance and the pill fill rate.

#### Scenario: Changing the interval takes effect
- **WHEN** the user selects a different rotation interval in Settings
- **THEN** subsequent slides use the new interval for both the auto-advance timing and the pill fill, and the choice survives relaunch

### Requirement: Pills are a non-focusable read-out
The pill timer SHALL be a status read-out that does not participate in the tvOS focus engine, and launch focus SHALL remain on the hero's primary (Resume) action.

#### Scenario: Focus is unaffected by the pills
- **WHEN** the Home screen appears and focus is moved with the remote
- **THEN** the pills never receive focus and the hero's Resume action is the default focused element
