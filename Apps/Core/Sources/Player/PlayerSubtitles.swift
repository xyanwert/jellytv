import SwiftUI
import JellyTVKit

/// Subtitles the app draws itself — design canvas "TV · Subtitles on the
/// picture": each line on its own ink plate, Schibsted at 800, a teal dash
/// where a speaker changes, centred above the TV's overscan and never wider
/// than the middle 1400pt. One look on a direct play and on a transcode,
/// because the lines come from the server as timed text
/// (`PlayerEngine.subtitleCues`) rather than from whatever AVPlayer would
/// render — which differs by route and can't be styled like this.
///
/// It reads the playhead straight off the player at 10 Hz
/// (`controller.preciseTime`); the chrome's 4 Hz clock is a quarter-second
/// late for a cue. Ticks only while there are lines to show.
struct PlayerSubtitleOverlay: View {
    let controller: PlayerController
    /// True while the chrome is up: the lines rise clear of the foot row.
    let lifted: Bool

    @EnvironmentObject private var theme: Theme

    private var device: DeviceClass { DeviceClass.current }
    private var fontSize: CGFloat { device == .tv ? 52 : (device == .phone ? 19 : 30) }
    private var bottom: CGFloat {
        let base: CGFloat = device == .tv ? 120 : (device == .phone ? 28 : 60)
        let lift: CGFloat = device == .tv ? 250 : (device == .phone ? 84 : 160)
        return base + (lifted ? lift : 0)
    }
    private var maxWidth: CGFloat { device == .tv ? 1400 : (device == .phone ? 620 : 900) }

    var body: some View {
        if !controller.subtitleCues.isEmpty {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let lines = SubtitleText.lines(of: SubtitleText.cue(at: controller.preciseTime, in: controller.subtitleCues))
                VStack(spacing: fontSize * 0.15) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        plate(line)
                    }
                }
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, bottom)
                .animation(.easeOut(duration: 0.18), value: lifted)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func plate(_ line: String) -> some View {
        let dash = line.hasPrefix("–") || line.hasPrefix("-") || line.hasPrefix("—")
        let body = dash ? String(line.dropFirst()).trimmingCharacters(in: .whitespaces) : line
        return (Text(dash ? "– " : "").foregroundStyle(theme.isPoster ? Palette.posterTeal : theme.accent)
                + Text(body).foregroundStyle(.white))
            .font(Typography.font(fontSize, .heavy))
            .multilineTextAlignment(.center)
            .lineSpacing(fontSize * 0.1)
            .padding(.horizontal, fontSize * 0.54)
            .padding(.vertical, fontSize * 0.16)
            .background(Palette.posterInk.opacity(0.78),
                        in: RoundedRectangle(cornerRadius: fontSize * 0.27, style: .continuous))
    }
}

/// The text side of a cue: which line is on at a moment, and a raw cue's
/// text as clean lines. Jellyfin flattens srt/ass/mov_text to plain text but
/// leaves `<i>`, `<b>`, `<font>` and ASS `{\an8}` tags in; those go, and
/// `\N` / `<br>` become line breaks.
enum SubtitleText {
    static func cue(at time: Double, in cues: [JellyfinAPI.SubtitleCue]) -> JellyfinAPI.SubtitleCue? {
        // Binary search for the last cue starting at or before `time`, then
        // walk back a couple in case an overlapping earlier cue is still on.
        var low = 0, high = cues.count - 1, found = -1
        while low <= high {
            let mid = (low + high) / 2
            if cues[mid].start <= time { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        guard found >= 0 else { return nil }
        for i in stride(from: found, through: max(0, found - 3), by: -1) where cues[i].end > time {
            return cues[i]
        }
        return nil
    }

    private static let tags = try! NSRegularExpression(pattern: "<[^>]+>|\\{\\\\[^}]*\\}", options: [])

    static func lines(of cue: JellyfinAPI.SubtitleCue?) -> [String] {
        guard let cue else { return [] }
        var text = cue.text
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        text = tags.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// The language check: the moment a video starts, what it chose — the
/// sound and the subtitles — as two stickers top-right, gone after three
/// seconds. Says "automatic" when the subtitles came on by the library's
/// smart rule or a forced track, so a surprise has its reason on it.
struct PlayerLanguageCheck: View {
    let controller: PlayerController
    let accent: Color

    @EnvironmentObject private var theme: Theme

    private var s: CGFloat { DeviceClass.current == .tv ? 1 : (DeviceClass.current == .phone ? 0.5 : 0.7) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10 * s) {
            if let audio = controller.currentAudioTrack {
                sticker(icon: "speaker.wave.2.fill", label: audio.languageLabel.uppercased(),
                        tag: channels(audio), primary: true)
            }
            sticker(icon: nil, label: controller.currentSubtitleTrack.map { $0.languageLabel.uppercased() } ?? "OFF",
                    tag: controller.trackChoice.subtitleIsAutomatic ? "AUTO" : nil, primary: false)
        }
        .rotationEffect(.degrees(theme.isPoster ? -2 : 0))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 76 * s)
        .padding(.trailing, 88 * s)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private func channels(_ stream: JellyfinAPI.MediaStream) -> String? {
        switch stream.channels {
        case 8: return "7.1"
        case 6: return "5.1"
        case 2: return "2.0"
        case 1: return "MONO"
        default: return nil
        }
    }

    @ViewBuilder
    private func sticker(icon: String?, label: String, tag: String?, primary: Bool) -> some View {
        let poster = theme.isPoster
        HStack(spacing: 14 * s) {
            if let icon {
                Image(systemName: icon).font(.system(size: 26 * s, weight: .bold))
            } else {
                Text("CC")
                    .font(Display.font(22 * s)).tracking(1)
                    .padding(.horizontal, 8 * s).padding(.vertical, 2 * s)
                    .overlay(RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                        .strokeBorder(poster ? Palette.posterInk : .white, lineWidth: 3 * s))
            }
            Text(label).font(poster ? Display.font(30 * s) : Typography.font(24 * s, .black)).tracking(1)
            if let tag {
                Text(tag)
                    .font(Mono.font(18 * s, .bold)).tracking(1)
                    .padding(.horizontal, 8 * s).padding(.vertical, 4 * s)
                    .background(poster ? Palette.posterInk : Color.white.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 6 * s, style: .continuous))
                    .foregroundStyle(.white)
            }
        }
        .foregroundStyle(poster ? Palette.posterInk : .white)
        .padding(.horizontal, 22 * s)
        .frame(height: 62 * s)
        .background(poster ? (primary ? Color.white : Palette.posterTeal) : Color.black.opacity(0.62),
                    in: RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12 * s, style: .continuous)
            .strokeBorder(poster ? .clear : (primary ? accent : Palette.text(0.2)), lineWidth: 2))
        .compositingGroup()
        .shadow(color: poster ? Palette.posterInk : .black.opacity(0.4), radius: poster ? 0 : 16,
                x: poster ? 6 * s : 0, y: poster ? 6 * s : 6)
    }
}
