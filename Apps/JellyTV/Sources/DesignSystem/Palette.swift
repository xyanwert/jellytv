import SwiftUI
import JellyTVKit

extension Color {
    /// Create a color from a `#RRGGBB` (or `#RGB`) hex string.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v & 0xFF0000) >> 16) / 255
        let g = Double((v & 0x00FF00) >> 8) / 255
        let b = Double(v & 0x0000FF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Convert an OKLCH color (as authored in the design) to sRGB.
    init(_ oklch: OKLCH) {
        let hr = oklch.h * .pi / 180
        let a = oklch.c * cos(hr)
        let b = oklch.c * sin(hr)
        // OKLab → LMS (Björn Ottosson)
        let l_ = oklch.l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = oklch.l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = oklch.l - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        func gamma(_ x: Double) -> Double {
            let c = min(max(x, 0), 1)
            return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
        let r = gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)
        let g = gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)
        let bl = gamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        self.init(.sRGB, red: r, green: g, blue: bl, opacity: 1)
    }
}

extension Artwork {
    /// Top→bottom SwiftUI gradient for card/hero artwork.
    var gradient: LinearGradient {
        LinearGradient(colors: [Color(top), Color(bottom)], startPoint: .top, endPoint: .bottom)
    }
}

/// Design color tokens.
enum Palette {
    static let page = Color(hex: "#07080C")
    static let screen = Color(hex: "#0B0D13")
    static let screenTop = Color(hex: "#0D1220")
    static let panel = Color(red: 20 / 255, green: 22 / 255, blue: 30 / 255).opacity(0.96)
    static let textPrimary = Color(hex: "#F4F5F7")
    static let connected = Color(hex: "#6FD68F")

    /// Translucent-white text tier, e.g. `Palette.text(0.55)`.
    static func text(_ opacity: Double) -> Color { .white.opacity(opacity) }

    /// The screen background gradient.
    static var background: LinearGradient {
        LinearGradient(colors: [screenTop, screen], startPoint: .top, endPoint: .bottom)
    }
}
