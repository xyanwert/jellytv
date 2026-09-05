import SwiftUI
import JellyTVKit

/// Screenshot-only harness for `PlayerChrome` — no live `AVPlayer`, no
/// network resolve, just fixture state seeded via `PlayerEngine.previewSeed`.
/// Launched via `JT_SHOW_PLAYER=1`, matching the `JT_SHOW_DEMO=movie|show`
/// family (see `RootView`).
struct PlayerPreviewFixture: View {
    @State private var engine: PlayerEngine?
    @State private var controller: PlayerController?
    @State private var chromeVisible = ProcessInfo.processInfo.environment["JT_SHOW_PLAYER"] != "hidden"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let controller {
                PlayerChrome(controller: controller, visible: $chromeVisible, onClose: {}, onOpenScenes: {})
            }
        }
        // **iPhone only**, matching `PlayerView`'s identical pair — this
        // fixture is presented through the exact same `RootView`
        // `.fullScreenCover` as real playback (see `PlayerPresentation
        // .fixture`), so it races the same presentation-transition timing
        // `PlayerPresentationProbe` exists for. It used to flip
        // `OrientationLock` from a bare `.onAppear`/`.onDisappear`, which
        // made this fixture *not* actually exercise the sequencing bug real
        // playback hit — a screenshot taken from it could look fine while
        // the real path was still broken.
        #if os(iOS)
        .background(
            PlayerPresentationProbe(
                onDidAppear: { OrientationLock.shared.inPlayer = true },
                onDidDisappear: { OrientationLock.shared.inPlayer = false }
            )
        )
        #endif
        .task {
            guard engine == nil else { return }
            let client = JellyfinClient(baseURL: URL(string: "http://localhost")!, apiKey: "", deviceId: "")
            let e = PlayerEngine(client: client, userId: "")
            let item = PlayableItem(
                id: "ep-0", seriesId: "series-1", title: "Aida",
                subtitle: "S1 · E0 — \"Una nueva vida (Piloto)\"",
                runtimeTicks: 33_160_000_000, resumePositionTicks: 40_000_000,
                isFavorite: true, imageURL: nil,
                // No `logoURL`: the fixture has no server to fetch artwork
                // from, so it deliberately exercises the *title* fallback.
                // Tags are inline, so the chip row can be seen without one —
                // and there are deliberately more of them than the row shows,
                // so the "+N" overflow chip is in every screenshot too.
                tags: ["Drama", "Spanish", "Watched before", "Comfort",
                       "Subtitled", "Ensemble", "Slow burn", "Rewatch",
                       "Late night", "Award winner"]
            )
            let showFailure = ProcessInfo.processInfo.environment["JT_SHOW_PLAYER"] == "failed"
            e.previewSeed(
                // Parked 27 minutes in rather than at zero, so the position
                // readout shows something worth reading in a screenshot.
                item: item, currentTime: 1620, duration: 3316, isPlaying: true, isFavorite: true,
                // Parked one *into* the queue, not at its head, so the foot
                // renders PREV as well as NEXT — both hide at the ends of a
                // queue, and a fixture that never shows one is a fixture that
                // can't catch it breaking.
                queue: Array(repeating: item, count: 68), queueIndex: 1,
                failureMessage: showFailure ? "Playback failed — the server returned repeated 500 errors and a fresh session didn't recover." : nil
            )
            engine = e
            controller = PlayerController(engine: e)
        }
    }
}
