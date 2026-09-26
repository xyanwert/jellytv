import Foundation

/// The app's overall look, picked in Settings → Appearance and persisted.
///
/// `.poster` is the anime key-visual direction: condensed display type, sticker
/// name tags, grid paper, stripes, and cut-out figures over giant ghost titles.
/// `.classic` is the neon look the app shipped with. Poster Mode is drawn *over*
/// the same foundations as Classic — the full-bleed backdrops and the hero
/// crumble belong to both — so switching never loses those.
public enum AppStyle: String, CaseIterable, Sendable, Identifiable {
    case poster
    case classic

    public var id: String { rawValue }

    /// The label on the Settings picker.
    public var displayName: String {
        switch self {
        case .poster: return "Poster"
        case .classic: return "Classic"
        }
    }

    public static let `default`: AppStyle = .poster
}
