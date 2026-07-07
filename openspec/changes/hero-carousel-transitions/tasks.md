# Tasks: hero-carousel-transitions

## 1. Assets & content model

- [x] 1.1 Add imagesets to `Apps/JellyTV/Resources/Assets.xcassets`: `HeroBob` (from `/Users/xyan/jellytv_bob_main.jpg`) for hero slide 1, and `PreviewBob1/2/3` (from `jellytv_bob_episode01/2/3.jpg`) for the card pool — each a universal imageset (survives `generate-icons.swift`). Hero slide 0 reuses the existing `HeroBackdrop` (Cyberpunk) asset
- [x] 1.2 `JellyTVKit`: give `HeroFeature` a stable `id: String` and an `image: String` (asset name); keep existing fields
- [x] 1.3 `SampleCatalog`: add `heroes: [HeroFeature]` = 2 slides — slide 0 = `HeroBackdrop` (keep the existing "The Deep Signal" copy), slide 1 = `HeroBob` (Bob's Burgers copy); keep `hero` as `heroes[0]`. Mix `PreviewBob1/2/3` into the Continue Watching + Recommended image pool (cycle with the existing `Preview1/2/3`)
- [x] 1.4 Add `HeroTransitionStyle` (`crumble` default, `fade`) and `HeroRotation` (`s5`/`s15` default/`s30`, seconds) enums to `JellyTVKit` with labels; extend `SampleCatalogTests` for the new hero list + enums; `swift test` passes

## 2. Metal shader

- [x] 2.1 Add `Apps/JellyTV/Resources/HeroTransitions.metal` porting the `[[stitchable]] hexCrumble(position, layer, progress, invertDelay, canvasWidth)` shader (90pt tiles, hashed per-tile delay, left/right drift + rotation + alpha fade) from the reference `Core/Resources/HexCrumble.metal`
- [x] 2.2 `xcodegen generate` and build; confirm the `.metal` compiles into the target's default metal library (no build error, `default.metallib` present in the app bundle)

## 3. Transition bridge (SwiftUI)

- [x] 3.1 `DesignSystem/HeroTransitions.swift`: `AnyTransition.hexCrumble(canvasWidth:)` = asymmetric insertion/removal of `HexCrumbleModifier(progress:invertDelay:canvasWidth:)`; the modifier is `ViewModifier, Animatable` (`animatableData = progress`) applying `.layerEffect(ShaderLibrary.hexCrumble(...), maxSampleOffset: CGSize(600, 200))`
- [x] 3.2 Map `HeroTransitionStyle` → `AnyTransition`: `.crumble` → `.hexCrumble(canvasWidth:)`, `.fade` → `.opacity`

## 4. Pill timer

- [x] 4.1 `Home/HeroPillTimer.swift`: horizontal `HStack` of accent `Capsule`s, active pill wider (~96×14) with 1pt border, inactive short (14×14); fill mask is a leading `Color.clear` of `width = proxy.size.width * progress` over a `Color.white`
- [x] 4.2 Drive fill with `TimelineView(.animation(minimumInterval: 1/30))`: `progress = clamp((now − slideStartTime − 0.5) / (interval − 0.5), 0...1)` (0.5s hold-full lead-in); animate only the pill morph (`.animation(.smooth(0.65), value: index)`), never the mask; pills `.focusable(false)`; hide when ≤1 item

## 5. Hero carousel rework

- [x] 5.1 Rework `HeroView`: add `@State index`, `slideStartTime`, `rotateTask`; render backdrop `Image(current.image).id(current.id).transition(style.anyTransition(canvasWidth:))` inside a `GeometryReader`; wrap every index change in `withAnimation(.easeInOut(1.0))`; per-slide text (title/meta/synopsis) crossfades via `.transition(.opacity)`
- [x] 5.2 Auto-advance: `startRotation()` cancels the task, sets `slideStartTime = .now`, loops `sleep(interval) → withAnimation { index = (index+1) % n } → reset clock`; `.task(id: rotationInterval)` starts it, `.onDisappear` cancels; keep default focus on Resume
- [x] 5.3 Replace the static pager dots with `HeroPillTimer`; read `transitionStyle` + `rotationInterval` from the theme/prefs

## 6. Settings pickers

- [x] 6.1 Extend the theme/prefs store with persisted `transitionStyle` (`HeroTransitionStyle`) and `rotationInterval` (`HeroRotation`), published and injected
- [x] 6.2 Add two horizontal pill-row rows to `SettingsPanel` — **Transition** (Crumble / Fade) and **Rotation** (5s / 15s / 30s) — as segmented capsules with the active option highlighted; both apply live

## 7. Build, run, verify

- [x] 7.1 `xcodegen generate`; build the `JellyTV` scheme for a tvOS simulator; `swift test` passes; no warnings-as-errors
- [x] 7.2 Run on the simulator: confirm the hero auto-rotates, the horizontal pill fills over the interval and resets per slide, and the **crumble** transition actually renders between backdrops (capture a mid-transition frame); switch to Fade and confirm crossfade
- [x] 7.3 Verify Settings: changing Transition and Rotation applies live and persists across relaunch (e.g. via the defaults + relaunch check)
- [x] 7.4 Walk every scenario in `specs/**`; commit on the feature branch (assets + `.metal` handled per `.gitignore`); clean `git status` after build
