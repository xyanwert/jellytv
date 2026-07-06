import Foundation

/// The four brand accent colors from the design ("Brand" section). Selectable in
/// Settings → Theme, persisted, and applied across the app.
public enum AccentOption: String, CaseIterable, Sendable, Identifiable {
    case coral
    case amber
    case blue
    case green

    public var id: String { rawValue }

    /// sRGB hex string, e.g. `#F0525F`.
    public var hex: String {
        switch self {
        case .coral: return "#F0525F"
        case .amber: return "#E8B44A"
        case .blue: return "#4AA8E8"
        case .green: return "#3FBF8F"
        }
    }

    /// Human-readable name shown in the Theme row ("Dark · Coral").
    public var displayName: String {
        switch self {
        case .coral: return "Coral"
        case .amber: return "Amber"
        case .blue: return "Blue"
        case .green: return "Green"
        }
    }

    public static let `default`: AccentOption = .coral
}
