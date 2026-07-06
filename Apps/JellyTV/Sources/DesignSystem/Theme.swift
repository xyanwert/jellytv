import SwiftUI
import JellyTVKit

/// App-wide theme: the selected accent color, persisted in `UserDefaults` and
/// published so both screens update live when it changes.
@MainActor
final class Theme: ObservableObject {
    static let storageKey = "accentColor"

    @Published var option: AccentOption {
        didSet { UserDefaults.standard.set(option.rawValue, forKey: Self.storageKey) }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey)
        option = raw.flatMap(AccentOption.init(rawValue:)) ?? .default
    }

    /// The current accent as a SwiftUI color.
    var accent: Color { Color(hex: option.hex) }

    /// The Theme row's trailing value, e.g. "Dark · Coral".
    var appearanceValue: String { "Dark · \(option.displayName)" }

    /// Advance to the next accent (used by the Theme row on select).
    func cycleAccent() {
        let all = AccentOption.allCases
        if let i = all.firstIndex(of: option) {
            option = all[(i + 1) % all.count]
        }
    }
}
