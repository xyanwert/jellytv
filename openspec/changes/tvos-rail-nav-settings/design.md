## Context

Home and Settings currently live in two disconnected shapes: `HomeView` owns a full-width `TopBar` (logo + wordmark + center nav pill + clock + avatar), and `SettingsPanel` is a 620px overlay triggered by tapping the avatar, dimming/blurring Home behind it. The new design mockup (`3a`/`3b`/`3c`) unifies both screens around a single persistent 118px left rail that's present regardless of which screen is showing, with Settings promoted to a full peer screen (not a modal) and a new Libraries slide-out submenu. This touches the app shell's top-level composition (`RootView`), not just leaf views.

`ServerStatus.isConnected` (from `tvos-home-settings-ui`) already models the connectivity signal the new status dot needs — no new model required there.

## Goals / Non-Goals

**Goals:**
- Replace the top pill nav + avatar-triggered overlay with the rail/submenu/full-screen-Settings shapes from the mockup, pixel-matching colors/dimensions/typography where the mockup specifies them.
- Keep `HeroView`, `HeroPillTimer`, the hex-crumble/fade transition, `ContinueWatchingRow`, and `RecommendedRow` untouched — this change only touches navigation chrome and Settings.
- Give every rail-reachable destination a defined behavior (Home, Libraries, Settings functional; Search/Movies/TV Shows keep the existing non-blocking placeholder behavior already specced for secondary nav).

**Non-Goals:**
- No real Jellyfin connectivity, playback, subtitle, audio, or parental-control backend — Settings detail content beyond Playback stays sample/demo data, same as the rest of the app today.
- No change to how the accent theme or hero transition/rotation preferences persist (`@AppStorage`) — only where their pickers are surfaced in the UI.
- Not implementing Search/Movies/TV Shows screens — they keep the placeholder from `tvos-home-screen`'s existing "Secondary nav destinations are non-blocking" requirement.

## Decisions

**Rail is a single shared component, not duplicated per screen.** A `NavRail` view (new, under `Apps/JellyTV/Sources/Nav/`) renders the app-mark+status-dot tile, the 5 nav icons, and the pinned settings icon, parameterized by which destination is active and the server-connected flag. Both `HomeView` and the new `SettingsView` are laid out as `HStack { NavRail(...); <content> }` from a shared root composition — avoids drifting two copies of the same 118px rail styling.

**Root shell owns navigation state, not a modal presentation.** `RootView` holds a `NavDestination` enum (`.home`, `.settings`, plus the placeholder cases already used for Movies/Shows/Search) and swaps main content directly, instead of Settings being a `fullScreenCover`/overlay over Home. This matches the mockup, where Settings is a full peer screen with its own rail — not a dimmed sheet. `isLibrariesOpen: Bool` is separate root-level state: the submenu only ever layers over Home (mockup screen `3b`), so it's ignored/reset when navigating to Settings.

**Libraries is a submenu, not a route.** Selecting the rail's Libraries icon does not navigate away from Home; it opens the 392px slide-out panel over a dimmed (50%-opacity) Home, matching `3b`. Back/Menu (or re-selecting the rail's Home icon) closes it. This reuses the "panel over dimmed content, dismiss with Menu/Back" interaction already validated for the old `SettingsPanel` (see `tvos-settings-menu`'s existing "Account panel over dimmed Home" requirement) rather than inventing a new dismissal pattern.

**Status dot has two explicit visual states**, both using the same 13×13-circle/2px-white-border geometry the mockup specifies for "live": *connected* = `#58D399` fill, glow shadow, `statusPulse` animation; *disconnected* = a desaturated gray fill (`rgba(255,255,255,0.35)`), no shadow, no animation. The mockup only shows the connected state; the disconnected treatment is a deliberate, minimal extrapolation (same shape, drop the glow/motion) rather than inventing new iconography.

**Settings category → content mapping** (the mockup only fully specifies the `Playback` detail pane; the other 6 categories in `settingsCats` — Subtitles, Audio, Parental, Server, Account, About — need a content decision since there's no source design for them):
| Category | Detail content |
|---|---|
| Playback | New: streaming-quality segmented control (Auto/1080p/4K), playback-method segmented control (Direct Play/Transcode), 3 toggle rows (Auto-play next episode, Skip intros, HDR passthrough) — session-local `@State`, not persisted (no real playback backend yet, consistent with the rest of the app's sample data) |
| Server | Existing Server row content relocated (name, version, connected status) |
| Account | Existing Profile content (avatar, name, email·role, Sign Out) **plus** the existing Theme accent picker and the hero Transition/Rotation pickers relocated here — the mockup's category list has no dedicated "Appearance" category, and Account (a personal-preferences category) is the closest fit for preferences that were previously exposed in the old Settings panel. Flagged in Open Questions since this is a judgment call. |
| Subtitles, Audio, Parental, About | Lightweight "Coming soon" placeholder detail pane — same non-blocking pattern already specced for Movies/Shows/Search, since neither the app nor the mockup has real content for these yet |

**`Library` gains `itemCount: String`** (not `Int`) because the mockup's counts are already display-formatted (`"1.2k"`, `"428"`) — matching that shape avoids a formatter no other model in the catalog needs.

**`SettingsEntry` (4-case `Kind`: profile/settings/theme/server) is replaced by `SettingsCategory`** (7 cases matching the mockup's category list) rather than extended, since the old model's shape (icon + label + description + trailing value + chevron, used for the old panel's flat row list) doesn't fit the new category-list-only-shows-label+description shape. `SettingsEntry`'s old call sites (the removed `SettingsPanel`/`SettingsRow`) are deleted, not migrated.

## Risks / Trade-offs

- [Rail present on every screen is a bigger structural change than a leaf-component swap — touches `RootView`, `HomeView`, and Settings simultaneously] → Build and verify incrementally: rail + Home first (tasks section 2-3), Settings second (section 4), wiring last (section 5), with a build/test checkpoint after each.
- [Account category becomes a grab-bag: Profile + Sign Out + Theme + Transition + Rotation] → Acceptable for a sample-data-driven app; revisit if/when a real Appearance category is designed. Called out explicitly so it's easy to move later.
- [Libraries submenu dismiss-on-Back could conflict with tvOS's default Menu-button-exits-app behavior at the root] → Same risk already exists and was already solved for the old Settings panel; reuse that solution rather than re-deriving it.

## Open Questions

- Confirm the Account-category placement of Theme/Transition/Rotation pickers (vs. e.g. leaving them under a renamed "About" or splitting them out) — proceeding with Account as the default per the table above; easy to move in a follow-up if wrong.
- Confirm Subtitles/Audio/Parental/About should be inert placeholders for now (vs. inventing plausible sample content) — proceeding with placeholders since the mockup doesn't specify them and no real backend exists yet.
