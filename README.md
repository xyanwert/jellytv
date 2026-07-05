# JellyTV

A native **tvOS** client for [Jellyfin](https://jellyfin.org) media servers, with an
**iOS/iPadOS companion app** that acts as a remote control. This repository currently
contains the App Store–ready *shell* of both apps — real Jellyfin functionality is
tracked as future work.

> JellyTV is an unofficial, independent client. "Jellyfin" is used descriptively only.

## Apps

| Target   | Platform        | Bundle ID              | Role                                   |
| -------- | --------------- | ---------------------- | -------------------------------------- |
| `JellyTV`| tvOS 17+        | `net.graficx.jellytv`  | The TV client                          |
| `Remote` | iOS/iPadOS 17+  | `net.graficx.jellytv`  | Companion remote (same ID → universal purchase) |

Both ship as a single App Store product via **universal purchase**.

## Getting started

The Xcode project is **generated** from [`project.yml`](project.yml) with
[XcodeGen](https://github.com/yonaskolb/XcodeGen); `JellyTV.xcodeproj` is not committed.

```sh
Scripts/bootstrap.sh        # installs tools, generates icons + the Xcode project
open JellyTV.xcodeproj       # then build/run the JellyTV or Remote scheme in Xcode
```

After editing `project.yml` or adding files, re-run `xcodegen generate` (or `Scripts/bootstrap.sh`).

## Repository layout

```
project.yml              XcodeGen project definition (source of truth)
Apps/JellyTV/            tvOS app target
Apps/Remote/             iOS/iPadOS companion target
Packages/JellyTVKit/     shared Swift package (models, API client — future)
Scripts/                 bootstrap.sh, generate-icons.swift
fastlane/                metadata + release lanes
docs/                    privacy policy (published via GitHub Pages)
```

## Release

See `fastlane/` for metadata and lanes. Full workflow documented at the end of implementation.

## License

MIT — see [LICENSE](LICENSE).
