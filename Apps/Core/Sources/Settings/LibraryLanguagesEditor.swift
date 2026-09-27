import SwiftUI
import JellyTVKit

/// Settings → Libraries → a library → Languages: three slots for the sound,
/// three for the subtitles, each in order of preference, and whether
/// subtitles start on. What the player checks every time a video from this
/// library starts (`TrackPicker`).
///
/// A slot is a button naming its language (in that language's own
/// spelling) or "—"; pressing one opens the ten languages as chips under
/// the row, with CLEAR. Ten, not thirty: a row of chips is a picker, a
/// scroll of them is a chore.
struct LibraryLanguagesEditor: View {
    let libraryId: String
    let libraryName: String

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: Theme
    /// Which slot is open for picking — "audio:0" … "subtitles:2".
    @State private var openSlot: String?

    private var preference: LibraryLanguagePreference { appState.languagePreference(forLibrary: libraryId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailRow(label: "Sound", description: "The first of these the video has is what plays") {
                slots(kind: "audio", codes: preference.audio)
            }
            if openSlot?.hasPrefix("audio") == true { chips }
            DetailDivider()
            DetailRow(label: "Subtitles", description: "In order — the first the video has") {
                slots(kind: "subtitles", codes: preference.subtitles)
            }
            if openSlot?.hasPrefix("subtitles") == true { chips }
            DetailDivider()
            DetailRow(label: "Subtitles start", description: modeDescription) {
                SegmentedControl(options: Self.modeLabels.map(\.1),
                                 selection: Binding(
                                    get: { Self.modeLabels.first { $0.0 == preference.subtitleMode }?.1 ?? "Off" },
                                    set: { label in
                                        var pref = preference
                                        pref.subtitleMode = Self.modeLabels.first { $0.1 == label }?.0 ?? .off
                                        appState.setLanguagePreference(pref, forLibrary: libraryId)
                                    }))
            }
        }
    }

    private static let modeLabels: [(SubtitleMode, String)] = [(.on, "On"), (.off, "Off"), (.smart, "When needed")]

    private var modeDescription: String {
        switch preference.subtitleMode {
        case .on: return "Always, in the first language above the video has"
        case .off: return "Never — only a forced track in the sound's own language"
        case .smart: return "Only when the sound isn't one of your languages (the anime rule)"
        }
    }

    private func slots(kind: String, codes: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<LibraryLanguagePreference.slots, id: \.self) { i in
                let id = "\(kind):\(i)"
                let code = i < codes.count ? codes[i] : nil
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { openSlot = openSlot == id ? nil : id }
                } label: {
                    HStack(spacing: 8) {
                        Text("\(i + 1)")
                            .font(Mono.font(13, .bold))
                            .foregroundStyle(Palette.text(0.4))
                        Text(code.map { LanguageTable.endonym(for: $0) } ?? "—")
                            .font(Typography.font(17, .bold))
                            .foregroundStyle(code == nil ? Palette.text(0.35) : Palette.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(minWidth: 118)
                    .background(openSlot == id ? theme.accent.opacity(0.25) : Palette.text(0.06),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(openSlot == id ? theme.accent : Palette.text(0.12), lineWidth: 1.5))
                }
                .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 10))
                .accessibilityLabel("\(kind == "audio" ? "Sound" : "Subtitle") language \(i + 1): \(code.map { LanguageTable.endonym(for: $0) } ?? "none")")
            }
        }
    }

    /// The ten languages plus CLEAR, for the open slot. Picking one already
    /// in another slot swaps it out of there, so a list never holds a
    /// language twice.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LanguageTable.all) { language in
                    chip(language.endonym, selected: current == language.code) { set(language.code) }
                }
                chip("Clear", selected: false) { set(nil) }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, -6)
        .padding(.bottom, 10)
        .transition(.opacity)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private var current: String? {
        guard let openSlot else { return nil }
        let parts = openSlot.split(separator: ":")
        guard parts.count == 2, let i = Int(parts[1]) else { return nil }
        let list = parts[0] == "audio" ? preference.audio : preference.subtitles
        return i < list.count ? LanguageTable.canonical(list[i]) : nil
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Typography.font(16, .bold))
                .foregroundStyle(selected ? Palette.screen : Palette.text(0.8))
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(selected ? Color.white : Palette.text(0.07), in: Capsule())
                .overlay(Capsule().stroke(selected ? .clear : Palette.text(0.14), lineWidth: 1.5))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.08, cornerRadius: 999))
    }

    private func set(_ code: String?) {
        guard let openSlot else { return }
        let parts = openSlot.split(separator: ":")
        guard parts.count == 2, let i = Int(parts[1]) else { return }
        var pref = preference
        var list = parts[0] == "audio" ? pref.audio : pref.subtitles
        if let code { list.removeAll { LanguageTable.canonical($0) == code } }
        if i < list.count {
            if let code { list[i] = code } else { list.remove(at: i) }
        } else if let code {
            list.append(code)
        }
        list = Array(list.prefix(LibraryLanguagePreference.slots))
        if parts[0] == "audio" { pref.audio = list } else { pref.subtitles = list }
        appState.setLanguagePreference(pref, forLibrary: libraryId)
        withAnimation(.easeOut(duration: 0.2)) { self.openSlot = nil }
    }
}
