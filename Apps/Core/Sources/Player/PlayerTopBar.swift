import SwiftUI
import JellyTVKit

/// BACK and the item's tags on the left; AirPlay and Night on the right.
///
/// **BACK is the only word left in the control layer.** Everything else that
/// could be read from a glyph lost its label so the five transport circles
/// could be full size — the kicker line (`MOVIE · 1993 · PG-13`, plus the
/// queue position) went with it.
///
/// **The identity is no longer here.** The logo/title moved to the opposite
/// corner (`PlayerIdentityMark`) so the tag row gets the whole width of this
/// column instead of whatever a wordmark left over — this is the screen tags
/// are edited from, and it was showing four of them where it now shows eight.
///
/// The Night toggle is the only way in and out of Night mode, so it still
/// carries that mode's whole readout: how long the sleep timer has left, and
/// — while the lock is open — how long until it closes itself again.
struct PlayerTopBar: View {
    let item: PlayableItem?
    /// Live tags, not `item.tags` — a `PlayableItem` is built when the queue
    /// is, so it can't reflect a tag applied a minute ago from the panel.
    let tags: [String]
    let accent: Color
    let night: NightModeController
    let onBack: () -> Void
    let onToggleNight: () -> Void
    /// Non-nil when this account may edit tags; the row becomes the way into
    /// `PlayerTagsPanel`. Nil leaves the chips as a read-only display.
    var onEditTags: (() -> Void)?
    @FocusState.Binding var focus: PlayerFocusField?

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 20) {
                backButton
                tagRow
            }
            // Takes whatever the cluster on the right doesn't. That is what
            // gives `ViewThatFits` below a truthful width to measure against
            // — proposed the whole bar, it would happily fit eight chips
            // straight through the AirPlay button.
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 12) {
                    // iOS only. On tvOS the TV owns routing (there is no
                    // `AVRoutePickerView`), so this was an inert readout that
                    // said "SPEAKER" in exactly the clothes of the live Night
                    // button beside it — a control-shaped non-control, the
                    // same problem the SIGNAL/4K·HDR readout had before it
                    // went. Nothing to press, nothing it could tell a viewer
                    // on a TV they don't already know.
                    #if os(iOS)
                    AirPlayButton(accent: accent)
                    #endif
                    nightButton
                }
                if let nightCaption {
                    Text(nightCaption)
                        .font(Mono.font(12, .bold))
                        .tracking(1.6)
                        .foregroundStyle(NightPalette.amberBright.opacity(0.85))
                }
            }
            // Sized first, at its ideal — these are controls, and they never
            // give ground to a tag list however long it gets.
            .layoutPriority(1)
        }
    }

    /// Jellyfin's free-form `Tags`, as chips — and, where the account can
    /// edit them, the way into `PlayerTagsPanel`.
    ///
    /// **It renders even with no tags**, as a single ADD TAGS pill. An item
    /// with nothing on it is exactly the item you want to tag, and a control
    /// that only appears once the job is done is no control at all — v1 shipped
    /// that bug and had to fix it (`de310da` → `c4a472c`).
    @ViewBuilder
    private var tagRow: some View {
        if let onEditTags {
            Button(action: onEditTags) {
                chips
            }
            .buttonStyle(FocusScaleStyle(cornerRadius: 24))
            .remoteFocus($focus, equals: .tags)
            .accessibilityLabel(tags.isEmpty ? "Add tags"
                                             : "Tags: \(tags.joined(separator: ", ")). Edit.")
        } else if !tags.isEmpty {
            chips.accessibilityElement(children: .combine)
        }
    }

    /// **How many chips fit is measured, not assumed.**
    ///
    /// A fixed count can't work: "Drama" and "Watched before" are not the
    /// same width, and picking a number that suits one truncates the other.
    /// Capping at eight and letting SwiftUI compress produced a row of
    /// `Dr… Sp… Watc…` — chips that take the space of a tag while naming
    /// none. So the chips refuse to shrink (`fixedSize`) and `ViewThatFits`
    /// walks down from eight until a whole row genuinely fits the width the
    /// controls left over. Whatever that costs is *counted*, not dropped.
    private var chips: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Self.chipCounts, id: \.self) { count in
                chipRow(showing: count)
            }
        }
    }

    /// Descending, because `ViewThatFits` takes the first that fits.
    private static let chipCounts = [8, 7, 6, 5, 4, 3, 2, 1, 0]

    private func chipRow(showing count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tag")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.text(0.4))
            if tags.isEmpty {
                chip("ADD TAGS", mono: true)
            } else {
                ForEach(tags.prefix(count), id: \.self) { tag in
                    chip(tag, mono: false)
                }
                if tags.count > count {
                    chip("+\(tags.count - count)", mono: true)
                }
                // Only when the row is a control: a read-only row has nothing
                // to promise with a plus sign.
                if onEditTags != nil {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Palette.text(0.55))
                        .frame(width: 48, height: 48)
                        .background(Palette.text(0.10), in: Circle())
                        .overlay(Circle().stroke(Palette.text(0.16), lineWidth: 1))
                }
            }
        }
    }

    private func chip(_ text: String, mono: Bool) -> some View {
        Text(text)
            .font(mono ? Mono.font(16, .bold) : Typography.font(19, .bold))
            .tracking(mono ? 1.6 : 0)
            .foregroundStyle(Palette.text(mono ? 0.6 : 0.88))
            .lineLimit(1)
            // Never ellipsised: a chip narrower than its tag is worse than no
            // chip, because it occupies the row without naming anything.
            .fixedSize()
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(Palette.text(0.10), in: Capsule())
            .overlay(Capsule().stroke(Palette.text(0.16), lineWidth: 1))
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
