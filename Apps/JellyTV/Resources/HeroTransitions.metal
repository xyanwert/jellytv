//
//  HeroTransitions.metal
//
//  Hero slide-to-slide transition shader, applied via SwiftUI's native
//  `.layerEffect(ShaderLibrary.…)` API (tvOS 17+).
//
//    - hexCrumble → HeroTransitionStyle.crumble
//    - heatHaze  → incoming slide distortion during crumble
//
//  Used as a *reveal*: the incoming slide sits underneath as a solid base and
//  only the OUTGOING slide runs this shader on top, shattering away to expose
//  the new image — so no black ever shows between cells. (The .fade style uses
//  SwiftUI's .opacity — no shader.)

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

    /// Signed distance for a line segment from `a` to `b` at point `p`.
    float sdSegment(float2 p, float2 a, float2 b) {
        float2 pa = p - a, ba = b - a;
        float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        return length(pa - ba * h);
    }

    /// Smooth noise via value noise with hermite interpolation.
    float valueNoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);  // hermite
        float a = hash21(i);
        float b = hash21(i + float2(1.0, 0.0));
        float c = hash21(i + float2(0.0, 1.0));
        float d = hash21(i + float2(1.0, 1.0));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    /// FBM noise for organic warping.
    float fbm(float2 p) {
        float v = 0.0;
        float a = 0.5;
        float2 shift = float2(100.0);
        for (int i = 0; i < 4; i++) {
            v += a * valueNoise(p);
            p = p * 2.0 + shift;
            a *= 0.5;
        }
        return v;
    }
}

/// Honeycomb shatter (scatter-away). v3 — organic hex shapes, stretch
/// deformation, edge turbulence, dramatic crack propagation.
///
///   progress: 1 = intact, 0 = fully scattered (Animatable-driven, 1 → 0)
///   size:     canvas size in pt (wave normalization)
///   accent:   crack-glow tint (theme accent)
///   time:     absolute time in seconds (for ember animation)
[[ stitchable ]]
half4 hexCrumble(float2 position,
                 SwiftUI::Layer layer,
                 float progress,
                 float2 size,
                 half4 accent,
                 float time) {
    float u = 1.0 - progress;                       // 0 = intact, 1 = scattered
    if (u <= 0.001) { return layer.sample(position); }   // clean idle, zero cost

    // ---- organic cell distortion ----
    // Use FBM noise to warp the grid coordinates, making hex shapes irregular
    float2 noiseCoord = position * 0.012;  // scale for visible warping
    float2 warp = float2(
        fbm(noiseCoord + float2(0.0, 0.0)),
        fbm(noiseCoord + float2(5.2, 1.3))
    ) - 0.5;  // center around 0
    warp *= 18.0;  // warp strength in pixels

    // ---- variable cell sizes ----
    float scaleSelect = hash21(floor(position / 200.0));
    float cellW = scaleSelect < 0.7 ? 98.0 : 66.0;

    // Warp the UV coordinates for organic cell shapes
    float2 uv = (position + warp) / cellW;

    // ---- honeycomb partition ----
    const float2 r = float2(1.0, 1.7320508);
    const float2 h = r * 0.5;
    float2 a = gmod(uv, r) - h;
    float2 b = gmod(uv - h, r) - h;
    float2 gv = (dot(a, a) < dot(b, b)) ? a : b;
    float2 id = uv - gv;
    float2 center = id * cellW - warp;  // unwarp center for positioning

    float rnd  = hash21(id);
    float rnd2 = hash21(id + 17.17);
    float rnd3 = hash21(id + 31.42);

    // ---- parallax depth layer ----
    float depth = step(0.8, rnd);
    float depthBg = step(0.75, rnd3);
    if (depth < 0.5 && depthBg > 0.5) depth = -0.5;
    float depthMul = 1.0 + depth * 0.7;

    // ---- shatter wave: diagonal sweep with per-cell jitter ----
    const float2 dir = float2(0.9438, 0.3303);
    float ph = saturate(dot(center, dir) / dot(size, dir));
    ph = saturate(ph + (rnd - 0.5) * 0.10);

    const float life = 0.58;
    float start = ph * (1.0 - life);
    float t = saturate((u - start) / life);         // this cell's local 0 → 1
    if (t <= 0.0001) { return layer.sample(position); }

    // ---- slow-motion pause at peak shatter ----
    float tMod = t;
    float pauseCenter = 0.30;
    float pauseWidth = 0.08;
    float pauseAmount = 0.12;
    float pauseDist = abs(t - pauseCenter);
    if (t > pauseCenter - pauseWidth && t < pauseCenter + pauseWidth) {
        float pauseFactor = 1.0 - pauseAmount * (1.0 - smoothstep(0.0, pauseWidth, pauseDist));
        tMod = pauseCenter + (t - pauseCenter) * pauseFactor;
    }

    // ---- crack propagation (before tear-off) ----
    float crackPhase = saturate((tMod - 0.0) / 0.18);
    float crackVisibility = 0.0;
    float crackIntensity = 0.0;  // for edge glow boost
    if (crackPhase > 0.01 && crackPhase < 0.95) {
        float2 crackOrigin = float2(rnd2, rnd3) * cellW * 0.6 - cellW * 0.3;
        float minDist = 1e5;
        for (int i = 0; i < 3; i++) {
            float angle = (float(i) / 3.0 + rnd) * 6.28318 + rnd2 * 1.5;
            float len = crackPhase * cellW * 0.55;
            float2 crackEnd = crackOrigin + float2(cos(angle), sin(angle)) * len;
            float2 branchEnd = crackOrigin + float2(cos(angle + 0.4), sin(angle + 0.4)) * len * 0.5;
            float d = sdSegment(gv * cellW, crackOrigin, crackEnd);
            float db = sdSegment(gv * cellW, crackOrigin * 0.6, branchEnd);
            minDist = min(minDist, min(d, db));
        }
        crackVisibility = smoothstep(2.5, 0.5, minDist) * crackPhase * (1.0 - smoothstep(0.8, 1.0, crackPhase));
        crackIntensity = crackVisibility * 2.0;
    }

    // ---- stretch deformation (before tear-off) ----
    // Tiles stretch in the flight direction during crack phase, then snap back
    float2 perp = float2(-dir.y, dir.x);
    float stretchAmount = 0.0;
    float2 stretchDir = dir;
    if (tMod < 0.25) {
        // Stretch builds up during crack phase
        stretchAmount = smoothstep(0.0, 0.22, tMod) * 0.35;  // up to 35% elongation
        // Add slight perpendicular wobble for organic feel
        stretchDir = normalize(dir + perp * sin(tMod * 12.0 + rnd * 6.28) * 0.15);
    } else if (tMod < 0.35) {
        // Snap-back: stretch releases as tile tears off
        stretchAmount = mix(0.35, 0.0, smoothstep(0.25, 0.35, tMod));
    }

    // Non-uniform scale: elongate along stretch direction, compress perpendicular
    float stretchScale = 1.0 + stretchAmount;
    float compressScale = 1.0 / sqrt(stretchScale);  // preserve area

    // ---- edge turbulence (during flight) ----
    // Add noise-based warping to the hex distance field during flight
    float edgeNoise = 0.0;
    if (tMod > 0.15) {
        float noiseStrength = smoothstep(0.15, 0.5, tMod) * 0.08;  // builds during flight
        float2 edgeNoiseCoord = gv * 3.0 + float2(rnd * 10.0, rnd2 * 10.0);
        edgeNoise = (valueNoise(edgeNoiseCoord) - 0.5) * noiseStrength;
    }

    // ---- flight ----
    float su = tMod * tMod;
    float2 fdir = normalize(dir + perp * (rnd2 - 0.5) * 1.3);
    float2 disp = fdir * su * (320.0 + 260.0 * rnd) * depthMul;
    disp.y += (300.0 * tMod * tMod - 80.0 * tMod) * depthMul;

    float rot = (rnd - 0.5) * 3.6 * su * depthMul;
    float pop = smoothstep(0.0, 0.10, tMod) * (1.0 - smoothstep(0.10, 0.30, tMod));
    float scale = 1.0 - 0.5 * tMod + 0.05 * pop;

    // Fade trails the motion
    float alpha = 1.0 - smoothstep(0.50, 0.92, tMod);
    // Crack ignition window
    float glow = smoothstep(0.0, 0.08, tMod) * (1.0 - smoothstep(0.30, 0.58, tMod));

    // ---- color shift during flight ----
    float desat = smoothstep(0.2, 0.7, tMod) * 0.35;
    float warmShift = smoothstep(0.15, 0.6, tMod) * 0.12;

    // ---- inverse-transform sampling with stretch ----
    // Apply rotation
    float ca = cos(-rot), sa = sin(-rot);
    float2 q = position - center - disp;

    // Apply stretch deformation (non-uniform scale along stretch direction)
    float2 sd = stretchDir;
    float2 sp = float2(-sd.y, sd.x);
    // Project onto stretch axes
    float alongStretch = dot(q, sd);
    float alongPerp = dot(q, sp);
    // Apply non-uniform scale
    alongStretch /= stretchScale;
    alongPerp *= compressScale;
    // Reconstruct
    q = sd * alongStretch + sp * alongPerp;

    // Apply rotation and uniform scale
    q = float2(ca * q.x - sa * q.y, sa * q.x + ca * q.y) / max(scale, 0.05);
    float2 src = center + q;

    // ---- organic hex mask ----
    // Apply edge noise to the hex distance for irregular borders
    float hexD = hexDist(q / cellW) + edgeNoise;
    float mask = 1.0 - smoothstep(0.5 - 1.8 / cellW, 0.5, hexD);
    mask = mix(1.0, mask, saturate(tMod * 10.0));

    half4 color = layer.sample(src);

    // Apply color shift (desat + warm)
    half lum = dot(color.rgb, half3(0.299, 0.587, 0.114));
    color.rgb = mix(color.rgb, half3(lum), half(desat));
    color.r += half(warmShift * 0.8);
    color.g += half(warmShift * 0.3);

    // Crack lines
    color.rgb += accent.rgb * half(crackVisibility * 2.5);
    color *= half(alpha * mask);

    // Accent-lit cracks along cell borders + brightness pop
    float line = smoothstep(0.5 - 0.14, 0.5 - 0.02, hexD);
    // Boost edge glow during stretch phase for dramatic tearing look
    float edgeBoost = 1.0 + stretchAmount * 1.5 + crackIntensity;
    color.rgb += accent.rgb * half(glow * (1.8 * line + 0.22) * edgeBoost) * color.a;
    color.rgb *= half(1.0 + 0.22 * pop);

    // ---- ember particles (boosted for visibility) ----
    float emberAlpha = 0.0;
    float3 emberColor = float3(0.0);
    if (tMod > 0.05 && tMod < 0.75) {
        for (int e = 0; e < 6; e++) {
            float eRand = hash21(id + float2(e) * 7.77 + 5.55);
            float eRand2 = hash21(id + float2(e) * 13.13 + 9.99);
            float eStart = 0.05 + eRand * 0.15;
            float eLife = saturate((tMod - eStart) / 0.45);
            if (eLife <= 0.0 || eLife >= 1.0) continue;

            float2 eDir = normalize(dir + perp * (eRand2 - 0.5) * 2.0);
            float2 eDisp = eDir * eLife * (80.0 + 60.0 * eRand) * depthMul;
            eDisp.y += 40.0 * eLife - 120.0 * eLife * eLife;

            float2 ePos = center + gv * cellW + eDisp + disp;
            float2 eScreen = position - ePos;
            float eDist = length(eScreen);

            float eSize = (3.0 + 3.0 * eRand) * (1.0 - eLife * 0.4);
            float eBright = smoothstep(eSize, 0.0, eDist);
            eBright *= (1.0 - smoothstep(0.6, 1.0, eLife));

            emberAlpha += eBright * 1.2;
            emberColor += float3(1.0, 0.6 + 0.3 * eRand, 0.2) * eBright;
        }
    }
    color.rgb += half3(emberColor) * half(emberAlpha);
    color.a = max(color.a, half(emberAlpha * 0.6));

    // ---- shockwave ring ----
    float waveFront = ph * (1.0 - life);
    float waveDist = abs(u - waveFront - life * 0.5);
    float waveRing = smoothstep(0.08, 0.0, waveDist) * smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.85, 1.0, u));
    float2 ringCenter = dir * dot(size, dir) * u;
    float ringDist = abs(dot(position, dir) - dot(ringCenter, dir));
    float ringMask = smoothstep(10.0, 0.0, ringDist);
    color.rgb += accent.rgb * half(waveRing * ringMask * 0.6) * half(1.0 - alpha);

    // ---- stretch trails (motion blur effect) ----
    // During peak stretch, add a subtle directional blur along flight path
    if (stretchAmount > 0.1) {
        float trailAlpha = stretchAmount * 0.15;
        float2 trailOffset = -stretchDir * stretchAmount * 12.0;
        half4 trailColor = layer.sample(src + trailOffset);
        trailColor.rgb += accent.rgb * 0.3;
        color = mix(color, trailColor, half(trailAlpha));
    }

    return color;
}

/// Heat haze distortion for the incoming slide during crumble transition.
/// Applies a subtle sine-wave displacement that peaks in the middle of the
/// transition and fades at start/end.
///
///   progress: 1 = intact (no haze), 0 = fully transitioned (no haze)
///   size:     canvas size in pt
///   time:     absolute time for animation
[[ stitchable ]]
half4 heatHaze(float2 position,
               SwiftUI::Layer layer,
               float progress,
               float2 size,
               float time) {
    float u = 1.0 - progress;
    // Bell curve: peaks at u = 0.5, zero at 0 and 1
    float intensity = exp(-pow((u - 0.5) * 4.0, 2.0));
    if (intensity < 0.01) { return layer.sample(position); }

    float2 uv = position / size;
    // Two overlapping sine waves at different frequencies
    float wave1 = sin(uv.y * 25.0 + time * 3.5) * 4.0;
    float wave2 = sin(uv.y * 40.0 - time * 2.2 + uv.x * 8.0) * 2.5;
    float displacement = (wave1 + wave2) * intensity;

    return layer.sample(position + float2(displacement, 0.0));
}
