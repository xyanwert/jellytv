## 1. JellyTVKit: DTOs and type definitions

- [x] 1.1 Add `JellyfinItem` DTO to `JellyfinAPI.swift` with PascalCase CodingKeys for all fields (id, name, type, overview, genres, productionYear, officialRating, communityRating, runTimeTicks, seriesName, seriesId, indexNumber, parentIndexNumber, imageTags, backdropImageTags, parentBackdropItemId, parentBackdropImageTags, userData with playbackPositionTicks/played/lastPlayedDate/isFavorite/playCount, childCount)
- [x] 1.2 Add `JellyfinUserView` DTO to `JellyfinAPI.swift` (id, name, collectionType, imageTags)
- [x] 1.3 Add `ItemsResponse<T>` generic wrapper to `JellyfinAPI.swift` (items: [T], totalRecordCount)
- [x] 1.4 Create `MetaCategory.swift` with the 8-case enum + `isNSFW`, `isAnime`, `collectionType` computed properties
- [x] 1.5 Create `LibraryClassifier.swift` with the regex-based `classify(collectionType:name:) -> MetaCategory?` function ported from v1's `LibraryConfig.LibraryClassifier`
- [x] 1.6 Run `swift test` in `Packages/JellyTVKit` to ensure existing tests still pass

## 2. JellyTVKit: API client

- [x] 2.1 Create `JellyfinClient.swift` — struct initialized with `baseURL`, `apiKey`, `deviceId`; builds `MediaBrowser` auth header
- [x] 2.2 Implement `fetchUserViews(userId:) -> [JellyfinUserView]` calling `GET /UserViews?userId=...`
- [x] 2.3 Implement `fetchItems(userId:parentId:includeItemTypes:filters:sortBy:sortOrder:limit:fields:) -> [JellyfinItem]` calling `GET /Items` with query params
- [x] 2.4 Implement `imageURL(itemId:type:tag:maxWidth:) -> URL?` helper building `/Items/{id}/Images/{type}` URLs
- [x] 2.5 Add unit tests for `JellyfinClient` DTO decoding from sample JSON

## 3. JellyTVKit: Item conversion helpers

- [x] 3.1 Add `JellyfinItem.toContinueWatchingItem()` — maps name→title, seriesName/indexNumber→episodeLabel, playbackPositionTicks/runTimeTicks→progress/remaining, imageTags→image
- [x] 3.2 Add `JellyfinItem.toMediaItem()` — maps name→title, genres/type→meta+kinds, imageTags→image
- [x] 3.3 Add `JellyfinItem.toHeroFeature()` — maps name→title, overview→synopsis, genres→genre, productionYear→year, officialRating→certification, userData→resumeLabel
- [x] 3.4 Add `JellyfinUserView.toLibrary()` — maps name, itemCount, and classified MetaCategory to the UI `Library` model

## 4. JellyTVKit: Authenticated image loading

- [x] 4.1 Create `JellyfinAsyncImage.swift` — SwiftUI view wrapping `JellyfinClient.imageURL()`, custom `URLSession` with auth header, shows gradient placeholder on missing/error
- [ ] 4.2 Test image loading against a real Jellyfin server

## 5. tvOS: AppState data orchestrator

- [x] 5.1 Create `Apps/JellyTV/Sources/AppState.swift` — `@MainActor ObservableObject` with `@Published` properties: `libraries: [JellyfinUserView]`, `continueWatching: [ContinueWatchingItem]`, `recommended: [MediaItem]`, `heroes: [HeroFeature]`, `hideNSFW: Bool`
- [x] 5.2 Implement `refresh()` — sequential: fetch user views → classify libraries → fetch continue watching (per-library `IsResumable` fan-out) → fetch items for recommended pool → compute recommended → compute heroes
- [x] 5.3 Implement `computeRecommended()` — affinity from recently watched MetaCategory (3 items) + unwatched items (3) + random fallback to 6 total
- [x] 5.4 Implement `computeHeroes()` — top 3 from continue watching → HeroFeature + top 3 from recommended → HeroFeature; fallback to 3 random on fresh install
- [x] 5.5 Implement NSFW filter helper that excludes items from libraries where `MetaCategory.isNSFW == true`
- [x] 5.6 Implement periodic refresh timer (5-minute interval, cancels on disconnect, restarts on reconnect)
- [x] 5.7 Persist `hideNSFW` to `UserDefaults`

## 6. tvOS: Wire RootView and server connection

- [x] 6.1 Add `@StateObject private var appState = AppState()` to `RootView`
- [x] 6.2 Inject `appState` as `.environmentObject(appState)`
- [x] 6.3 Trigger `appState.refresh()` when `server.status` transitions to `.connected`; cancel timer on `.disconnected`
- [x] 6.4 Pass `JellyfinClient` credentials (baseURL, apiKey, deviceId) from `ServerConnection` to `AppState`
- [x] 6.5 Expose `deviceId` property on `ServerConnection`
- [x] 6.6 Update `ServerConnection.ServerInfo` to expose the data `JellyfinClient` needs

## 7. tvOS: Update Home screen views

- [x] 7.1 Update `HomeView` to read `@EnvironmentObject var appState: AppState` instead of `SampleCatalog` for heroes, continueWatching, and recommended
- [x] 7.2 Conditionally hide Continue Watching row when `appState.continueWatching.isEmpty`
- [x] 7.3 Conditionally hide hero when `appState.heroes.isEmpty`
- [x] 7.4 Apply NSFW filtering via `appState.hideNSFW` in all three sections
- [x] 7.5 Update detail presentation (`presentedDetail`) to use `appState`-derived show/movie data instead of `SampleCatalog.show(for:)` / `SampleCatalog.movie(for:)`

## 8. tvOS: Update Libraries submenu

- [x] 8.1 Update `LibrariesSubmenu` to accept libraries from `appState.libraries` converted to `[Library]` UI models
- [x] 8.2 Map `MetaCategory.isNSFW` to the existing `Library.isAdult` flag for the "18+" badge
- [x] 8.3 Filter out music/books libraries (nil MetaCategory)

## 9. tvOS: Meta-library views (Movies and Shows tabs)

- [x] 9.1 Create `Apps/JellyTV/Sources/MetaLibrary/MetaLibraryView.swift` — grid view fetching items from all libraries of a given Jellyfin `CollectionType`
- [x] 9.2 Wire `.movies` destination in `RootView` to `MetaLibraryView(collectionType: "movies")`
- [x] 9.3 Wire `.tv` destination in `RootView` to `MetaLibraryView(collectionType: "tvshows")`
- [x] 9.4 Include focus handling and nav rail in the meta-library screen layout

## 10. tvOS: Settings — Hide NSFW toggle

- [x] 10.1 Update `HomeDetail.swift` to add a "Hide NSFW" `ToggleSwitch` as the first row, bound to `appState.hideNSFW`
- [x] 10.2 Update `SettingsCategoryList.swift` categories to reflect updated Home description ("Hero rotation, transitions, NSFW filter")
- [x] 10.3 Update `SampleCatalog.settingsCategories` Home description to match

## 11. Remove SampleCatalog from runtime paths

- [x] 11.1 Audit all `SampleCatalog.` references in `Apps/JellyTV/Sources/`; replace with `appState` reads unless inside a `JT_*` screenshot hook
- [x] 11.2 Verify screenshot/testing hooks (`JT_SETUP_DEMO`, `JT_SHOW_DEMO`, `JT_FOCUS`) still function with sample data
- [x] 11.3 Remove `SampleCatalog.` imports/references from `HomeView`, `RootView` (non-hook paths), `LibrariesSubmenu`, `ContentRows`

## 12. Tests and validation

- [x] 12.1 Add unit tests for `MetaCategory` computed properties (isNSFW, isAnime, collectionType for each case)
- [x] 12.2 Add unit tests for `LibraryClassifier` with each mapping combination from the spec table
- [x] 12.3 Add unit tests for `JellyfinItem` conversion helpers (toContinueWatchingItem, toMediaItem, toHeroFeature)
- [x] 12.4 Run `swift test` in `Packages/JellyTVKit` and verify all tests pass
- [ ] 12.5 Manual smoke test: connect to a Jellyfin server, verify libraries appear in submenu, continue watching populates, hero rotates
- [ ] 12.6 Manual smoke test: toggle Hide NSFW, verify content filters; verify setting persists across launches
- [ ] 12.7 Manual smoke test: fresh install (no resume-able items), verify hero falls back to random items
