# CLAUDE.md

Project basics (repo layout, build/test commands, branding) live in [`README.md`](README.md) — read that first for mechanics.

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
gap rather than growing one tall panel. The library browse screens no longer carry a panel at
all: their hero (`LibraryHero`) is text over the backdrop in one fixed-height, bottom-aligned
block — the same rule applied to a paragraph, with an empty slot standing in for the cast line
while the detail loads. Every boxed panel needs its **own** loading/decode indicator sized to
its own footprint — a sibling panel finishing first while another sits blank reads as broken, even
if each panel's fixed-size rule is individually satisfied.

**Cast/person portraits are rounded squares, not circles** (`CastPortrait` in
`MetadataComponents.swift`): a deterministic per-person gradient monogram fallback (hash the id
into a hue), an accent-colored ring for a lead/featured role, and a distinct gold ring + a small
gold medal badge tucked into a corner for a special/decorated status (e.g. an Oscar-winning
actor). Reuse this shared component rather than a one-off circular avatar. **The one deliberate
exception is the tvOS movie page**, where the cast are struck as coins (`CastCoin` — see "Movie
Night"): round because coins are, gold for the Oscar winner, the same monogram inside. Nowhere
else.

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

## Home on tvOS

**Every control on Home does something, or it isn't there.** The hero's Details button was an
empty `Button {}` and its "+" a stub for years; the top bar's "M" avatar opened Settings, which the
rail's gear already does. Now: Details opens the film's page or, for an episode hero, its *show's*
(`HomeView.presentDetails(for:)` — there is no episode page); the "+" is a heart that favourites
the item on the server, optimistic and reverted on failure; the avatar is gone. `TopBarClock` is
the real time (`TimelineView`, breathing colon, meridiem in the accent only in 12-hour locales,
locale's own abbreviated date) — it replaced a `Text("9:41 PM")` frozen at keynote time on a screen
people leave on for hours.

**The hero crumble runs at half resolution on tvOS** (`HomeView.departingLayer`,
`HeroDepartureModifier.renderScale`/`flightScale`, the shader's `unitScale`). An Apple TV 4K draws
the app at 3840×2160 and `layerEffect` runs `hexCrumble` once per pixel of the departing layer
*plus* its `maxSampleOffset` margin (600×560pt, which more than doubled the layer) — on the order
of 25 million hex/noise/crack evaluations a frame, and the real box stuttered; `lite` trimmed
instructions, never pixels. Now the departing layer is laid out at 0.5× and scaled back up (¼ the
fragments), tiles fly 60% as far so the margin shrinks with them (~1.5× more), and `lite` keeps
one warp octave instead of two. The shader computes in *screen* points and converts only at its
texture taps, so cells, cracks and glow are the size they were designed at — change `renderScale`
freely without retuning anything. iPad stays at 1/1. `HeroDotsRow` also redraws at 12 fps, not 60:
`TimelineView(.animation)` alone invalidated the row every frame for as long as Home was on
screen, a constant tax on the GPU the crumble has to share.

**A movie opened from Home used to eat the Menu button.** `MovieDetailView`'s `.defaultFocus`
never resolved when the page was presented as Home's same-`ZStack` overlay — the Resume card sat
unlit, and Menu, with no focused view for `.onExitCommand` to hang off, fell through to tvOS and
backgrounded the whole app (verified from both the hero's Details and a Recommended poster). It
now seeds `.resume` in `.onAppear`, the same way the player's failure overlay and the library
grids do; the same page's own "+" became the heart that iPhone's quick action already had.

**The "connect remote" icon is Jellyfin remote control** (`RemoteControl`, `JellyfinSocket`,
`JellyfinClient.postRemoteControlCapabilities`). There is no pairing of its own: the server relays
it. Switched on, this session posts `/Sessions/Capabilities/Full` (`SupportsMediaControl`,
`PlayableMediaTypes: Video`, and only the `GeneralCommandType` names it handles — an unknown one
fails the whole call) and holds `/socket?api_key&deviceId` open, so every other Jellyfin client on
the server lists it as "JellyTV" under Play On / Cast. `Play` becomes the same request a tap here
would build (`AppState.playbackRequest(forItemIds:…)` → `resumeRequest` for one item, so an
episode still queues the rest of its show; `PlayQueue.playableItem` for a list); `Playstate` goes
to `AppState.activePlayerController`, registered by `PlayerView` for as long as it is up; `Stop` /
`GoHome` clear `activePlaybackRequest`, which `RootView` now mirrors into dismissing the cover.
The socket's first message is the handshake (`ForceKeepAlive` → answer `KeepAlive` at half its
timeout, or the server drops you); it reconnects with capped backoff while enabled, and the
choice persists (`jelly:remote.enabled`, default off — a TV any phone in the house can start is a
prank in some households). Verified end to end against the real server: `GET /Sessions` shows
the capabilities, `POST /Sessions/{id}/Playing` started a film, `…/Playing/Pause` showed
`IsPaused: true` server-side, `…/Playing/Stop` dismissed the player. **The top bar is a
`.focusSection()`** for the same reason `ShowView`'s shelf header is: the switch sits far right and
the hero's buttons far left, and without it Up from Resume went nowhere.

## Library screens on tvOS (Movies, TV Shows, Anime, Late Night, Home Videos)

One shape, the one every commercial TV app lands on: a one-line header, a chip row, the focused
title as a **hero of text over its own backdrop** (`LibraryHero`), and a grid of **clean
posters**. What went, and why it stays gone:

- **The "SIGNAL DOSSIER / DECODED / SCANNING" panel, the `SELECTED // NOW IN YOUR LIBRARY`
  eyebrow, "CONTENT DOSSIER / RESTRICTED", "VIEWER DISCRETION", "EXPLICIT CONTENT", the
  vertical アニメ / 深夜アニメ signatures.** Chrome describing chrome. The hero is logo art (or
  the title in type), one facts line (★ · certification · year · genre · length · critic
  scores · Oscar badge), three lines of synopsis, and `Starring A, B, C · Directed by D` /
  the network. Fixed height, bottom-aligned, so the grid never moves; the people line is an
  empty slot while the detail loads rather than a spinner for a sentence.
- **The 1000pt search field and its default focus.** Search is compact (440pt) at the header's
  trailing end (`LibraryHeaderLayout`, tvOS branch); focus opens on the **first poster**.
  Seed it from the first card's own `.onAppear` (`seedFocusIfNeeded`), not from an `onChange`
  on the loaded flag — that pass runs before the lazy grid has mounted the card, the assignment
  lands on nothing, and focus stays on the first filter chip (verified). `lastFocusedId` keeps
  the hero on the last poster while the remote is up on the chips.
- **The header "Play" button** — an empty `Button {}` in the accent colour, the most prominent
  control on the screen and the only one that did nothing. Random stays; it works.
- **Poster overlays** (title, ★ badge, year · genre caption) on tvOS. The art carries its own
  title and the hero names whatever is focused; forty stamped captions read as a spreadsheet.
  Only a poster-less item keeps its name on the card. The count is said once, in the header
  (`LibraryChrome.countLabel`: "30 titles" / "12 of 30 titles"), not three times.

**Filter chips: selected is the accent, focused is white** (`FilterChipStyle`). The LED ring that
suits a 190pt transport circle is a hairline on a 40pt capsule — a focused chip was the resting grey
pill with a thin glow, visibly *weaker* than the accent-filled chip beside it. The pill under the
remote is now solid white with ink text, scaled 1.1× over a plain dark lift shadow (an accent glow
was tried and read as a red smear into the backdrop); selected *and* focused keeps the white pill
and sets the label in the accent, so the two states never blur. Touch keeps
the old look (accent / translucent, press dip). Don't put `FocusScaleStyle` on anything pill-sized.

**`SampleCatalog.movie(for:)` / `.show(for:)` are bare now — keep them that way.** Until
September 2026 they copied the demo template's rating, certification, year, director, runtime,
synopsis, resume progress, studio line, "more like this" row and even key art onto any real item
that lacked them, plus a genre fallback ("Thriller" / "Sci-Fi Drama"). Every detail screen opened
on "Mara Ellingsen · 2h 14m · 8.6", a demo synopsis and a fake RESUME for the ~300ms the fetch
took, and the library bands wore ★ 8.9 for as long as anyone looked. They now carry only what the
`MediaItem` really has (id, title, genre, rating, certification, year, synopsis, art, favourite);
everything the detail fetch fills starts empty, and empty renders as a dash or as nothing.
`LibraryHeroContent` still reads the list fields off the item directly — the item is the source
either way. `MediaItem.logoImage` exists for the same reason: a logo'd title must never render in
type and then swap.

## Home Videos on tvOS — a camera roll, not a grid

**These files have nothing but a frame and a date, so the screen is built from those two.** What
the 399-video library here actually carries: trickplay sprite sheets on 377 (a frame every 10s,
10×10 tiles, 320px wide), the day the video was shot (`PremiereDate`) on 296, a third of them
portrait phone clips (608×1080, 720×1280), UUID filenames, a median length of one minute — and no
chapters, overviews or titles worth reading. So (`HomeVideoRollView`, tvOS; the iPad keeps its
16:9 grid): an **"On this day" strip** first (videos shot within ±3 days of today in an earlier
year, "6 YEARS AGO" / "LAST YEAR" badges — with five years of dates it is rarely empty), then the
videos **by month, newest first, a pinned header over each**, undated ones last; each month a
**justified mosaic** (`HomeVideoRoll.justifiedRows`: one shared height per row, every row filled
edge to edge, a tile's aspect from the file's own `Width`/`Height`, clamped 9:16…2:1, 16:9 when
unknown, the last row never stretched), so a portrait clip stands tall beside a landscape one
instead of being letterboxed. The card's label is the **date, never the filename**, with the
duration; narrow tiles drop the year and stack the two. The "Shuffled" order is one flat mosaic —
months would only re-sort what was just scrambled. A card plays the order that is on screen (the
month order, or the strip's), not the server's. The arithmetic — sections, anniversaries, rows,
frame picks — is `HomeVideoRoll` (kit, tested).

**The focused card plays the video's own frames.** `HomeVideoCard` pages through up to eight
trickplay frames spread across the runtime, 1.2s each with a crossfade, and a hairline at its foot
stepping along to where each frame sits — one sheet download (`AppState.cardTrickplay`, one
`TrickplayClient` shared by every card), no video decode, no scrubbing. Only the focused card
ticks (`TimelineView` paused otherwise), so a wall of them costs what one does. The picks skip the
first frame (the black before anything happens) and the last (end of file; missing from the sheet
as often as not), and a clip with fewer than two frames between those keeps its still. The
geometry rides on the list item (`MediaItem.trickplay`, from `fields=Trickplay` in
`loadHomeVideos`) so there is no per-card request. The player's scenes panel keeps its own client.

## Movie detail on tvOS

**It is the iPad one-sheet at TV size** (`MovieDetailView.tvBody` / `contentTV`,
`MovieOneSheet.swift`): the poster as a physical object on the left (700pt tall at most), the
text column held to the poster's height so the Play bar lands on its bottom edge, a hairline
metadata rail (rating · runtime · director · year), the cast band across the foot, all over
`PosterBloom` — the poster's own dominant colour thrown across the screen (`DominantColor.of(url:)`).
`OneSheetMetrics` holds the sizes that differ by viewing distance. The "signal dossier" it
replaced — a boxed 780×439 key-art panel with a floating `ResumeCard`, a 2×2 `SpecSheet`, a MORE
LIKE THIS row of `SampleCatalog` posters on a real film's page, and Trailer / EN·5.1 / CC·OFF
`DetailPill`s that were focusable buttons doing nothing — is deleted, components and all.
**The Play bar is `TVNeonPlayBar`, not `NeonTransportBar`:** the whole bar is the one button, and
it is **the brightest thing on the page** — a solid slab of the film's own colour (glass top,
shaded foot, a near-black tint lifted so it reads as a surface), a white disc with the glyph in
the tint, the label in ink or white by the colour's luminance (`Color.luminance`). Under the
remote it comes alive on a `TimelineView` that ticks only while focused: the bloom behind it
breathes, a band of light crosses the face every ~2.6s, and two rings pulse out of the disc like a
sonar ping ("more POP, WOW — let's play!"). At rest it is the same solid colour, calm. RESUME
shades the unwatched stretch and draws a filament where you stopped. Deliberately not
`FocusScaleStyle`: the bar is its own ring of light. It carries no readout — the iPad's TRAILER /
AUDIO / SUBS / ＋LIST items aren't settings this app has, and on a TV unlit glass nobody can
select reads as broken. **And it is a third of the column wide (352pt), the heart beside it**,
not the full width it inherited from the iPad: there the right two-thirds carried that readout,
and once the readout went the stretch was lit glass saying nothing ("seems so empty"). A remote
needs no finger-width target, so the bar shrank rather than being filled; the earlier outlined
tube around a dark fill was the calmer look this solid one replaced. Focus seeds to `.play` on appear. This one-sheet is now the first *fold* of the Movie
Night page below, and the unfocusable cast band under it became the `CastLineup`.

## Movie Night — the tvOS movie page

**The page has to sell the film to a family deciding what to watch tonight.** One vertical
`ScrollView` of four folds (`MovieDetailView.contentTV`), each its own `.focusSection()` so Down
from the Play bar walks them: the **pitch** (the one-sheet plus a facts row, under `AmbientBackdrop`
— the film's wide art on a 24s Ken Burns drift behind the `PosterBloom`, crossfading through up to
six when TMDB is on), **`CastLineup`** (figures on a lit stage beside a fixed 560×300 fact card),
**`ScenesStrip`** (chapter frames — only when ≥3 chapters carry an image; 8 of 30 films here), and
**`SimilarRow`** (`/Items/{id}/Similar`, so every poster in it is in this library). Select on a figure
opens `PersonSheet` (same-ZStack overlay, page `.disabled` beneath, Menu closes it); Select on a
poster in the sheet's IN YOUR LIBRARY row swaps the presented film via `onOpenItem`.

**Everything on it is real, and each fact is absent rather than invented.** What the server turned
out to hold, per film: a person item carries the biography, birth and death dates and birthplace
(`Overview`, `PremiereDate`, `EndDate`, `ProductionLocations`) — the fact card's `AGE 39 AT RELEASE`
/ `BORN BEIRUT, LEBANON` / `1985 – 2025` come from those; `/Items?personIds=` gives "N MORE IN YOUR
LIBRARY"; `Chapters[].ImageTag` → `/Items/{id}/Images/Chapter/{index}?tag=`; `MediaStreams` gives
the audio line and subtitle languages; `Logo` art is the title. Ruled out: trailers (every one is a
remote YouTube URL — not playable in-app) and theme media (none). TMDB is an opt-in *enhancement*
(more backdrops, keywords, collection progress) and the page is complete without it.
`MovieNightFacts` (kit, pure, tested) holds the arithmetic: ENDS = now + runtime − resume; TOP N%
only with ≥20 rated films *and* N ≤ 25 ("TOP 64% OF YOUR MOVIES" is a statistic dressed as a
compliment); person ages by year only.

**The vibe chips need no TMDB key.** Jellyfin's own TMDB provider files TMDB's keywords on the item
as `Tags` (`alcohol`, `pen pals`, `road trip`…), so `MovieNightFacts.vibeChips` reads those, with
TMDB's ranked list first when the key is on. `duringcreditsstinger` / `aftercreditsstinger` are
facts, not vibes, and lead as STAY FOR THE CREDITS / SCENE AFTER THE CREDITS; place tags
("berlin, germany") and run-on machine tokens are dropped.

**The cast are coins** (`CastCoin`, 190pt in the lineup, 440 as the person sheet's hero). The
headshot sits recessed in a milled metal rim — an `AngularGradient` of light and dark stops for
brushed metal, a dashed stroke for the reeding, a second bevel ring lit from another angle so
the rim reads as raised, stepped darker discs behind for thickness — silver, or gold for an
Academy Award winner; the coin's field carries the same monogram as `CastPortrait` when there
is no photo. **The coin under the remote is live:** one full `rotation3DEffect` turn on arrival
(showing its tails side — a star in the same metal and a hairline of the film's colour — on the
way round), then a slow rock and nod, a light travelling the rim, a streak crossing the face
every couple of seconds, and a pool of the film's colour on the stage under it. Coins at rest
lean ±14° alternately, like a row stood on a table. Only the live coin ticks — its
`TimelineView` is paused otherwise — so eight cost what one does, and nothing here is a shader.
Where a cut-out exists, the bust stands on the field **in relief**, its head rising up to 17% of
the diameter above the rim: the photo's bottom sits on the coin's bottom so the circle always
does the cutting there, and its sides are feathered so hair never ends on a straight photo edge.

**Cut-outs (`PortraitCutoutCache`) do not run on the tvOS simulator.** Vision's
`VNGenerateForegroundInstanceMaskRequest` fails there with *Could not create inference context*
(`JT_PLAYER_LOG=1` prints it as `cutout:` lines), so the simulator shows the photo in the coin's
field, never the relief — that is the designed degrade, not a bug. The identical pipeline run on
the Mac cuts server headshots cleanly (70–88% mask coverage, inside the 8–95% gate), so the code
is right; the busts need a real Apple TV to be seen. **To see them on the simulator anyway, run
`Scripts/seed-simulator-cutouts.sh`:** results live as PNG under the app container's
`Library/Caches/cutouts/<sha256 of the image URL>.png` (the URL is
`{base}/Items/{personId}/Images/Primary?quality=90&tag={tag}&maxWidth=600`), and the script makes
the same cut-outs on the Mac (`Scripts/segment-headshots.swift`, the same Vision calls and gate)
for every actor of every movie and drops them in under those names — 30 films, 217 busts, about a
minute. Without it only whatever was seeded by hand has a bust, which is why "only EuroTrip has
them" was once a question. Two segmentations at a time on device, never redone for a URL.

**Pages zoom out of what you selected** (`ZoomTransition.swift`, tvOS only; iOS keeps its
crossfade through the same calls). A focused card marks itself with `zoomOrigin(_:)` (an anchor
preference — `LibraryPosterCard`, Home's `PosterCard`, the hero's Details button, a cast coin); the
presenting screen reads it with `trackZoomOrigin(_:)` into a `UnitPoint` of its own frame and
clears the preference so a coin focused inside the movie page can't become the library's origin;
the page gets `zoomPresented(from:)` (scale 0.94 → 1 out of that point, back to 0.97 on Menu) and
the screen beneath `zoomedBehind(_:origin:)` (pushes in to 1.04× toward the same point and fades),
all on `.animation(.zoomPresentation)`, one even 0.45s ease. **Subtle is the whole point:** the
first cut flew the page in from 30% on a spring with the shelf pushing to 1.18×, and the user's
verdict was "NOT smooth" — a big scale range moves every pixel of a 4K frame a long way per frame
and the spring settles with a wobble; the anchor is what makes it read as a zoom, not the
distance. The person sheet takes the same route out of its coin. Inside the movie page the folds
then `entrance(_:delay:)` in order — poster, column, cast, scenes, shelf, a 14pt rise — and the
folds that arrive with the detail fetch (`foldSignature`) fade in rather than pop, as does the
poster's colour (`.animation(value: posterTint)`), because data landing mid-transition reads as
stutter. **Nothing heavy happens while the zoom runs:** the detail fetch is applied no sooner
than 500ms after appear (fetched at once, applied after the transition — it lands in ~300ms,
squarely mid-animation, and the reflow was a visible hitch), and `PosterBloom` (a 90pt blur at
1.3× the screen) and `AmbientBackdrop` fade in over 0.9s starting 0.4s after appear instead of
being drawn during it. Scale and opacity only; no new blur (a full-screen blur at 3840×2160 is
exactly the cost the crumble taught). **The simulator cannot judge smoothness:** a recording of
the zoom (`simctl io recordVideo`, frames dumped with `AVAssetImageGenerator`) showed it drawing a
new frame every 150–180ms during the transition, whatever the code does — judge on the Apple TV.
Two things the zoom cost: the screen beneath fades to 2%, not 0, because the focus engine won't
land on alpha ≤ 0.01 and focus is handed back on the first frame of the return; and each
presenting screen puts focus back explicitly on Menu (`focusedId = lastFocusedId`, or the focus
saved when the page opened) — left to the engine it fell to the first filter chip.

**Focus on this page, learned the hard way.** Entering the lineup lands on whoever the fact card
shows (lead, or last looked at) — left to geometry, Down from a Play bar that spans the page landed
on the *fifth* of eight figures, the one under the bar's centre. Closing the person sheet puts
focus back on that figure (`onChange(of: presentedPerson)`), otherwise the re-enabled page picks
its own nearest and the lineup scrolls back to the start. The sheet's scrim is 0.92 black: at 0.74
the Play bar and fact card read through the biography as if they were part of the sheet.

**Play from a scene** rebuilds the film's `PlayableItem` with `resumePositionTicks` set to the
chapter's start (the same rebuild `restartMovie` does with zero), and the engine's ordinary
resume seek does the rest — `resume seek → 443s of 5366s` in the log for the 7:23 chapter.

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

**The chrome is the "Grandma menu"** (design canvas artboard A) — one centred column: the two
opinions over four transport circles over a position readout, then the two places you can *go*:

    👎  ❤️                                                          (`PlayerOpinionRow`)
    ↺30  ·  play/pause  ·  ↻30  ·  ↻1min                           (`PlayerTransportRow`)
    27:00 / 55:16                                                   (`PlayerClockReadout`)
    [ PREV ]  [ SCENES ]  [ NEXT ]                                  (`PlayerFootActions`)

It replaced a 13-control chrome (repeat, a right-hand rail of favourite/next/dislike, a progress
bar, and a 7-tile seek strip). Gone and staying gone unless someone asks: **the progress bar** (a
bar invites dragging, and a dragged bar is the easiest way to lose your place by accident);
**start over**, which was a fifth circle whose one press costs the whole film, sitting next to the
most-mashed buttons in the app (`PlayerController.jump(to:)` survives it, callerless); and
**captions**, except where the glyph can't carry it — BACK, PREV, SCENES, NEXT. PREV and NEXT
flank SCENES rather than pairing up: a miss between two adjacent queue buttons lands on the wrong
episode, and with the widest target in the row between them a slip opens the harmless scene grid
instead. Each hides when the queue has nothing that way.

Two consequences of that list worth knowing before touching the row. **Play stays screen-centred
by an empty leading slot** the width of the deleted circle — deleting it outright pushed the
biggest target ~96pt off centre, and "the button you press most needs no aiming" is the premise,
not a detail. And **repeat-one lives on a long press of the play button**: the circle then shows
`repeat.1` in a white ring (a playback mode you can't see is one you can't escape), and one
ordinary tap clears it — so while repeat is on, *pausing costs two taps*. A `longPressedAt`
timestamp swallows the tap that finger-up leaves behind; a plain flag would sit armed forever when
a long press slides off the button.

**Tags are editable from the chrome** (`PlayerTagsPanel`, opened by the tag row under the title —
which renders as an `ADD TAGS` pill when there are none, because the item with no tags is exactly
the one you want to tag). Real Jellyfin `Tags`, not a local list; v1 kept tags in a local SwiftData
store per library and **never wrote one to a server**, so the write path here is new ground. What
it cost to find:

- **`POST /Items/{id}` takes the whole `BaseItemDto` and nulls every field the body omits.** So the
  write is a read-modify-write of the *raw JSON the server just returned*
  (`JellyfinClient.setItemTags` → `JellyfinTags.itemDTO`), never a struct of ours — fields this app
  has never heard of go back verbatim. The GET must name every writable field explicitly
  (`Overview`, `Genres`, `People`, `ProviderIds`, …): Jellyfin returns a lean DTO by default, and a
  field missing from the read is a field wiped by the write.
- **Strip `Trickplay` from the body or every write 500s.** `TrickplayInfoDto` is a record Jellyfin
  can serialise but not deserialise, so posting its own DTO back throws
  `InvalidOperationException: Each parameter in the deserialization constructor … must bind to an
  object property`. It arrives whether or not `Trickplay` was in `fields`. The response is a bare
  "Error processing request." — the real exception is only in the server's log
  (`/var/log/jellyfin/jellyfin*.log`). `JellyfinTags.unparseableKeys` is the list to extend if
  another type ever does this.
- **The tag vocabulary comes from `/Items/Filters`, not `/Items/Filters2`.** The newer endpoint
  advertises a `Tags` array and returns it **empty** on 10.11.11 (verified: 0 vs 1,266 server-wide),
  with or without `parentId`/`recursive`/`includeItemTypes`. A silently-empty vocabulary reads as
  "this server has no tags", so nothing at the call site notices. There is no `/Tags` endpoint.
- **Editing requires an admin account** (`RequiresElevation`). `AppState.canEditItemMetadata` is
  `Bool?` on purpose: `nil` means "haven't asked", and it must not read as "no" — v1 hid its whole
  tag strip behind an unresolved async answer and left slow servers with no way to create a first
  tag.
- **The vocabulary is a search index, not a menu** (1,266 tags here). The panel shows what's on the
  item, then *recents* (`AppState.recentTags`, persisted) or live matches as you type — never the
  list. Typing a case-variant of an existing tag reuses that tag's spelling
  (`JellyfinTags.canonical`), or `gaby`/`Gaby` become two tags Jellyfin will happily keep apart.
- **For an episode the panel edits the *series*.** Jellyfin puts tags on shows, not episodes, so
  every episode `PlayableItem` here carries its series' tags — editing anywhere else would mean the
  chips you see and the chips you change are different lists (`PlayerController.tagTargetId`).
- Writes are optimistic, chained (never parallel — two read-modify-writes overlapping is how a
  mashed chip row saves a stale list), and revert with a visible message on failure. Tags written
  mid-video are re-applied over the library screens' own cached copies
  (`AppState.applyingTagOverrides`), since nothing re-runs their loaders while the player is up.

Where an item has **logo artwork** (`/Items/{id}/Images/Logo`) that artwork *is* the title; plain
type is the fallback, and only the fallback. Both the logo and the tags needed new plumbing —
`PlayableItem.logoURL`/`.tags`, `Movie`/`Show.logoArt`/`.tags`, and `Tags` added to
`fetchItemDetail`'s `fields` (Jellyfin won't return it otherwise). An episode borrows its
*series'* logo and tags via `AppState.seriesIdentity(for:)`; Jellyfin almost never gives an
episode either.

**The identity sits bottom-right, diagonally opposite BACK** (`PlayerIdentityMark`), and the tags
have the top-left column to themselves. The wordmark used to sit above them, and on the one screen
tags are *edited* from it capped the row at what a logo left over. Identity is the only thing here
nobody needs to act on, so it goes in the corner furthest from the controls — inert
(`allowsHitTesting(false)`) and capped narrow (240pt on iPad, 380 on tvOS) so it can never reach
the centred `PlayerFootActions` row, whose tiles are the widest targets in the chrome.

**How many chips fit is measured, not assumed.** A fixed count can't work — "Drama" and
"Watched before" aren't the same width, so a number that suits one truncates the other, and
capping at eight and letting SwiftUI compress produced a row of `Dr… Sp… Watc…`: chips taking a
tag's space while naming none. The chips refuse to shrink (`fixedSize`) and `ViewThatFits` walks
8 → 1 until a whole row fits; whatever is left over is *counted* in a `+N` chip, never silently
dropped. For that measurement to be truthful the header's right-hand cluster carries
`.layoutPriority(1)` and the left column `.frame(maxWidth: .infinity)` — proposed the whole bar
instead, `ViewThatFits` would happily fit eight chips straight through the AirPlay button. It
lands on 5 chips on iPad and 8 on tvOS, which is the point of measuring rather than hardcoding.

**Seeks are coalesced, because these big circles are the most mashable surface in the app.**
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
picker — the TV owns routing — so `PlayerTopBar` doesn't show it there at all. It used to, as an
inert "SPEAKER" readout in exactly the clothes of the live Night button beside it: a control-shaped
non-control, the same problem the SIGNAL/4K·HDR readout had before it went.

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

## Playlists — what plays next

A "playlist" here is **the queue behind whatever is playing**: the thing NEXT and
auto-advance walk. It is ephemeral and client-side. Nothing is written to Jellyfin's own
`/Playlists` API (v1 never touched it either), nothing is persisted, and a queue lives exactly
as long as the player showing it. Two rules decide what goes in one:

- **A tap queues the list you tapped it from.** Home videos have no detail screen, so a card
  *is* a play button — and what should play next is plainly the shelf you were looking at.
  `AppState.listQueueRequest` builds the queue from the view's `filtered` rows: the visible,
  searched, sorted list, in screen order, starting where the finger landed. Built from what the
  grid already holds, with no fetch in between, which is what keeps "tap and it plays" honest.
  This is why `MediaItem` carries `resumePositionTicks`/`isFavorite` — Jellyfin returns
  `UserData` on every user-scoped `/Items` response whether asked or not, so the whole queue is
  resume-correct for free; without them the *fourth* video restarts from zero even though the
  server knows you were halfway through it.
- **Playing an episode queues the whole show from there** — the rest of that season in order,
  then every season after it (`AppState.seriesQueueRequest`, used by the Show screen's episode
  drawer, its resume card, and Continue Watching alike). It used to stop at the season boundary,
  which made the last episode of a season the end of the evening with nine seasons still sitting
  one tap away. Same single recursive call as the shuffle, only `sortBy=ParentIndexNumber,
  IndexNumber` instead of `Random`, so it inherits `isMissing=false` and cannot queue a fileless
  episode. Specials (season 0) sort ahead of season 1, which is right for free: starting at the
  tapped episode drops everything before it, so a normal episode never gets a pile of specials in
  front of it while someone who taps a special still gets them. Verified end to end — tapping
  S01E13 of The Simpsons and pressing NEXT plays S02E01.
- **A show's SHUFFLE ALL is every episode of every season, re-rolled per press.** The order comes
  from the server, so two presses are two different queues, never a re-entry into the last one
  (verified: four presses gave S02E03, S03E11, S05E09, S05E15). It carries an in-flight guard —
  a second press mid-build would throw the first queue away and hand `.fullScreenCover` a new
  identity, tearing down a player already on its way up.
- **Random reaches past the visible page to the whole library, and plays it.** Not
  `filtered.randomElement()` — a shuffle that can only reach what happens to be on screen isn't
  a shuffle, and the old version didn't play anything anyway (it opened a detail page, or on
  tvOS merely moved the focus). `AppState.randomQueue(for:)` takes a `PlaylistScope`
  (`.movies` / `.shows` / `.anime` / `.lateNight` / `.homeVideos`), each naming **the same
  library set that screen's list loader uses** — "random" has to mean "random out of what this
  page shows", or it plays something the user can't find on the page they pressed it from. For
  the episodic scopes the queue is every episode of every season of every show, flattened; the
  Anime scope adds its films, because that screen is two loaders shown as one library.

**One recursive call flattens a whole library** (`JellyfinClient.fetchPlayQueueItems`):
`/Items?parentId=<library>&recursive=true&includeItemTypes=Episode` returns every episode of
every season of every series under it. Walking series → seasons → episodes is hundreds of round
trips for the same answer — `shufflePlayRequest` used to do exactly that for one show and now
doesn't. `parentId` takes a series as happily as a library.

**`sortBy=Random` shuffles server-side over the whole library, so the fetch cap costs nothing.**
This is the load-bearing measurement: two independent 500-item draws from a 3,525-episode library
overlapped by **69** items, against 71 expected for a uniform sample — a "first page, then
shuffle" implementation would have overlapped by 500. So `PlayQueue.limit = 500` is a uniform
sample of everything, not a truncation, and no viewer reaches the end of it. Lifting it to the
whole library does cost: 3,525 episodes is 4.1 MB and 3.3s after a button press, against 608 KB
and 0.5s. Jellyfin re-rolls the order per request, which is what makes a second press of Random
a genuinely different queue rather than a re-entry into the last one.

**`isMissing=false`, or a quarter of the queue is dead ends.** Jellyfin files metadata-only rows
— unaired episodes, and the stubs AniDB/TheTVDB invent for specials and sketch galleries — as
ordinary episodes with no file behind them: **859 of 3,525** in the adult-anime library here.
The query parameter drops them at the source (`hasPath`/`isVirtualItem` do *not* — verified,
both return the full 3,525), and `PlayQueue.isPlayable` re-checks `LocationType` client-side.
Belt and braces on purpose: v1 shipped this bug three times, as a crash on an empty expanded
queue and then as Next stranding on a fileless special.

**An episode's logo and tags belong to its series**, and a cross-library shuffle mixes dozens of
shows — so `AppState.seriesIdentities(in:)` collects the distinct `SeriesId`s and fetches them in
one batched `/Items?ids=` call (chunked at 100 to keep the query string sane), rather than a
detail fetch per episode. A series missing from the lookup degrades to no logo and no tags, never
to another show's.

**Multi-library scopes are fetched in parallel and re-shuffled across the merge**
(`PlayQueue.merge`): concatenating already-random lists would play all of library A and then all
of B. Ids are de-duplicated first — the same item reachable through two libraries would make the
player's own queue position lie. A library that is empty, slow, or erroring contributes nothing
instead of failing the press; v1 picked one library up front and, per its own commit message,
came back empty most of the time because of it.

**The two caps mean different things.** `PlayQueue.limit` (500, for a shuffle) is a *sample* — the
server randomises across everything first, so item 501 was never likelier to be missed than item
1. `PlayQueue.seriesLimit` (2,000, for an ordered series queue) is a *wall*: it truncates from the
far end, and episode 2,001 is simply unreachable. Hence the higher ceiling, which is nearly free
at these field weights — 226 episodes measured at 328 KB and ~150 ms, fast enough that the Show
screen waits for the full run rather than opening the player on a short queue and extending it
later.

**`NeonTransportBar`'s `Spacer` belongs inside its `Button`.** The bar reads as one 78pt-tall
control, but with the spacer as a sibling only the disc and its label caught a touch — roughly the
leading third — and SHUFFLE ALL did nothing at all if you pressed the part of the bar nearest the
readout. Verified with real HID taps before the fix: identical tap at x=300 fires, at x=531 does
not. Anything that looks like one wide bar has to *be* one wide target.

**`PlaybackRequest.id` is hashed, not joined.** SwiftUI reads it on every render pass that
touches the `.fullScreenCover`, and a 500-item queue would rebuild a 16 KB string each time to
answer a question only ever asked as an equality check. Still content-derived, so an unrelated
`AppState` publish can't retrigger the cover mid-film.

**The Random button reports itself** (`RandomPlayButton`, shared by both platforms at two sizes).
A press is a round trip over a whole library, and an unchanged button during that gap gets
pressed again — which would throw the first queue away and start a second — so the glyph becomes
a spinner and the second press is swallowed. A scope with nothing playable says **"Nothing to
play"** for a beat rather than doing nothing silently; the frame carries a `minWidth` sized for
the longest of the three labels so the row doesn't reflow. `Play`, beside it, is still the empty
`Button {}` it always was.

**`PlayableItem.subtitle` ("S2 · E4 — …") renders under the identity mark** (`PlayerIdentityMark`,
bottom-right), truncated from the tail so the season/episode numbers survive a long title. It
spent a while built-but-rendered-nowhere after the chrome's kicker line went with the full-size
transport circles — fine while every queue was one season of a show you had just navigated into,
and not fine once Random shuffles a whole series: the logo said *what* was playing and nothing
said *where in it*.

**On tvOS every reveal of the chrome lands focus on play/pause** (`PlayerChrome`'s
`.onChange(of: visible)`), and the failure overlay seeds its own Retry on appear. Before that, the
idle-hide → nudge cycle left focus on BACK — the geometrically-first control — so on a chrome whose
premise is "press without aiming", the stray Select after a reveal *exited playback*. Menu on tvOS
always leaves the player (the system dismisses the `.fullScreenCover` before SwiftUI sees it —
see `RootView`); that's platform behaviour, not something to fight.

## Three targets, one core

jellytv ships three targets off one shared SwiftUI core: `JellyTV` (tvOS),
`Remote` (iOS — both iPad and iPhone, since `TARGETED_DEVICE_FAMILY` widened
to `"1,2"`), and the platform-agnostic `JellyTVKit` package. New UI/UX work is
still designed and built **on iPad first**, exactly as this repo always has.
What changes: once that iPad work is finished — built, tested,
screenshot-verified per "Verification & workflow" below — it is not done
until tvOS and iPhone have each had a real pass too, made directly (no
dedicated subagent dispatch; a prior version of this workflow spawned
`tvos-expert`/`iphone-expert` agents for this and it didn't hold up in
practice — repeated context loss across long sessions, and reports that
didn't match what `git diff` actually showed. Do the adaptation yourself, in
the main conversation, the same way any other edit gets made).

**Neither platform gets a mechanical port of the iPad layout.** Exercise real
UX judgment for each, and be willing to *disagree* with the iPad approach when
that platform's own conventions call for something else — a left-hand nav
rail is right for an iPad's wide landscape canvas and wrong for a tvOS focus
grid or an iPhone held in one hand, and forcing the same layout onto all three
is itself the bug. If a platform's right answer is genuinely different from
what iPad does, say so to the user rather than silently forcing parity.

**Skip the tvOS/iPhone pass** for: `JellyTVKit` package-only changes with no
UI surface (already shared automatically), a fix the user explicitly scopes
to one platform ("just on iPad," "tvOS only"), and non-visual chores (docs,
build config, tests) with nothing to adapt.

**iPhone has real phone branches across most of the app now** (Home, the
library screens, Search, Settings, Setup, Show/Movie detail, the player
chrome all carry `DeviceClass.current == .phone` paths) — it is no longer
the "still just the iPad layout in a narrow column" state this note used to
describe, but it also isn't finished: assume any screen you haven't
personally verified on the iPhone simulator still needs a phone pass, not
that one now exists. `DeviceClass` (`Apps/Core/Sources/DesignSystem/Theme.swift`)
is the shared `.phone`/`.pad`/`.tv` idiom check for introducing iPhone
branches into shared `Core` code, the same way `#if os(iOS)`/`#if os(tvOS)`
already splits tvOS from iOS. `OrientationLock`
(`Apps/Remote/Sources/Chrome/OrientationLock.swift`) is the other piece worth
knowing before touching iPhone playback: it dynamically flips the phone
between portrait (browsing) and landscape (the player), and getting that
sequencing wrong is subtle — see `PlayerPresentationProbe`'s and
`OrientationLock.applyToCurrentScene`'s own doc comments for a real bug this
already caused (`requestGeometryUpdate` racing a `.fullScreenCover`'s own
presentation transition, silently rejected with no error handler, leaving
edge-anchored chrome off-frame while centred content looked fine — the kind
of thing that reads as "half the UI is missing" and is actually an
orientation-timing bug). Default iPhone simulator: **iPhone 17 Pro**, UDID
`FB41ABA0-B0DA-44F9-BDD1-377BA80E153C` — re-resolve by name if it's gone
stale, same as the iPad default below.

## Verification & workflow

- **New files need XcodeGen.** After adding a `.swift` file, run `xcodegen generate` (project.yml
  globs the source dirs) before building, or the build won't see it.
- **Build/test.** App via XcodeBuildMCP (`build_sim` / `build_run_sim`, scheme `JellyTV`); the
  package via `swift test` in `Packages/JellyTVKit` (XCTest — update the row-count assertions when
  adding e.g. a settings category).
- **Screenshot every visual change.** Launch with env hooks to land directly on a screen:
  `JT_SHOW_MOVIES=1`, `JT_SHOW_SETTINGS=1`, `JT_SHOW_SEARCH=1`, `JT_SHOW_DEMO=movie|show`,
  `JT_SHOW_VIDEOS=1|nsfw` / `RT_SHOW_VIDEOS=1|nsfw` (Home Videos / After Hours),
  and on `Remote` (iPad *and* iPhone — same hooks, same scheme, just a different simulator
  destination) the rest of the library screens — `RT_SHOW_MOVIES`, `RT_SHOW_TV`,
  `RT_SHOW_ANIME`, `RT_SHOW_LATE_NIGHT`, `RT_SHOW_SEARCH` (all `=1`),
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
  `magick screenshot.jpg -rotate -90 out.png` before inspecting it. Same fix applies to `Remote`'s
  iPad simulator: `simctl io screenshot` returns the device's native-orientation buffer regardless
  of how it's actually displayed, so a landscape-locked app comes back needing `-rotate 90`.
- **iPad simulator: `iPad Pro 11-inch (M5)`, not 13-inch.** Set as the `Remote` scheme's default
  (`.xcodebuildmcp/config.yaml`) after the 13-inch simulator's player chrome measured "too big" on
  a size the user doesn't actually use — the two Pro sizes render UI at the same point-scale, so a
  control sized for the 13-inch is oversized on every smaller iPad, not just this one. Boot with
  `xcrun simctl boot D63C44DF-5A7B-4369-AE5B-5BD2B2B11ECB` (iOS 26.5) if the UDID in
  `session_show_defaults` has gone stale (simulator UDIDs aren't stable across machines/Xcode
  updates — re-resolve by name via `xcrun simctl list devices available | grep "iPad Pro 11-inch"`).
- **iPhone simulator: `iPhone 17 Pro`** (same `Remote` scheme, a different destination). Boot with
  `xcrun simctl boot FB41ABA0-B0DA-44F9-BDD1-377BA80E153C` (iOS 26.2), re-resolving by name the
  same way if stale. Unlike the iPad, this one runs genuinely in portrait outside the player
  (`OrientationLock` — see "Three targets, one core" above) — a portrait screen's
  `simctl io screenshot` output is already right-side-up, no rotation needed. Once the player
  flips it to landscape, though, the buffer comes back the same way the iPad's always does — needs
  `-rotate -90` to view correctly; don't assume the earlier "no rotation needed" finding still
  holds once playback starts.
- **The simulator fights you when verifying the player.** Two failure modes that both look like
  app bugs and are not: the sim's display sleeps within seconds and **suspends the app**, so
  injected taps do nothing and timers don't fire (a screenshot loop keeps it awake — `sleep`
  doesn't); and `axe describe-ui` regularly returns a **stale hierarchy**, happily reporting the
  view *under* a presented cover. Neither is visible as an error. When behaviour is in question,
  read the app's own log rather than the AX tree:
  `xcrun simctl launch --console-pty <udid> <bundle>` captures stdout, and `JT_PLAYER_LOG=1` puts
  chrome visibility transitions, cover presentation, and the trickplay path on it. Hours went into
  chasing a "chrome never reappears" bug that was display sleep.
- **Capturing the app's stdout from a scripted pass.** `xcrun simctl launch --stdout=<file>
  --stderr=<file> <udid> <bundle>` returns immediately and streams the app's prints to the file —
  but only if the file lives somewhere the simulator's own launchd can write, e.g.
  `~/Library/Logs/CoreSimulator/<udid>/`; pointed at the scratchpad or `/tmp` it silently writes
  nothing. `--console-pty` blocks instead, and killing it kills the app. Swift's `print` is fully
  buffered when stdout is a file, so `PlayerDiagnostics.isEnabled` line-buffers it — before that a
  captured log came back empty even with tracing on. Run such scripts with **`/bin/zsh`**: the
  `zsh` on this machine's PATH (`/usr/local/bin/zsh`) is x86_64, and AXe launched from it fails
  with *SimulatorKit couldn't be loaded … doesn't contain a version for the current architecture*.
- Real HID injection for touch/swipe is AXe (bundled with XcodeBuildMCP):
  `~/.npm/_npx/*/node_modules/xcodebuildmcp/bundled/axe {tap,touch,swipe,key} … --udid <udid>`.
  `touch --down --up` is more reliable than `tap` for a control that may still be animating in.
  Coordinates are device points. For real playback without tap automation, `RT_AUTOPLAY=<substring>`
  resumes a Continue Watching entry at launch (any non-empty value falls back to the first one).
- SourceKit frequently shows stale `No such module 'JellyTVKit'` (or missing-member) errors in the
  editor after package edits; trust the actual `xcodebuild` / `swift test` result, not the inline
  diagnostics.
