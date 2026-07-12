# tvos-nav-rail Specification

## Purpose

Defines the persistent left navigation rail shared by the tvOS Home and Settings screens: its icon buttons and active-state treatment, the server-connectivity status dot, the Libraries slide-out submenu, and the non-blocking behavior of secondary rail destinations.

## Requirements

### Requirement: Left navigation rail
The tvOS app SHALL present a persistent 118px-wide left navigation rail on every screen (Home and Settings), containing: an app-mark tile with a server-status dot, five nav icon buttons (Home, Search, Movies, TV Shows, Libraries), and a pinned Settings icon at the bottom.

#### Scenario: Rail renders on Home and Settings
- **WHEN** either the Home screen or the Settings screen is shown
- **THEN** the same rail component is present at the left edge with identical styling, differing only in which icon is marked active

#### Scenario: Active icon is visually distinguished
- **WHEN** a rail icon corresponds to the currently-shown screen (or, for Libraries, the currently-open submenu)
- **THEN** that icon shows an accent-tinted background, an accent border, a white icon color, and a left accent bar; all other icons show a transparent background, a subtle border, and a dimmed icon color

### Requirement: Server connectivity status dot
The rail's app-mark tile SHALL show a small status dot reflecting `ServerStatus.isConnected`: connected renders a green, glowing, pulsing dot; disconnected renders a dim, static, non-glowing dot of the same size and position.

#### Scenario: Connected server shows a live pulse
- **WHEN** the sample server status has `isConnected == true`
- **THEN** the status dot is green with a glow and a continuous pulse animation

#### Scenario: Disconnected server shows a static dot
- **WHEN** the sample server status has `isConnected == false`
- **THEN** the status dot is a dim gray with no glow and no animation

### Requirement: Libraries slide-out submenu
Selecting the rail's Libraries icon SHALL open a 392px submenu panel listing every library (icon, name, item count, and an accent-tinted "18+" badge for adult libraries) without navigating away from Home; the Home content behind it dims rather than being fully hidden, and Back/Menu (or reselecting another rail icon) closes it.

#### Scenario: Libraries submenu opens over dimmed Home
- **WHEN** the rail's Libraries icon is selected
- **THEN** the submenu panel appears, the rail marks Libraries active, and the Home content behind is visible but dimmed

#### Scenario: Adult libraries are marked in the submenu
- **WHEN** the submenu renders a library flagged adult
- **THEN** that row shows the accent-tinted background/border, the pinkish name color, and the "18+" badge

#### Scenario: Submenu dismisses back to Home
- **WHEN** the submenu is open and the remote's Menu/Back is pressed (or another rail icon is selected)
- **THEN** the submenu closes and Home returns to full opacity

### Requirement: Secondary rail destinations are non-blocking
Selecting the rail's Search, Movies, or TV Shows icon SHALL not crash or dead-end; these destinations are out of scope for this change and MAY render a lightweight placeholder, consistent with the existing non-Home nav-tab behavior.

#### Scenario: Non-Home rail icon is safe
- **WHEN** the Search, Movies, or TV Shows rail icon is selected
- **THEN** the app remains responsive (e.g. shows a "coming soon" placeholder) and the user can return to Home
