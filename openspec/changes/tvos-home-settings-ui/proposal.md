# Proposal: tvos-home-settings-ui

## Why

The tvOS app currently launches to a branded placeholder. We have a finished visual design for the Apple TV client ([Claude Design project](https://claude.ai/design/p/3ea3d153-f74d-4ca9-aef4-94f2f1b9a808), mirrored in `Design/jelly-tv-screens.dc.html`), and the first real screens to build are the **Home screen** and the **Settings menu**. Building them now — against typed content models with sample data — turns the shell into a navigable app and establishes the design system, focus-navigation patterns, and data seam that the eventual Jellyfin integration will plug into.

## What Changes

- **Home screen** replaces the placeholder root: top bar (logo + `jelly·tv` wordmark, centered nav pill `Home / Movies / Shows / Search`, clock, profile avatar), a horizontally-scrolling **library chips** row (with `18+` treatment for adult libraries), a **hero** block (eyebrow, title, rating/meta, synopsis, Resume/Details/＋ actions, animated pager dots), a **Continue Watching** row (progress bar + remaining-time pie), and a **Recommended for You** poster row — all navigable with the Apple TV remote via the tvOS focus engine.
- **Settings menu**: a right-aligned **account panel** presented over a dimmed, blurred Home — profile header (avatar, name, role), rows for **Profile**, **Settings**, **Theme**, **Server** (status), and **Sign Out**, opened from the top-bar avatar.
- **Design system**: shared palette (`#0B0D13` surfaces, tiered text), **Schibsted Grotesk** typography, a themeable **accent color** with the design's four options (coral/amber/blue/green) persisted across launches and applied live from the Theme row, and reusable focusable components (chip, media card, section header).
- **Sample content layer**: typed models in `JellyTVKit` (media item, library, hero feature, continue-watching item, user profile, server status, settings entry) plus a `SampleCatalog` reproducing the design's demo data, unit-tested — the seam a future Jellyfin API client will fill.
- The `JellyTV` tvOS target now launches to Home instead of the placeholder view.

**Out of scope (future changes):** connecting to a real Jellyfin server (all data is mock/sample); the Detail screen (`1b`); the Movies/Shows/Search destinations (nav tabs render but only Home is populated); the iOS companion app (unchanged).

## Capabilities

### New Capabilities

- `tvos-design-system`: Shared visual foundation — color palette, Schibsted Grotesk typography scale, persisted themeable accent color (4 options), and reusable focusable SwiftUI components used by both screens.
- `tvos-sample-content`: Typed content models and a `SampleCatalog` of demo data in `JellyTVKit`, giving the UI real types to bind to and a clean seam for future Jellyfin data.
- `tvos-home-screen`: The Home screen — top bar/nav, library chips, hero, Continue Watching, and Recommended rows, navigable with the tvOS focus engine and bound to the sample catalog.
- `tvos-settings-menu`: The account/settings panel overlay — profile header and Profile/Settings/Theme/Server/Sign Out rows over a dimmed Home, with the Theme row switching the accent live.

### Modified Capabilities

- `tvos-app-shell`: The "Buildable, launchable tvOS app" requirement changes — the app launches to the **Home screen** (not a branded placeholder).

## Impact

- **Code:** new SwiftUI under `Apps/JellyTV/Sources/` (Home, Settings, design-system components, theme store) and new model/catalog code + tests under `Packages/JellyTVKit/`. `RootView` rewritten. Possible bundled font (`Schibsted Grotesk`, SIL OFL) + `UIAppFonts` entry in `project.yml`; asset/color additions in `Assets.xcassets`.
- **Reference:** `Design/jelly-tv-screens.dc.html` (committed design reference).
- **No change** to identity/metadata, signing, icons, privacy manifest, the iOS target, or the release pipeline.
- **Constraints:** tvOS 17 focus-engine behavior (focusable, focus effects); custom-font bundling; all content is sample data until the Jellyfin integration lands.
