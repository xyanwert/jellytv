# CLAUDE.md

Project basics (repo layout, build/test commands, branding) live in [`README.md`](README.md) — read that first for mechanics.

## Fundamental: check the v1 app before building anything new

This repo (`jellytv`, "Why.So.Jelly?") is a **from-scratch rewrite** of an earlier project at
`/Users/xyan/code/jelly-tv-ios`. That v1 app talks directly to a real Jellyfin server (REST
client, SwiftData local store, auth/player/theme state, a working setup wizard) but got
architecturally messy, which is why this rewrite started. It is not being deleted — there is
real, working logic in it worth mining.

**Before implementing any new mechanism, screen, or capability in this repo, look at whether
`/Users/xyan/code/jelly-tv-ios` already solved it.** Concretely:

- Search its `Core/`, `iOS/`, `tvOS/`, and `docs/` for an existing implementation, component,
  or shader before designing one from scratch here.
- If something is worth bringing over, port the *idea* (and code where it's clean enough)
  deliberately — don't copy its structural mess along with it. Note in the proposal/design doc
  what was ported from where (see `openspec/changes/archive/2026-07-11-hero-carousel-transitions/`
  for the pattern: it explicitly named the v1 files a mechanism was ported from).

Do not assume this rule is satisfied just because a feature "looks new" in this repo — most of
what jellytv will eventually need (real Jellyfin browsing/playback, SwiftData, auth) already has
a first draft in v1.

## Design, style & layout standards

**Designs are the source of truth.** Screens follow the claude.ai/design project *"Jelly-tv
Screens"* (screen ids like `3a` Home, `4a` Movies) — read it via the `/design-sync` skill /
`DesignSync` tool. Match the design, then verify every visual change with a simulator screenshot
(see Verification below). When something feels off, iterate against a real screenshot, not by
reasoning about the code alone.

**Reuse the design system — never hardcode.**
- Colors: `Palette` (`Palette.text(_:)` opacity tiers, `Color(hex:)`, `Color(OKLCH:)`). Primary
  accent is `theme.accent`; `theme.secondaryAccent` is its complement (`Color.complementary`,
  hue +180°) for controls that shouldn't compete with primary actions (e.g. the search field).
- Type: `Typography` (Schibsted Grotesk) for content; `Mono` for the technical "readout" voice
  (eyebrows, section labels, counts, ids, keys).
- Focus: `FocusScaleStyle` / `CardFocusStyle` / `LEDRing` — the deliberately-loud, reads-from-
  across-the-room tvOS focus treatment. Never the plain white system focus ring/pill.

**tvOS focus containment.** A horizontal row of many focusable siblings (a season selector, an
episode strip) needs `.focusSection()` — without it, Left/Right at the row's edge lets the focus
engine search the *whole screen* for the geometrically-nearest focusable view and jump there,
which reads as the selection just vanishing. Scope it to the one row that needs it, not a whole
containing bar — two `.focusSection()`s stacked directly adjacent can fight each other and block
Up/Down traversal between them. Separately: a focusable `Button` styled `.plain`/`.automatic`
still paints the system's white focus card when focused, even for content meant to be invisible
(e.g. a full-screen tap-to-reveal-chrome catcher in the video player) — give it a custom
`ButtonStyle` that renders only `configuration.label`, same reasoning as never using `.plain` for
visible controls either.

**tvOS text input:** use the shared `AppTextField` (DesignSystem/AppTextField.swift), never a raw
SwiftUI `TextField`. A focused tvOS TextField paints an un-removable white pill and won't reliably
raise the keyboard for an off-screen field; `AppTextField` fixes both (a styled Button over a
hidden `UITextField` driven by `becomeFirstResponder()`). It also carries an explicit
`.frame(height:)` — a bare focusable field otherwise expands to fill a `ScrollView`'s proposed
height.

**Atmospheric backdrops** (Home hero, Movies selected-item — see `SelectedBackdrop` /
`HomeView.heroBackdropLayer`): a full-width layer pinned to the top *behind* the rail (the rail is
semi-transparent, so draw the backdrop earlier in the ZStack / give the rail a higher `zIndex`).
Render the image into a 1.5× box then clip (a subtle zoom). Layer scrims: left-darken (text
legibility) + top-darken (header legibility) + a pre-darken toward black at the fading edge
*before* an alpha mask — that pre-darken is what makes the image dissolve into the page instead of
hard-cutting. A blurred copy masked to the top softens busy art under the header.

**Panels don't jump.** Give info panels a fixed frame (`.frame(width:height:, alignment: .top)`)
with top-aligned content so they hold one size across loading / sparse / rich states. Prefer this
over letting a panel resize to its content. If a panel's content keeps growing (more sections
added over iterations), **split it into multiple independently-fixed-size panels** stacked with a
gap rather than growing one tall panel — see the Movies dossier's `StatsCastPanel` +
`MetaPanel` (design 4a). Every such panel needs its **own** loading/decode indicator sized to
its own footprint — a sibling panel finishing first while another sits blank reads as broken, even
if each panel's fixed-size rule is individually satisfied.

**Cast/person portraits are rounded squares, not circles** (`CastPortrait` in
`MetadataComponents.swift`): a deterministic per-person gradient monogram fallback (hash the id
into a hue), an accent-colored ring for a lead/featured role, and a distinct gold ring + a small
gold medal badge tucked into a corner for a special/decorated status (e.g. an Oscar-winning
actor). Reuse this shared component rather than a one-off circular avatar.

**Award callouts are narrow and literal.** When a product decision says "surface X, ignore
everything else" (e.g. Oscar *wins* only — not nominations, not other festivals' wins), encode
that as the single gate a view checks (`MovieAwards.academyAwardsLabel`), not a chain of
fallbacks that also surfaces the ignored cases. When a panel already carries several visual
indicators (rating chips, badges, medals), prefer a **quiet atmospheric treatment** — a relevant
image as the panel's own background at low opacity (~40%), centered and clipped to the panel's
shape — over stacking another text badge.

**External (non-Jellyfin) images** — anything not served by the user's Jellyfin instance (a
static reference/decorative image, a third-party artwork URL) — load with plain SwiftUI
`AsyncImage(url:)` directly. Reserve `JellyfinAsyncImage` for the server's own token-less image
endpoints.

**Layout regions.** On a browse screen, pin the header/filters/selected-item band and scroll only
the catalog (put the grid in its own inner `ScrollView`, everything else outside it). Don't wrap a
whole screen in one `ScrollView` — a default-focused grid item then makes tvOS auto-scroll the
header off the top.

**Never show fake data as a placeholder.** While real data loads, show a loading state, then the
real thing (not sample/demo values that then swap out). Sample enrichment lives only on the
*static* `SampleCatalog.movie` / `.show`; the `movie(for:)` / `show(for:)` used for real items are
**bare**, so nothing fake ever flashes. This applies to whole lists too, not just per-item
enrichment — a library grid (`MoviesLibraryView`/`ShowsLibraryView`) that falls back to
`SampleCatalog.recommended` while the real fetch is in flight has the exact same problem. Track a
`hasLoaded` flag (set once, on first successful fetch, never reset by a later re-sort) instead of
branching on `list.isEmpty` — otherwise every first-load flashes sample posters, and a `.isEmpty`
check can't tell "still loading" apart from "genuinely no results."

**Data fetching.** Lazy, per selected/opened item, cached by id, debounced (~300 ms). Never
request heavy fields (`People`, etc.) for a whole list — enrich one item at a time. When combining
sources, go two-phase (Jellyfin first, external merged in after). Every UI section gates on its own
data so sparse metadata degrades cleanly. External services (e.g. OMDb) are opt-in behind a
Settings toggle + key, with a single choke point that returns nil on any failure.

**Jellyfin gotchas.** `CriticRating` only comes back when `ProductionLocations` is *also* in the
`fields` param. Images are served unauthenticated (token-less URLs); person headshots are
`/Items/{personId}/Images/Primary`.

**Additive model changes.** Append new params to `JellyfinItem` / `Movie` / `Show` inits with
`= nil` / `[]` defaults so existing call sites and tests keep compiling.

**Horizontally-scrolling strips fade at the edges, not hard-cut.** Use `View.horizontalEdgeFade()`
(`Detail/DetailComponents.swift`) instead of `.scrollClipDisabled()` — the fade is a fixed-width
`.mask` gradient at the leading/trailing edges of the `ScrollView`'s own frame, so it also
re-enables normal clipping. That clipping matters beyond the fade: a focused card's
`CardFocusStyle` scale-up (~1.1×) needs the ScrollView to actually clip, or the enlarged card
bleeds into whatever sits above/below the strip. Give the scrolled content extra vertical padding
(absorbing the scale-up) rather than relying on `scrollClipDisabled()` to let it hang out unclipped.

## Video player architecture

Custom `AVPlayer`-based player — zero AVKit/system chrome. Ported as *behavior*, not
file-for-file, from `/Users/xyan/code/jelly-tv-ios`'s player (`Core/Player/*.swift`). Three layers
in `Apps/JellyTV/Sources/Player/`:

- **`PlayerEngine`** (App target, `AVFoundation`-dependent) — owns the one `AVPlayer` and all
  robustness: resolve → direct-play/HLS fallback → resume-seek → progress reporting → teardown.
  KVO on `status`/buffer state registered with `[.initial, .new]` (`.new` alone can miss a status
  transition AVPlayer performs synchronously inside `replaceCurrentItem`); direct→HLS fallback on
  `AVPlayerItem.status == .failed`; HTTP 5xx-burst detection via
  `AVPlayerItem.newErrorLogEntryNotification` (Jellyfin's transcoder can go half-dead — stays
  `.readyToPlay` while every segment 500s, which `status` alone never surfaces); stale-session
  re-resolve after 3 consecutive 404s on the progress POST (capped 1/item; suppressed within 30s
  of natural end-of-video so the re-resolve doesn't cancel the in-flight end-of-video/auto-advance
  handler); 20s load-timeout watchdog for an item stuck on `.unknown`; 3-strike queue auto-skip.
- **`PlayerController`** — thin chrome-facing facade. **All chrome talks to this controller and
  only this controller**, never `PlayerEngine` directly. Owns mash-protection (250ms leading-edge
  coalesce + re-entrancy guard) for queue navigation and favorite toggles.
- **`PlayerLayerView`** — `UIViewRepresentable` wrapping a `UIView` whose `layerClass` IS
  `AVPlayerLayer`. Deliberately not `AVPlayerViewController` / SwiftUI `VideoPlayer` — both always
  ship some system chrome.

**Lifecycle rule.** Engine/controller live in `@State` on `PlayerView`, built exactly once in
`.task { if engine == nil { ... } }` — SwiftUI rebuilds tear playback down otherwise. Teardown in
`.onDisappear`: dismiss first, async engine teardown after, so back-navigation doesn't wait on the
`/Sessions/Playing/Stopped` network round-trip. `PlaybackRequest.id` is content-derived (not
`UUID()`) so `RootView`'s `.fullScreenCover(item:)` doesn't retrigger on an unrelated `AppState`
publish mid-play.

**`PlayableItem`** is the one normalized shape the player queues/seeks/reports-progress against —
`Movie.asPlayableItem()` / `Episode.asPlayableItem(seriesTitle:seasonNumber:)` build it from the
domain-shaped `Movie`/`Episode`/`Show` structs, which stay separate display types (v1 used one
unified item DTO everywhere; this is the deliberate "port the idea, not the code" adapter instead).

**Jellyfin playback protocol.** `POST /Items/{id}/PlaybackInfo` with `JellyfinAPI.DeviceProfile
.tvOS` → trust the server's own `SupportsDirectPlay` flag, never second-guess it with a
client-side container allowlist (that's how a perfectly direct-playable file ends up routed
through an unnecessary transcode). The HLS fallback is always built, with
`enableAdaptiveBitrateStreaming=false` — AVPlayer's HLS ABR doesn't pair with Jellyfin's
on-demand transcode. Progress: `/Sessions/Playing` once on start, `/Sessions/Playing/Progress`
throttled to 10s, `/Sessions/Playing/Stopped` on teardown with the position captured *before*
observer teardown (otherwise a queue advance reports position 0 and wrecks Continue Watching).
`JellyfinClient`'s retry policy (capped exponential backoff, 3 attempts): GET/PUT/DELETE always
retried on a transient failure; POST retried *only* for `/Sessions/Playing/Progress` (a
double-posted tick is a no-op); `/Sessions/Playing` and `/Sessions/Playing/Stopped` are never
retried (a duplicate creates a ghost session server-side); 401 is never retried.

Favorite → real Jellyfin endpoint (`setFavorite`/`clearFavorite`). Dislike has no Jellyfin
equivalent — it's a local-only `UserDefaults` flag owned by `PlayerController`.

**Scenes (Phase 2) is not implemented** — the chrome's SCENES transport tile exists but its tap
handler is a no-op. **The tags row is omitted from the chrome entirely** (Phase 3, interactive
tags — not just hidden, never rendered). **Night mode is a bare toggle** — the button flips its
own on/off visual and nothing else; the dim/warm video treatment it's meant to drive isn't wired up.

## Verification & workflow

- **New files need XcodeGen.** After adding a `.swift` file, run `xcodegen generate` (project.yml
  globs the source dirs) before building, or the build won't see it.
- **Build/test.** App via XcodeBuildMCP (`build_sim` / `build_run_sim`, scheme `JellyTV`); the
  package via `swift test` in `Packages/JellyTVKit` (XCTest — update the row-count assertions when
  adding e.g. a settings category).
- **Screenshot every visual change.** Launch with env hooks to land directly on a screen:
  `JT_SHOW_MOVIES=1`, `JT_SHOW_SETTINGS=1`, `JT_SHOW_DEMO=movie|show`,
  `JT_SHOW_PLAYER=1` (or `=failed` / `=hidden`) — the last renders `PlayerChrome` over
  `PlayerPreviewFixture` (fixture state, no live `AVPlayer`/network) for chrome-only iteration.
  Crop/zoom with ImageMagick (`magick … -crop`) for close inspection. These are permanent,
  inert-unless-set hooks (same convention as `JT_SHOW_MOVIES` etc.) — nothing to revert.
  `SIMCTL_CHILD_<VAR>=<value> xcrun simctl launch <device> <bundle-id>` sets the env var directly
  when driving the simulator outside XcodeBuildMCP's `launch_app_sim`. The Apple TV simulator's
  screenshot capture sometimes comes back portrait-rotated (e.g. 450×800 instead of landscape) —
  `magick screenshot.jpg -rotate -90 out.png` before inspecting it.
- SourceKit frequently shows stale `No such module 'JellyTVKit'` (or missing-member) errors in the
  editor after package edits; trust the actual `xcodebuild` / `swift test` result, not the inline
  diagnostics.
