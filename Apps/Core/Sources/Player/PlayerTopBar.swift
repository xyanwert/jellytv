import SwiftUI
import JellyTVKit

/// Back pill + mono season/episode/queue readout + title, left-aligned;
/// an inert cast glyph (visual only this pass — no AirPlay wiring, matching
/// the detail screens' inert `EN·5.1`/`CC·OFF` pills) and the Night toggle,
/// right-aligned. The tags row from the design stays hidden per the
/// confirmed scope (interactive tags are Phase 3).
struct PlayerTopBar: View {
    let item: PlayableItem?
    let queuePositionLabel: String?
    let accent: Color
    let nightMode: Bool
    let onBack: () -> Void
    let onToggleNight: () -> Void
    @FocusState.Binding var focus: PlayerFocusField?

    /// `Episode.asPlayableItem` bakes the subtitle as `"S1 · E4 — \"Title\""`
    /// — split it here into the mono kicker and the quoted episode title so
    /// the top bar can lay them out the way the design does (kicker on its
    /// own line, title merged into the big headline).
    private var kicker: String? {
        guard let subtitle = item?.subtitle, let range = subtitle.range(of: " — ") else { return nil }
        return String(subtitle[..<range.lowerBound])
    }

    private var episodeTitleSuffix: String? {
        guard let subtitle = item?.subtitle, let range = subtitle.range(of: " — ") else { return nil }
        return String(subtitle[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 16) {
                backButton
                if kicker != nil || queuePositionLabel != nil {
                    kickerReadout
                }
                titleText
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                castGlyph
                nightButton
            }
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 12) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                Text("BACK")
                    .font(Typography.font(20, .heavy))
            }
            .foregroundStyle(.white)
            .padding(.leading, 20)
            .padding(.trailing, 26)
            .padding(.vertical, 14)
            .background(accent, in: Capsule())
            .shadow(color: accent.opacity(0.4), radius: 20, y: 8)
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: 30))
        .remoteFocus($focus, equals: .back)
    }

    private var kickerReadout: some View {
        HStack(spacing: 8) {
            if let kicker {
                Text(kicker.uppercased())
                    .foregroundStyle(accent)
                if queuePositionLabel != nil {
                    Text("·").foregroundStyle(Palette.text(0.3))
                }
            }
            if let queuePositionLabel {
                Text("QUEUE \(queuePositionLabel)")
                    .foregroundStyle(Palette.text(0.5))
            }
        }
        .font(Mono.font(15, .bold))
        .tracking(2)
    }

    private var titleText: some View {
        Group {
            if let suffix = episodeTitleSuffix {
                Text(item?.title ?? "").foregroundStyle(Palette.textPrimary)
                    + Text(" — ").foregroundStyle(Palette.textPrimary)
                    + Text(suffix).foregroundStyle(Palette.text(0.55))
            } else {
                Text(item?.title ?? "").foregroundStyle(Palette.textPrimary)
            }
        }
        .font(Typography.font(40, .black))
        .lineLimit(1)
        .shadow(color: .black.opacity(0.6), radius: 16, y: 2)
    }

    private var castGlyph: some View {
        Image(systemName: "airplayvideo")
            .font(.system(size: 27, weight: .semibold))
            .foregroundStyle(Palette.text(0.9))
            .frame(width: 62, height: 62)
            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.text(0.14), lineWidth: 1))
    }

    private var nightButton: some View {
        Button(action: onToggleNight) {
            HStack(spacing: 12) {
                Image(systemName: nightMode ? "moon.fill" : "moon")
                    .font(.system(size: 22, weight: .semibold))
                Text("Night")
                    .font(Typography.font(18, .heavy))
                Text(nightMode ? "ON" : "OFF")
                    .font(Mono.font(13, .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(nightMode ? Color.black.opacity(0.25) : Palette.text(0.1),
                                in: RoundedRectangle(cornerRadius: 6))
            }
            .foregroundStyle(nightMode ? Color(hex: "#1A0E02") : Palette.text(0.9))
            .padding(.horizontal, 22)
            .frame(height: 62)
            .background(nightMode ? Color(OKLCH(l: 0.55, c: 0.13, h: 55)) : Color.black.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(nightMode ? Color(OKLCH(l: 0.62, c: 0.14, h: 55)) : Palette.text(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: 18))
        .remoteFocus($focus, equals: .night)
    }
}
