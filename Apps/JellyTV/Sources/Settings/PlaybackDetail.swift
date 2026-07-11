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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: "Playback", readout: "\(SampleCatalog.server.name) · \(SampleCatalog.server.version)")

            DetailRow(label: "Streaming quality", description: "Max resolution on this Apple TV") {
                SegmentedControl(options: SampleCatalog.playbackQualityOptions, selection: $quality)
            }
            DetailDivider()

            DetailRow(label: "Playback method", description: "Direct Play avoids re-encoding when possible") {
                SegmentedControl(options: SampleCatalog.playbackMethodOptions, selection: $method)
            }
            DetailDivider()

            ForEach(SampleCatalog.playbackToggles) { toggle in
                DetailRow(label: toggle.label, description: toggle.description) {
                    ToggleSwitch(isOn: Binding(
                        get: { toggleState[toggle.label] ?? toggle.isOnByDefault },
                        set: { toggleState[toggle.label] = $0 }
                    ))
                }
                DetailDivider()
            }

            Spacer(minLength: 0)
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
