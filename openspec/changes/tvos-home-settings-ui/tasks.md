# Tasks: tvos-home-settings-ui

## 1. Sample content layer (JellyTVKit)

- [x] 1.1 Add `Equatable`/`Sendable` models to `JellyTVKit`: `MediaItem`, `Library`, `HeroFeature`, `ContinueWatchingItem`, `UserProfile`, `ServerStatus`, `SettingsEntry`, plus an `Artwork` gradient descriptor (two OKLCH-ish stops) so cards render without image assets
- [x] 1.2 Add `AccentOption` enum (coral `#F0525F` default, amber `#E8B44A`, blue `#4AA8E8`, green `#3FBF8F`) with hex + display name
- [x] 1.3 Add `SampleCatalog` reproducing the design data: hero "The Deep Signal"; Continue Watching (Deep Signal, Copper Season, Night Cartographers, Undertow, Field Notes); Recommended posters (7, incl. focused idx 2); libraries (Movies, TV Shows, Anime, Documentaries, Music, Home Videos, After Dark 18+, Uncut Films 18+); profile "Marina · marina@home.local · Administrator"; server "reef.local · v10.9.2 · Connected"; settings entries (Profile/Settings/Theme/Server)
- [x] 1.4 Unit tests in `Packages/JellyTVKit`: catalog counts, adult-library flag, hero/profile/server fields, accent option set; `swift test` passes

## 2. Design system (Apps/JellyTV/Sources/DesignSystem)

- [x] 2.1 `Palette` (surfaces, panel, tiered text) + a `Color(hex:)` helper
- [x] 2.2 Bundle Schibsted Grotesk TTFs under `Apps/JellyTV/Resources/Fonts/` and register via `UIAppFonts` in `project.yml` `info.properties`; if the files can't be obtained, implement `Typography` with a `.system(design: .rounded)` fallback (single swap point) and note it
- [x] 2.3 `Typography` scale (hero/title/section/body/caption) resolving Schibsted Grotesk or the fallback
- [x] 2.4 `Theme` (Observable) holding the current `AccentOption`, persisted via `@AppStorage("accentColor")`, injected through the environment; expose `theme.accent` as a SwiftUI `Color`
- [x] 2.5 Reusable components: `Chip` (with 18+ variant), `NavPill`, `MediaCard` (continue + poster variants), `SectionHeader`, and a `focusEffect` modifier (scale + outline + shadow) matching the design's focused state

## 3. Home screen (Apps/JellyTV/Sources/Home)

- [x] 3.1 `TopBar`: logo tile + `jelly·tv` wordmark (accent `·`), centered nav pill (Home active / Movies / Shows / Search), clock, focusable profile avatar
- [x] 3.2 `LibraryChipsRow`: horizontal focusable chips from the catalog, adult chips accent-tinted + `18+` badge
- [x] 3.3 `HeroView`: eyebrow (accent line + label), title, rating/meta line (badges + dots), synopsis, `Resume`/`Details`/`＋` actions with the focused/glow treatment on Resume, and animated-ish pager dots
- [x] 3.4 `ContinueWatchingRow`: 280×140 cards with artwork gradient, title overlay, accent progress bar, remaining pie/indicator, episode label
- [x] 3.5 `RecommendedRow`: 168×248 poster cards with title overlay + meta, focus scale/outline
- [x] 3.6 `HomeView` composition on the `#0B0D13` gradient background; horizontal rows scroll to keep the focused card visible (`ScrollViewReader`); default focus lands on hero Resume at launch

## 4. Settings menu (Apps/JellyTV/Sources/Settings)

- [x] 4.1 `SettingsPanel`: right-aligned 620px account panel over a dimmed + blurred Home; profile header (gradient avatar, name, email·role)
- [x] 4.2 `SettingsRow`: icon tile + label + description + optional trailing value + chevron, focusable with highlight; rows Profile/Settings/Theme/Server from the catalog; Sign Out in accent color
- [x] 4.3 Present the panel from the top-bar avatar (overlay/`fullScreenCover`); dismiss with Menu/Back to return to Home
- [x] 4.4 Theme row selects among the four accents; selection updates `Theme` live (Home + Settings) and persists; Theme value shows "Dark · <accent>"

## 5. Wire-up

- [x] 5.1 Replace the placeholder `RootView` with the app shell that hosts `HomeView` and can present `SettingsPanel`; inject `Theme` at the root
- [x] 5.2 Non-Home nav tabs (Movies/Shows/Search) route to a lightweight "Coming soon" placeholder (no crash/dead-end)

## 6. Build, run, verify

- [x] 6.1 `xcodegen generate`; build the `JellyTV` scheme for a tvOS simulator (via XcodeBuildMCP) with no warnings-as-errors; `swift test` still passes
- [x] 6.2 Launch on the tvOS simulator; drive the focus engine (directional moves + select): confirm launch focus, focus visuals, row scrolling, avatar → Settings, accent change persisting; capture Home and Settings screenshots
- [x] 6.3 Walk every scenario in `specs/**` (home sections from catalog, adult 18+ chip, focus/scroll, continue progress, settings open/dismiss, rows+values, live accent change + persistence, non-Home tab safe, launch-to-Home) and confirm each passes
- [x] 6.4 Commit on a feature branch with the Design reference; clean `git status` after build (generated project/fonts handled per `.gitignore`)
