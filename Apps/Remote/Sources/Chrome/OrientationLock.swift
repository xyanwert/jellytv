import UIKit

/// This app is iPad-only and always landscape (see `Remote`'s
/// `UISupportedInterfaceOrientations~ipad` in project.yml) — unlike v1's
/// iPhone-supporting `OrientationLock` (`jelly-tv-ios/iOS/Chrome/OrientationLock.swift`),
/// there's no per-device or in-player branch here. Kept as a singleton +
/// `UIApplicationDelegateAdaptor` pair (not just the static Info.plist
/// restriction) because that's the only way to make `AppDelegate`'s
/// `supportedInterfaceOrientationsFor` answer authoritative, and it leaves a
/// seam if a future screen ever needs to request a geometry update.
@MainActor
final class OrientationLock {
    static let shared = OrientationLock()

    let allowedOrientations: UIInterfaceOrientationMask = .landscape

    func applyToCurrentScene() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: allowedOrientations))
    }
}
