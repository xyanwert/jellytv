import SwiftUI
import JellyTVKit

// The lit transport bar (design D2) and its readout — shared by both iPad
// detail screens. The Movie one fills it with how far you got; the Show one
// carries shuffle-everything and no fill, because a series has no single
// progress to draw. tvOS gets its own `TVNeonPlayBar` at the foot of the file.

#if os(iOS)

/// The one-sheet's whole action row as a single lit bar (design D2): the
/// control and the progress are the same object — how far you got is filled
/// into the bar, with a hot filament at its leading edge — and the playback
/// settings ride along its right side as a readout rather than as more
/// buttons.
///
/// The light is `NeonTube`, which is `LEDRing`'s recipe: the tube reads as
/// lit from inside, and the settings read as unlit glass until they carry a
/// value, so only what is actually on glows.
struct NeonTransportBar<Readout: View>: View {
    /// The glyph in the disc — `play.fill` for a movie, `shuffle` for a show.
    var icon: String = "play.fill"
    let label: String
    let sub: String
    let progress: Double
    let tint: Color
    var action: () -> Void = {}
    @ViewBuilder var readout: () -> Readout

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 7, style: .continuous) }

    var body: some View {
        HStack(spacing: 20) {
            Button(action: action) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(tint.opacity(0.14))
                        NeonTube(shape: Circle(), accent: tint, intensity: 0.62)
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(label)
                            .font(Typography.font(17, .heavy)).tracking(1.2)
                            .foregroundStyle(Palette.textPrimary)
                            .neonGlow(tint)
                        if !sub.isEmpty {
                            Text(sub)
                                .font(Mono.font(11, .bold)).tracking(1.5)
                                .foregroundStyle(tint.opacity(0.75))
                        }
                    }

                    // **Inside the button, not beside it.** The bar reads as
                    // one 78pt-tall control, but with this spacer outside the
                    // `Button` only the disc and its label caught a touch —
                    // roughly the leading third — and a press anywhere on the
                    // rest of it did nothing at all. Verified with real HID
                    // taps: the same tap at x=300 fires and at x=531 doesn't.
                    // Sweeping the free width into the label is what makes
                    // the whole bar the target it looks like.
                    Spacer(minLength: 12)
                }
                // The label block is the only painted thing here, so the rest
                // of the button's footprint needs a shape to catch a touch.
                .contentShape(Rectangle())
            }
            .buttonStyle(FocusScaleStyle(scale: 1.03, cornerRadius: 7))

            readout()
        }
        .padding(.horizontal, 22)
        .frame(height: 78)
        .background { barFill }
        // Deliberately not clipped: the tube's outer bloom belongs outside
        // the bar's own bounds — clipping it turns the lamp back into a border.
        .overlay { NeonTube(shape: shape, accent: tint) }
    }

    private var barFill: some View {
        ZStack(alignment: .leading) {
            shape.fill(Color(hex: "#061A21").opacity(0.55))
            GeometryReader { geo in
                ZStack(alignment: .trailing) {
                    LinearGradient(colors: [tint.opacity(0.30), tint.opacity(0.10)],
                                   startPoint: .leading, endPoint: .trailing)
                    if progress > 0 {
                        // Thin, and glowing less than the label it crosses:
                        // at a quarter of a column-width bar the filament
                        // lands right on "RESUME", and a hotter one read as
                        // a text cursor sitting in the word.
                        Rectangle().fill(Palette.textPrimary.opacity(0.9))
                            .frame(width: 1.5)
                            .neonGlow(tint, intensity: 0.7)
                    }
                }
                .frame(width: max(0, geo.size.width * progress))
            }
        }
        .clipShape(shape)
    }
}

/// One setting on the transport bar: its name stays unlit, its value lights up
/// — the row tells you what is on at a glance without another five buttons.
struct NeonReadoutItem: View {
    let label: String
    var value: String? = nil
    let tint: Color
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            // fixedSize, or the row compresses these into two-line stacks
            // ("AUDI/O") long before it runs out of bar.
            HStack(spacing: 6) {
                Text(label)
                    .font(Mono.font(11, .bold)).tracking(1.2)
                    .foregroundStyle(tint.opacity(0.42))
                    .fixedSize()
                if let value {
                    Text(value)
                        .font(Mono.font(11, .bold)).tracking(1.2)
                        .foregroundStyle(Palette.textPrimary)
                        .neonGlow(tint, intensity: 0.55)
                        .fixedSize()
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 6, outline: false))
    }
}
#endif

#if os(tvOS)
/// The one-sheet's Play button — **the same button as Home's Resume and the
/// show page's**, because that is what it should always have been.
///
/// What it replaced: an 84pt slab of the film's own colour with a glass top
/// and a shaded foot, a white disc with the glyph struck in the tint, a bloom
/// that breathed behind it, a band of light crossing its face every ~2.6s and
/// two rings pulsing out of the disc like a sonar ping — all driven by a
/// `TimelineView` ticking at 30fps for as long as it held focus. It was built
/// to be "the brightest thing on the page" and it was; it just belonged to no
/// other screen in the app, and read as a control borrowed from somewhere
/// else. The verdict was that the style didn't match, and it didn't.
///
/// It is now `HeroView.resumeButton` / `ShowView.tvHeroActions`: accent fill,
/// 14pt corners, `Typography.font(21, .heavy)`, the same accent shadow, the
/// same `FocusScaleStyle`. With three quiet things those don't have, **none
/// of which move**:
///
/// - a **vertical gradient** in the fill instead of a flat colour, so the
///   pill has some depth from across a room;
/// - a **hairline along the top inside edge**, which is what makes it read as
///   lit from above rather than printed on;
/// - and for a part-watched film **a rule along its foot** showing how far in
///   you are — the one genuinely useful thing the old slab did, and
///   information no other button in this app carries.
///
/// Nothing animates on focus beyond the shared `FocusScaleStyle`, and that is
/// the trade rather than an omission: the old bar avoided that style because
/// "two rings on one control fight", so taking the house ring means giving up
/// a second glow of its own, not stacking both.
///
/// **The fill is `theme.accent`, not the film's colour.** Matching the rest of
/// the app was the point; if the poster's own tint is ever wanted back here it
/// is this one property, not the shape around it.
struct TVNeonPlayBar: View {
    var icon: String = "play.fill"
    let label: String
    let sub: String
    let progress: Double
    /// Reads as "the widest of the row, but not the whole of it" — the same
    /// idiom as `HeroView.resumeButton`'s 220pt floor at its own size.
    var minWidth: CGFloat = 300
    var action: () -> Void = {}

    @EnvironmentObject private var theme: Theme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }
    private var clampedProgress: Double { min(max(progress, 0), 1) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 19, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(Typography.font(21, .heavy))
                        .lineLimit(1)
                    if !sub.isEmpty {
                        Text(sub)
                            .font(Mono.font(12, .bold)).tracking(1.3)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                // No trailing `Spacer` — that is the iPad bar's idiom, where
                // the whole width had to catch a *touch*. Given one here the
                // HStack takes the column's full width and the pill stretches
                // across it, which is the shape this button was just moved
                // away from. A remote has nothing to aim.
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 30)
            .padding(.vertical, sub.isEmpty ? 18 : 14)
            .frame(minWidth: minWidth, alignment: .leading)
            .background { surface }
            .shadow(color: theme.accent.opacity(0.45), radius: 24, y: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(FocusScaleStyle(scale: 1.05, cornerRadius: 14))
    }

    /// Fill, foot rule and top hairline, clipped once to the pill.
    private var surface: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [theme.accent.opacity(0.98), theme.accent.opacity(0.82)],
                           startPoint: .top, endPoint: .bottom)

            if clampedProgress > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(.white.opacity(0.85))
                        .frame(width: geo.size.width * clampedProgress, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }

            // Inset from the corners so it stops before the radius curves
            // away and doesn't leave two bright pixels hanging in the round.
            Rectangle()
                .fill(.white.opacity(0.22))
                .frame(height: 1)
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .clipShape(shape)
    }
}
#endif
