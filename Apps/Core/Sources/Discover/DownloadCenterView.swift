import SwiftUI
import JellyTVKit

/// The download centre — what is being fetched, how far along, and what went wrong.
///
/// Its own destination rather than a sheet over Discover, for one reason: a download
/// outlives the browsing that started it. Someone queues a season and goes back to
/// watching something; the rail badge counts what is running and this is where it leads.
///
/// **Polling only happens while this is on screen.** A season download runs for an hour;
/// an hour of requests from a TV nobody is looking at is not a status display, it is a
/// background job nobody asked for. `DiscoverStore.startPolling` is started in `.onAppear`
/// and cancelled in `.onDisappear`, at the interval the server itself nominates
/// (`capabilities.features.downloads.pollSeconds`).
struct DownloadCenterView: View {
    @ObservedObject var store: DiscoverStore
    var isLibrariesOpen: Bool = false
    var onSelectRail: (RailTarget) -> Void = { _ in }
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var appState: AppState

    private var pollSeconds: Int {
        appState.ysojCapabilities?.features.downloads?.pollSeconds ?? 2
    }

    var body: some View {
        HStack(spacing: 0) {
            NavRail(destination: .downloads, isLibrariesOpen: isLibrariesOpen,
                    onSelect: onSelectRail)
            centreBody
        }
        .background(Palette.background)
        .onAppear { store.startPolling(every: pollSeconds) }
        .onDisappear { store.stopPolling() }
        .discoverActionAlert(store)
    }

    private var centreBody: some View {
        VStack(alignment: .leading, spacing: DiscoverMetrics.sectionGap) {
            DiscoverPageHeader(
                eyebrow: "DOWNLOADS", title: "Download centre",
                count: store.activeJobCount > 0 ? "\(store.activeJobCount) running" : nil
            )
            if store.downloadsAreSimulated { simulatedBanner }
            if store.jobs.isEmpty {
                // Empty and unreachable must not look the same: "nothing downloading" is
                // only true once the server has said so.
                switch store.downloadsState {
                case .loading:
                    LibraryLoadingState(message: "Checking…", accent: theme.accent)
                case .failed(let message):
                    LibraryEmptyState(message: "Couldn't reach the server", hint: message,
                                      systemImage: "exclamationmark.triangle")
                case .loaded:
                    LibraryEmptyState(
                        message: "Nothing downloading",
                        hint: "Pick something in Discover and it'll show up here."
                    )
                }
            } else {
                jobList
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DiscoverMetrics.pagePadding)
        .padding(.top, DiscoverMetrics.topPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The one thing this screen must never let anyone misread: with the stub engine
    /// every bar below moves and no file is fetched. Said once, at the top, in the
    /// server's own words rather than ours.
    private var simulatedBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "flask.fill")
                .foregroundStyle(Color(hex: "#E8B44A"))
            VStack(alignment: .leading, spacing: 3) {
                Text("Simulated downloads")
                    .font(Typography.font(DiscoverMetrics.body, .bold))
                    .foregroundStyle(Color(hex: "#E8B44A"))
                Text("This server has no download engine installed yet. Jobs run and report progress, but no file is actually fetched.")
                    .font(Typography.font(DiscoverMetrics.body - 2, .medium))
                    .foregroundStyle(Palette.text(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: 900, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "#E8B44A").opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: "#E8B44A").opacity(0.35), lineWidth: 1))
        )
    }

    /// Watch something the centre finished. Same rule as the title page: one id goes
    /// through the generic library path (which is the only one that can start a
    /// *series*), several play in the order the server sent them.
    private func play(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        Task {
            let request = ids.count == 1
                ? await appState.libraryPlaybackRequest(forItemId: ids[0])
                : await appState.playbackRequest(forItemIds: ids, startIndex: 0,
                                                 startPositionTicks: nil)
            guard let request else {
                store.actionError = "That finished, but the server wouldn't hand it over to play."
                return
            }
            appState.requestPlayback(request)
        }
    }

    private var jobList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(store.jobs) { job in
                    DownloadJobRow(
                        job: job,
                        canManage: store.canManageDownloads,
                        accent: theme.accent,
                        onPause: { Task { await store.pause(jobId: job.id) } },
                        onResume: { Task { await store.resume(jobId: job.id) } },
                        onRemove: { Task { await store.remove(jobId: job.id) } },
                        // Only what the server says it landed. A row with no ids behind
                        // it — a stub job, a failure — gets no Play button rather than
                        // one that apologises when pressed.
                        onPlay: job.landedItemIds.isEmpty ? nil : { play(job.landedItemIds) }
                    )
                }
            }
            .padding(.bottom, 60)
            // The phone's tab bar and TV bar float over the list; without this the last
            // row sits under them and a tap on it opens the remote instead.
            .phoneTabBarClearance()
        }
    }

}

/// One job.
///
/// The progress bar appears only once a percentage means something. "Searching" has no
/// denominator — a bar at 0% there would claim the download had started and stalled,
/// which is the opposite of what is happening.
struct DownloadJobRow: View {
    let job: YsojAPI.DownloadJob
    let canManage: Bool
    let accent: Color
    let onPause: () -> Void
    let onResume: () -> Void
    let onRemove: () -> Void
    /// Watch what this job landed. Nil when there is nothing to play.
    var onPlay: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            poster
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(job.title)
                        .font(Typography.font(titleSize, .bold))
                        .foregroundStyle(Palette.text(0.92))
                        .lineLimit(1)
                    stateChip
                    Spacer(minLength: 0)
                    controls
                }
                if let subtitle = job.subtitle {
                    Text(subtitle)
                        .font(Mono.font(metaSize, .medium))
                        .foregroundStyle(Palette.text(0.5))
                }
                if job.state.showsProgress { progressBar }
                if let message = job.message, !message.isEmpty {
                    Text(message)
                        .font(Typography.font(metaSize, .medium))
                        .foregroundStyle(job.state == .failed
                                         ? Color(hex: "#E8544A") : Palette.text(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(rowPadding)
        .frame(maxWidth: 1100, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.text(0.05))
        )
    }

    private var poster: some View {
        AsyncImage(url: job.posterURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.text(0.1))
        }
        .frame(width: posterWidth, height: posterWidth * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var stateChip: some View {
        Text(stateLabel.uppercased())
            .font(Mono.font(metaSize - 2, .bold))
            .tracking(1.4)
            .foregroundStyle(stateColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(stateColor.opacity(0.15)))
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.text(0.12))
                    // The state's own colour, like the title page's panel: a green DONE
                    // chip over an accent-red bar read as two different verdicts.
                    Capsule().fill(job.state.color(accent: accent))
                        .frame(width: max(0, min(1, job.progress)) * geo.size.width)
                }
            }
            .frame(height: 8)
            .animation(.linear(duration: 0.4), value: job.progress)

            HStack(spacing: 14) {
                Text("\(Int(job.progress * 100))%")
                if job.bytesTotal > 0 {
                    Text("\(DownloadFormatting.bytes(job.bytesDownloaded)) of \(DownloadFormatting.bytes(job.bytesTotal))")
                }
                if job.state == .downloading, job.speedBytesPerSecond > 0 {
                    Text(DownloadFormatting.bytes(job.speedBytesPerSecond) + "/s")
                }
                if job.state == .downloading, let eta = job.etaSeconds, eta > 0 {
                    Text(DownloadFormatting.eta(eta) + " left")
                }
            }
            .font(Mono.font(metaSize, .medium))
            .foregroundStyle(Palette.text(0.45))
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            // Playing what landed is not managing the queue — a member who may not
            // start or cancel a download may certainly watch what is in the library.
            if let onPlay {
                iconButton("play.fill", action: onPlay, label: "Play")
            }
            if canManage { manageControls }
        }
    }

    @ViewBuilder
    private var manageControls: some View {
        Group {
            if job.canPause {
                iconButton("pause.fill", action: onPause, label: "Pause")
            } else if job.canResume {
                iconButton("play.fill", action: onResume, label: "Resume")
            }
            // One gesture whose meaning depends on the state it's in — cancel a running
            // job, forget a finished one. The server decides which; the row doesn't need
            // two buttons for what reads as one idea.
            iconButton(job.state.isTerminal ? "xmark" : "stop.fill",
                       action: onRemove,
                       label: job.state.isTerminal ? "Remove" : "Cancel")
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void,
                            label: String) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: metaSize + 2, weight: .bold))
                .foregroundStyle(Palette.text(0.75))
                .frame(width: buttonSize, height: buttonSize)
                .background(Circle().fill(Palette.text(0.1)))
        }
        // Never `.plain` on a focusable tvOS control — that is the system's white pill.
        .buttonStyle(FocusScaleStyle(scale: 1.1, cornerRadius: buttonSize / 2))
        .accessibilityLabel(label)
    }

    private var stateLabel: String { job.state.label }
    private var stateColor: Color { job.state.color(accent: accent) }

    #if os(tvOS)
    private var posterWidth: CGFloat { 76 }
    private var titleSize: CGFloat { 24 }
    private var metaSize: CGFloat { 16 }
    private var rowPadding: CGFloat { 20 }
    private var buttonSize: CGFloat { 46 }
    #else
    private var isPhone: Bool { DeviceClass.current == .phone }
    private var posterWidth: CGFloat { isPhone ? 44 : 60 }
    private var titleSize: CGFloat { isPhone ? 16 : 19 }
    private var metaSize: CGFloat { isPhone ? 11 : 13 }
    private var rowPadding: CGFloat { isPhone ? 12 : 16 }
    private var buttonSize: CGFloat { isPhone ? 34 : 38 }
    #endif
}
