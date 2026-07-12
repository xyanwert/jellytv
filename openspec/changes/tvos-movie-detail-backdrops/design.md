## Context

Design `1b` (Movie detail) is the movie counterpart to the show dossier `2a`; `2a` gained a synopsis; and design `1d` plus the reference app show the atmospheric backdrop we're missing. The Show view already exists (`ShowView`) with the framed key-art dossier layout; the Movie detail shares almost all of that chrome.

Reference (per CLAUDE.md): v1's `/Users/xyan/code/jelly-tv-ios/Core/Components/Backdrop.swift` renders a full-bleed Jellyfin backdrop image clipped to a height with a bottom-up scrim fading to the theme background; `HomeHero` adds a horizontal left-opaque scrim; `LibraryGridView` has a blurred full-page wallpaper (`.blur(radius:).saturation(...)` + gradient mask). v1 loads via `AsyncImage`; we render bundled sample art (no networking), so we adapt the *look* (fill + blur + directional scrims fading to `Palette.screen`), not the loader.

## Goals / Non-Goals

**Goals:**
- Implement `1b` faithfully, reusing the show dossier's chrome.
- Add the show synopsis (`2a` update).
- Add a reusable atmospheric backdrop behind both detail screens.
- Refactor the shared dossier pieces out of `ShowView` so both screens use one implementation.

**Non-Goals:**
- No real playback/trailer/Jellyfin data — controls stay focusable but inert (sample-data app).
- Not implementing design `1d` as a separate screen; it's used only as reference for the backdrop treatment.
- No async image loading/caching or blurhash — sample art is bundled and synchronous.

## Decisions

- **Shared `Detail/` group.** Move `ShowView`/`EpisodeCard` into `Apps/JellyTV/Sources/Detail/` and add `MovieDetailView`, a `MoreLikeThisCard`, and a `DetailComponents.swift` holding the shared chrome: `DetailBackground` (base color + blurred backdrop + accent radial + directional legibility scrims), `DetailSpine` (logo, vertical genre label, back control, marker), `SpecSheet`/`SpecCell`, `KeyArtPanel` (framed art + corner ticks + resume card), and the control pills. Both detail screens compose these, so the layout lives in one place.
- **Backdrop as a blurred wallpaper, not a second crisp image.** `DetailBackground` renders the key art `scaledToFill` at heavy blur (~55) and reduced opacity, biased so the visible art sits top-right (away from the title text), with a left→right and bottom→top scrim to `Palette.screen`. This adds depth while the crisp framed key-art panel remains the focal image — the classic poster-over-blurred-backdrop look, and unambiguously the "background image" requested. Replaces the flat deep-sea gradient (a faint accent radial is kept for the blue cast).
- **Routing by kind.** Add a `MediaItem.kind` (`.movie`/`.series`), derived from the existing `meta` prefix ("Movie …" → movie). `HomeView` holds a single `presentedDetail` enum (`.show(Show)` / `.movie(Movie)`) set from the Recommended selection and overlays the matching screen. Keeps one presentation path and one dismiss handler.
- **`Movie` as its own model, not a `Show` variant.** The movie spec sheet (Runtime/Director/Year), cast/audio credits, and More-Like-This list differ enough from `Show` that a dedicated struct is clearer than overloading `Show`. Both are sample value types following the catalog pattern; `movie(for:)` mirrors `show(for:)`.

## Risks / Trade-offs

- [Blurred backdrop could hurt legibility of the left title/spec text] → Bias the visible art to the top-right and scrim the left/bottom to `Palette.screen`; verify the title/synopsis contrast in a simulator screenshot.
- [Refactor moves `ShowView`/`EpisodeCard` — regeneration + import churn] → Pure file moves; run `xcodegen generate` and rebuild; behavior unchanged, verified by re-screenshotting the Show view.
- [This change modifies `tvos-home-screen`'s "Recommended posters open the Show view", added by the just-archived `tvos-show-view`] → That requirement is already in the main specs; this delta MODIFIES it to branch by kind, which composes cleanly.
