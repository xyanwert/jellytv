import SwiftUI
import JellyTVKit

/// BACK, the item's identity, and its tags on the left; AirPlay and Night on
/// the right.
///
/// **BACK is the only word left in the control layer.** Everything else that
/// could be read from a glyph lost its label so the five transport circles
/// could be full size — the kicker line (`MOVIE · 1993 · PG-13`, plus the
/// queue position) went with it.
///
/// **Where the item has logo artwork, that artwork *is* the title.** Jellyfin
/// serves it at `/Items/{id}/Images/Logo`; a title already set as art beats
/// the same words in the UI font. Plain type is the fallback, and only the
/// fallback — see `PlayableItem.logoURL`.
///
/// The Night toggle is the only way in and out of Night mode, so it still
/// carries that mode's whole readout: how long the sleep timer has left, and
/// — while the lock is open — how long until it closes itself again.
struct PlayerTopBar: View {
    let item: PlayableItem?
    let accent: Color
    let night: NightModeController
    let onBack: () -> Void
    let onToggleNight: () -> Void
    @FocusState.Binding var focus: PlayerFocusField?

    /// Tall enough to read as artwork, capped so a wide logo can't push the
    /// tags row off its line.
    private static let logoMaxHeight: CGFloat = 96
    private static let logoMaxWidth: CGFloat = 520

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 20) {
                backButton
                identity
                if let tags = item?.tags, !tags.isEmpty {
                    tagRow(tags)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 12) {
                    AirPlayButton(accent: accent)
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

    // MARK: - Identity

    /// Logo artwork when the server has it, the title in type when it does
    /// not.
    ///
    /// Deliberately a bare `AsyncImage` rather than the shared
    /// `JellyfinAsyncImage`: that component's contract is "fill this rect
    /// with art, or with a gradient" — both halves wrong here. A logo has to
    /// *fit* (filling crops the wordmark), and its fallback is the title in
    /// type, never a coloured rectangle. The URL is one of Jellyfin's
    /// token-less image endpoints, so it needs no auth wrapper either way.
    @ViewBuilder
    private var identity: some View {
        if let logo = item?.logoURL, let url = URL(string: logo) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: Self.logoMaxWidth, maxHeight: Self.logoMaxHeight,
                               alignment: .leading)
                        .shadow(color: .black.opacity(0.7), radius: 18, y: 2)
                        .accessibilityLabel(item?.title ?? "")
                default:
                    // Never a spinner and never a placeholder box: a logo
                    // still in flight, or one that fails, reads as the title
                    // — not as a hole where the title goes.
                    titleText
                }
            }
            .frame(height: Self.logoMaxHeight, alignment: .leading)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(item?.title ?? "")
            .font(Typography.font(40, .black))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .shadow(color: .black.opacity(0.6), radius: 16, y: 2)
    }

    /// Jellyfin's free-form `Tags`, as chips. Display only this pass —
    /// interactive tags (tap a tag, get that tag's library search) are a
    /// separate piece of work; nothing here pretends to be tappable.
    private func tagRow(_ tags: [String]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tag")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.text(0.4))
            ForEach(tags.prefix(4), id: \.self) { tag in
                Text(tag)
                    .font(Typography.font(19, .bold))
                    .foregroundStyle(Palette.text(0.88))
                    .lineLimit(1)
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .background(Palette.text(0.10), in: Capsule())
                    .overlay(Capsule().stroke(Palette.text(0.16), lineWidth: 1))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Controls

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

    /// Off it reads `OFF`; on, it becomes the sleep timer's own countdown, so
    /// the one control both switches the mode and reports it. The word
    /// "Night" is gone with every other label — the moon carries it.
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
                    .font(.system(size: 24, weight: .semibold))
                Text(nightChip)
                    .font(Mono.font(15, .bold))
                    .tracking(0.8)
                    .monospacedDigit()
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
        .accessibilityLabel("Night mode — \(nightChip)")
    }
}
