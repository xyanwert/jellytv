# Design: tvos-home-settings-ui

## Context

The `JellyTV` tvOS target (SwiftUI, tvOS 17) currently shows a placeholder `RootView`. We are building the first two real screens — Home and Settings — from a finished visual design (`Design/jelly-tv-screens.dc.html`, target 1920×1080). No Jellyfin backend exists yet, so screens render from sample data. `JellyTVKit` is the shared package both apps link; it is where models and the sample catalog go. Owner has XcodeBuildMCP available for build/simulator loops.

Design tokens (from the reference): surfaces `#0B0D13`/`#0D1220` gradients, panel `rgba(20,22,30,0.96)`, primary text `#F4F5F7` with translucent-white tiers (.75/.65/.55/.5/.48/.4), accent default `#F0525F` with options coral/amber/blue/green, radii 24 (screen) / 20 (panel) / 14 (card, chip icon) / 999 (pill), font **Schibsted Grotesk**.

## Goals / Non-Goals

**Goals:**
- Pixel-faithful, **remote-navigable** Home and Settings screens using the tvOS focus engine (not static mockups).
- A reusable design system (colors, type, accent theming, focusable components) both screens share.
- Typed models + `SampleCatalog` in `JellyTVKit` so views bind to real types — the seam for future Jellyfin data.
- A working, persisted accent-color theme driven from the Settings → Theme row.

**Non-Goals:**
- Any real Jellyfin networking/auth (separate change). The Detail screen and Movies/Shows/Search destinations. iOS companion changes. Real playback.

## Decisions

### D1 — Layout scale: design-fixed points, no scaling math
The design is authored at 1920×1080, which is exactly tvOS's point resolution (@1x = 1920×1080 pt, rendered @2x). So design pixel values map **1:1 to SwiftUI points** — no conversion needed. Use the design's numbers directly (padding 80, hero title 74, etc.). *Alternative rejected:* a scale factor — unnecessary and error-prone.

### D2 — Screen composition & navigation
`RootView` becomes a `TVAppShell` holding the top bar + the active destination. Home is the only populated destination; the nav pill's other tabs (Movies/Shows/Search) are focusable but route to a lightweight "Coming soon" placeholder. Settings is presented as an **overlay** (`.fullScreenCover` or a `ZStack` overlay with dimmed/blurred Home behind, matching `1c`), opened from the top-bar avatar. *Alternative rejected:* making Settings a nav tab — the design shows it as an account panel over Home.

### D3 — Focus engine
Use SwiftUI's tvOS focus system: interactive elements are `.focusable()` (or `Button`s with `.buttonStyle(.card)` where the card lift is wanted). Rows are `ScrollView(.horizontal)` inside `ScrollViewReader`; focus drives horizontal scrolling. Focus visuals come from `@Environment(\.isFocused)` / `.focused` state → scale + outline + shadow (hero Resume button, Recommended poster idx-2 focused-state in the design). A `FocusState`-driven default focus lands on the hero Resume action at launch. *Alternative rejected:* `TabView`/collection wrappers that fight custom focus visuals.

### D4 — Design system module (`Apps/JellyTV/Sources/DesignSystem/`)
- `Palette` — static colors from tokens; `Color(hex:)` helper.
- `Typography` — a `Font` scale (hero/title/section/body/caption) using Schibsted Grotesk with weights, falling back to `.system(design: .rounded)` if the font isn't registered.
- `Theme` — an `@Observable` (or `ObservableObject`) holding the current `AccentOption`, persisted via `@AppStorage("accentColor")`; injected through the environment so any view reads `theme.accent`.
- Components: `Chip`, `NavPill`, `MediaCard` (continue + poster variants), `SectionHeader`, `FocusableCard` modifier.
Keeping these in the app target (not `JellyTVKit`) is fine — they're tvOS/SwiftUI-only; `JellyTVKit` stays platform-shared and holds models/data.

### D5 — Content models + sample data in `JellyTVKit`
Add value types: `MediaItem` (id, title, meta, kind, artworkGradient), `Library` (name, isAdult), `HeroFeature` (title, eyebrow, rating, meta, synopsis, resumeLabel, progress), `ContinueWatchingItem` (item, episodeLabel, progress, remaining), `UserProfile` (name, email, role, initial), `ServerStatus` (name, version, isConnected), `SettingsEntry` (title, subtitle, value, iconKind). A `SampleCatalog` static provides the design's exact demo data (hero "The Deep Signal", the continue/poster/library lists, profile "Marina", server "reef.local · v10.9.2 · Connected"). Artwork uses OKLCH-style gradients recreated as SwiftUI gradients (design draws gradients, not photos), so no image assets are required. All models are `Sendable`/`Equatable` and unit-tested. This is the abstraction a future `JellyfinCatalog` will also satisfy.

### D6 — Accent theming is real and persisted
The four accent options (coral `#F0525F`, amber `#E8B44A`, blue `#4AA8E8`, green `#3FBF8F`) are an enum in `JellyTVKit`. The Settings → Theme row cycles/selects them; the choice is stored in `@AppStorage` and applied live across both screens (hero eyebrow, buttons, progress bars, chips, Sign Out). This makes the Theme row functional rather than decorative and exercises the required-reason UserDefaults API already declared in the privacy manifest.

### D7 — Typography: bundle Schibsted Grotesk (SIL OFL)
Bundle the variable/weighted TTFs under `Apps/JellyTV/Resources/Fonts/`, register via `UIAppFonts` in the target Info.plist (`project.yml` `info.properties`). If acquiring the font files is blocked at implementation time, fall back to `.system(size:weight:design: .rounded)` behind the `Typography` API so the screens still build and read correctly — the font is swappable in one place. *Alternative rejected:* hard-coding the system font — loses the design's identity.

### D8 — Wordmark vs product name
The design's in-app logo treatment is `jelly·tv`. The App Store product name is "Why.So.Jelly?" and the technical name is JellyTV. The in-app top-bar wordmark follows the **design** (`jelly·tv`) for fidelity; this is cosmetic and independent of the store/bundle identity. Flag for the owner in the summary in case they want it reconciled.

## Risks / Trade-offs

- [tvOS focus visuals differ from the static design's "focused" snapshot] → Implement real focus effects (scale/outline/shadow) matching the design's focused poster/button; verify by driving focus in the simulator, not just a screenshot.
- [Schibsted Grotesk files unavailable offline] → `Typography` fallback to system rounded (D7); screens still ship, font swapped later in one place.
- [Over-abstracting models before the real API is known] → Keep models thin and design-shaped; they're sample-data carriers, explicitly provisional, and cheap to reshape when Jellyfin's schema lands.
- [Horizontal focus scrolling jank on long rows] → Use `ScrollViewReader` + `.scrollTargetBehavior`/manual `scrollTo(focusedID)`; cap sample rows to the design's counts.
- [Launch-to-Home changes the tvos-app-shell "launch" scenario] → Spec MODIFIES that requirement; verification checks the app launches to Home (top bar + hero) rather than the placeholder.

## Migration Plan

Additive within the tvOS target. `RootView`'s placeholder is replaced by the Home composition; the old placeholder text/screenshot references in `tvos-app-shell` are superseded by the MODIFIED requirement. Rollback = restore the placeholder `RootView`. No data, signing, or release-pipeline impact.

## Open Questions

- Final accent default — design defaults to coral; keep unless the owner prefers another.
- Whether the nav tabs beyond Home should show "Coming soon" or be visually disabled (default: focusable → lightweight placeholder).
