# Proposal: hero-carousel-transitions

## Why

The tvOS Home hero is currently a single static featured item with decorative (non-functional) pager dots. The reference v1 app (`/Users/xyan/code/jelly-tv-ios`) turns the hero into a living, auto-rotating carousel with a **horizontal pill timer** and a **Metal-shader backdrop transition** between slides. We want v2 to mimic that behavior (improved), using the provided Bob's Burgers images as the demo rotation — a real carousel with a genuine "cool animation" between backdrops.

## What Changes

- **Hero becomes an auto-rotating carousel** over multiple featured items (seeded with the Bob's Burgers images — `bob_main` plus three episode stills).
- **Horizontal pill timer** replaces the static pager dots: a row of accent capsules where the active pill grows wider and fills left→right as a visible countdown to the next auto-advance, driven by a `TimelineView(.animation)` wall-clock (with a ~0.5s "hold full" lead-in), matching the reference's timing math (flipped from its vertical geometry to horizontal).
- **Metal backdrop transition** between slides: a per-tile **crumble** shader (image partitions into 90pt tiles that drift apart, rotate, and fade — outgoing disassembles as incoming assembles) plus a plain **fade** fallback. Implemented with SwiftUI's native shader API (`.layerEffect(ShaderLibrary.…)`) via a `[[stitchable]]` `.metal` file and `AnyTransition` + `Animatable` `ViewModifier` bridge — no `MTKView`.
- **Settings pills** (horizontal pill-rows, matching the app's style): a **Transition** picker (Crumble / Fade, default Crumble) and a **Rotation** interval picker (5s / 15s / 30s, default 15s), both persisted.
- **Data/assets**: add the hero images; extend `HeroFeature` with an image field and give `SampleCatalog` a `heroes: [HeroFeature]` rotation.

**Out of scope:** the ripple and fan shader styles (crumble + fade only for now); the screensaver `particleDissolve`; any real Jellyfin data (still sample content); the iOS companion.

## Capabilities

### New Capabilities

- `tvos-hero-carousel`: The Home hero as a multi-item, auto-rotating carousel with a horizontal pill timer, auto-advance loop, clock reset on manual/auto change, and a persisted rotation-interval setting.
- `tvos-hero-transitions`: The Metal-shader backdrop transition system — a `[[stitchable]]` crumble shader, the `AnyTransition`/`Animatable` bridge that drives it, a plain-fade fallback, and a persisted transition-style setting.

### Modified Capabilities

_None in the baseline._ This builds directly on the Home hero and Settings panel introduced by the in-flight `tvos-home-settings-ui` change (not yet archived, so its specs aren't in `openspec/specs/` yet). The hero rework supersedes that change's single-item hero + static pager dots; when both archive, the carousel behavior is the authoritative hero spec.

## Impact

- **Code (tvOS target only):** new `Apps/JellyTV/Resources/HeroTransitions.metal`; new `DesignSystem/HeroTransitions.swift` (styles + `AnyTransition` bridge) and `Home/HeroPillTimer.swift`; `HeroView` reworked into a carousel; `SettingsPanel`/`Theme` gain transition + rotation pickers; `JellyTVKit` `HeroFeature`/`SampleCatalog` extended.
- **Assets:** `bob_main` + 3 episode imagesets in `Assets.xcassets` (survive icon regeneration, like `HeroBackdrop`).
- **Build:** the `.metal` is compiled into the app's default metal library automatically (XcodeGen sweeps the sources dir; Xcode compiles `[[stitchable]]` shaders — SwiftUI 17+ / tvOS 17).
- **Reference:** ported near-verbatim from `/Users/xyan/code/jelly-tv-ios` (`Core/Resources/HexCrumble.metal`, `Core/Components/HomeHero.swift`, `Core/Components/WaterDropRippleTransition.swift`, `Core/State/PlayerStore.swift`).
- **Gotchas carried over:** `maxSampleOffset` must cover the crumble's ~440px tile drift (use ~600×200); `.id()` freshness on the animation clock; the 0.5s fill lead-in; cancel+restart the advance task on manual jump.
