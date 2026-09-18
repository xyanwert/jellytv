import SwiftUI
import JellyTVKit

/// Settings → Playback: streaming-quality and playback-method segmented
/// controls plus toggle rows. Session-local state — no real playback backend
/// exists yet, consistent with the rest of the app's sample data.
struct PlaybackDetail: View {
    @State private var quality = SampleCatalog.defaultPlaybackQuality
    @State private var method = SampleCatalog.defaultPlaybackMethod
    @State private var toggleState: [String: Bool] = Dictionary(
        uniqueKeysWithValues: SampleCatalog.playbackToggles.map { ($0.label, $0.isOnByDefault) }
    )
    @EnvironmentObject private var server: ServerConnection
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(
                title: "Playback",
                readout: server.serverInfo.map { "\($0.name) · \($0.version)" }
            )

            DetailRow(label: "Streaming quality", description: "Max resolution on this Apple TV") {
                SegmentedControl(options: SampleCatalog.playbackQualityOptions, selection: $quality)
            }
            DetailDivider()

            DetailRow(label: "Playback method", description: "Direct Play avoids re-encoding when possible") {
                SegmentedControl(options: SampleCatalog.playbackMethodOptions, selection: $method)
            }
            DetailDivider()

            DetailRow(label: "Sleep timer",
                      description: "How long Night mode plays before it stops itself") {
                SegmentedControl(
                    options: SleepTimer.allCases.map(\.label),
                    selection: Binding(
                        get: { appState.sleepTimer.label },
                        set: { label in
                            if let match = SleepTimer.allCases.first(where: { $0.label == label }) {
                                appState.sleepTimer = match
                            }
                        }
                    )
                )
            }
            DetailDivider()

            ForEach(SampleCatalog.playbackToggles) { toggle in
                DetailRow(label: toggle.label, description: toggle.description) {
                    ToggleSwitch(isOn: binding(for: toggle))
                }
                DetailDivider()
            }

            Spacer(minLength: 0)
        }
    }

    /// A row with a `kind` writes through to the real preference; the rest
    /// keep the session-local state they have always had.
    ///
    /// Those others are still display-only, and knowingly so: "Auto-play next
    /// episode" describes behaviour the engine performs unconditionally, and
    /// "HDR passthrough" has nothing behind it at all. Wiring this one row
    /// does not make its neighbours honest — flagged rather than quietly left
    /// looking identical to the one that now works.
    private func binding(for toggle: PlaybackToggle) -> Binding<Bool> {
        switch toggle.kind {
        case .skipSegments:
            return Binding(
                get: { PlayerController.skipSegmentsEnabled },
                set: { PlayerController.skipSegmentsEnabled = $0 }
            )
        case nil:
            return Binding(
                get: { toggleState[toggle.label] ?? toggle.isOnByDefault },
                set: { toggleState[toggle.label] = $0 }
            )
        }
    }
}

/// A detail pane's title row, optionally with a trailing server readout.
struct DetailHeader: View {
    let title: String
    var readout: String?

    init(title: String, readout: String? = nil) {
        self.title = title
        self.readout = readout
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(Typography.font(40, .black))
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 20)
            if let readout {
                Text(readout)
                    .font(Typography.font(14, .medium))
                    .tracking(1.4)
                    .foregroundStyle(Palette.text(0.4))
            }
        }
        .padding(.bottom, 8)
    }
}
