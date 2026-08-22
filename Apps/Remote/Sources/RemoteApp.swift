import SwiftUI
import AVFoundation

@main
struct RemoteApp: App {
    /// Drives `supportedInterfaceOrientationsFor` so `OrientationLock` is the
    /// authoritative source the system consults (Info.plist alone can't be
    /// changed at runtime) — ported from `jelly-tv-ios/iOS/JellyApp_iOS.swift`.
    @UIApplicationDelegateAdaptor(RemoteAppDelegate.self) private var appDelegate

    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }

    /// Bootstraps the audio session at launch so the first player appearance
    /// doesn't have an audible glitch/route surprise — ported from
    /// `jelly-tv-ios/iOS/JellyApp_iOS.swift`'s `configureAudioSession()`.
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback,
                                     options: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("AVAudioSession setup failed: \(error.localizedDescription)")
        }
    }
}
