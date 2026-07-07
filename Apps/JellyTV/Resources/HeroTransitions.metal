//
//  HeroTransitions.metal
//
//  Hero slide-to-slide transition shaders, applied via SwiftUI's native
//  `.layerEffect(ShaderLibrary.…)` API (tvOS 17+). Ported from the reference
//  jelly-tv-ios app (Core/Resources/HexCrumble.metal).
//
//    - hexCrumble → HeroTransitionStyle.crumble (per-tile drift-apart)
//
//  (The .fade style uses SwiftUI's .opacity — no shader.)
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace {
    /// 2D hash — bucket by integer tile position so the per-tile delay is
    /// stable across frames.
    float hash21(float2 p) {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
    }
}

/// Per-tile crumble. The image is partitioned into 90pt square tiles; each
/// tile gets a hashed delay so the crumble cascades across the canvas rather
/// than firing all at once. Tiles on the left drift left, tiles on the right
/// drift right, with a small rotation + vertical jitter for organic variance,
/// fading out as they scatter. Applied to BOTH images (outgoing disassembles
/// while incoming assembles via `invertDelay`), so the two are co-present
/// through the transition.
[[ stitchable ]]
half4 hexCrumble(float2 position,
                 SwiftUI::Layer layer,
                 float progress,
                 float invertDelay,
                 float canvasWidth) {
    const float tileSize = 90.0;
    float2 tileIdx = floor(position / tileSize);
    float2 tileCenter = (tileIdx + 0.5) * tileSize;
    float hDelay = hash21(tileIdx);
    float hRot   = hash21(tileIdx + float2(43.0, 91.0));

    float baseDelay = hDelay * 0.65;
    float delay = (invertDelay > 0.5) ? (0.65 - baseDelay) : baseDelay;
    const float fadeWindow = 0.35;
    float t = clamp((progress - delay) / fadeWindow, 0.0, 1.0);
    float scatter = 1.0 - t;

    float side = (tileCenter.x < canvasWidth * 0.5) ? -1.0 : 1.0;
    float vertJitter = (hRot - 0.5) * 0.25;
    float2 dir = normalize(float2(side, vertJitter));
    // Drift kept modest so the sampled area (and thus the GPU-processed
    // backing texture set by maxSampleOffset) stays small.
    const float driftDistance = 320.0;
    float2 offset = dir * scatter * driftDistance;

    float rotAngle = (hRot - 0.5) * 1.2 * scatter;
    float c = cos(-rotAngle);
    float s = sin(-rotAngle);
    float2 localPos = position - tileCenter;
    float2 rotated = float2(c * localPos.x - s * localPos.y,
                            s * localPos.x + c * localPos.y);
    float2 samplePos = tileCenter + rotated - offset;
    half4 color = layer.sample(samplePos);
    color.a *= half(t * t);
    return color;
}
