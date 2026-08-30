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

- **Send the `v1-scout` subagent first** (`.claude/agents/v1-scout.md`) — before writing code or a
  proposal. It knows the v1 tree, reads its header docs and git history, and comes back with a
  briefing: what v1 did, the hard-won details, and what to port / adapt / leave. Do this once per
  feature, at the start; it is cheap next to rediscovering a solved problem.
- Or search its `Core/`, `iOS/`, `tvOS/`, and `docs/` yourself for an existing implementation,
  component, or shader before designing one from scratch here.
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

**That invisible-`Button` trick is tvOS-only — on iOS it silently eats touches.** A `Button`
whose label is `Color.clear` and whose `ButtonStyle` draws nothing has no shape for a direct
touch to land on: `.contentShape(Rectangle())` on the outside doesn't rescue it, and the action
simply never fires (verified by bisect — three consecutive real taps on the player's hidden
chrome catcher produced nothing). On iOS use `Color.clear` + `.contentShape(Rectangle())` +
`.onTapGesture`; keep the `Button` on tvOS, where it must be *focusable* for a Select press.
See `PlayerChrome.tapCatcher`.

**Do not "verify" a touch control with AppleScript.** `tell process "Simulator" to click at
{x, y}` resolves the accessibility element under the point and sends it an `AXPress` — it is not
a touch. An invisible `Button` is in the AX tree, so AXPress drives it happily while a real
finger cannot: a broken control tests green. Use real HID injection instead — XcodeBuildMCP
bundles AXe, and `.mcp.json` enables its `ui-automation` workflow, so the `tap`/`swipe`/`touch`
tools inject genuine touch events. Ad hoc:
`~/.npm/_npx/*/node_modules/xcodebuildmcp/bundled/axe tap -x <x> -y <y> --udid <udid>`
(coordinates are device points, not screenshot pixels).

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

**The HLS manifest must declare a real bitrate, or video silently dies.** `master.m3u8` derives
the playlist's `BANDWIDTH` from the **`videoBitRate`/`audioBitRate` query params — not from
`maxStreamingBitrate`**, which it ignores for this purpose. Omit `videoBitRate` and Jellyfin
emits `BANDWIDTH=256000` and downscales the picture to match that invented ceiling, while ffmpeg
writes segments far larger than 256 kbps. AVPlayer enforces the declaration, fails the variant
with `CoreMediaErrorDomain -12318` ("Segment exceeds specified bandwidth for variant"), and —
since `enableAdaptiveBitrateStreaming=false` leaves no other variant — **drops the video track
while the audio keeps playing**. Sound with a black picture is this bug, not a decode problem.
Pin `profile=high&level=41` too: without them Jellyfin advertises `CODECS="avc1.424029"`
(Baseline @ 4.1 — not even a legal pairing) no matter what ffmpeg actually encodes, and AVPlayer
refuses a track whose bitstream contradicts the declared codec string. Keep the HLS `videoCodec`
at **`h264` only** — offering `hevc` makes Jellyfin *copy* HEVC into the MPEG-TS segments, and
AVFoundation only decodes HEVC from fMP4, so that's the same black picture by another route.
Same reason `flac`/`opus` stay out of the audio list. None of this surfaces as an
`AVPlayerItem` error: `status` stays `.readyToPlay` throughout.

**Diagnosing playback: `JT_PLAYER_LOG=1`.** Turns on `PlayerDiagnostics` — the negotiated
container/codec/profile/bit-depth, direct-vs-HLS route, the generated `master.m3u8` and variant
playlist, the `AVPlayerItem` error log, and a track census once playback settles (`videoTracks`,
`presentationSize`, and an explicit AUDIO-ONLY/OK verdict). Read tracks off `AVPlayerItem.tracks`,
never `asset.loadTracks` — an HLS asset has no statically-known tracks and always answers zero.
Pair it with `RT_AUTOPLAY=<title substring>` on iPad, which resumes the first matching Continue
Watching entry at launch so a playback bug is reproducible without tap automation.

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
  only this controller**, never `PlayerEngine` directly. Owns mash-protection for queue
  navigation and favorite toggles (250ms leading-edge coalesce + re-entrancy guard) *and* for
  seeking (see below).
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

**The chrome is the "Grandma menu"** (design canvas artboard A) — five circles in one row over a
position readout, three actions in the foot, and nothing written on any of them except BACK:

    ⏮ start over  ·  ↺30  ·  play/pause  ·  ↻30  ·  ↻1min          (`PlayerTransportRow`)
    27:00 / 55:16                                                   (`PlayerClockReadout`)
    [👎]  [ SCENES ]  [❤️]                                           (`PlayerFootActions`)

It replaced a 13-control chrome (repeat, a right-hand rail of favourite/next/dislike, a progress
bar, and a 7-tile seek strip). Things that went, and stay gone unless someone asks: **the progress
bar** (a bar invites dragging, and a dragged bar is the easiest way to lose your place by
accident), **every caption except BACK** (which is what buys five full-size targets in one row),
and **the repeat and next buttons** — the engine still auto-advances and `PlayerController` still
exposes `toggleRepeatOne()`/`next()`, there is simply no control for them.

Where an item has **logo artwork** (`/Items/{id}/Images/Logo`) that artwork *is* the title; plain
type is the fallback, and only the fallback. Tags render as chips under it. Both required new
plumbing — `PlayableItem.logoURL`/`.tags`, `Movie`/`Show.logoArt`/`.tags`, and `Tags` added to
`fetchItemDetail`'s `fields` (Jellyfin won't return it otherwise). An episode borrows its
*series'* logo and tags via `AppState.seriesIdentity(for:)`; Jellyfin almost never gives an
episode either.

**Seeks are coalesced, because five big circles are the most mashable surface in the app.**
`PlayerController.jump(by:)`/`jump(to:)` accumulate a burst of taps onto a running target and
commit **one** seek 280ms after the tapping stops, with a busy gate so a commit landing mid-seek
re-arms rather than stacking a second `avPlayer.seek`. `seek(to:)` stays uncoalesced for callers
that already know an exact target and aren't mashable (a scenes thumbnail). Two real bugs this
fixes, both of which shipped in v1 as well as here: the old version re-read `currentTime` per tap,
so taps landing before the first seek resolved all read the *same stale* position and three fast
taps on +30s produced **one** +30s jump (reads as the button not registering); and each seek was
frame-accurate, so a burst of them hammered a possibly-transcoding server. `displayTime` exposes
the pending target so the readout moves on the tap while the picture follows a beat later — that
feedback is what stops someone pressing again to check. v1 never gated seeks at all; its own port
plan states the principle it didn't apply here: *"coalesce + busy gate solves mash, debounce alone
does not."*

**The position readout is `M:SS` / `H:MM:SS`, never hours:minutes.** The design mockup drew
`00:27/01:17`; implemented literally that changes once a minute (looks frozen against the engine's
4Hz tick) and `00:27` reads as twenty-seven *seconds*. `formatPlayerClock(_:matching:)` formats
**both halves against the duration**, so a long film can't render `8:03 / 2:11:00` — the pair
keeps one width for the whole runtime.

**AirPlay is real** (`AirPlayButton`): a live `AVRoutePickerView` held at 2% alpha over our own
button, because a fully transparent `UIView` stops hit-testing. It reads the actual route name off
`AVAudioSession.currentRoute` and lights up when output leaves the device. tvOS has no route
picker — the TV owns routing — so there it is an inert readout.

**Scenes / trickplay** (`TrickplayClient` + `PlayerScenesPanel`) — a grid of thumbnails around the
current moment, swipe to travel, tap one to go there. **It never scrubs the video to build these.**
Jellyfin pre-bakes frames into sprite sheets; one sheet download plus bitmap arithmetic gives a
whole page, measured at ~80ms against ~1.1s for a frame-accurate seek per thumbnail. Three
protocol landmines, all of which cost v1 a bugfix commit each:

- **The `Trickplay` field nests two levels** — `mediaSourceId → widthString → info`. Reading the
  media-source key as a width is a *decode failure that presents as "this item has no trickplay"*,
  not as an error, so it fails silently and permanently.
- **Never gate on `ThumbnailCount`.** It counts only non-black frames, so an item whose opening is
  a fade reports `1` while the sheet holds a full valid grid. Fetch and crop; let 404 /
  decode-failure / out-of-bounds be the only rejections.
- **Dedupe in-flight sheet fetches.** Six cells missing the cache at once otherwise pull the same
  sheet six times and only the last write survives.

Sheets are cached LRU (24) on an actor, wiped explicitly on sign-out — the URLs carry an
`api_key` but the decoded images have no auth boundary of their own.

Panel behaviour worth keeping: **times past the runtime are filtered out before anything renders**
(a cell that can never load spins forever — that was a real bug), rows collapse to
`ceil(count/3)` with *invisible* spacers so surviving tiles keep their one-third width, and the
**"Next video" tile sits in the grid** in the slot the next thumbnail would have occupied rather
than on an edge page of its own. Paging widens as you travel (10s per cell near the current
moment, then 50s, then 60s). `TabView(.page)` does the swiping — v1 shipped a hand-rolled
`DragGesture` carousel first and replaced it because the commit-vs-settle race made the outgoing
page slide back in; the native pager also can't be spammed, since a drag must physically complete
to land a page. `.page` style is **iOS-only**: on tvOS a `TabView` without it paints a tab bar
across the panel, so tvOS renders the current page directly and travels by the footer buttons.

**Resuming an episode queues the rest of its season.** `AppState.resumeRequest` used to return
`.single(item)` for Continue Watching, which silently disabled everything downstream that needs a
next episode — auto-advance at end of item, and the scenes panel's Next-video tile. Someone
resuming episode 4 means to keep watching. A movie stays a single item.

**A `.fullScreenCover` must hang off a container whose identity never changes.** `RootView`'s
cover previously sat on a `Group` whose branch swaps when `server.isConnected` flips — which it
does whenever stored credentials are tried, fail, or later succeed — and each flip tore the
presented cover down. It now hangs off a `Color.clear` sibling inside a `ZStack`. This is not just
the screenshot hook: a server blip mid-film used to drop the user out of the player. Presenting a
cover from an initial `@State` value is separately unreliable (SwiftUI drops it during the first
render pass), so the `RT_SHOW_PLAYER` fixture is raised in `.onAppear` instead.

**Night mode** (`NightModeController` + `NightModeOverlay.swift`) is a sleep aid, not a colour
filter, and every part of it exists to survive someone falling asleep holding the iPad:

- **It locks the chrome.** Engaging it hides the controls and puts a full-screen catcher over
  everything, so a stray touch is *inert* — a tap only wakes the status badge. Only a press held
  for `unlockHoldSeconds` (1.2s, with a ring that fills as it's held) opens the lock, and an open
  lock closes itself again after `relockSeconds` (15s) of idleness. That countdown measures
  idleness, so every deliberate control tap pushes it back out (`noteInteraction`, called from
  `PlayerChrome.interact`) — and a *paused* player holds it open indefinitely, same rule as the
  chrome's own auto-hide.
- **It dims and de-blues.** `UIScreen.brightness` to its minimum (iOS only — tvOS has no such
  knob) *plus* `NightVeil`: a warm wash `.blendMode(.multiply)`'d into the picture. Multiply is
  what actually removes blue; a normal-blended warm layer only lifts the blacks. The blend does
  **not** leak onto the chrome drawn above it (verified on device). There is no public API for
  system Night Shift, so this is the app's own filter over its own video.
- **It stops itself.** A wall-clock sleep timer (`SleepTimer`, 1/2/8 hrs, Settings → Playback,
  persisted on `AppState.sleepTimer`), and across its last `fadeFraction` (15%) the app's output
  gain — `AVPlayer.volume`, never the system volume — rides from wherever the user had it to
  zero while the veil deepens in step. At zero it pauses, opens the lock (waking to a screen you
  can't get into is worse than a stray touch) and hands the gain back.
- **Everything it took, it gives back**: brightness and volume are captured on the way in and
  restored on the way out — switching Night mode off, tearing the player down (`onDisappear`),
  and whenever the app leaves the foreground (an app's brightness change outlives it, so
  `setForeground(false)` returns the user's level and coming back re-takes it).

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
  `JT_NIGHT`/`RT_NIGHT` = `on` | `locked` | `ending` | `ended` seeds Night mode's states, and
  `=fast` runs a *real* one — lock, countdown, volume wind-down, auto-stop — compressed into 90
  seconds, so the end of the timer can be watched instead of taken on trust. Pair it with
  `JT_PLAYER_LOG=1`: the wind-down logs its percentage and the live volume each quarter.
  Crop/zoom with ImageMagick (`magick … -crop`) for close inspection. These are permanent,
  inert-unless-set hooks (same convention as `JT_SHOW_MOVIES` etc.) — nothing to revert.
  `SIMCTL_CHILD_<VAR>=<value> xcrun simctl launch <device> <bundle-id>` sets the env var directly
  when driving the simulator outside XcodeBuildMCP's `launch_app_sim`. The Apple TV simulator's
  screenshot capture sometimes comes back portrait-rotated (e.g. 450×800 instead of landscape) —
  `magick screenshot.jpg -rotate -90 out.png` before inspecting it.
- **The simulator fights you when verifying the player.** Two failure modes that both look like
  app bugs and are not: the sim's display sleeps within seconds and **suspends the app**, so
  injected taps do nothing and timers don't fire (a screenshot loop keeps it awake — `sleep`
  doesn't); and `axe describe-ui` regularly returns a **stale hierarchy**, happily reporting the
  view *under* a presented cover. Neither is visible as an error. When behaviour is in question,
  read the app's own log rather than the AX tree:
  `xcrun simctl launch --console-pty <udid> <bundle>` captures stdout, and `JT_PLAYER_LOG=1` puts
  chrome visibility transitions, cover presentation, and the trickplay path on it. Hours went into
  chasing a "chrome never reappears" bug that was display sleep.
- Real HID injection for touch/swipe is AXe (bundled with XcodeBuildMCP):
  `~/.npm/_npx/*/node_modules/xcodebuildmcp/bundled/axe {tap,touch,swipe,key} … --udid <udid>`.
  `touch --down --up` is more reliable than `tap` for a control that may still be animating in.
  Coordinates are device points. For real playback without tap automation, `RT_AUTOPLAY=<substring>`
  resumes a Continue Watching entry at launch (any non-empty value falls back to the first one).
- SourceKit frequently shows stale `No such module 'JellyTVKit'` (or missing-member) errors in the
  editor after package edits; trust the actual `xcodebuild` / `swift test` result, not the inline
  diagnostics.
