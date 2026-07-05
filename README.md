# JellyTV

> **App Store name:** *Why.So.Jelly?* — the store listing and on-device name are
> "Why.So.Jelly?" (the plain "JellyTV" store name was already taken). "JellyTV" remains
> the internal/technical name of the repo, Xcode targets, and Swift package.

A native **tvOS** client for [Jellyfin](https://jellyfin.org) media servers, with an
**iOS/iPadOS companion app** that acts as a remote control. This repository currently
contains the App Store–ready *shell* of both apps — the branding, identity, and release
plumbing are complete; the actual Jellyfin browsing/playback features are future work.

> JellyTV is an unofficial, independent client and is not affiliated with or endorsed by
> the Jellyfin project. "Jellyfin" is used descriptively only.

## Apps

| Target   | Platform        | Bundle ID              | Role                                             |
| -------- | --------------- | ---------------------- | ------------------------------------------------ |
| `JellyTV`| tvOS 17+        | `net.graficx.jellytv`  | The TV client                                    |
| `Remote` | iOS/iPadOS 17+  | `net.graficx.jellytv`  | Companion remote (same ID → universal purchase)  |

Both platforms share one bundle identifier so the App Store treats them as a single
**universal purchase** product. Version and build numbers are defined once in
[`project.yml`](project.yml) so the two targets can never drift apart.

## Getting started

The Xcode project is **generated** from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen); `JellyTV.xcodeproj` is **not** committed
(it, and the per-target `Info.plist` files, are generated artifacts).

```sh
Scripts/bootstrap.sh        # verifies/installs tools, generates icons + the Xcode project
open JellyTV.xcodeproj       # then build/run the JellyTV or Remote scheme in Xcode
```

`bootstrap.sh` is safe to re-run. After editing `project.yml` or adding source files,
regenerate with:

```sh
xcodegen generate
```

Run the shared package's tests directly:

```sh
cd Packages/JellyTVKit && swift test
```

## Branding assets

All app icons and Top Shelf images are generated from code — no design tool required:

```sh
swift Scripts/generate-icons.swift
```

The generator is deterministic and idempotent. It produces the tvOS layered parallax
brand assets (App Store icon, home-screen icon, Top Shelf wide + standard) and the iOS
1024pt icon, plus the shared accent color, writing PNGs and asset-catalog JSON directly
into each target's `Assets.xcassets`. Swap the drawing routines for final artwork and
re-run — the catalog layout stays valid for App Review.

## Repository layout

```
project.yml              XcodeGen project definition (source of truth)
Apps/JellyTV/            tvOS app target (Sources, Resources/Assets.xcassets, PrivacyInfo)
Apps/Remote/             iOS/iPadOS companion target
Packages/JellyTVKit/     shared Swift package (Jellyfin client, models, remote proto — future)
Scripts/bootstrap.sh     one-command setup
Scripts/generate-icons.swift   branding asset generator
fastlane/                release lanes + App Store metadata
docs/privacy/            privacy policy (published via GitHub Pages)
```

## Release

Release automation lives in [`fastlane/`](fastlane/). Credentials come from an App Store
Connect **API key** loaded via `fastlane/.env` (copy `fastlane/.env.example`); the key
file and `.env` are never committed.

| Lane | What it does |
| ---- | ------------ |
| `fastlane bump`          | Increment the shared build number in `project.yml`, regenerate the project |
| `fastlane build_tvos`    | Archive + export the tvOS app (App Store) |
| `fastlane build_ios`     | Archive + export the iOS companion (App Store) |
| `fastlane beta`          | Build both targets and upload to TestFlight |
| `fastlane metadata`      | Upload App Store metadata + screenshots (no binary) |
| `fastlane release_check` | Validate metadata + screenshots without uploading |

App Store metadata is versioned under `fastlane/metadata/`; placeholder screenshots for
Apple TV, iPhone (6.9"), and iPad (13") are under `fastlane/screenshots/`.

**First-time App Store Connect setup**

1. Create an App Store Connect API key (App Manager role), download the `.p8`, and fill in
   `fastlane/.env`.
2. Register the bundle ID and create the app record for **both** platforms:
   `fastlane produce -a net.graficx.jellytv --tvos --ios` (or create it manually in App
   Store Connect and add both platforms to one record).
3. `fastlane release_check` to validate metadata, then `fastlane beta` to upload builds.

> **Note on public release:** App Review guideline 4.2 (minimum functionality) means the
> current empty shell is suitable for **TestFlight** but would be rejected from public sale.
> Public App Store submission is expected once the first real feature ships.

## License

MIT — see [LICENSE](LICENSE).
