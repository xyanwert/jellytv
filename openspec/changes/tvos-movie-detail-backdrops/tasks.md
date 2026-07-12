# Tasks: tvos-movie-detail-backdrops

## 1. Models & sample data (JellyTVKit)

- [x] 1.1 Add `synopsis: String` to `Show`; update `SampleCatalog.show` (design 2a copy) and `show(for:)` to carry it
- [x] 1.2 Add a `MediaItem.Kind` (`movie`/`series`) — a stored field defaulting via the `meta` prefix, or a computed `kind` deriving from `meta` ("Movie …" → movie, else series); expose on `MediaItem`
- [x] 1.3 Add a `Movie` model (id, title, studioLine, rating, certification, runtime, director, year, genreLabel, synopsis, keyArt image?, artwork, resumeProgress, resumeRemaining, resumeLabel, starring, audioLine, moreLikeThis: [MediaItem]) — `Equatable`/`Sendable`/`Hashable`/`Identifiable`
- [x] 1.4 `SampleCatalog`: add a demo `Movie` ("Undertow" — Feature Film // Benthic Pictures, ★8.6 PG-13, 2h 14m, Mara Ellingsen, 2026, design synopsis, starring "Ines Duval, Theo Marsh", audio "EN · FR · 12 subtitles", moreLikeThis from recommended) and a `movie(for: MediaItem)` builder carrying the item's title + key art
- [x] 1.5 Extend `SampleCatalogTests`: `Show.synopsis` non-empty; `MediaItem.kind` classifies a movie vs series correctly; sample `Movie` fields populated + non-empty moreLikeThis; `movie(for:)` carries the item's title; `swift test` passes

## 2. Shared dossier chrome (Apps/JellyTV/Sources/Detail)

- [x] 2.1 Create `Apps/JellyTV/Sources/Detail/`; move `ShowView.swift` and `EpisodeCard.swift` there (`git mv`); `xcodegen generate`; confirm the Show view still builds/renders unchanged
- [x] 2.2 `DetailComponents.swift`: `DetailBackground(image:artwork:)` — base `Palette.screen`, the key art `scaledToFill` blurred (~55) + dimmed + biased top-right, a subtle accent radial, and left→right + bottom→top scrims to `Palette.screen` for legibility (adapted from v1 `Backdrop`/blurred wallpaper)
- [x] 2.3 `DetailComponents.swift`: extract `DetailSpine(genreLabel:marker:onBack:back-focus)`, `SpecSheet`/`SpecCell`, `KeyArtPanel(image:artwork:resume card slot)` with corner ticks, and the reusable control pill; refactor `ShowView` to use them (background now `DetailBackground`)

## 3. Show view synopsis (design 2a)

- [x] 3.1 `ShowView`: render `show.synopsis` under the spec sheet in the title column (≤560pt, ~21pt, tiered text), matching 2a

## 4. Movie detail (design 1b)

- [x] 4.1 `MovieDetailView.swift`: `DetailBackground` + `DetailSpine` (genre "Movies / <genre>", marker "FILM 001"); tech readout "READY TO PLAY · 4K · HDR · ATMOS"; takes `movie: Movie` + `onDismiss`; `.onExitCommand`; default focus on Play
- [x] 4.2 Title block: "Feature Film // …" eyebrow, large single-line title, spec sheet (Rating ★ + cert, Runtime, Director, Year), synopsis
- [x] 4.3 `KeyArtPanel` with a resume card (progress ring at `resumeProgress`, play disc, "RESUME", title, remaining)
- [x] 4.4 `MoreLikeThisCard` (128×190 portrait) + a "More Like This" row from `movie.moreLikeThis`, focusable
- [x] 4.5 Bottom bar: cast credits (Starring / Audio columns) on the left; Play (accent primary), Trailer, audio (EN·5.1), subtitle (CC·OFF), add (＋) controls on the right, focusable

## 5. Wire-up (Home)

- [x] 5.1 `HomeView`: replace `selectedShow` with a `presentedDetail` enum (`.show(Show)` / `.movie(Movie)`); set it from `RecommendedRow` by `item.kind` (movie → `movie(for:)`, series → `show(for:)`); overlay the matching detail view; Menu/Back / back control dismiss; update the `JT_SHOW_DEMO` hook
- [x] 5.2 Verify Continue Watching / hero unaffected; the main rail is not shown by either detail screen

## 6. Build, run, verify

- [x] 6.1 `xcodegen generate`; build the `JellyTV` scheme for a tvOS simulator with no warnings-as-errors; `swift test` passes
- [x] 6.2 Run on the simulator: open a movie poster → Movie detail (backdrop visible, More Like This, cast, Play); open a series poster → Show view (now with synopsis + backdrop); Menu/Back returns to Home; capture screenshots of both
- [x] 6.3 Walk every scenario in this change's `specs/**` and confirm each passes
- [x] 6.4 Commit on the feature branch; clean `git status` after build
