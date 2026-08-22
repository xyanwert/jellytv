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
        .task {
            guard engine == nil else { return }
            let client = JellyfinClient(baseURL: URL(string: "http://localhost")!, apiKey: "", deviceId: "")
            let e = PlayerEngine(client: client, userId: "")
            let item = PlayableItem(
                id: "ep-0", seriesId: "series-1", title: "Aida",
                subtitle: "S1 · E0 — \"Una nueva vida (Piloto)\"",
                runtimeTicks: 33_160_000_000, resumePositionTicks: 40_000_000,
                isFavorite: true, imageURL: nil
            )
            let showFailure = ProcessInfo.processInfo.environment["JT_SHOW_PLAYER"] == "failed"
            e.previewSeed(
                item: item, currentTime: 4, duration: 3316, isPlaying: true, isFavorite: true,
                queue: Array(repeating: item, count: 68), queueIndex: 0,
                failureMessage: showFailure ? "Playback failed — the server returned repeated 500 errors and a fresh session didn't recover." : nil
            )
            engine = e
            controller = PlayerController(engine: e)
        }
    }
}
