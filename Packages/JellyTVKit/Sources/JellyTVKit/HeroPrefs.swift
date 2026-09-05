import Foundation

/// How the hero backdrop transitions between slides. Selectable in Settings.
public enum HeroTransitionStyle: String, CaseIterable, Sendable, Identifiable {
    case crumble
    case fade

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .crumble: return "Crumble"
        case .fade: return "Fade"
        }
    }

    public static let `default`: HeroTransitionStyle = .crumble
}

/// How long each hero slide stays before auto-advancing. Selectable in Settings.
public enum HeroRotation: Double, CaseIterable, Sendable, Identifiable {
    case s5 = 5
    case s15 = 15
    case s30 = 30

    public var id: Double { rawValue }

    /// Interval in seconds.
    public var seconds: Double { rawValue }

    public var label: String {
        switch self {
        case .s5: return "5s"
        case .s15: return "15s"
        case .s30: return "30s"
        }
    }

    public static let `default`: HeroRotation = .s15
}

/// What happens to the artwork behind a library screen (Movies, TV Shows,
/// Anime, Late Night). Selectable in Settings → Appearance.
///
/// The case is named `off` rather than `none` so it never collides with
/// `Optional.none` when the type is inferred.
public enum LibraryBackdropEffect: String, CaseIterable, Sendable, Identifiable {
    case blur
    case off = "none"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .blur: return "Blur"
        case .off: return "None"
        }
    }

    /// Gaussian radius applied to the backdrop. Heavy enough that the artwork
    /// reads as colour and shape behind the posters rather than as a competing
    /// picture — the point is atmosphere, not a second thing to look at.
    public var blurRadius: Double {
        switch self {
        case .blur: return 40
        case .off: return 0
        }
    }

    public static let `default`: LibraryBackdropEffect = .blur
}
