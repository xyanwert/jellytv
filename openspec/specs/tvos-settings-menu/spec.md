# tvos-settings-menu Specification

## Purpose

Defines the tvOS Settings menu: an account panel over the dimmed Home screen, its focusable rows, and the live-updating theme accent selection.

## Requirements

### Requirement: Account panel over dimmed Home
The tvOS app SHALL present a Settings menu as a right-aligned account panel over a dimmed, blurred Home background, opened from the top-bar profile avatar, matching the reference design. The panel SHALL contain a profile header (avatar, name, email·role) and rows for Profile, Settings, Theme, Server, and Sign Out.

#### Scenario: Settings opens and dismisses
- **WHEN** the profile avatar in the Home top bar is focused and selected
- **THEN** the account panel appears over a dimmed/blurred Home, and it can be dismissed with the remote's Menu/Back to return to Home

#### Scenario: Panel content matches the profile and server
- **WHEN** the account panel is shown
- **THEN** the profile header shows the sample user (name, email, role) and the Server row shows the sample server name/version and a connected status

### Requirement: Rows are focusable with values and chevrons
Each account row (Profile, Settings, Theme, Server) SHALL show an icon tile, a label, a description, an optional trailing value, and a chevron, and SHALL be focusable with a focus highlight; Sign Out SHALL render in the accent color.

#### Scenario: Rows focus and show values
- **WHEN** focus moves through the account rows
- **THEN** each row shows its label/description and, where applicable, its value (e.g. Theme "Dark · <accent>", Server "Connected"), with the focused row highlighted

### Requirement: Theme row changes the accent live
The Theme row SHALL let the user change the app accent among the four options; the change SHALL apply immediately to both screens and persist across launches.

#### Scenario: Changing the accent updates the UI
- **WHEN** the user selects a different accent from the Theme row
- **THEN** accent-colored elements on the Settings panel and the Home screen update immediately, the Theme row's value reflects the new accent, and the choice survives relaunch
