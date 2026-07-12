## ADDED Requirements

### Requirement: Movie detail screen
The tvOS app SHALL present a full-screen Movie detail screen for a single-video title, matching design `1b`. It SHALL use the same left spine and dossier layout as the Show view (its own spine — not the main nav rail — with a genre label and a "FILM 001"-style marker) and SHALL show: a "Feature Film // …" studio eyebrow, the movie title, a spec sheet of rating, runtime, director, and year, a synopsis, a framed key-art panel with corner ticks and a floating resume card, a "More Like This" row of portrait posters, and a bottom bar with cast credits (Starring / Audio) and Play / Trailer / audio / subtitle / add controls.

#### Scenario: Movie detail renders from the model
- **WHEN** the Movie detail is presented for a movie
- **THEN** the title block, spec sheet, synopsis, key-art panel with resume card, More Like This row, cast credits, and control bar are all displayed, populated from the movie model

### Requirement: Remote navigation and dismissal
The Movie detail SHALL be navigable with the Apple TV remote: the back control, resume/play card, More Like This posters, and control-bar buttons are focusable with the focus treatment, and a focused element is present at launch. Pressing Menu/Back (or the on-screen back control) SHALL dismiss the screen and return to Home.

#### Scenario: Focus and dismiss
- **WHEN** the Movie detail appears and directional focus moves are issued
- **THEN** an element is focused at launch, focus moves among the back control / play / posters / controls, and pressing Menu/Back returns to Home

### Requirement: Launch from the Recommended row
Selecting a Recommended poster whose kind is a movie SHALL open the Movie detail populated with demo data derived from that poster (at least its title and key art).

#### Scenario: Selecting a movie poster opens the movie detail
- **WHEN** a Recommended poster representing a movie is focused and selected
- **THEN** the Movie detail opens showing a film whose title and key art come from that poster
