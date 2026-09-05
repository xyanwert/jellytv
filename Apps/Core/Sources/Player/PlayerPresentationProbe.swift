import SwiftUI

#if os(iOS)
import UIKit

/// A zero-size, invisible signal for "the enclosing `.fullScreenCover`
/// presentation has genuinely finished" — UIKit calls `viewDidAppear(_:)` on
/// a child view controller only once the transition that added it has
/// finished animating, unlike SwiftUI's own `.onAppear`, which fires as soon
/// as the view enters the hierarchy (i.e. mid-transition, while the cover is
/// still animating in).
///
/// `PlayerView` needs exactly this signal before it asks `OrientationLock` to
/// flip the interface orientation: requesting a geometry update while the
/// presenting transition is still in flight is fragile, undocumented
/// sequencing, and a rejected request fails completely silently — see
/// `OrientationLock.applyToCurrentScene`'s error-logging comment for what
/// that silent failure looked like on screen (edge-anchored chrome missing,
/// the video settling into its corrected frame only once something else
/// triggered a fresh layout pass).
///
/// `viewDidDisappear` is the disappearing-side mirror — called once the
/// dismiss transition has actually completed — used here so handing the
/// phone back to portrait gets the same protection, even though the
/// symptom that prompted this was only ever observed on the appearing side.
struct PlayerPresentationProbe: UIViewControllerRepresentable {
    var onDidAppear: (() -> Void)?
    var onDidDisappear: (() -> Void)?

    func makeUIViewController(context: Context) -> ProbeViewController {
        let controller = ProbeViewController()
        controller.onDidAppear = onDidAppear
        controller.onDidDisappear = onDidDisappear
        return controller
    }

    func updateUIViewController(_ controller: ProbeViewController, context: Context) {
        controller.onDidAppear = onDidAppear
        controller.onDidDisappear = onDidDisappear
    }

    final class ProbeViewController: UIViewController {
        var onDidAppear: (() -> Void)?
        var onDidDisappear: (() -> Void)?
        private var hasFiredAppear = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !hasFiredAppear else { return }
            hasFiredAppear = true
            onDidAppear?()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            onDidDisappear?()
        }
    }
}
#endif
