//
//  HeroTransitions.metal
//
//  Hero slide-to-slide transition shader, applied via SwiftUI's native
//  `.layerEffect(ShaderLibrary.…)` API (tvOS 17+).
//
//    - hexCrumble → HeroTransitionStyle.crumble
//
//  Used as a *reveal*: the incoming slide sits underneath as a solid base and
//  only the OUTGOING slide runs this shader on top, shattering away to expose
//  the new image — so no black ever shows between cells. (The .fade style uses
//  SwiftUI's .opacity — no shader.)
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
}

/// Honeycomb shatter (scatter-away). A diagonal wave sweeps the canvas; as it
/// reaches each hex cell the cell's borders ignite in the accent color, the
/// tile pops (anticipation), then tears off — accelerating along the wave with
/// per-cell spread, tumbling, sagging under gravity, and fading only once the
/// flight is underway (follow-through). Because this runs on the outgoing
/// image over an opaque incoming base, each departing tile reveals the new
/// slide beneath it.
///
///   progress: 1 = intact, 0 = fully scattered (Animatable-driven, 1 → 0)
///   size:     canvas size in pt (wave normalization)
///   accent:   crack-glow tint (theme accent)
[[ stitchable ]]
half4 hexCrumble(float2 position,
                 SwiftUI::Layer layer,
                 float progress,
                 float2 size,
                 half4 accent) {
    float u = 1.0 - progress;                       // 0 = intact, 1 = scattered
    if (u <= 0.001) { return layer.sample(position); }   // clean idle, zero cost

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
    const float2 dir = float2(0.9438, 0.3303);      // normalize(1, 0.35)
    float ph = saturate(dot(center, dir) / dot(size, dir));
    ph = saturate(ph + (rnd - 0.5) * 0.10);

    const float life = 0.58;                        // fraction of u each cell takes
    float start = ph * (1.0 - life);
    float t = saturate((u - start) / life);         // this cell's local 0 → 1
    if (t <= 0.0001) { return layer.sample(position); }  // wave not here yet → intact

    // ---- flight ----
    float su = t * t;                               // ease-in
    float2 perp = float2(-dir.y, dir.x);
    float2 fdir = normalize(dir + perp * (rnd2 - 0.5) * 1.3);
    float2 disp = fdir * su * (240.0 + 220.0 * rnd);
    disp.y += 260.0 * t * t - 70.0 * t;             // slight lift, then gravity sag

    float rot = (rnd - 0.5) * 3.6 * su;
    float pop = smoothstep(0.0, 0.10, t) * (1.0 - smoothstep(0.10, 0.30, t));
    float scale = 1.0 - 0.5 * t + 0.05 * pop;

    // Fade trails the motion — overlapping action, not a synchronized on/off.
    float alpha = 1.0 - smoothstep(0.50, 0.92, t);
    // Crack ignition window: borders glow as the tile tears off.
    float glow = smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.30, 0.58, t));

    // ---- inverse-transform sampling, masked to the tile's own hex ----
    float ca = cos(-rot), sa = sin(-rot);
    float2 q = position - center - disp;
    q = float2(ca * q.x - sa * q.y, sa * q.x + ca * q.y) / max(scale, 0.05);
    float2 src = center + q;

    float mask = 1.0 - smoothstep(0.5 - 1.8 / cellW, 0.5, hexDist(q / cellW));
    // Blend the hex mask in with motion so the intact image shows no seams.
    mask = mix(1.0, mask, saturate(t * 10.0));

    half4 color = layer.sample(src);
    color *= half(alpha * mask);

    // Accent-lit cracks along the cell borders + an ember wash and a brightness
    // pop while the tile lifts. Loud on purpose — has to read across a room.
    float line = smoothstep(0.5 - 0.14, 0.5 - 0.02, hexDist(gv));
    color.rgb += accent.rgb * half(glow * (1.8 * line + 0.22)) * color.a;
    color.rgb *= half(1.0 + 0.22 * pop);
    return color;
}
