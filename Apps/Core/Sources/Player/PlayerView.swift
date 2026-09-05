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
    /// Only for registering the live controller as
    /// `AppState.activePlayerController` — the engine gets its client and
    /// user id passed in explicitly above, not read from here.
    @EnvironmentObject private var appState: AppState

    @State private var engine: PlayerEngine?
    @State private var controller: PlayerController?
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
        // **tvOS Siri Remote — Play/Pause only.** Wired at the root (not
        // inside `PlayerChrome`) so it's always in the responder chain
        // regardless of which chrome child currently has focus. iOS has no
        // remote-control commands to receive — play/pause is a tappable
        // button in `PlayerCenterControls`, and chrome-visibility-toggle-on-
        // tap is handled directly inside `PlayerChrome`'s own tap catcher.
        //
        // **Menu lives inside `PlayerChrome` instead**, not here — it used to
        // be a bare `chromeVisible.toggle()` at this root, which mutated
        // `visible` outside the chrome's `withAnimation` fade and had no way
        // to know a full-screen panel (tags/scenes) was covering the chrome.
        // In practice neither version's Menu handling is ever reached on
        // tvOS: this cover gets dismissed by the system before a Menu press
        // reaches either root, at any chrome/panel state — see
        // `PlayerChrome.handleMenuPress` for the three-way confirmation and
        // why that isn't actually the wrong outcome.
        #if os(tvOS)
        .onPlayPauseCommand {
            controller?.togglePlay()
        }
        #endif
        // **iPhone only.** Flips the phone into landscape for the duration
        // of playback so full-screen video gets the full width, then hands
        // portrait back — iPad stays landscape throughout (see
        // `OrientationLock`), and tvOS has no such concept.
        //
        // **Not `.onAppear`/`.onDisappear` directly.** This view is the
        // content of `RootView`'s `.fullScreenCover`, and `.onAppear` fires
        // as soon as SwiftUI mounts it — while the cover's own presentation
        // transition is still animating in. Requesting an interface-
        // orientation geometry change at that moment is exactly the fragile
        // sequencing that made the landscape chrome look "half missing" on a
        // real device (see `PlayerPresentationProbe` and
        // `OrientationLock.applyToCurrentScene`): everything centred via
        // `Spacer()`s still read fine against the stale frame the window kept
        // reporting, while everything anchored to a screen edge landed off-
        // frame. The probe's `viewDidAppear`/`viewDidDisappear` only fire
        // once UIKit's own transition has actually finished.
        #if os(iOS)
        .background(
            PlayerPresentationProbe(
                onDidAppear: { OrientationLock.shared.inPlayer = true },
                onDidDisappear: { OrientationLock.shared.inPlayer = false }
            )
        )
        #endif
        .task {
            if engine == nil {
                let e = PlayerEngine(client: client, userId: userId)
                let c = PlayerController(engine: e)
                engine = e
                controller = c
                // So a remote-control Pause/Seek/Next from another Jellyfin
                // app (`RemoteControl`) reaches the player that is actually
                // up. Cleared below; weak on the other side regardless.
                appState.activePlayerController = c
                await e.play(request)
            }
        }
        .onDisappear {
            if appState.activePlayerController === controller {
                appState.activePlayerController = nil
            }
            // Dismiss-first, teardown-async: don't make the back button
            // wait on the /Sessions/Playing/Stopped network round-trip.
            Task { await engine?.teardown() }
        }
    }
}
