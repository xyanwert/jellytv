import SwiftUI
import JellyTVKit

/// App-wide theme: the selected accent color, persisted in `UserDefaults` and
/// published so both screens update live when it changes.
@MainActor
final class Theme: ObservableObject {
    static let storageKey = "accentColor"
    static let transitionKey = "heroTransition"
    static let rotationKey = "heroRotation"

    @Published var option: AccentOption {
        didSet { UserDefaults.standard.set(option.rawValue, forKey: Self.storageKey) }
    }

    /// Hero backdrop transition style.
    @Published var transitionStyle: HeroTransitionStyle {
        didSet { UserDefaults.standard.set(transitionStyle.rawValue, forKey: Self.transitionKey) }
    }

    /// Hero auto-rotation interval.
    @Published var rotationInterval: HeroRotation {
        didSet { UserDefaults.standard.set(rotationInterval.rawValue, forKey: Self.rotationKey) }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey)
        option = raw.flatMap(AccentOption.init(rawValue:)) ?? .default

        let t = UserDefaults.standard.string(forKey: Self.transitionKey)
        transitionStyle = t.flatMap(HeroTransitionStyle.init(rawValue:)) ?? .default

        let r = UserDefaults.standard.object(forKey: Self.rotationKey) as? Double
        rotationInterval = r.flatMap(HeroRotation.init(rawValue:)) ?? .default
    }

    /// The current accent as a SwiftUI color.
    var accent: Color { Color(hex: option.hex) }
}
