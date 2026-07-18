# tvos-settings-menu Delta Spec

## ADDED Requirements

### Requirement: Home category includes Hide NSFW toggle
The Home category's detail pane SHALL include a "Hide NSFW" toggle row (enabled by default) that controls `AppState.hideNSFW`. When toggled, the home screen's hero, Continue Watching, and Recommended sections SHALL immediately re-filter to include or exclude NSFW library content without re-fetching from the server. The preference SHALL persist across launches via `UserDefaults`.

#### Scenario: Hide NSFW toggle is present and defaults to on
- **WHEN** the Home category is selected in Settings
- **THEN** the detail pane shows a "Hide NSFW" toggle row as the first row, labeled "Hide NSFW" with a description like "Exclude adult content from Home", and it is in the "on" position by default

#### Scenario: Toggling Hide NSFW updates the home screen
- **WHEN** the user toggles "Hide NSFW" to off and returns to Home
- **THEN** NSFW items appear in the hero, Continue Watching, and Recommended sections if any exist on the server

#### Scenario: Hide NSFW preference persists
- **WHEN** the user sets "Hide NSFW" to off and relaunches the app
- **THEN** the toggle remains in the "off" position

### Requirement: Home category includes hero rotation and transition controls
The Home category's detail pane SHALL continue to include the hero rotation interval segmented control (5s / 15s / 30s) and the hero transition style segmented control (Crumble / Fade), as previously defined. The Hide NSFW toggle SHALL be the first control, followed by Rotation and Transition.

#### Scenario: Home category controls are all present
- **WHEN** the Home category is selected
- **THEN** the detail pane shows Hide NSFW toggle, Rotation control, and Transition control in that order, all focusable with the remote

## MODIFIED Requirements

### Requirement: Settings categories
The category list SHALL show one row per category — Playback, Subtitles, Audio, Home, Appearance, Parental, Server, Account, About — each with a label and a one-line description; the selected category is focusable and shows an accent-tinted background and left accent bar, and its detail content renders in the detail pane.

#### Scenario: Home category is present with correct label
- **WHEN** the Settings screen is opened
- **THEN** the Home category row appears with label "Home" and description "Hero rotation, transitions, NSFW filter"

### Requirement: Account category detail
The Account category's detail pane SHALL show the profile header (avatar, name, email·role) and a Sign Out action in the accent color, plus the accent-theme picker (four options).

#### Scenario: Hero and transition controls are in Home, not Account
- **WHEN** the Account category is selected
- **THEN** the hero rotation and transition controls are NOT shown in Account; they are in the Home category detail pane instead
