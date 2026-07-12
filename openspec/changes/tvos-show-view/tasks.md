# Tasks: tvos-show-view

## 1. Models & sample data (JellyTVKit)

- [x] 1.1 Add `Episode` (id, number, title, runtime, isCurrent, image?, artwork), `Season` (id, number, name, episodes), and `Show` (id, title, studioLine, rating, certification, runSummary, createdBy, years, genreLabel, techLine, keyArt image?, artwork, resumeEpisodeLabel, resumeProgress, resumeRemaining, seasons) — all `Equatable`/`Sendable`/`Hashable`/`Identifiable` — to `Models.swift`
- [x] 1.2 `SampleCatalog`: add a demo `Show` — studio "Series 003 // Benthic Pictures", title "The Deep Signal", rating 8.9 / TV-MA, run "3 seasons · 24 ep", creator "Mara Ellingsen", years "2023 – 2026", genre "TV Shows / Sci-Fi Drama", tech "4K · HDR · ATMOS", resume "S3 · E4 — Trench" 62% "31:04 LEFT · 62%"; 4 seasons (S01/S02/S03/Specials) with episodes; season 3 has 8 episodes (Descent/Pressure/Blackwater/Trench[current, E4]/The Answer/Surfacing/…), episode images cycling the preview assets
- [x] 1.3 `SampleCatalog.show(for: MediaItem)` builder: returns a `Show` over the demo template but with the item's title as the show title and the item's image as key art
- [x] 1.4 Extend `SampleCatalogTests`: season/episode counts, exactly one current episode across the show, resume fields non-empty, `show(for:)` carries the item's title; `swift test` passes

## 2. Show view (Apps/JellyTV/Sources/Show)

- [x] 2.1 `ShowView.swift` scaffold: deep-sea gradient background + sonar-rings motif; `HStack { spine; content }`; takes `show: Show` and `onDismiss`; `@State selectedSeasonIndex`; `@FocusState`; `.onExitCommand(onDismiss)`; default focus on the resume/play card
- [x] 2.2 Left spine: app-mark tile (top), vertical genre label (`genreLabel`, rotated), and a focusable back control + current-episode marker ("EP 04") at the bottom; back control calls `onDismiss`
- [x] 2.3 Title block: studio eyebrow (`studioLine`), oversized multi-line title, and a 2×2 spec sheet (Rating ★ + cert, Run, Created by, Years) with the design's dividers
- [x] 2.4 Key-art panel: framed image (`keyArt`/artwork) with accent corner ticks + a floating resume card (circular progress ring at `resumeProgress`, accent play disc, "RESUME" eyebrow, resume label, remaining line), focusable
- [x] 2.5 Episode strip: heading (selected season name + "N Episodes") + a horizontally-scrolling row of focusable episode cards (E## badge, runtime, title, NOW badge + accent outline for the current episode) for the selected season
- [x] 2.6 Bottom action bar: season selector as a focusable segmented control bound to `selectedSeasonIndex`, and focusable controls Shuffle Play (accent primary), audio (EN·5.1), subtitles (CC·OFF), and add (＋)

## 3. Wire-up (Home)

- [x] 3.1 `PosterCard`: add an `onSelect: () -> Void` invoked on button tap
- [x] 3.2 `RecommendedRow`: add `onSelectShow: (MediaItem) -> Void` and pass each poster's select through
- [x] 3.3 `HomeView`: own `@State selectedShow: Show?`; set it from `RecommendedRow` via `SampleCatalog.show(for:)`; overlay `ShowView` full-screen when set (over content + rail) with `onDismiss` clearing it; ensure Menu/Back closes the show

## 4. Build, run, verify

- [x] 4.1 `xcodegen generate` (if needed); build the `JellyTV` scheme for a tvOS simulator with no warnings-as-errors; `swift test` passes
- [x] 4.2 Run on the simulator: from Home, open a Recommended poster → Show view appears with the poster's title; switch seasons updates the episode strip; the current episode is marked; Menu/Back returns to Home; capture a Show-view screenshot
- [x] 4.3 Walk every scenario in this change's `specs/**` and confirm each passes
- [x] 4.4 Commit on the feature branch; clean `git status` after build
