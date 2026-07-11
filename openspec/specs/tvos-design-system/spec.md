# tvos-design-system Specification

## Purpose

Defines the shared design-system module for the tvOS app: color palette, typography, themeable accent color, and reusable focusable components used consistently across the Home and Settings screens.

## Requirements

### Requirement: Shared palette and typography
The tvOS app SHALL provide a design-system module exposing the design's color palette (surfaces `#0B0D13`/gradients, panel `rgba(20,22,30,0.96)`, primary text `#F4F5F7`, tiered translucent-white text) and a typography scale (hero, title, section, body, caption) using Schibsted Grotesk, with a system-rounded fallback if the font is not registered.

#### Scenario: Screens render from shared tokens
- **WHEN** the Home and Settings screens are built
- **THEN** they source colors and fonts from the design-system module (no ad-hoc hex literals scattered per view), and the app builds whether or not the Schibsted Grotesk font files are present

### Requirement: Persisted themeable accent color
The app SHALL support the four design accent options — coral `#F0525F` (default), amber `#E8B44A`, blue `#4AA8E8`, green `#3FBF8F` — as a selectable theme persisted across launches and injected into the view environment.

#### Scenario: Accent persists and applies app-wide
- **WHEN** the accent is changed and the app is relaunched
- **THEN** the previously selected accent is restored and applied to accent-colored elements (hero eyebrow, primary/Resume actions, progress bars, adult-library chips, Sign Out) on both screens

### Requirement: Reusable focusable components
The design-system module SHALL provide reusable components used by both screens — at minimum a chip/pill, a media card (continue and poster variants), and a section header — that express tvOS focus state (scale/outline/shadow) consistently.

#### Scenario: Components show consistent focus treatment
- **WHEN** a focusable component receives focus via the remote
- **THEN** it applies the shared focus effect (e.g. scale-up with outline and elevated shadow) matching the design's focused-state treatment
