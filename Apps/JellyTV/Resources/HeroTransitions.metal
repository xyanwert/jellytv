//
//  HeroTransitions.metal
//
//  Hero slide-to-slide transition shaders, applied via SwiftUI's native
//  `.layerEffect(ShaderLibrary.…)` API (tvOS 17+). Originally ported from the
//  reference jelly-tv-ios app, then re-choreographed: honeycomb cells, a
//  diagonal shatter wave, accent-lit cracks, an anticipation pop, arced
//  tumbling flight with gravity, and an ease-out-back landing for the
//  incoming slide.
//
//    - hexCrumble → HeroTransitionStyle.crumble
//
//  (The .fade style uses SwiftUI's .opacity — no shader.)
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace {
    /// Stable 2D hash, bucketed by hex-cell id so per-cell values hold
    /// steady across frames.
    float hash21(float2 p) {
        p = fract(p * float2(234.34, 435.345));
        p += dot(p, p + 34.23);
        return fract(p.x * p.y);
    }

    /// True (non-negative) modulo.
    float2 gmod(float2 p, float2 m) { return p - m * floor(p / m); }

    /// Field for a pointy-top hexagon in grid space; the cell border sits
    /// at 0.5.
    float hexDist(float2 p) {
        p = abs(p);
        return max(dot(p, float2(0.5, 0.8660254)), p.x);
    }

    /// Decelerating landing with a small overshoot — the "settle".
    float easeOutBack(float t) {
        const float c1 = 1.70158, c3 = c1 + 1.0;
        float u = t - 1.0;
        return 1.0 + c3 * u * u * u + c1 * u * u;
    }
}

/// Honeycomb shatter. A diagonal wave sweeps the canvas; as it reaches each
/// hex cell the cell's borders flash in the accent color (crack ignition),
/// the tile pops slightly (anticipation), then tears off — accelerating along
/// the wave direction with per-cell spread, tumbling, sagging under gravity,
/// and fading only after the flight is well underway (follow-through). The
/// incoming slide runs the same flight in reverse just behind the wave and
/// settles with an ease-out-back overshoot.
///
///   progress: 1 = seated/intact, 0 = fully scattered (Animatable-driven)
///   assemble: 1 = incoming slide (lands), 0 = outgoing (breaks away)
///   size:     canvas size in pt (wave normalization)
///   accent:   crack-glow tint (theme accent)
[[ stitchable ]]
half4 hexCrumble(float2 position,
                 SwiftUI::Layer layer,
                 float progress,
                 float assemble,
                 float2 size,
                 half4 accent) {
    bool landing = assemble > 0.5;
    // Shared transition clock: 0 → 1 in wall time for both directions.
    float tau = landing ? progress : (1.0 - progress);

    // Resting states contribute nothing (clean idle frame, zero cost).
    if (!landing && tau <= 0.001) { return layer.sample(position); }
    if (landing && tau >= 0.999) { return layer.sample(position); }

    // ---- honeycomb partition ----
    const float cellW = 98.0;
    float2 uv = position / cellW;
    const float2 r = float2(1.0, 1.7320508);
    const float2 h = r * 0.5;
    float2 a = gmod(uv, r) - h;
    float2 b = gmod(uv - h, r) - h;
    float2 gv = (dot(a, a) < dot(b, b)) ? a : b;
    float2 id = uv - gv;
    float2 center = id * cellW;

    float rnd  = hash21(id);
    float rnd2 = hash21(id + 17.17);

    // ---- shatter wave: diagonal sweep with per-cell jitter ----
    const float2 dir = float2(0.9438, 0.3303);   // normalize(1, 0.35)
    float ph = saturate(dot(center, dir) / dot(size, dir));
    ph = saturate(ph + (rnd - 0.5) * 0.10);

    // Outgoing tiles break just ahead of the incoming ones landing, so each
    // cell reads as a hand-off rather than a crossfade.
    float life  = landing ? 0.45 : 0.50;
    float start = landing
        ? mix(0.14, 1.0 - life - 0.01, ph)
        : mix(0.02, 1.0 - life - 0.02, ph);
    float t = saturate((tau - start) / life);

    // Dissolve amount u: 0 = seated, 1 = flown. The landing runs the flight
    // in reverse; easeOutBack dips u slightly below 0 for a settle-bounce.
    float u = landing ? (1.0 - easeOutBack(t)) : t;
    if (abs(u) < 0.0005) { return layer.sample(position); }

    // ---- flight ----
    float su = u * abs(u);                        // signed, ease-in square
    float2 perp = float2(-dir.y, dir.x);
    float2 fdir = normalize(dir + perp * (rnd2 - 0.5) * 1.3);
    float2 disp = fdir * su * (240.0 + 200.0 * rnd);
    disp.y += 250.0 * u * u - 70.0 * u;           // slight lift, then gravity sag

    float rot = (rnd - 0.5) * 3.6 * su;
    float pop = smoothstep(0.0, 0.10, u) * (1.0 - smoothstep(0.10, 0.30, u));
    float scale = 1.0 - 0.55 * saturate(u) + 0.05 * pop;

    // Fade starts only after the flight is underway and completes before the
    // motion does — overlapping action, not a synchronized on/off.
    float alpha = 1.0 - smoothstep(0.50, 0.92, u);
    // Crack ignition window: borders glow as the tile tears off (or seals
    // back in, on the landing side).
    float glow = smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.32, 0.60, u));

    // ---- inverse-transform sampling, masked to the tile's own hex ----
    float ca = cos(-rot), sa = sin(-rot);
    float2 q = position - center - disp;
    q = float2(ca * q.x - sa * q.y, sa * q.x + ca * q.y) / max(scale, 0.05);
    float2 src = center + q;

    float mask = 1.0 - smoothstep(0.5 - 1.8 / cellW, 0.5, hexDist(q / cellW));
    // Blend the mask in with motion so the idle image shows no hex seams.
    mask = mix(1.0, mask, saturate(abs(u) * 10.0));

    half4 color = layer.sample(src);
    color *= half(alpha * mask);

    // Accent-lit cracks along the cell borders + a faint ember wash and a
    // brightness pop while the tile lifts. Loud on purpose — it has to read
    // from across a room.
    float line = smoothstep(0.5 - 0.14, 0.5 - 0.02, hexDist(gv));
    color.rgb += accent.rgb * half(glow * (1.8 * line + 0.22)) * color.a;
    color.rgb *= half(1.0 + 0.22 * pop);
    return color;
}
