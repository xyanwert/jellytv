import SwiftUI
import JellyTVKit

/// Back pill + mono season/episode/queue readout + title, left-aligned;
/// an inert cast glyph (visual only this pass — no AirPlay wiring, matching
/// the detail screens' inert `EN·5.1`/`CC·OFF` pills) and the Night toggle,
/// right-aligned. The tags row from the design stays hidden per the
/// confirmed scope (interactive tags are Phase 3).
///
/// The Night toggle is the only way in and out of Night mode, so it carries
/// that mode's whole readout: how long the sleep timer has left, and — while
/// the lock is open — how long until it closes itself again.
struct PlayerTopBar: View {
    let item: PlayableItem?
    let queuePositionLabel: String?
    let accent: Color
    let night: NightModeController
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
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 12) {
                    castGlyph
                    nightButton
                }
                if let nightCaption {
                    Text(nightCaption)
                        .font(Mono.font(12, .bold))
                        .tracking(1.6)
                        .foregroundStyle(NightPalette.amberBright.opacity(0.85))
                }
            }
        }
    }

    /// The line under the toggle — only ever says something Night mode is
    /// about to *do*, so it's absent whenever nothing is pending.
    private var nightCaption: String? {
        switch night.phase {
        case .off:
            return nil
        case .ended:
            return "SLEEP TIMER ENDED"
        case .running:
            guard let seconds = night.relockRemaining else { return nil }
            return "RE-LOCKS IN \(Int(seconds.rounded(.up)))s"
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

    /// Off it reads `Night OFF`; on, the chip becomes the sleep timer's own
    /// countdown, so the one control both switches the mode and reports it.
    private var nightChip: String {
        switch night.phase {
        case .off: return "OFF"
        case .running: return SleepTimer.remainingLabel(night.remaining)
        case .ended: return "ENDED"
        }
    }

    private var nightButton: some View {
        let on = night.isOn
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button(action: onToggleNight) {
            HStack(spacing: 12) {
                Image(systemName: on ? "moon.zzz.fill" : "moon")
                    .font(.system(size: 22, weight: .semibold))
                Text("Night")
                    .font(Typography.font(18, .heavy))
                Text(nightChip)
                    .font(Mono.font(13, .bold))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(on ? Color.black.opacity(0.25) : Palette.text(0.1),
                                in: RoundedRectangle(cornerRadius: 6))
            }
            .foregroundStyle(on ? NightPalette.ink : Palette.text(0.9))
            .padding(.horizontal, 22)
            .frame(height: 62)
            .background(on ? NightPalette.amber : Color.black.opacity(0.4), in: shape)
            .overlay(shape.stroke(on ? NightPalette.amberBright : Palette.text(0.14), lineWidth: 1))
            // The lit bar's language (`NeonTube`) marking a live mode rather
            // than a focused control — iOS only, where nothing else is
            // already drawing a ring around this button.
            #if os(iOS)
            .overlay { if on { NeonTube(shape: shape, accent: NightPalette.amberBright, intensity: 0.55) } }
            #endif
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: 18))
        .remoteFocus($focus, equals: .night)
    }
}
