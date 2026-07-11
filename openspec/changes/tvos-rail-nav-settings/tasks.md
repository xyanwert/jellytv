# Tasks: tvos-rail-nav-settings

## 1. Sample content layer (JellyTVKit)

- [x] 1.1 `Library`: add `itemCount: String` (display-ready, e.g. `"428"`, `"1.2k"`); update `SampleCatalog.libraries` with counts matching the design (Movies 428, TV Shows 96, Anime 213, Documentaries 154, Music 1.2k, Home Videos 37, After Dark 62, Uncut Films 18)
- [x] 1.2 Replace `SettingsEntry`/`Kind` with `SettingsCategory` (id/kind: `playback`, `subtitles`, `audio`, `parental`, `server`, `account`, `about`; `label`; `description`); add `SampleCatalog.settingsCategories` with the 7 entries and descriptions matching the design (`"Quality, auto-play"`, `"Language, size"`, `"Output, passthrough"`, `"PIN, 18+ libraries"`, `"Connection, sync"`, `"Profile, sign out"`, `"Version, licenses"`)
- [x] 1.3 Add Playback sample data to `SampleCatalog`: `playbackQualityOptions: [String]` (`Auto`/`1080p`/`4K`, `4K` default-active), `playbackMethodOptions: [String]` (`Direct Play`/`Transcode`, `Direct Play` default-active), and a `PlaybackToggle` model (`label`, `description`, `isOnByDefault`) with 3 sample rows (Auto-play next episode: on, Skip intros: on, HDR passthrough: off)
- [x] 1.4 Remove now-unused `SettingsEntry` references; update/extend `SampleCatalogTests`: library item counts present and non-empty, `settingsCategories` has exactly 7 entries with the expected kinds, Playback sample data is non-empty and defaults match; `swift test` passes

## 2. Nav rail component (Apps/JellyTV/Sources/Nav)

- [x] 2.1 `NavIcons.swift`: SwiftUI `Shape`/`Path`-based icons matching the design's SVG paths — Home (house), Search (magnifying glass), Movies (film-strip rect + tick marks), TV Shows (tv-with-antenna rect), Libraries (2×2 rounded-square grid with a `+` in place of the 4th square), Cog (settings gear)
- [x] 2.2 `NavDestination.swift`: enum with `.home`, `.settings`, plus placeholder cases for `.search`/`.movies`/`.tv`; `.libraries` modeled as separate submenu-open state, not a destination (per design.md)
- [x] 2.3 `StatusDot.swift`: 13×13 circular dot, 2px white border; connected = `#58D399` fill + glow shadow + `statusPulse`-equivalent looping animation; disconnected = dim gray fill, no shadow, no animation — driven by `ServerStatus.isConnected`
- [x] 2.4 `NavRail.swift`: 118px-wide rail — app-mark tile (66×66, rounded 18, white bg) with `StatusDot` overlay top-left; 5 nav icon buttons (60×60, rounded 17, gap 14) with active/inactive styling (accent-tinted bg/border/left-bar when active, dimmed/transparent when not) driven by the current `NavDestination`/submenu state; pinned Settings/cog icon at the bottom with the same active treatment; all icons focusable
- [x] 2.5 `LibrariesSubmenu.swift`: 392px panel — blurred/translucent background, "LIBRARIES" eyebrow + "Your Media" title, one row per `SampleCatalog.libraries` entry (icon tile, name, item count, accent-tinted "18+" badge for adult libraries with pinkish name color + tinted row bg/border for adult rows), focusable rows

## 3. Settings screen (Apps/JellyTV/Sources/Settings — rewrite)

- [x] 3.1 Remove the old `SettingsPanel.swift` (620px overlay) and `SettingsRow.swift` (flat row list); this replaces `tvos-settings-menu`'s previous shape entirely (see design.md)
- [x] 3.2 `SettingsCategoryList.swift`: 420px-wide left pane — "SYSTEM" eyebrow + "Settings" title, focusable rows from `SampleCatalog.settingsCategories` (label + description), active category gets accent-tinted bg + left accent bar
- [x] 3.3 `PlaybackDetail.swift`: streaming-quality segmented control, playback-method segmented control, 3 toggle rows from `SampleCatalog`'s Playback sample data, session-local `@State` (not persisted)
- [x] 3.4 `AccountDetail.swift`: profile header (avatar, name, email·role) + Sign Out (accent color) from `SampleCatalog.profile`, plus the accent-theme picker (4 options, live + persisted via `Theme`) and the hero Transition/Rotation pickers (moved from the old `SettingsPanel`, same live-update + persistence behavior)
- [x] 3.5 `ServerDetail.swift`: server name/version/connected status from `SampleCatalog.serverStatus`
- [x] 3.6 `PlaceholderDetail.swift`: lightweight "coming soon" content reused for Subtitles/Audio/Parental/About categories
- [x] 3.7 `SettingsView.swift`: composes `NavRail` (Settings active) + `SettingsCategoryList` + the selected category's detail view; default focus lands on the first category (Playback)

## 4. Home screen rewrite (Apps/JellyTV/Sources/Home)

- [x] 4.1 Remove the top-center pill nav (Home/Movies/Shows/Search) from `TopBar.swift`; keep/relocate the wordmark out of the top bar (it now lives in the rail's app-mark tile) and reduce `TopBar` to (or replace it with) a small content-area readout row: "Home // Featured"-style eyebrow left, clock + profile avatar right
- [x] 4.2 `HomeView.swift`: compose `NavRail` (Home active, or Libraries active + `LibrariesSubmenu` shown) alongside the existing hero/Continue Watching/Recommended content; when the Libraries submenu is open, dim Home content to 50% opacity without removing it from the hierarchy
- [x] 4.3 Verify `HeroView`/`HeroPillTimer`/hex-crumble transition, `ContinueWatchingRow`, and `RecommendedRow` are unchanged (no edits needed — confirm during review, not modified by this task group)

## 5. Root shell wiring (Apps/JellyTV/Sources)

- [x] 5.1 `RootView.swift`: own `NavDestination` + `isLibrariesOpen` state; route rail selections — Home shows `HomeView`, Settings shows `SettingsView`, Search/Movies/TV Shows show the existing "coming soon" placeholder, Libraries toggles the submenu over Home without changing the active destination
- [x] 5.2 Wire dismissal: remote Menu/Back (and re-selecting Home in the rail) closes the Libraries submenu when open, else returns from Settings to Home
- [x] 5.3 Default focus: app launch still lands on the hero's Resume action (unchanged from `tvos-home-screen`'s existing focus requirement); Settings entry focuses the first category row

## 6. Build, run, verify

- [x] 6.1 `xcodegen generate`; build the `JellyTV` scheme for a tvOS simulator (via XcodeBuildMCP) with no warnings-as-errors; `swift test` passes in `Packages/JellyTVKit`
- [x] 6.2 Launch on the tvOS simulator; drive the focus engine: rail icons focusable and show active/inactive treatment correctly, status dot renders connected (green/pulsing), Libraries submenu opens/dims Home/closes, Settings opens full-screen from the rail cog and each category switches its detail pane, Playback controls and Account's theme/transition/rotation pickers still work live; capture screenshots of Home, Home+Libraries-submenu, and Settings
- [x] 6.3 Walk every scenario in `specs/**` for this change (`tvos-nav-rail`, and the modified `tvos-home-screen`/`tvos-settings-menu`/`tvos-sample-content` requirements) and confirm each passes
- [ ] 6.4 Commit on a feature branch with the Design reference; clean `git status` after build (generated project handled per `.gitignore`)
