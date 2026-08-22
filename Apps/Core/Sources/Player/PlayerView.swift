import SwiftUI
import JellyTVKit

/// Full-screen player surface: `PlayerLayerView` (raw AVPlayer canvas) under
/// `PlayerChrome` (the "Jelly-tv Player" design's custom controls) — no
/// AVKit chrome anywhere in between.
///
/// **Lifecycle rule** (ported from `/Users/xyan/code/jelly-tv-ios`): engine
/// and controller live in `@State`, built exactly once in `.task { if
/// engine == nil { ... } }`. SwiftUI rebuilds this view on unrelated
/// `AppState` changes; deriving the engine from anything but a one-time
/// `.task` check would tear playback down mid-play. `PlaybackRequest.id` is
/// content-derived (not `UUID()`) so `RootView`'s `.fullScreenCover(item:)`
/// doesn't retrigger for the same request either.
struct PlayerView: View {
    let request: PlaybackRequest
    let client: JellyfinClient
    let userId: String

    @Environment(\.dismiss) private var dismiss

    @State private var engine: PlayerEngine?
    @State private var controller: PlayerController?
    /// Lifted out of `PlayerChrome` so the Siri Remote Menu handler here at
    /// the root can toggle it without reaching into the chrome view.
    @State private var chromeVisible = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let engine, let controller {
                PlayerLayerView(player: engine.avPlayer)
                    .ignoresSafeArea()

                PlayerChrome(
                    controller: controller,
                    visible: $chromeVisible,
                    onClose: { dismiss() },
                    onOpenScenes: {}
                )
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        // **tvOS Siri Remote.** Wired at the root (not inside PlayerChrome)
        // so these are always in the responder chain regardless of which
        // chrome child currently has focus. iOS has no remote-control
        // commands to receive — play/pause is a tappable button in
        // `PlayerCenterControls`, and chrome-visibility-toggle-on-tap is
        // handled directly inside `PlayerChrome`'s own tap catcher instead.
        #if os(tvOS)
        .onPlayPauseCommand {
            controller?.togglePlay()
        }
        .onExitCommand {
            chromeVisible.toggle()
        }
        #endif
        .task {
            if engine == nil {
                let e = PlayerEngine(client: client, userId: userId)
                let c = PlayerController(engine: e)
                engine = e
                controller = c
                await e.play(request)
            }
        }
        .onDisappear {
            // Dismiss-first, teardown-async: don't make the back button
            // wait on the /Sessions/Playing/Stopped network round-trip.
            Task { await engine?.teardown() }
        }
    }
}
