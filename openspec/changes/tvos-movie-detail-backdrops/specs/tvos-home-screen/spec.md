## MODIFIED Requirements

### Requirement: Recommended posters open the Show view
The Home Recommended row's posters SHALL be focusable and selectable; selecting a poster SHALL open the appropriate detail screen for that poster — the Movie detail (see `tvos-movie-detail`) if the poster represents a movie, otherwise the Show view (see `tvos-show-view`).

#### Scenario: Selecting a poster opens the right detail
- **WHEN** a Recommended poster is focused and the user presses select
- **THEN** a movie poster opens the Movie detail and a series poster opens the Show view, each for that poster's title, and dismissing it (Menu/Back) returns to the Home screen with focus restored to the browse content
