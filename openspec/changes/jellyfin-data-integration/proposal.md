## Why

The app currently runs entirely on `SampleCatalog` — hardcoded demo data. Users who connect to a real Jellyfin server see the same demo content regardless of their actual library. This change replaces the sample data with live Jellyfin API data so the Home screen, Libraries submenu, and meta-library screens (Movies, Shows) reflect the user's actual media collection. It also introduces the app's library classification system (NSFW/Anime meta-categories) as the foundation for content filtering and personalized recommendations.

## What Changes

- **New Jellyfin API client** in `JellyTVKit` — fetches libraries, items, and builds authenticated image URLs
- **Library classification** — maps Jellyfin's `CollectionType` + name heuristics into 8 meta-categories (`movies`, `moviesxxx`, `animefilm`, `shows`, `anime`, `hentai`, `videos`, `porn`) with NSFW/Anime flags
- **Home screen data** — Continue Watching fetched from Jellyfin's `IsResumable` items; Recommended computed from watch history + meta-category affinity; Hero carousel assembled from a mix of both; all three sections filtered by a "Hide NSFW" preference
- **Libraries submenu** — shows the user's actual Jellyfin libraries with meta-category classification instead of sample entries
- **Meta-library screens** — Movies and Shows rail destinations become real content grids showing all items across libraries of the matching CollectionType
- **Hide NSFW toggle** — new setting in Settings → Home, enabled by default
- **Periodic refresh** — home data refreshes on a timer and on reconnection
- **Image loading** — custom `AsyncImage`-compatible loader with Jellyfin auth headers for artwork
- Music and books libraries are ignored

## Capabilities

### New Capabilities
- `jellyfin-data-layer`: Jellyfin REST API client, DTOs (items, user views, auth), authenticated image URL loading — all in the shared `JellyTVKit` package
- `tvos-library-classification`: Meta-category system classifying Jellyfin libraries into 8 categories via `CollectionType` + name regex heuristics, with NSFW/Anime flag derivation
- `tvos-home-data`: Home screen data pipeline — fetching Continue Watching, computing Recommended via watch-history affinity + fallback random, assembling Hero from both sources, applying NSFW filtering, and periodic refresh

### Modified Capabilities
- `tvos-home-screen`: Hero count becomes dynamic (up to 6 from live data); Continue Watching row hides when empty; Recommended row uses computed data; all sections respect NSFW filter
- `tvos-sample-content`: Retained for design-screenshot hooks (`JT_SHOW_DEMO`, `JT_FOCUS`, `JT_SETUP_DEMO`) but no longer the primary runtime data source
- `tvos-settings-menu`: Home category gains a "Hide NSFW" toggle (enabled by default) filtering all Home sections
- `tvos-nav-rail`: Libraries submenu content switches from sample libraries to live Jellyfin libraries classified by meta-category
- `tvos-hero-carousel`: Hero pill timer count adapts to dynamic number of hero slides

## Impact

- **`JellyTVKit`**: New files — `JellyfinClient.swift`, `JellyfinItem.swift`, `JellyfinUserView.swift`, `ItemsResponse.swift`, `MetaCategory.swift`, `LibraryClassifier.swift`, `JellyfinAsyncImage.swift`; modified — `Models.swift` (conversion helpers), `JellyfinAPI.swift` (expanded DTOs)
- **`Apps/JellyTV/Sources/`**: New files — `AppState.swift` (data orchestrator), `MetaLibraryView.swift`; modified — `RootView.swift`, `HomeView.swift`, `ContentRows.swift`, `LibrariesSubmenu.swift`, `HomeDetail.swift`, `SettingsCategoryList.swift`, `ServerConnection.swift`, `DesignSystem/Components.swift` (image loading integration)
- **`Apps/Remote/`**: Not affected by this change
- **`openspec/specs/`**: 3 new specs, 5 delta specs
- **`project.yml`**: No changes needed
