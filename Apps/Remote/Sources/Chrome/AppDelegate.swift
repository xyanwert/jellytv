import UIKit

/// Ported from `jelly-tv-ios/iOS/Chrome/AppDelegate.swift`. Without an app
/// delegate, iOS reads orientation solely from Info.plist and `OrientationLock`
/// has no way to be authoritative.
final class RemoteAppDelegate: NSObject, UIApplicationDelegate {
    nonisolated func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated {
            OrientationLock.shared.allowedOrientations
        }
    }
}
