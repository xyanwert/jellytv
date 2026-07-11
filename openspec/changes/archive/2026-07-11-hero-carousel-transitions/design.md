# Design: hero-carousel-transitions

## Context

We're porting two mechanisms from the reference v1 app (`/Users/xyan/code/jelly-tv-ios`) into v2's tvOS `HeroView`: a horizontal **pill timer** and a **Metal-shader backdrop transition**. Both are self-contained and use only modern SwiftUI (tvOS 17): `TimelineView(.animation)`, `AnyTransition` + `Animatable` `ViewModifier`, and the native `.layerEffect(ShaderLibrary.…)` shader API backed by a `[[stitchable]]` `.metal` file — no `MTKView`/`CAMetalLayer`. Current v2 hero is a single `SampleCatalog.hero` with static pager dots; we replace it with a carousel over the Bob's Burgers images. Decisions already made with the user: **crumble + fade only**, **Settings pickers included now**, **scaffold as an OpenSpec change**.

## Goals / Non-Goals

**Goals:** faithful pill-timer behavior (fill + auto-advance + reset semantics); a genuine Metal crumble transition between backdrops that reads well at 10ft; a fade fallback; persisted Transition + Rotation settings; all driven by sample data.

**Non-Goals:** ripple/fan styles; screensaver dissolve; real Jellyfin data; per-slide network image loading (assets are bundled); iOS companion changes.

## Decisions

### D1 — Shader integration via SwiftUI's native API (no MTKView)
Port the reference's `hexCrumble` `[[stitchable]]` function into `Apps/JellyTV/Resources/HeroTransitions.metal` (`#include <SwiftUI/SwiftUI_Metal.h>`). XcodeGen already includes the sources dir, so Xcode compiles the `.metal` into the app's default `metallib`; SwiftUI resolves `ShaderLibrary.hexCrumble` at runtime. This is the same mechanism v1 uses and needs no Metal boilerplate. *Alternative rejected:* raw Metal/MTKView — vastly more code for no benefit here.

### D2 — Transition as an `AnyTransition` + `Animatable` modifier
Port the bridge verbatim in shape: `AnyTransition.hexCrumble(canvasWidth:)` returns `.asymmetric(insertion, removal)` where each side is `.modifier(active: HexCrumbleModifier(progress: 0, invertDelay:…), identity: HexCrumbleModifier(progress: 1, …))`. `HexCrumbleModifier: ViewModifier, Animatable` exposes `animatableData = progress` and applies `.layerEffect(ShaderLibrary.hexCrumble(.float(progress), .float(invertDelay ? 1 : 0), .float(canvasWidth)), maxSampleOffset: CGSize(600, 200))`. The asymmetric `invertDelay` makes outgoing + incoming co-present (complementary tile schedules). `maxSampleOffset` **must** cover the shader's max tile drift (~440px) or tiles clip — use 600×200. Fade is just `.opacity`.

### D3 — Trigger: `.id` + `.transition` + `withAnimation`
The backdrop `Image` is keyed `.id(currentHero.id)` and carries `.transition(style.anyTransition(canvasWidth:))`. Every `index` mutation happens inside `withAnimation(.easeInOut(duration: 1.0))`, so SwiftUI's insertion/removal system runs the shader transition over 1.0s. The per-slide hero **text** (title/meta/synopsis) crossfades separately via `.transition(.opacity)` keyed on the item id, so text doesn't crumble with the image. *Note:* GeometryReader supplies canvas width/height to the shader (needs the center).

### D4 — Horizontal pill timer
New `HeroPillTimer`: an `HStack` of `Capsule().fill(theme.accent)`; the active pill grows **wider** (e.g. inactive 14×14, active ~96×14) with a 1pt accent border. Fill mask flips the reference's vertical geometry to horizontal — an `HStack { Color.clear.frame(width: size.width * progress); Color.white }` so the accent drains/ fills left→right. Driven by `TimelineView(.animation(minimumInterval: 1/30))`: `progress = clamp((now − slideStartTime − 0.5) / (interval − 0.5), 0…1)` with the 0.5s "hold full" lead-in. Only the pill **morph** animates (`.animation(.smooth(0.65), value: index)`); the mask is recomputed per frame, never tweened. Pills are `.focusable(false)` status read-outs (match v1); rotation is auto on tvOS. Placed at the hero's bottom-left where the pager dots are today.

### D5 — Advance loop and clock
State on `HeroView`: `index: Int`, `slideStartTime: Date`, `rotateTask: Task<Void,Never>?`. `startRotation()` cancels any in-flight task, sets `slideStartTime = .now`, then loops: `try? await Task.sleep(for: .seconds(interval)); withAnimation(.easeInOut(1.0)) { index = (index+1) % heroes.count }; slideStartTime = .now`. Restarted via `.task(id: rotationInterval)` and cancelled `.onDisappear`. Any manual jump mutates `index` in `withAnimation` then calls `startRotation()` (cancel prevents a stale sleep double-advancing). No pause — matches v1. *Consideration:* we may pause while the Settings overlay is open (nice-to-have, deferred).

### D6 — Settings pickers (persisted)
Extend `Theme` (or a small `HeroPrefs`) with `transitionStyle: HeroTransitionStyle` (`.crumble`/`.fade`, default `.crumble`) and `rotationInterval: HeroRotation` (`.s5`/`.s15`/`.s30` = 5/15/30, default 15), persisted in `UserDefaults` and published. Add two horizontal **pill-row** rows to the Settings panel (a segmented capsule of options, active highlighted) — mirroring v1's settings pattern and the app's existing pill vocabulary. Both apply live.

### D7 — Content model
`HeroFeature` gains `id: String` + `image: String` (asset name). The **hero carousel is 2 slides** so the crumble transition has two distinct backdrops to cut between: slide 0 reuses the existing `HeroBackdrop` (the Cyberpunk "Lucy" still already in the catalog, keeping "The Deep Signal" sci-fi copy); slide 1 is `HeroBob` (`bob_main`, the bright Bob's Burgers splash) with its own copy. `SampleCatalog.heroes: [HeroFeature]` holds both; `SampleCatalog.hero` stays as `heroes[0]` for back-compat.

The **three Bob episode stills** (`jellytv_bob_episode01/2/3`, 480×270) are episode previews — added as `PreviewBob1/2/3` imagesets and mixed into the **Continue Watching and Recommended** preview pool alongside the existing `Preview1/2/3` (Cyberpunk stills), cycled across those cards. All new images are imagesets (survive `generate-icons.swift`, which only touches the icon/accent assets); `bob_main` is full-res, the episode stills upscale acceptably on the small cards.

## Risks / Trade-offs

- [`maxSampleOffset` too small → tiles clip at frame edges] → use 600×200 per the reference's tuning; verify the crumble reaches frame edges cleanly on-device.
- [`.metal` not compiled into the target] → confirm XcodeGen includes it and the build produces `default.metallib`; a missing shader surfaces as a runtime "unknown shader" — verify the transition actually renders, not just that it builds.
- [Stale animation clock on rapid advance] → cancel+restart the task on every manual change; key the pill `TimelineView` off `slideStartTime` so it can't capture a stale start.
- [Text crumbling with the image] → text is a separate layer with its own `.opacity` transition, not inside the shader-affected backdrop.
- [Low-res episode stills look soft full-bleed] → acceptable for sample content; `bob_main` carries the hero; real artwork replaces these later.
- [Shader cost at 4K/60] → crumble is a single `layer.sample` per pixel; fine on Apple TV 4K. Keep the transition to ~1.0s.

## Migration Plan

Additive to the tvOS target. `HeroView` gains carousel state; the single-hero code path becomes `heroes[0]`. Rollback = revert `HeroView` to the single-hero render and drop the `.metal`/transition files. No data or release-pipeline impact. Depends on the `tvos-home-settings-ui` change already on the branch.

## Open Questions

- Pause rotation while the Settings overlay is open? (Default: no, match v1.)
- Should the pills become focusable on tvOS so the remote can jump slides? (Default: no — read-out only, matching v1.)
- Final hero sample copy (Bob-themed vs the existing sci-fi placeholders).
