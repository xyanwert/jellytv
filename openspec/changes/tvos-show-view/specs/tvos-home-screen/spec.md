## ADDED Requirements

### Requirement: Recommended posters open the Show view
The Home Recommended row's posters SHALL be focusable and selectable; selecting a poster SHALL open the Show view (see `tvos-show-view`) for a series derived from that poster.

#### Scenario: Selecting a poster opens a show
- **WHEN** a Recommended poster is focused and the user presses select
- **THEN** the Show view opens for that poster's series, and dismissing it (Menu/Back) returns to the Home screen with focus restored to the browse content
