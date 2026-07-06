import Foundation

/// A color in the OKLCH space — the design authors artwork gradients in OKLCH.
/// Kept as plain numbers here so `JellyTVKit` stays platform-agnostic; the tvOS
/// design system converts these to on-screen colors.
public struct OKLCH: Equatable, Sendable, Hashable {
    /// Perceptual lightness, 0...1.
    public var l: Double
    /// Chroma, ~0...0.4.
    public var c: Double
    /// Hue angle in degrees, 0...360.
    public var h: Double

    public init(l: Double, c: Double, h: Double) {
        self.l = l
        self.c = c
        self.h = h
    }
}

/// A two-stop gradient descriptor for card/hero artwork (top → bottom).
public struct Artwork: Equatable, Sendable, Hashable {
    public var top: OKLCH
    public var bottom: OKLCH

    public init(top: OKLCH, bottom: OKLCH) {
        self.top = top
        self.bottom = bottom
    }

    /// Convenience: build from the design's `oklch(l c h)` base plus a slightly
    /// darker secondary hue for depth (matching the poster/continue gradients).
    public static func gradient(l: Double, c: Double, hue: Double, hue2: Double? = nil) -> Artwork {
        Artwork(
            top: OKLCH(l: l, c: c, h: hue),
            bottom: OKLCH(l: max(0, l - 0.14), c: c, h: hue2 ?? hue)
        )
    }
}
