## Why

Selecting a title on Home currently does nothing — the Recommended posters are dead-ends. The design mockup (Claude Design project `3ea3d153`, screen `2a` — "Show view / editorial signal dossier") defines a rich detail screen for any *collection* (a series with seasons and episodes, as opposed to a single video). We want the Recommended row to open this Show view with demo data so the browse→detail flow is real.

## What Changes

- Add typed `Show`, `Season`, and `Episode` models to `JellyTVKit`, plus sample data (a multi-season demo series with episodes, a resume point, spec-sheet metadata, and a per-poster show builder).
- Add a full-screen **Show view** matching design `2a`: a left spine (app mark, vertical genre label, back button, current-episode marker); a title block with a studio eyebrow, oversized title, and a 2×2 spec sheet (rating, run, created-by, years); a framed key-art panel with corner ticks and a floating "resume" card (circular progress + play); a horizontally-scrolling episode strip for the selected season; and a bottom action bar (season selector + Shuffle Play / audio / subtitle / add controls).
- Treat the Home **Recommended for You** posters as shows: selecting one opens the Show view populated with demo data derived from that poster (title + key art), dismissable with Menu/Back and the on-screen back button.
- The Show view is a self-contained full-screen takeover with its own left spine — it does **not** show the main nav rail (matching the design).

## Capabilities

### New Capabilities
- `tvos-show-view`: the collection/series detail screen (layout, seasons/episodes, resume, remote navigation) and its launch from the Recommended row.

### Modified Capabilities
- `tvos-sample-content`: add `Show`/`Season`/`Episode` models and sample series data backing the Show view.
- `tvos-home-screen`: the Recommended row's posters become selectable and open the Show view (previously non-interactive).

## Impact

- `Packages/JellyTVKit/Sources/JellyTVKit/Models.swift` — new `Show`/`Season`/`Episode` types.
- `Packages/JellyTVKit/Sources/JellyTVKit/SampleCatalog.swift` — sample series + a `show(for:)` builder; tests extended.
- New: `Apps/JellyTV/Sources/Show/ShowView.swift` (+ supporting subviews) implementing design `2a`.
- `Apps/JellyTV/Sources/DesignSystem/MediaCard.swift` — `PosterCard` gains an `onSelect` action.
- `Apps/JellyTV/Sources/Home/ContentRows.swift` — `RecommendedRow` plumbs selection up.
- `Apps/JellyTV/Sources/Home/HomeView.swift` — owns the presented-show state and overlays the Show view.
- No change to the hero carousel, Continue Watching cards, nav rail, or Settings.
- v1 note: `/Users/xyan/code/jelly-tv-ios/Core/Library/ShowDetailView.swift` exists but uses a different scrolling hero-on-top layout bound to the Jellyfin `JfItem` DTO; we implement the bespoke `2a` dossier with clean typed models instead of porting it.
