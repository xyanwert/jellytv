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
**bare**, so nothing fake ever flashes.

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

## Verification & workflow

- **New files need XcodeGen.** After adding a `.swift` file, run `xcodegen generate` (project.yml
  globs the source dirs) before building, or the build won't see it.
- **Build/test.** App via XcodeBuildMCP (`build_sim` / `build_run_sim`, scheme `JellyTV`); the
  package via `swift test` in `Packages/JellyTVKit` (XCTest — update the row-count assertions when
  adding e.g. a settings category).
- **Screenshot every visual change.** Launch with env hooks to land directly on a screen:
  `JT_SHOW_MOVIES=1`, `JT_SHOW_SETTINGS=1`, `JT_SHOW_DEMO=movie|show`. Crop/zoom with ImageMagick
  (`magick … -crop`) for close inspection. These debug branches in `RootView` / `HomeView` are
  temporary — revert them before finishing.
- SourceKit frequently shows stale `No such module 'JellyTVKit'` (or missing-member) errors in the
  editor after package edits; trust the actual `xcodebuild` / `swift test` result, not the inline
  diagnostics.
