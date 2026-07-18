## Context

The app currently uses `SampleCatalog` — a hardcoded set of demo models — to populate every screen: Home hero, Continue Watching, Recommended, Libraries submenu, Settings categories, and detail views. A user who connects to their real Jellyfin server still sees the same demo content. The underlying `JellyfinAPI` DTOs and `ServerConnection` already authenticate and reach a server, but nothing downstream consumes that connection for content browsing.

The v1 app (`jelly-tv-ios`) has a working Jellyfin API client, DTOs, library classification, and SwiftData-backed local state. This design ports the ideas from v1 into the new architecture but keeps the implementation clean and simpler — no SwiftData (yet), no CloudKit, no Wallhaven wallpaper integration. Just HTTP → typed models → UI.

## Goals / Non-Goals

**Goals:**
- Fetch real libraries, items, and images from a connected Jellyfin server
- Classify libraries into 8 meta-categories with NSFW/Anime flags
- Drive Home screen (hero, Continue Watching, Recommended) from live data
- Show real user libraries in the Libraries submenu
- Make Movies and Shows rail tabs show actual content grids
- Add a "Hide NSFW" preference that filters all Home content
- Refresh home data periodically and on reconnection
- Load Jellyfin artwork images through the auth layer

**Non-Goals:**
- Detail screens (ShowView, MovieDetailView) — still use placeholder data from sample catalog or minimal JellyfinItem conversion; full detail integration is a future change
- Search — the Search rail tab remains a placeholder
- Local persistence (SwiftData, UserDefaults beyond the NSFW toggle) — fetched data lives in memory only, refetched on reconnection/timer
- User profile / Server status from Jellyfin — these remain hardcoded for now (not part of the data pipeline)
- Music and books libraries — filtered out entirely
- Playback — no player integration in this change

## Decisions

### 1. Data layer lives in JellyTVKit, orchestration in the tvOS app

**Decision:** Place Jellyfin HTTP DTOs (`JellyfinItem`, `JellyfinUserView`, `ItemsResponse`) and the API client (`JellyfinClient`) in the shared `JellyTVKit` package. Place the app-level orchestrator (`AppState`) in the tvOS `Sources/`.

**Rationale:** The iOS Remote will eventually need the same API client and DTOs to browse libraries and control playback. Keeping the HTTP layer in the shared package avoids duplication. `AppState` is tvOS-specific — the iOS companion will have a different data model (focused on remote control, not full browsing).

**Alternatives considered:**
- All in tvOS app: would require copying to iOS later. Rejected.
- All in JellyTVKit: couples the package to SwiftUI's `@Published` / `ObservableObject`. Rejected — the package stays UI-framework-agnostic.

### 2. JellyfinClient uses the existing ServerConnection credentials

**Decision:** `JellyfinClient` is initialized with a `baseURL`, `apiKey`, and `deviceId` — all available from the `ServerConnection` singleton after successful connect. It does NOT own or persist credentials itself.

**Rationale:** `ServerConnection` already owns the auth lifecycle (connect, reconnect, sign out, keychain). Adding a second auth store would create split-brain. The client is a pure HTTP executor that takes credentials as input.

**Alternatives considered:**
- Merge API calls into ServerConnection: would make ServerConnection too large (already 380 lines). Rejected — separation of concerns (auth lifecycle vs data fetching).
- Have JellyfinClient read UserDefaults directly: couples client to storage mechanism. Rejected.

### 3. Library classification uses regex on name + CollectionType

**Decision:** Port the v1 heuristic directly: match library name against `/anime|アニメ|hentai/i` for Anime flag, `/xxx|nsfw|adult|porn|jav/i` for NSFW flag, then combine with Jellyfin's `CollectionType` (`movies` / `tvshows` / `homevideos`) to determine the exact `MetaCategory`.

**Rationale:** Jellyfin has no built-in "is adult" or "is anime" field on libraries. Name-based heuristics are the only portable mechanism. The v1 app has proven this works in practice. Users can name their libraries accordingly.

**The mapping table:**

| CollectionType | NSFW | Anime | MetaCategory  |
|----------------|------|-------|---------------|
| movies         | —    | —     | movies        |
| movies         | x    | —     | moviesxxx     |
| movies         | —    | x     | animefilm     |
| tvshows        | —    | —     | shows         |
| tvshows        | —    | x     | anime         |
| tvshows        | x    | x     | hentai        |
| homevideos     | —    | —     | videos        |
| homevideos     | x    | —     | porn          |

Combinations not in this table (e.g. `tvshows` + NSFW only, without Anime) are invalid per the user's spec and `LibraryClassifier` will log a warning and pick the closest match.

### 4. Home data is fetched via per-library fan-out (port from v1)

**Decision:** Continue Watching is fetched by querying `GET /Items` with `filters=IsResumable&sortBy=DatePlayed&sortOrder=Descending&limit=10` for each library, then pooling and sorting client-side by `lastPlayedDate`. Recommended uses a similar approach: fetch items with `sortBy=Random`, filter by meta-category affinity and recency, fill with random fallback. Hero is assembled from the top items of both pools.

**Rationale:** Ported from v1. Jellyfin's `/Items/Resume` endpoint has known issues (it misses finished items and Episodes with `ParentId=SeasonId`). The per-library approach is exact and proven. See v1's `HomeView.swift` lines 471-497 and the web snapshot docs at `docs/web-snapshots/server/src/routes/continue-watching.ts` for the original analysis.

**Alternatives considered:**
- Single `/Items?recursive=true&filters=IsResumable` call without parentId: Jellyfin may not support this query shape server-wide. Rejected.
- Use Jellyfin's "Latest" endpoint: returns recently-added, not in-progress. Rejected.

### 5. Recommended algorithm: client-side, meta-category affinity + recency + random fallback

**Decision:**
1. Identify the user's most-recently-watched items (from Continue Watching data, sorted by `lastPlayedDate`)
2. Determine their `MetaCategory`
3. Fetch up to 3 items from libraries of the same `MetaCategory` (using `sortBy=Random`)
4. Fetch up to 3 items the user hasn't watched recently (or ever) from any library
5. If < 6 items, fill with random picks from any available library
6. Apply NSFW filter last

All filtering and selection happens client-side after batch-fetching from Jellyfin.

**Rationale:** Jellyfin has no recommendation engine. Client-side logic over pooled libraries is the only option. The affinity + recency + random pattern provides a reasonable "Recommended for You" without ML/AI.

### 6. Hero assembly: top 3 continue watching + top 3 recommended

**Decision:** Convert up to 3 `ContinueWatchingItem`s to `HeroFeature`s, plus up to 3 `MediaItem`s from recommended. Total: up to 6 hero slides. On fresh install (0 items), pick up to 3 random items from any library as hero slides.

**Rationale:** The hero carousel is the most prominent real estate. Showing a mix of in-progress and discovery items maximizes utility. The dynamic count (1-6 slides) means the pill timer adapts naturally.

### 7. Image loading: authenticated URL construction + SwiftUI AsyncImage wrapper

**Decision:** `JellyfinClient` exposes `imageURL(itemId:type:tag:maxWidth:) -> URL?` that builds an absolute URL like `{baseURL}/Items/{id}/Images/{type}?tag=...&quality=90&maxWidth=...`. A `JellyfinAsyncImage` SwiftUI view wraps this: it takes a `baseURL`, `apiKey`, `itemId`, `imageType`, and `imageTag`, constructs the URL, and uses a custom `URLSession` with the `MediaBrowser` auth header to load the image.

**Rationale:** Jellyfin serves images via authenticated endpoints. Standard `AsyncImage(url:)` cannot attach custom headers. The `/Items/{id}/Images/{type}` endpoint is the documented Jellyfin image API.

**Alternatives considered:**
- Append `?api_key=` to image URLs (like v1 does for HLS): works but exposes the API key in plaintext URLs. Acceptable for v1 but we use the header approach for consistency.
- Use a general-purpose `CachedAsyncImage` library (like Kingfisher): adds a dependency. Rejected for now — we'll build a minimal version and consider caching later.

### 8. Refresh strategy: timer + reconnection trigger

**Decision:** `AppState` runs a `Task` that sleeps for a configurable interval (default 5 minutes), then re-fetches home data. Separately, `RootView` calls `appState.refresh()` when `server.status` transitions to `.connected`. The timer cancels on disconnect and restarts on reconnect.

**Rationale:** Server-side content changes (new items, playback progress from other devices) should appear without manual refresh. A 5-minute interval is frequent enough for a living-room experience but light enough on the server. Reconnection triggers an immediate refresh because the user just connected.

### 9. `AppState` is the single data owner, injected via environment

**Decision:** One `@MainActor ObservableObject` — `AppState` — owns all home screen data. `RootView` creates it as `@StateObject` and injects it via `.environmentObject()`. Any view in the tree reads from it.

**Rationale:** Follows the existing pattern (`Theme`, `ServerConnection` are both `@StateObject` in `RootView`, injected as `@EnvironmentObject`). Keeps data ownership in one place, avoids prop drilling through the view hierarchy.

## Risks / Trade-offs

- **[No caching]** Items are re-fetched on every timer tick. For large libraries (10k+ items), the per-library fan-out could generate many HTTP requests. → Mitigation: limit queries (`limit=10` for continue watching, `limit=20` for recommended) and only fetch what the Home screen actually displays. Server-side Jellyfin handles the filtering efficiently.

- **[Library name misclassification]** If a user names their anime library "Cartoons" instead of "Anime", the regex won't catch it. → Mitigation: the `LibraryClassifier` is a pure function that's easy to extend with more patterns later. A future Settings UI could let users manually override the classification (out of scope for now).

- **[Refresh during navigation]** If the user is in the Settings screen when the timer fires, the refresh still runs but the home view isn't visible. → Mitigation: data just updates in memory; the home view picks up the new data when navigated back. No UI disruption.

- **[Image loading without caching]** Every image load hits the network. → Mitigation: tvOS has limited memory — caching large backdrops could cause memory pressure. For now, network-only is simpler and safer. We can add `URLCache`-based disk caching later.

- **[No offline support]** Without SwiftData persistence, the app shows nothing when the server is unreachable. → Mitigation: `ServerConnection` already handles "disconnected" state and shows the setup screen. This is intentional — the app is a thin client for an always-on local server. Offline support would be a separate feature.

## Open Questions

- **What refresh interval?** 5 minutes is the starting default. Should it be configurable in Settings? (Deferred — add a setting if users ask for it.)
- **Detail screen data:** ShowView and MovieDetailView still render with sample data (title/key-art overridden). When should those be wired to real Jellyfin items with full episode/season fetching? (Next change — this is already scoped out.)
- **Image caching policy:** Should we set a `URLCache` with a disk-backed store for images? (Deferred — monitor memory/network in testing first.)
