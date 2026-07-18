import SwiftUI
import JellyTVKit

/// Settings → Metadata: opt into OMDb enrichment (awards/Oscars, true Rotten
/// Tomatoes %, Metacritic) and store the free API key. Off by default; when
/// enabled, the app sends only an item's IMDb id to omdbapi.com.
struct MetadataDetail: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme
    @FocusState private var keyFocused: Bool?

    /// Result of a "Test key" check.
    private enum TestStatus: Equatable { case idle, testing, ok, failed }
    @State private var testStatus: TestStatus = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(title: "Metadata")

            DetailRow(label: "Enrich with OMDb",
                      description: "Fetch Oscars, Rotten Tomatoes & Metacritic from omdbapi.com") {
                ToggleSwitch(isOn: $appState.omdbEnabled)
            }
            DetailDivider()

            if appState.omdbEnabled {
                VStack(alignment: .leading, spacing: 14) {
                    Text("API KEY")
                        .font(Mono.font(14, .bold)).tracking(2)
                        .foregroundStyle(Palette.text(0.5))
                    AppTextField(placeholder: "Paste your OMDb API key",
                                 text: $appState.omdbApiKey,
                                 secure: true, mono: true,
                                 accent: theme.accent, field: true, focus: $keyFocused,
                                 onSubmit: {})
                    HStack(spacing: 16) {
                        Button(action: testKey) {
                            Text(testLabel)
                                .font(Typography.font(17, .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 22).padding(.vertical, 12)
                                .background(theme.accent.opacity(appState.omdbApiKey.isEmpty ? 0.3 : 1),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(FocusScaleStyle(scale: 1.05, cornerRadius: 12))
                        .disabled(appState.omdbApiKey.isEmpty || testStatus == .testing)

                        Text("Get a free key at omdbapi.com/apikey.aspx")
                            .font(Typography.font(16, .medium))
                            .foregroundStyle(Palette.text(0.4))
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 24)
                DetailDivider()
            }

            Spacer(minLength: 0)
        }
    }

    private var testLabel: String {
        switch testStatus {
        case .idle: return "Test key"
        case .testing: return "Testing…"
        case .ok: return "✓ Working"
        case .failed: return "✗ Failed"
        }
    }

    private func testKey() {
        testStatus = .testing
        let key = appState.omdbApiKey
        Task {
            // "The Shawshank Redemption" — a stable id that always resolves.
            let ok = (try? await OmdbClient(apiKey: key).fetch(imdbId: "tt0111161"))?.isSuccess ?? false
            testStatus = ok ? .ok : .failed
        }
    }
}
