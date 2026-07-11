## Why

The tvOS Home screen currently navigates via a top-center pill strip (Home/Movies/Shows/Search) and Settings is a right-aligned overlay panel. An updated design mockup (Claude Design project `3ea3d153-f74d-4ca9-aef4-94f2f1b9a808`, screens `3a`/`3b`/`3c`) replaces both with a left icon rail (with a slide-out Libraries submenu and a live/off server-status indicator) and a full-screen two-pane Settings. We want v2 to match this newer design while preserving the hero carousel and card work already shipped.

## What Changes

- **BREAKING**: Remove the top-center pill nav (`Home`/`Movies`/`Shows`/`Search`) from `TopBar`; navigation moves to a new 118px-wide left icon rail present on every screen (Home and Settings).
- Add a 66×66 app-mark tile at the top of the rail with a 13×13 status dot indicating Jellyfin server connectivity: green + pulsing glow when connected (`ServerStatus.isConnected == true`), dim/gray/static when not.
- Add 5 rail nav icon buttons (Home, Search, Movies, TV Shows, Libraries) with an active/inactive visual treatment (accent-tinted background + left accent bar when active) and a pinned Settings/cog icon at the rail's bottom.
- Add a slide-out **Libraries submenu** (392px panel, blurred backdrop) that opens when the rail's Libraries icon is focused/selected, listing every library with an icon, name, item count, and an "18+" badge + accent tint for adult libraries; Home content behind it dims to 50% opacity rather than being fully covered.
- **BREAKING**: Replace the existing right-aligned 620px `SettingsPanel` overlay with a full-screen two-pane Settings (420px category list + detail pane), reached via the rail's cog icon instead of a top-bar avatar tap. Categories: Playback, Subtitles, Audio, Parental, Server, Account, About. The mockup only specifies Playback's detail content (streaming-quality + playback-method segmented controls, three toggle rows); the other six categories absorb the settings we already ship (profile, accent theme, hero transition/rotation, server status) — see design.md for the exact category mapping.
- Move the clock + profile-avatar readout from the (now-removed) full-width `TopBar` into a small breadcrumb-style row at the top of the Home content area itself (unchanged content, new position).
- Keep unchanged: `HeroView` (backdrop image, `HeroPillTimer`, hex-crumble/fade transition, auto-rotation), `ContinueWatchingRow`, `RecommendedRow`, and the `DesignSystem` tokens (`Palette`, `Typography`, `Theme`) — the rail and new Settings consume these rather than redefining styling.

## Capabilities

### New Capabilities
- `tvos-nav-rail`: the left icon rail (nav icons, active/inactive states, pinned settings icon, server-status dot) and the Libraries slide-out submenu.

### Modified Capabilities
- `tvos-home-screen`: top-center pill nav removed from `TopBar`; navigation and library browsing move to the rail/submenu; clock+avatar readout repositioned into the content area.
- `tvos-settings-menu`: settings entry point moves from a top-bar avatar tap to the rail's cog icon; the settings surface itself is replaced from a right-aligned overlay panel to a full-screen two-pane category/detail layout.
- `tvos-sample-content`: `Library` gains an item-count field (needed by the Libraries submenu rows); sample data adds per-category settings content (playback quality/method/toggles) backing the new Settings detail panes.

## Impact

- `Apps/JellyTV/Sources/Home/TopBar.swift` — pill nav removed; becomes (or is replaced by) the smaller content-area readout row.
- `Apps/JellyTV/Sources/Home/HomeView.swift` — hosts the new rail alongside existing hero/rows content.
- New: a rail component (nav icons, status dot, settings icon) and a Libraries-submenu component under `Apps/JellyTV/Sources/DesignSystem/` or a new `Nav/` group.
- `Apps/JellyTV/Sources/Settings/SettingsPanel.swift`, `SettingsRow.swift` — replaced/rewritten as a full-screen two-pane view; presentation call site in the app shell (`RootView`) changes from an overlay/`fullScreenCover` triggered by an avatar tap to a rail-icon-triggered mode switch.
- `Packages/JellyTVKit/Sources/JellyTVKit/Models.swift` — `Library` gains an item-count field.
- `Packages/JellyTVKit/Sources/JellyTVKit/SampleCatalog.swift` — library counts, and new sample data for the Settings detail panes (playback quality/method/toggle rows).
- No change to `HeroView`, `HeroPillTimer`, `HeroTransitions.metal`/`.swift`, `ContentRows.swift`'s card treatments, or `DesignSystem/Theme.swift`/`Palette.swift`/`Typography.swift`.
