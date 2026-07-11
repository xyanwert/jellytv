## ADDED Requirements

### Requirement: Full-screen two-pane Settings screen
The tvOS app SHALL present Settings as a full-screen peer of Home (not an overlay/dimmed panel), reached by selecting the rail's Settings icon, and laid out as the shared left navigation rail plus a two-pane content area: a category list (left) and a detail pane (right) for the selected category. Selecting the rail's Home icon (or the remote's Menu/Back) returns to Home.

#### Scenario: Settings opens as a full screen
- **WHEN** the rail's Settings icon is focused and selected
- **THEN** the app shows the rail (with Settings marked active) plus the category list and detail pane, replacing the Home content rather than overlaying it

#### Scenario: Settings dismisses back to Home
- **WHEN** Settings is shown and the remote's Menu/Back is pressed, or the rail's Home icon is selected
- **THEN** the app returns to the Home screen

### Requirement: Settings categories
The category list SHALL show one row per category — Playback, Subtitles, Audio, Parental, Server, Account, About — each with a label and a one-line description; the selected category is focusable and shows an accent-tinted background and left accent bar, and its detail content renders in the detail pane.

#### Scenario: Selecting a category updates the detail pane
- **WHEN** a category row is focused and selected
- **THEN** that row shows the active treatment and the detail pane shows that category's content

### Requirement: Playback category detail
The Playback category's detail pane SHALL show a streaming-quality segmented control (Auto/1080p/4K), a playback-method segmented control (Direct Play/Transcode), and toggle rows for "Auto-play next episode", "Skip intros", and "HDR passthrough", each with a label and description.

#### Scenario: Playback controls are focusable and reflect state
- **WHEN** the Playback category is shown
- **THEN** the segmented controls show their active option highlighted and each toggle shows its on/off state, and each control is focusable with the remote

### Requirement: Account category detail
The Account category's detail pane SHALL show the profile header (avatar, name, email·role) and a Sign Out action in the accent color, plus the accent-theme picker (four options) and the hero transition/rotation pickers.

#### Scenario: Account content matches the profile
- **WHEN** the Account category is shown
- **THEN** the profile section shows the sample user's name, email, and role

### Requirement: Server category detail
The Server category's detail pane SHALL show the sample server's name, version, and connected status.

#### Scenario: Server content matches the sample server status
- **WHEN** the Server category is shown
- **THEN** the detail pane shows the sample server name/version and a connected indicator matching `ServerStatus.isConnected`

### Requirement: Placeholder categories are non-blocking
The Subtitles, Audio, Parental, and About categories SHALL not crash or dead-end; each MAY render a lightweight placeholder, since no real backend or design content exists for them yet.

#### Scenario: Placeholder category is safe
- **WHEN** the Subtitles, Audio, Parental, or About category is selected
- **THEN** the detail pane shows a placeholder and the user can select a different category without error

## MODIFIED Requirements

### Requirement: Theme accent picker changes the accent live
The accent-theme picker (now shown in the Account category's detail pane) SHALL let the user change the app accent among the four options; the change SHALL apply immediately across Home and Settings and persist across launches.

#### Scenario: Changing the accent updates the UI
- **WHEN** the user selects a different accent from the Account category's theme picker
- **THEN** accent-colored elements on Settings and Home update immediately, the picker reflects the new accent, and the choice survives relaunch

## REMOVED Requirements

### Requirement: Account panel over dimmed Home
**Reason**: Settings is no longer an overlay panel triggered from a top-bar avatar; it's a full-screen peer of Home reached via the rail's Settings icon.
**Migration**: See "Full-screen two-pane Settings screen" above.

### Requirement: Rows are focusable with values and chevrons
**Reason**: The flat Profile/Settings/Theme/Server row list is replaced by the category-list-plus-detail-pane shape; individual settings no longer share one row style with a trailing value and chevron.
**Migration**: See "Settings categories", "Playback category detail", "Account category detail", and "Server category detail" above.
