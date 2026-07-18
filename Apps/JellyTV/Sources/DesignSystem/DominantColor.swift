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
    private static var cache: [String: Color] = [:]

    static func of(_ imageName: String, fallback: Color = .gray) -> Color {
        if let cached = cache[imageName] { return cached }
        #if canImport(UIKit)
        let color = compute(UIImage(named: imageName)) ?? fallback
        #else
        let color = fallback
        #endif
        cache[imageName] = color
        return color
    }

    /// Same extraction, but for a remotely-hosted (Jellyfin) image — fetched
    /// once and cached by URL so repeat lookups (card re-renders, revisiting
    /// Home) don't re-download or recompute.
    static func of(url: URL, fallback: Color = .gray) async -> Color {
        let key = url.absoluteString
        if let cached = cache[key] { return cached }
        #if canImport(UIKit)
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return fallback }
        let color = compute(UIImage(data: data)) ?? fallback
        #else
        let color = fallback
        #endif
        cache[key] = color
        return color
    }

    #if canImport(UIKit)
    private static func compute(_ image: UIImage?) -> Color? {
        guard let image, let cg = image.cgImage else { return nil }
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
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
    #endif
}
