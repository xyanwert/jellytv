import SwiftUI
import JellyTVKit

/// The download, on the page it was started from.
///
/// The requirement is the YouTube-style one: find a title, say "download this", and watch
/// the server do the rest right here — "looking for a source…", queued, 30%, "adding to
/// your library" — then leave, and come back to it still moving. So this stands in for
/// the Download bar, in the bar's own slot at the poster's foot, for as long as the
/// latest job for this title is worth watching; the download centre stays the place to
/// see every job at once.
///
/// It says only what the server says. `message` is the server's own sentence for the
/// state, the bar is drawn only once a percentage means something
/// (`State.showsProgress` — "searching" has no denominator), and a stub engine's job is
/// labelled SIMULATED, because a bar moving to 100% with no file behind it is the one
/// thing this must never let anyone misread.
struct DownloadProgressPanel: View {
    let job: YsojAPI.DownloadJob
    let tint: Color
    /// Stop a running job. The server decides what that means for its state.
    let onCancel: () -> Void
    /// Put the Download bar back once a finished job has been read.
    let onDismiss: () -> Void

    @FocusState private var actionFocused: Bool

    private static let amber = Color(hex: "#E8B44A")

    var body: some View {
        VStack(alignment: .leading, spacing: rowGap) {
            HStack(spacing: 10) {
                Image(systemName: job.state.glyph)
                    .font(.system(size: glyphSize, weight: .bold))
                    .foregroundStyle(stateColor)
                Text(job.state.label.uppercased())
                    .font(Mono.font(chipSize, .bold))
                    .tracking(1.6)
                    .foregroundStyle(stateColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(stateColor.opacity(0.15)))
                // On a phone the scope goes on its own line below: beside the state
                // chip and the SIMULATED tag it had about 90pt and rendered as
                // "Season 2 · 13 e…", which is the one part of the header that has to
                // be read in full — it says what is being downloaded.
                if !isNarrow, let subtitle = job.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Mono.font(metaSize, .medium))
                        .foregroundStyle(Palette.text(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if job.isSimulated {
                    Text("SIMULATED")
                        .font(Mono.font(chipSize - 1, .bold))
                        .tracking(1.4)
                        .foregroundStyle(Self.amber)
                }
            }

            if isNarrow, let subtitle = job.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(Mono.font(metaSize, .medium))
                    .foregroundStyle(Palette.text(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if job.state.showsProgress {
                progressBar
            } else if job.isActive {
                // Searching or queued: something is happening and there is no
                // percentage yet. A bar at 0% would claim the download had stalled.
                HStack(spacing: 10) {
                    ProgressView().tint(tint)
                    Text(job.message ?? "Working…")
                        .font(Typography.font(bodySize, .medium))
                        .foregroundStyle(Palette.text(0.6))
                        .lineLimit(2)
                }
            }

            if job.state.showsProgress, let message = job.message, !message.isEmpty {
                Text(message)
                    .font(Typography.font(bodySize, .medium))
                    .foregroundStyle(job.state == .failed ? Color(hex: "#E8544A") : Palette.text(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            } else if !job.isActive, let message = job.message, !message.isEmpty {
                Text(message)
                    .font(Typography.font(bodySize, .medium))
                    .foregroundStyle(job.state == .failed ? Color(hex: "#E8544A") : Palette.text(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                if job.isActive {
                    action("Cancel download", systemImage: "stop.fill", prominent: false,
                           perform: onCancel)
                } else {
                    // Read, understood, put away — the page's Download bar comes back.
                    // The job itself stays in the download centre.
                    action("OK", systemImage: "checkmark", prominent: true, perform: onDismiss)
                }
            }
            .padding(.top, 2)
        }
        .padding(panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tint.opacity(0.42), lineWidth: 1.5)
                )
        )
        // Focus lands on the one control here the moment the panel replaces the bar —
        // the bar had it, and a page with nothing focused eats the Menu button.
        .onAppear { actionFocused = true }
        .onChange(of: job.isActive) { _, _ in actionFocused = true }
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.text(0.12))
                    Capsule().fill(stateColor)
                        .frame(width: max(0, min(1, job.progress)) * geo.size.width)
                }
            }
            .frame(height: barHeight)
            .animation(.linear(duration: 0.4), value: job.progress)

            // Five numbers on one line is an iPad/TV width. On a phone they are two
            // rows — how far along, then how fast — rather than one row that truncates
            // at "7.12 GB of…", which drops the total the percentage refers to.
            if isNarrow {
                VStack(alignment: .leading, spacing: 3) {
                    metaLine(progressFacts)
                    if !rateFacts.isEmpty { metaLine(rateFacts) }
                }
            } else {
                metaLine(progressFacts + rateFacts)
            }
        }
    }

    /// How far along: the percentage and what it is a percentage of.
    private var progressFacts: [String] {
        var facts = ["\(Int(job.progress * 100))%"]
        if job.bytesTotal > 0 {
            facts.append("\(DownloadFormatting.bytes(job.bytesDownloaded)) of \(DownloadFormatting.bytes(job.bytesTotal))")
        }
        return facts
    }

    /// How fast, and from how many peers — only while it is actually moving.
    private var rateFacts: [String] {
        guard job.state == .downloading else { return [] }
        var facts: [String] = []
        if job.speedBytesPerSecond > 0 {
            facts.append(DownloadFormatting.bytes(job.speedBytesPerSecond) + "/s")
        }
        if let eta = job.etaSeconds, eta > 0 { facts.append(DownloadFormatting.eta(eta) + " left") }
        if let seeds = job.seeds { facts.append("\(seeds) seeds") }
        return facts
    }

    private func metaLine(_ facts: [String]) -> some View {
        HStack(spacing: 14) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                Text(fact)
                    .foregroundStyle(index == 0 ? Palette.text(0.85) : Palette.text(0.5))
            }
        }
        .font(Mono.font(metaSize, .medium))
        .lineLimit(1)
    }

    private func action(_ title: String, systemImage: String, prominent: Bool,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: systemImage)
                .font(Typography.font(bodySize + 1, .bold))
                .foregroundStyle(prominent ? Color.black : Palette.text(0.85))
                .padding(.horizontal, 18)
                .frame(height: buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(prominent ? tint : Palette.text(0.1))
                )
        }
        .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 12))
        .focused($actionFocused)
    }

    private var stateColor: Color { job.state.color(accent: tint) }

    /// Phone width — where a row of five numbers cannot fit.
    private var isNarrow: Bool {
        #if os(tvOS)
        false
        #else
        DeviceClass.current == .phone
        #endif
    }

    #if os(tvOS)
    private var rowGap: CGFloat { 12 }
    private var panelPadding: CGFloat { 22 }
    private var glyphSize: CGFloat { 20 }
    private var chipSize: CGFloat { 14 }
    private var metaSize: CGFloat { 16 }
    private var bodySize: CGFloat { 19 }
    private var barHeight: CGFloat { 10 }
    private var buttonHeight: CGFloat { 52 }
    #else
    private var isPhone: Bool { DeviceClass.current == .phone }
    private var rowGap: CGFloat { isPhone ? 8 : 10 }
    private var panelPadding: CGFloat { isPhone ? 14 : 18 }
    private var glyphSize: CGFloat { isPhone ? 15 : 17 }
    private var chipSize: CGFloat { isPhone ? 10 : 11 }
    private var metaSize: CGFloat { isPhone ? 11 : 13 }
    private var bodySize: CGFloat { isPhone ? 13 : 15 }
    private var barHeight: CGFloat { isPhone ? 7 : 8 }
    private var buttonHeight: CGFloat { isPhone ? 38 : 42 }
    #endif
}

/// The engine's states in the user's words, once, for every place a job is drawn —
/// the download centre's rows and the title page's panel had each other's copy before.
extension YsojAPI.DownloadJob.State {
    var label: String {
        switch self {
        case .searching: return "Searching"
        case .queued: return "Queued"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .importing: return "Adding"
        case .landed: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .unknown: return "Working"
        }
    }

    var glyph: String {
        switch self {
        case .searching: return "magnifyingglass"
        case .queued: return "clock"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .importing: return "tray.and.arrow.down.fill"
        case .landed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        case .unknown: return "circle.dashed"
        }
    }

    func color(accent: Color) -> Color {
        switch self {
        case .landed: return Color(hex: "#58D399")
        case .failed: return Color(hex: "#E8544A")
        case .cancelled: return Palette.text(0.45)
        case .paused: return Color(hex: "#E8B44A")
        default: return accent
        }
    }
}
