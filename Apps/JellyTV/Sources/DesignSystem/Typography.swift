import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Typography scale using Schibsted Grotesk, falling back to the system rounded
/// font if the bundled font isn't registered (single swap point).
enum Typography {
    /// The resolved custom-font name, or `nil` to use the system fallback.
    private static let resolvedName: String? = {
        #if canImport(UIKit)
        for name in ["Schibsted Grotesk", "SchibstedGrotesk-Regular", "SchibstedGrotesk"] {
            if UIFont(name: name, size: 12) != nil { return name }
        }
        return nil
        #else
        return nil
        #endif
    }()

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let name = resolvedName {
            return .custom(name, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .rounded)
    }

    // Scale (point sizes map 1:1 to the 1920×1080 design)
    static var screenTitle: Font { font(96, .black) }   // detail-style titles
    static var heroTitle: Font { font(74, .black) }
    static var wordmark: Font { font(26, .heavy) }
    static var section: Font { font(26, .heavy) }
    static var rowTitle: Font { font(23, .bold) }
    static var body: Font { font(22, .medium) }
    static var button: Font { font(22, .heavy) }
    static var cardTitle: Font { font(19, .heavy) }
    static var caption: Font { font(17, .medium) }
    static var eyebrow: Font { font(20, .heavy) }
    static var badge: Font { font(17, .heavy) }
}

/// Monospaced type for the technical "readout" voice in the design (eyebrows,
/// status lines, port/host, API keys). Uses the system monospaced face — the
/// design's Space Mono isn't bundled.
enum Mono {
    static func font(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
