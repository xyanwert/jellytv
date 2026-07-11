# tvos-hero-transitions

## ADDED Requirements

### Requirement: Metal crumble transition between backdrops
Advancing the hero SHALL transition the backdrop with a Metal per-tile "crumble" effect: the outgoing image partitions into tiles that drift apart, rotate, and fade while the incoming image assembles, implemented via a `[[stitchable]]` shader applied with SwiftUI's `.layerEffect` (no `MTKView`).

#### Scenario: Crumble renders on advance
- **WHEN** the transition style is Crumble and the hero advances (auto or manual)
- **THEN** the backdrop visibly crumbles from the old image to the new one over the transition, with tiles reaching the frame edges without clipping, and settles on the new backdrop with no visual artifact

#### Scenario: Shader is compiled and resolvable
- **WHEN** the app is built and run
- **THEN** the `.metal` shader compiles into the app's default metal library and `ShaderLibrary` resolves the crumble function at runtime (the transition actually renders, not just builds)

### Requirement: Fade fallback style
A plain fade SHALL be available as an alternative transition style.

#### Scenario: Fade crossfades the backdrop
- **WHEN** the transition style is Fade and the hero advances
- **THEN** the backdrop crossfades from the old image to the new one with no shader effect

### Requirement: Configurable, persisted transition style
The transition style SHALL be user-selectable between Crumble (default) and Fade, persisted across launches, and applied to subsequent hero advances.

#### Scenario: Changing the style takes effect
- **WHEN** the user selects a different transition style in Settings
- **THEN** the next hero advance uses the selected style and the choice survives relaunch

### Requirement: Clean resting state
At rest (no transition in progress) the backdrop SHALL show the current image with no shader artifacts from the transition.

#### Scenario: No artifact between transitions
- **WHEN** a transition completes and the hero is idle on a slide
- **THEN** the backdrop is the plain current image (the transition shader contributes nothing at rest)
