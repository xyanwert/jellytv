import UIKit
import JellyTVKit

/// Ported from `jelly-tv-ios/iOS/Chrome/OrientationLock.swift`, restored to
/// its original per-device shape now that `Remote` targets iPhone as well as
/// iPad (`TARGETED_DEVICE_FAMILY` in project.yml): iPad stays landscape at
/// all times (its rail-based layout assumes the wide canvas); iPhone is
/// portrait normally and flips to landscape only while a video is playing,
/// so full-screen video gets the phone's full width. tvOS never reaches this
/// type at all — its orientation isn't a UIKit concept.
///
/// Kept as a singleton + `UIApplicationDelegateAdaptor` pair (not just the
/// static Info.plist restriction) because that's the only way to make
/// `AppDelegate`'s `supportedInterfaceOrientationsFor` answer authoritative,
/// and it leaves the seam `PlayerView` needs to request a landscape flip when
/// it appears and hand portrait back when it disappears.
@MainActor
final class OrientationLock {
    static let shared = OrientationLock()

    /// Set true by `PlayerView` on appear, false on disappear (iPhone only —
    /// iPad's `allowedOrientations` never changes, so toggling this there
    /// would be a geometry-update call that changes nothing).
    var inPlayer: Bool = false {
        didSet {
            PlayerDiagnostics.log("orientation: inPlayer \(oldValue) -> \(inPlayer)")
            applyToCurrentScene()
        }
    }

    var allowedOrientations: UIInterfaceOrientationMask {
        switch DeviceClass.current {
        case .pad: return .landscape
        case .phone: return inPlayer ? .landscape : .portrait
        case .tv: return .landscape   // unreachable on iOS but harmless
        }
    }

    func applyToCurrentScene(retriesLeft: Int = 6) {
        // **Not filtered to `.foregroundActive`.** That was an earlier
        // silent-failure cause, found by logging every rejection here: a
        // `.fullScreenCover`'s own presentation transition — even *after*
        // `PlayerPresentationProbe` confirms the transition has finished
        // animating in — can leave the scene reporting `.foregroundInactive`
        // for a beat (the same transient state a Control Center swipe or a
        // system alert produces), which made the strict `.foregroundActive`
        // match find nothing and silently give up. A single-window app only
        // ever has the one scene worth updating; excluding `.background`/
        // `.unattached` is enough to avoid poking a scene that's genuinely
        // not on screen, without also excluding one that plainly is.
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState != .background && $0.activationState != .unattached }) else {
            PlayerDiagnostics.log("orientation: no usable window scene to update")
            return
        }
        // **The presented view controller needs to be told its supported
        // orientations may have changed, or `requestGeometryUpdate` validates
        // against a stale answer.** `RemoteAppDelegate` answers correctly the
        // moment `inPlayer` flips — confirmed by logging every call to it —
        // but the very first `requestGeometryUpdate` right after that flip
        // still failed with `UISceneErrorDomain` 101 ("Requested:
        // landscapeLeft, landscapeRight; Supported: portrait") every time,
        // even with the delegate already returning landscape and Info.plist
        // already listing it (see `project.yml`'s
        // `UISupportedInterfaceOrientations~iphone` for the other half of
        // this bug — a static list that used to permit Portrait only, which
        // made landscape unrequestable regardless of this dynamic answer).
        // UIKit doesn't re-derive "what this scene currently supports" on
        // every query; `setNeedsUpdateOfSupportedInterfaceOrientations()` is
        // the documented way to invalidate that cached answer.
        deepestPresentedViewController(in: scene)?.setNeedsUpdateOfSupportedInterfaceOrientations()
        // **This call has no error handler by default, and a rejected
        // request fails completely silently** — the exact bug that made the
        // phone player's landscape chrome look "half missing": everything
        // centred via `Spacer()`s still read fine against the *stale*
        // (portrait) frame the window kept reporting, while everything
        // anchored to a screen *edge* (the top bar, the opinion row, the
        // foot actions) landed off-frame or vanished. Logging the rejection
        // here is what turns that into something visible instead of
        // something guessed at.
        let requested = allowedOrientations
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: requested)) { [weak self] error in
            PlayerDiagnostics.log("orientation: requestGeometryUpdate(\(requested)) failed — \(error)")
            // **Several retries, not one.** `setNeedsUpdateOfSupportedInterfaceOrientations()`
            // only *marks* the view controller's answer dirty; UIKit re-asks it
            // on its own schedule, not synchronously inside this call, and
            // measured on-device that schedule can take 600-800ms (3-4 retries
            // at this spacing) before `requestGeometryUpdate`'s own internal
            // validation catches up with what `supportedInterfaceOrientations`
            // has already been answering correctly the whole time. Six retries
            // at 200ms is comfortably past that measured convergence point.
            guard retriesLeft > 0 else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                self?.applyToCurrentScene(retriesLeft: retriesLeft - 1)
            }
        }
    }

    /// Walks `.presentedViewController` to the end — the geometry request
    /// needs to invalidate whichever view controller is actually full-screen
    /// right now (`PlayerView`'s `.fullScreenCover`), not the window's root.
    private func deepestPresentedViewController(in scene: UIWindowScene) -> UIViewController? {
        var controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController
            ?? scene.windows.first?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
