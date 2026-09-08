import SwiftUI
import JellyTVKit
#if canImport(UIKit)
import UIKit
#endif

/// Find a release: the trackers, searched through the server, one row per release.
///
/// **Search only, and it says so.** The server's download engine cannot fetch anything
/// yet — `media-downloader` has search and no job model — so a row here has no Download
/// button: a button that simulated would be worse than none, the rule the server's own
/// Downloads page follows too. On iOS an open row offers its magnet to the clipboard,
/// which is real: paste it into any torrent client. On tvOS there is nowhere to paste,
/// so an open row is its facts and nothing else. When the job model lands, the button
/// goes on the open row.
struct ReleaseResultsView: View {
    @ObservedObject var store: DiscoverStore
    @EnvironmentObject private var theme: Theme
    /// The one open row, by info hash. One at a time: the facts are for weighing a
    /// release you are considering, not a second list.
    @State private var openId: String?

    private static let amber = Color(hex: "#E8B44A")

    var body: some View {
        switch store.releaseState {
        case .idle:
            EmptyView()
        case .searching:
            LibraryLoadingState(message: "Searching the trackers…", accent: theme.accent)
        case .failed(let message):
            // The server's own sentence — "the download service isn't running" — not a
            // paraphrase, because it says what to do.
            LibraryEmptyState(message: "Couldn't search", hint: message,
                              systemImage: "exclamationmark.triangle")
        case .loaded:
            if let found = store.releaseSearch {
                if found.results.isEmpty {
                    LibraryEmptyState(message: "No releases for “\(found.normalized)”",
                                      hint: emptyHint(found), systemImage: "magnifyingglass")
                } else {
                    list(found)
                }
            }
        }
    }

    /// Nothing came back. Was that an answer, or a tracker that never replied?
    private func emptyHint(_ found: YsojAPI.ReleaseSearch) -> String {
        let down = found.failedSources.map(\.id)
        if !down.isEmpty {
            return "\(down.joined(separator: " and ")) didn't answer. Try again in a minute."
        }
        return "Try fewer words, or another category."
    }

    private func list(_ found: YsojAPI.ReleaseSearch) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                summary(found)
                ForEach(found.results) { release in
                    ReleaseRow(release: release, accent: theme.accent,
                               isOpen: openId == release.id) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            openId = openId == release.id ? nil : release.id
                        }
                    }
                }
            }
            .padding(.bottom, 60)
            // The phone's tab bar and TV bar float over the list; without this the last
            // rows sit under them and a tap on one opens the remote instead.
            .phoneTabBarClearance()
        }
        .onChange(of: found) { _, _ in openId = nil }
    }

    /// What answered and what didn't, and the two things worth saying before the rows:
    /// nothing here downloads yet, and the library may already have this.
    private func summary(_ found: YsojAPI.ReleaseSearch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(found.results.count) releases for “\(found.normalized)”")
                    .font(Typography.font(DiscoverMetrics.body, .bold))
                    .foregroundStyle(Palette.text(0.9))
                Text(found.cached ? "CACHED" : String(format: "%.1f S", Double(found.tookMs) / 1000))
                    .font(Mono.font(DiscoverMetrics.count - 2, .medium))
                    .tracking(1.2)
                    .foregroundStyle(Palette.text(0.4))
            }
            note(Self.searchOnlyNotice, systemImage: "info.circle", tint: Palette.text(0.5))
            if found.isAlreadyInLibrary {
                note("Something by this name is already in your library.",
                     systemImage: "checkmark.circle.fill", tint: Self.amber)
            }
            if !found.failedSources.isEmpty {
                let names = found.failedSources.map { source in
                    source.detail.map { "\(source.id) (\($0))" } ?? source.id
                }
                note("\(names.joined(separator: ", ")) didn't answer — these rows are from the rest.",
                     systemImage: "exclamationmark.triangle.fill", tint: Self.amber)
            }
        }
        .padding(.bottom, 4)
    }

    private static var searchOnlyNotice: String {
        let base = "Search only for now — the server has no download engine yet, so nothing here can be fetched from the app."
        #if os(iOS)
        return base + " Open a row to copy its magnet."
        #else
        return base
        #endif
    }

    private func note(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(Typography.font(DiscoverMetrics.body - 3, .medium))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 1100, alignment: .leading)
    }
}

/// One release. The header is the one button and opens the facts beneath it; the facts
/// are a sibling, not part of the button, so the copy control on iOS is never a button
/// inside a button — SwiftUI does not say which of two nested buttons a tap belongs to.
struct ReleaseRow: View {
    let release: YsojAPI.Release
    let accent: Color
    let isOpen: Bool
    let onToggle: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onToggle) {
                header
                    .padding(rowPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Palette.text(isOpen ? 0.08 : 0.05))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            // Never `.plain` on a focusable tvOS control — that is the system's white pill.
            .buttonStyle(FocusScaleStyle(scale: 1.02, cornerRadius: 16))
            .accessibilityLabel(release.name)
            .accessibilityHint(isOpen ? "Closes the details" : "Opens the details")

            if isOpen {
                facts
                    .padding(rowPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Palette.text(0.04))
                    )
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: 1100, alignment: .leading)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if !release.quality.isEmpty { qualityChip }
                Text(release.name)
                    .font(Typography.font(titleSize, .semibold))
                    .foregroundStyle(Palette.text(0.92))
                    .lineLimit(isOpen ? nil : 2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: metaSize, weight: .bold))
                    .foregroundStyle(Palette.text(0.35))
            }
            HStack(spacing: 14) {
                Text(DownloadFormatting.bytes(release.sizeBytes))
                    .foregroundStyle(Palette.text(0.7))
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                    Text("\(release.seeders)")
                }
                .foregroundStyle(seedColor)
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down")
                    Text("\(release.leechers)")
                }
                if let files = release.fileCountLabel { Text(files) }
                Text(release.provider.uppercased()).tracking(1.2)
                Text(release.category).foregroundStyle(Palette.text(0.35))
            }
            .font(Mono.font(metaSize, .medium))
            .foregroundStyle(Palette.text(0.5))
            .lineLimit(1)
        }
    }

    private var qualityChip: some View {
        Text(release.quality.uppercased())
            .font(Mono.font(metaSize - 2, .bold))
            .tracking(1.4)
            .foregroundStyle(accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(accent.opacity(0.16)))
    }

    /// A release nobody is seeding is not a release, and the row says so before anyone
    /// waits on it — the same three bands the server's own page colours by.
    private var seedColor: Color {
        switch release.seedHealth {
        case .healthy: return Palette.connected
        case .thin: return Color(hex: "#E8B44A")
        case .dead: return Color(hex: "#E8544A")
        }
    }

    // MARK: - Facts

    private var facts: some View {
        VStack(alignment: .leading, spacing: 10) {
            fact("INFO HASH", release.infoHash.lowercased())
            fact("FROM", "\(release.provider) · \(release.category)")
            fact("FILES", filesFact)
            fact("SWARM", "\(release.seeders) seeding · \(release.leechers) leeching")
            #if os(iOS)
            Button {
                UIPasteboard.general.string = release.magnet
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy magnet link",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(Typography.font(metaSize + 2, .bold))
                    .foregroundStyle(copied ? Palette.connected : Palette.text(0.9))
                    .padding(.horizontal, 14)
                    .frame(height: buttonHeight)
                    .background(Capsule().fill(Palette.text(0.1)))
            }
            .buttonStyle(FocusScaleStyle(scale: 1.04, cornerRadius: buttonHeight / 2))
            .accessibilityLabel("Copy the magnet link")
            Text("Paste it into any torrent client. The app can't download it yet.")
                .font(Typography.font(metaSize, .medium))
                .foregroundStyle(Palette.text(0.4))
            #else
            Text("The app can't download this yet. Copy its magnet from the iPhone or iPad app, or from the server's own Downloads page.")
                .font(Typography.font(metaSize + 1, .medium))
                .foregroundStyle(Palette.text(0.4))
                .fixedSize(horizontal: false, vertical: true)
            #endif
        }
    }

    /// Only one tracker reports a real count; a guess is said to be one.
    private var filesFact: String {
        guard release.fileCount > 0 else { return "unknown" }
        return release.fileCountExact
            ? "\(release.fileCount)"
            : "about \(release.fileCount), guessed from the name"
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(Mono.font(metaSize - 2, .bold))
                .tracking(1.6)
                .foregroundStyle(Palette.text(0.35))
                .frame(width: factLabelWidth, alignment: .leading)
            Text(value)
                .font(Mono.font(metaSize, .medium))
                .foregroundStyle(Palette.text(0.75))
                #if os(iOS)
                .textSelection(.enabled)
                #endif
        }
    }

    #if os(tvOS)
    private var titleSize: CGFloat { 24 }
    private var metaSize: CGFloat { 16 }
    private var rowPadding: CGFloat { 20 }
    private var buttonHeight: CGFloat { 46 }
    private var factLabelWidth: CGFloat { 130 }
    #else
    private var isPhone: Bool { DeviceClass.current == .phone }
    private var titleSize: CGFloat { isPhone ? 15 : 18 }
    private var metaSize: CGFloat { isPhone ? 11 : 13 }
    private var rowPadding: CGFloat { isPhone ? 12 : 16 }
    private var buttonHeight: CGFloat { isPhone ? 36 : 40 }
    private var factLabelWidth: CGFloat { isPhone ? 80 : 100 }
    #endif
}
