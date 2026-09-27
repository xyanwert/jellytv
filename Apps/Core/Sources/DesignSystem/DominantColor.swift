import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Extracts a punchy dominant color from an image asset — used to tint media
/// cards and color their borders. Results are cached per asset name.
///
/// Method: downscale to 32×32, drop near-black/near-gray pixels, bucket the rest
/// by hue and weight each by saturation×value, pick the heaviest bucket, then
/// normalize brightness so the color reads as an accent.
enum DominantColor {
    // Reached from several places at once — card bodies on the main actor and
    // the detail screens' async extraction on whatever thread URLSession
    // resumes on. An unguarded static dictionary corrupts under that (a real
    // crash: doesNotRecognizeSelector inside Dictionary.subscript.setter), so
    // every read and write goes through the lock.
    private static let lock = NSLock()
    private static var cache: [String: Color] = [:]

    private static func cached(_ key: String) -> Color? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]
    }

    private static func store(_ color: Color, for key: String) {
        lock.lock(); defer { lock.unlock() }
        cache[key] = color
    }

    static func of(_ imageName: String, fallback: Color = .gray) -> Color {
        if let cached = cached(imageName) { return cached }
        #if canImport(UIKit)
        let color = compute(UIImage(named: imageName)) ?? fallback
        #else
        let color = fallback
        #endif
        store(color, for: imageName)
        return color
    }

    /// Same extraction, but for a remotely-hosted (Jellyfin) image — fetched
    /// once and cached by URL so repeat lookups (card re-renders, revisiting
    /// Home) don't re-download or recompute.
    static func of(url: URL, fallback: Color = .gray) async -> Color {
        let key = url.absoluteString
        if let cached = cached(key) { return cached }
        #if canImport(UIKit)
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return fallback }
        let color = compute(UIImage(data: data)) ?? fallback
        #else
        let color = fallback
        #endif
        store(color, for: key)
        return color
    }

    /// The dominant colour of an image already in hand — a cut-out figure,
    /// say — keyed by the caller so it is computed once.
    static func of(image: UIImage, key: String, fallback: Color = .gray) -> Color {
        if let cached = cached(key) { return cached }
        #if canImport(UIKit)
        let color = compute(image) ?? fallback
        #else
        let color = fallback
        #endif
        store(color, for: key)
        return color
    }

    /// The dominant colour's hue on the OKLCH wheel, in degrees — nil for an
    /// image with nothing saturated in it. What a key visual's palette is
    /// derived from: the ground takes the complement, the accent the hue.
    static func hue(of image: UIImage) -> Double? {
        #if canImport(UIKit)
        guard let (r, g, b) = components(image) else { return nil }
        return OKLab.hue(r: r, g: g, b: b)
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    private static func compute(_ image: UIImage?) -> Color? {
        guard let image, let (r, g, b) = components(image) else { return nil }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// The heaviest hue bucket's mean colour, brightness-normalised so it
    /// reads as an accent. Transparent pixels come through black and are
    /// dropped with the rest of the near-blacks.
    private static func components(_ image: UIImage) -> (Double, Double, Double)? {
        guard let cg = image.cgImage else { return nil }
        let w = 32, h = 32
        let space = CGColorSpaceCreateDeviceRGB()
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        let buckets = 12
        var weight = [Double](repeating: 0, count: buckets)
        var rAcc = [Double](repeating: 0, count: buckets)
        var gAcc = [Double](repeating: 0, count: buckets)
        var bAcc = [Double](repeating: 0, count: buckets)

        var i = 0
        while i < data.count {
            let r = Double(data[i]) / 255, g = Double(data[i + 1]) / 255, b = Double(data[i + 2]) / 255
            i += 4
            let mx = max(r, g, b), mn = min(r, g, b), v = mx
            let s = mx == 0 ? 0 : (mx - mn) / mx
            if v < 0.15 || s < 0.22 { continue }
            var hue = 0.0
            let d = mx - mn
            if d != 0 {
                if mx == r { hue = (g - b) / d }
                else if mx == g { hue = 2 + (b - r) / d }
                else { hue = 4 + (r - g) / d }
                hue *= 60
                if hue < 0 { hue += 360 }
            }
            let bkt = min(buckets - 1, Int(hue / 30))
            let wt = s * v
            weight[bkt] += wt
            rAcc[bkt] += r * wt; gAcc[bkt] += g * wt; bAcc[bkt] += b * wt
        }

        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0 else { return nil }
        var r = rAcc[best] / weight[best], g = gAcc[best] / weight[best], b = bAcc[best] / weight[best]
        let mx = max(r, g, b)
        if mx > 0 { let f = 0.78 / mx; r *= f; g *= f; b *= f }
        return (r, g, b)
    }
    #endif
}

/// The forward half of the OKLab conversion (`Color(OKLCH:)` has the other):
/// sRGB in, the hue angle out, so a colour taken off an image can be put back
/// on the same wheel the palette is built on.
enum OKLab {
    static func hue(r: Double, g: Double, b: Double) -> Double? {
        func linear(_ c: Double) -> Double {
            let x = min(max(c, 0), 1)
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        let rl = linear(r), gl = linear(g), bl = linear(b)
        let l = cbrt(0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl)
        let m = cbrt(0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl)
        let s = cbrt(0.0883024619 * rl + 0.2817188376 * gl + 0.6299787005 * bl)
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let chroma = (a * a + bb * bb).squareRoot()
        guard chroma > 0.02 else { return nil }
        var h = atan2(bb, a) * 180 / .pi
        if h < 0 { h += 360 }
        return h
    }
}
