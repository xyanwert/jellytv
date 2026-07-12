## Context

The Show view is design screen `2a` — a bespoke "editorial dossier" for a collection, visually unlike anything shipped so far (deep-sea gradient, sonar rings, a left *spine* rather than the nav rail, an oversized 3-line title, a 2×2 spec sheet, a framed key-art panel with a floating resume card, an episode strip, and a season selector + control bar). It launches from the Home Recommended row, which is currently non-interactive.

Per the CLAUDE.md "check v1 first" rule: `/Users/xyan/code/jelly-tv-ios/Core/Library/ShowDetailView.swift` exists but is a different design — a vertical `ScrollView` with a hero backdrop on top, season pills, and an episode grid, all bound to the Jellyfin `JfItem` DTO (seasons/episodes are `JfItem`s distinguished by a `type` field). It's not portable to the `2a` dossier layout and its DTO doesn't match our clean sample-data approach, so we build fresh.

## Goals / Non-Goals

**Goals:**
- Implement `2a` faithfully at the tvOS 1920×1080 canvas, adapted for the focus engine (focusable spine back control, season selector, episode cards, and action-bar controls; a focused element at launch; Menu/Back dismiss).
- Clean typed `Show`/`Season`/`Episode` models in `JellyTVKit` + sample data, following the existing sample-catalog pattern.
- Wire the Recommended row so any poster opens the Show view with demo data carrying that poster's title and key art.

**Non-Goals:**
- No real playback, Jellyfin data, or player — the controls (Shuffle Play, audio, subtitles, add, resume) are focusable but inert, consistent with the rest of the sample-data app.
- Not reusing the main `NavRail`; the Show view has its own spine per the design.
- Not a generic movie/single-video detail — `2a` is explicitly the collection (seasons/episodes) view. A single-video variant is future work.

## Decisions

- **Presented as a full-screen overlay owned by `HomeView`.** `HomeView` holds `@State selectedShow: Show?` and overlays `ShowView` (opaque deep-sea background) above its content + rail when set. The Show view is contextual to browsing (launched from a card deep in Home's content), so Home owns it rather than `RootView`; the overlay covers the rail because the design gives the Show view its own spine. `ShowView` takes an `onDismiss` closure and handles Menu/Back via `.onExitCommand`.
- **Fixed design metrics.** The tvOS render surface is a fixed 1920×1080, so the view uses the design's absolute sizes (118pt spine, ~640pt title column, key-art panel, 236×133 episode cards) rather than a fluid layout — simplest path to matching `2a`.
- **Clean typed models, not the v1 `JfItem` DTO.** `Show`/`Season`/`Episode` structs carry exactly the fields `2a` needs (spec-sheet strings, resume label/progress, current-episode flag). This matches the app's existing `SampleCatalog` value-type style and keeps the view declarative.
- **Per-poster shows via a builder.** `SampleCatalog.show(for: MediaItem)` returns a `Show` using the item's `title` and `image` (key art) over a shared demo template (seasons, episodes, spec sheet, resume). Every Recommended poster thus opens a distinct-titled show without authoring one per item.
- **Episode artwork** reuses the existing bundled preview assets (`Preview1/2/3`, `PreviewBob1/2/3`) cycled per episode and tinted via the existing `Artwork` gradient + dominant-color treatment, so no new image assets are required.
- **Default focus** lands on the resume/play card (the primary CTA). The season selector drives `@State selectedSeasonIndex`, re-rendering the episode strip.

## Risks / Trade-offs

- [Dense fixed-metric layout could overflow on the 1080 canvas] → Mirror the design's own spacing and verify with a simulator screenshot; the design is authored at the same 1920×1080 so metrics transfer directly.
- [Nested `.onExitCommand` (Home has one for the Libraries submenu, Show view adds its own)] → The focused view's handler wins; when the Show overlay is up, focus is inside it, so its dismiss fires. Home's handler stays guarded on `isLibrariesOpen`.
- [Two unarchived changes (`tvos-rail-nav-settings`, this) both touch `tvos-sample-content` and `tvos-home-screen`] → This change's deltas are additive (ADDED requirements / new model types), so they compose with the rail change's pending modifications without conflict at sync time.
