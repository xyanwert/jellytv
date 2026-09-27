import SwiftUI
import JellyTVKit

/// SOUND & SUBTITLES — the item's tracks, and the way to make a pick the
/// library's default. Design canvas "TV · Sound & subtitles panel": two
/// columns of sticker rows, the one playing in teal, the library's preferred
/// languages wearing a coral tag, an OFF row at the head of the subtitles.
///
/// Same bargain as SCENES and TAGS: a surface of its own with targets the
/// size of the transport circles, the video paused underneath, resumed on
/// the way out. A pick applies at once (`PlayerController.setAudioTrack` /
/// `setSubtitleTrack` — in place where the player can, a reload at the same
/// position where the transcode has to change). MAKE THIS THE DEFAULT writes
/// the pick to the top of the library's preference (Settings → Libraries →
/// Languages), so the next episode starts that way without the panel.
struct PlayerLanguagesPanel: View {
    let controller: PlayerController
    let accent: Color
    let onDismiss: () -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme
    @FocusState private var focus: String?

    @State private var wasPlaying = false
    @State private var libraryId: String?
    @State private var savedAt: Date?
    @State private var switching = false

    private var device: DeviceClass { DeviceClass.current }
    private var s: CGFloat { device == .tv ? 1 : (device == .phone ? 0.5 : 0.68) }
    private var poster: Bool { theme.isPoster }
    private var preference: LibraryLanguagePreference {
        libraryId.map { appState.languagePreference(forLibrary: $0) } ?? .none
    }
    private var libraryName: String? { libraryId.flatMap { appState.libraryName(for: $0) } }

    var body: some View {
        ZStack {
            Color.black.opacity(poster ? 0.72 : 0.94).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 26 * s) {
                header
                if device == .phone {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24 * s) {
                            soundColumn
                            subtitleColumn
                            footer
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 40 * s) {
                        soundColumn
                        subtitleColumn
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    footer
                }
            }
            .padding(.horizontal, 48 * s).padding(.vertical, 40 * s)
            .frame(maxWidth: device == .tv ? 1500 : .infinity, maxHeight: device == .tv ? 760 : .infinity)
            .background {
                if poster {
                    RoundedRectangle(cornerRadius: 34 * s, style: .continuous)
                        .fill(Palette.posterInk.opacity(0.92))
                        .overlay(RoundedRectangle(cornerRadius: 34 * s, style: .continuous)
                            .strokeBorder(.white, lineWidth: 6 * s))
                        .shadow(color: Palette.posterInk, radius: 0, x: 14 * s, y: 14 * s)
                }
            }
            .padding(device == .tv ? 0 : 16)
        }
        .task {
            wasPlaying = controller.isPlaying
            if wasPlaying { controller.pause() }
            if let item = controller.currentItem { libraryId = await appState.libraryId(for: item) }
            #if os(tvOS)
            focus = controller.trackChoice.subtitleIndex.map { "sub:\($0)" } ?? "sub:off"
            #endif
        }
        .onDisappear { if wasPlaying { controller.play() } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 22 * s) {
            Text("SOUND & SUBTITLES")
                .font(poster ? Display.font(44 * s) : Typography.font(30 * s, .black)).tracking(1)
                .foregroundStyle(poster ? Palette.posterInk : .white)
                .padding(.horizontal, poster ? 18 * s : 0).padding(.vertical, poster ? 4 * s : 0)
                .background(poster ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 10 * s, style: .continuous))
                .rotationEffect(.degrees(poster ? -2 : 0))
            if device != .phone, let libraryName {
                Text("PICKED BY THE \(libraryName.uppercased()) LIBRARY'S SETTINGS")
                    .font(Mono.font(20 * s, .bold)).tracking(2)
                    .foregroundStyle(Palette.text(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(controller.trackChoice.subtitleIsBurnIn ? "BURNED IN" : "")
                .font(Mono.font(18 * s, .bold)).tracking(2)
                .foregroundStyle(Palette.posterTeal)
            backButton
        }
    }

    private var backButton: some View {
        Button(action: onDismiss) {
            HStack(spacing: 12 * s) {
                Image(systemName: "chevron.left").font(.system(size: 20 * s, weight: .bold))
                Text("BACK").font(poster ? Display.font(26 * s) : Typography.font(20 * s, .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 26 * s)
            .frame(height: 64 * s)
            .background(poster ? Palette.posterInk.opacity(0.4) : accent, in: Capsule())
            .overlay(Capsule().strokeBorder(poster ? .white : .clear, lineWidth: 4 * s))
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: 999))
        .panelFocus($focus, "back")
    }

    // MARK: - Columns

    private var soundColumn: some View {
        VStack(alignment: .leading, spacing: 14 * s) {
            columnHead(icon: "speaker.wave.2.fill", title: "SOUND")
            ForEach(controller.audioTracks, id: \.index) { track in
                row(id: "audio:\(track.index ?? -1)",
                    name: track.languageLabel.uppercased(),
                    meta: audioMeta(track),
                    preferred: rank(of: track.language, in: preference.audio),
                    playing: track.index == controller.trackChoice.audioIndex) {
                    guard let index = track.index else { return }
                    Task { switching = true; await controller.setAudioTrack(index); switching = false }
                }
            }
            if controller.audioTracks.isEmpty {
                Text("One sound track.").font(Typography.font(20 * s, .semibold)).foregroundStyle(Palette.text(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelSection()
    }

    private var subtitleColumn: some View {
        VStack(alignment: .leading, spacing: 14 * s) {
            columnHead(icon: nil, title: "SUBTITLES")
            row(id: "sub:off", name: "OFF", meta: nil, preferred: nil,
                playing: controller.trackChoice.subtitleIndex == nil) {
                Task { switching = true; await controller.setSubtitleTrack(nil); switching = false }
            }
            ForEach(controller.subtitleTracks, id: \.index) { track in
                row(id: "sub:\(track.index ?? -1)",
                    name: subtitleName(track),
                    meta: subtitleMeta(track),
                    preferred: track.isForced == true ? nil : rank(of: track.language, in: preference.subtitles),
                    playing: track.index == controller.trackChoice.subtitleIndex) {
                    guard let index = track.index else { return }
                    Task { switching = true; await controller.setSubtitleTrack(index); switching = false }
                }
            }
            if controller.subtitleTracks.isEmpty {
                Text("This video has no subtitles.").font(Typography.font(20 * s, .semibold)).foregroundStyle(Palette.text(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelSection()
    }

    private func columnHead(icon: String?, title: String) -> some View {
        HStack(spacing: 14 * s) {
            if let icon {
                Image(systemName: icon).font(.system(size: 26 * s, weight: .bold))
            } else {
                Text("CC").font(Display.font(22 * s)).tracking(1)
                    .padding(.horizontal, 8 * s).padding(.vertical, 2 * s)
                    .overlay(RoundedRectangle(cornerRadius: 6 * s, style: .continuous).strokeBorder(.white, lineWidth: 3 * s))
            }
            Text(title).font(poster ? Display.font(34 * s) : Typography.font(24 * s, .black)).tracking(1)
            Rectangle().fill(Palette.text(0.18)).frame(height: 3 * s)
        }
        .foregroundStyle(.white)
    }

    private func row(id: String, name: String, meta: String?, preferred: Int?, playing: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18 * s) {
                Text(name)
                    .font(poster ? Display.font(40 * s) : Typography.font(28 * s, .black)).tracking(1)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                if let meta {
                    Text(meta)
                        .font(Mono.font(20 * s, .bold)).tracking(1)
                        .padding(.horizontal, 10 * s).padding(.vertical, 5 * s)
                        .background(playing ? Palette.posterInk : Palette.text(0.1),
                                    in: RoundedRectangle(cornerRadius: 6 * s, style: .continuous))
                        .foregroundStyle(playing ? .white : Palette.text(0.7))
                }
                if let preferred {
                    Text("PREFERRED #\(preferred)")
                        .font(poster ? Display.font(20 * s) : Mono.font(14 * s, .bold)).tracking(1)
                        .foregroundStyle(Palette.posterInk)
                        .padding(.horizontal, 10 * s).padding(.vertical, 4 * s)
                        .background(Color(hex: "#F0525F"), in: RoundedRectangle(cornerRadius: 6 * s, style: .continuous))
                        .rotationEffect(.degrees(poster ? -3 : 0))
                }
            }
            .foregroundStyle(playing ? Palette.posterInk : .white)
            .padding(.horizontal, 24 * s)
            .frame(height: 96 * s)
            .frame(maxWidth: .infinity)
            .background(playing ? Palette.posterTeal : Palette.text(0.06),
                        in: RoundedRectangle(cornerRadius: 18 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18 * s, style: .continuous)
                .strokeBorder(playing ? Palette.posterTeal : Palette.text(0.16), lineWidth: 4 * s))
            .compositingGroup()
            .shadow(color: Palette.posterInk, radius: 0, x: playing && poster ? 6 * s : 0, y: playing && poster ? 6 * s : 0)
        }
        .buttonStyle(PanelRowStyle(cornerRadius: 18 * s))
        .panelFocus($focus, id)
        .disabled(switching)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 18 * s) {
            if let libraryName {
                Button(action: makeDefault) {
                    HStack(spacing: 12 * s) {
                        Image(systemName: savedAt == nil ? "checkmark" : "checkmark.seal.fill")
                            .font(.system(size: 22 * s, weight: .bold))
                        Text(savedAt == nil ? "MAKE THIS THE DEFAULT FOR \(libraryName.uppercased())" : "SAVED")
                            .font(poster ? Display.font(26 * s) : Typography.font(19 * s, .heavy)).tracking(1)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26 * s)
                    .frame(height: 64 * s)
                    .background(savedAt == nil ? Palette.posterInk.opacity(0.4) : Palette.posterTeal.opacity(0.35), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white, lineWidth: 4 * s))
                }
                .buttonStyle(FocusScaleStyle(cornerRadius: 999))
                .panelFocus($focus, "default")
                if device != .phone {
                    Text("SETTINGS → LIBRARIES → \(libraryName.uppercased()) → LANGUAGES")
                        .font(Mono.font(18 * s, .bold)).tracking(2)
                        .foregroundStyle(Palette.text(0.45))
                        .lineLimit(1)
                }
            }
        }
        .panelSection()
    }

    /// The pick becomes the library's first choice: the sound's language at
    /// the head of its list; the subtitles' language at the head of theirs
    /// with the mode set to on, or the mode set to off when they are off.
    private func makeDefault() {
        guard let libraryId else { return }
        var pref = appState.languagePreference(forLibrary: libraryId)
        if let code = LanguageTable.canonical(controller.currentAudioTrack?.language) {
            pref.audio = Array(([code] + pref.audio.filter { LanguageTable.canonical($0) != code }).prefix(LibraryLanguagePreference.slots))
        }
        if let subtitle = controller.currentSubtitleTrack {
            if let code = LanguageTable.canonical(subtitle.language) {
                pref.subtitles = Array(([code] + pref.subtitles.filter { LanguageTable.canonical($0) != code }).prefix(LibraryLanguagePreference.slots))
            }
            pref.subtitleMode = .on
        } else {
            pref.subtitleMode = .off
        }
        appState.setLanguagePreference(pref, forLibrary: libraryId)
        withAnimation(.easeOut(duration: 0.2)) { savedAt = Date() }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeOut(duration: 0.3)) { savedAt = nil }
        }
    }

    // MARK: - Labels

    private func rank(of language: String?, in list: [String]) -> Int? {
        guard let code = LanguageTable.canonical(language),
              let i = list.firstIndex(where: { LanguageTable.canonical($0) == code }) else { return nil }
        return i + 1
    }

    private func audioMeta(_ track: JellyfinAPI.MediaStream) -> String? {
        var parts: [String] = []
        if controller.isOriginalAudio(track) { parts.append("ORIGINAL") }
        if let codec = track.codec { parts.append(codec.uppercased()) }
        switch track.channels {
        case 8: parts.append("7.1")
        case 6: parts.append("5.1")
        case 2: parts.append("2.0")
        case 1: parts.append("MONO")
        default: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func subtitleName(_ track: JellyfinAPI.MediaStream) -> String {
        var name = track.languageLabel.uppercased()
        if track.isForced == true { name += " · FORCED" }
        return name
    }

    private func subtitleMeta(_ track: JellyfinAPI.MediaStream) -> String? {
        var parts: [String] = []
        if let codec = track.codec {
            switch codec.lowercased() {
            case "subrip": parts.append("SRT")
            case "pgssub": parts.append("PGS")
            case "dvdsub": parts.append("VOBSUB")
            case "mov_text": parts.append("MP4")
            default: parts.append(codec.uppercased())
            }
        }
        if track.isExternal == true { parts.append("EXTERNAL") }
        if track.isTextSubtitleStream == false { parts.append("BURNED IN") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A row's focus on the panel: lift and a white ring — teal is what
/// *playing* means here.
private struct PanelRowStyle: ButtonStyle {
    let cornerRadius: CGFloat
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration, cornerRadius: cornerRadius) }
    private struct Styled: View {
        @Environment(\.isFocused) private var focused
        let configuration: ButtonStyle.Configuration
        let cornerRadius: CGFloat
        var body: some View {
            configuration.label
                .overlay(RoundedRectangle(cornerRadius: cornerRadius + 6, style: .continuous)
                    .strokeBorder(.white, lineWidth: 5).padding(-6).opacity(focused ? 1 : 0))
                .scaleEffect(focused ? 1.03 : (configuration.isPressed ? 0.98 : 1))
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: focused)
        }
    }
}

private extension View {
    /// tvOS-only focus binding and sections — see `PlayerChrome.remoteFocus`
    /// for why focus is never bound on iOS inside the player.
    @ViewBuilder func panelFocus(_ focus: FocusState<String?>.Binding, _ id: String) -> some View {
        #if os(tvOS)
        self.focused(focus, equals: id)
        #else
        self
        #endif
    }
    @ViewBuilder func panelSection() -> some View {
        #if os(tvOS)
        self.focusSection()
        #else
        self
        #endif
    }
}
