## ADDED Requirements

### Requirement: Show view for collections
The tvOS app SHALL present a full-screen Show view for a collection (a series with seasons and episodes), matching the reference design `2a`. It SHALL show: a left spine (app mark, a vertical genre label, a back control, and a current-episode marker); a title block with a studio/eyebrow line, the show title, and a spec sheet of rating, run summary, creator, and years; a framed key-art panel with corner ticks and a floating resume card (circular progress ring + play glyph + resume label); a horizontally-scrolling episode strip for the selected season; and a bottom action bar with a season selector and playback controls. The Show view SHALL present its own left spine and SHALL NOT show the main navigation rail.

#### Scenario: Show view renders from the model
- **WHEN** the Show view is presented for a show
- **THEN** the title block, spec sheet, key-art panel with resume card, episode strip for the selected season, and the season selector + controls are all displayed, populated from the show model

### Requirement: Season selection
The Show view SHALL let the user switch the selected season via the season selector; changing the season SHALL update the episode strip to that season's episodes and its heading (season name + episode count).

#### Scenario: Switching season updates the strip
- **WHEN** a different season is selected in the season selector
- **THEN** the episode strip shows that season's episodes and the heading reflects the new season's name and episode count

### Requirement: Episode strip marks the current episode
Each episode card SHALL show an episode number badge, runtime, and title; the show's current/resume episode SHALL be marked (e.g. a "NOW" badge and an accent outline).

#### Scenario: Current episode is marked
- **WHEN** the episode strip renders the season containing the resume episode
- **THEN** that episode's card shows the current-episode marker distinct from the others

### Requirement: Remote navigation and dismissal
The Show view SHALL be navigable with the Apple TV remote: the back control, resume/play card, season selector, episode cards, and action-bar controls are focusable with the focus treatment, and a focused element is present at launch. Pressing Menu/Back (or selecting the on-screen back control) SHALL dismiss the Show view and return to Home.

#### Scenario: Focus and dismiss
- **WHEN** the Show view appears and directional focus moves are issued
- **THEN** an element is focused at launch, focus moves among the back control / resume / season selector / episodes / controls, and pressing Menu/Back returns to Home

### Requirement: Launch from the Recommended row
Selecting a poster in the Home Recommended row SHALL open the Show view populated with demo data derived from that poster (at least its title and key art).

#### Scenario: Selecting a recommended poster opens the show
- **WHEN** a Recommended poster is focused and selected
- **THEN** the Show view opens showing a series whose title and key art come from that poster
