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
