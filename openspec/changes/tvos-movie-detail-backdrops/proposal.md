## Why

The design mockup gained a **Movie detail** screen (`1b`) and added a synopsis to the **Show view** (`2a`); and the reference v1 app renders real backdrop imagery behind its detail screens (a full-bleed art with directional scrims fading into the background) which our flat deep-sea gradient lacks. This change brings all three in: the movie detail, the show synopsis, and atmospheric backdrops on both detail screens.

## What Changes

- Add a `synopsis` to the `Show` model and display it under the spec sheet on the Show view (design `2a` update).
- Add a `Movie` model + sample data and a **Movie detail** screen (`MovieDetailView`) matching design `1b`: the same left spine and dossier layout as the Show view, but with a "Feature Film // …" eyebrow, a Runtime/Director/Year spec sheet, a longer synopsis, a **More Like This** portrait-poster row (instead of an episode strip), a bottom bar of cast credits (Starring / Audio) plus **Play / Trailer / audio / subtitle / add** controls (instead of a season selector + Shuffle Play).
- Add an atmospheric **detail backdrop**: the item's key art rendered full-bleed, blurred, dimmed, and scrimmed into the page background (adapted from the reference app's `Backdrop`/blurred-wallpaper treatment and design `1d`), used behind both the Show and Movie detail screens in place of the flat gradient.
- Extract the shared "dossier chrome" (background+backdrop, left spine, spec sheet, framed key-art panel with corner ticks, floating resume card, control pills) so the Show and Movie detail screens reuse it.
- Route Recommended selection by type: a poster whose kind is a movie opens the Movie detail; a series opens the Show view.

## Capabilities

### New Capabilities
- `tvos-movie-detail`: the movie detail screen (layout, More Like This, cast/credits, play/trailer controls) and its launch from the Recommended row.

### Modified Capabilities
- `tvos-show-view`: the Show view gains a synopsis and the shared atmospheric backdrop.
- `tvos-sample-content`: add a `synopsis` to `Show`, add a `Movie` model + sample movie data + a `movie(for:)` builder.
- `tvos-home-screen`: Recommended posters route to the Movie detail or the Show view based on the item's kind.

## Impact

- `Packages/JellyTVKit/Sources/JellyTVKit/Models.swift` — `Show.synopsis`; new `Movie` type; a `kind` on `MediaItem` (or derived from `meta`) to route show vs movie.
- `Packages/JellyTVKit/Sources/JellyTVKit/SampleCatalog.swift` — show synopsis, sample `Movie`, `movie(for:)` builder; tests extended.
- New: `Apps/JellyTV/Sources/Detail/` — shared dossier components (`DetailBackground`, spine, spec sheet, key-art panel, resume card), plus `MovieDetailView` and a More-Like-This card; `ShowView`/`EpisodeCard` move here.
- `Apps/JellyTV/Sources/Home/HomeView.swift` — presents either detail by item kind.
- No change to the hero carousel, nav rail, or Settings.
- Reference: adapts `/Users/xyan/code/jelly-tv-ios/Core/Components/Backdrop.swift` (full-bleed art + fade-to-bg scrim) and its blurred-wallpaper treatment (`LibraryGridView.swift`); v1 loads via `AsyncImage` from Jellyfin — we render bundled sample art, so no networking.
