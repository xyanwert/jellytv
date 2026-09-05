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
/// The one-sheet's Play bar at TV size: **the brightest thing on the page**,
/// because it is the one thing the page exists for. A solid slab of the
/// film's own colour with a glass top and a shaded foot, a white disc with
/// the play glyph struck in the tint, and the label in whichever ink reads on
/// that colour. The **whole bar is the one button**.
///
/// Under the remote it comes alive — all of it transforms, gradients and a
/// `TimelineView` that ticks only while focused: a bloom behind the slab that
/// breathes, a band of light crossing the face every couple of seconds, and
/// rings pulsing out of the play disc like a sonar ping — *press me*. At rest
/// it is still the solid colour, just calm. A RESUME bar shades the unwatched
/// stretch and draws a white filament where you left off.
///
/// No readout: the iPad's TRAILER / AUDIO / SUBS / ＋LIST items are settings
/// this app doesn't have yet, and on a TV unlit glass nobody can select reads
/// as broken. The earlier outlined-tube version was calmer and, with the
/// readout gone, mostly empty — a lit outline around nothing.
struct TVNeonPlayBar: View {
    var icon: String = "play.fill"
    let label: String
    let sub: String
    let progress: Double
    let tint: Color
    var action: () -> Void = {}

    /// Ink or white on the film's colour, whichever reads.
    private var ink: Color { tint.luminance > 0.55 ? Color(hex: "#0C0F16") : .white }

    var body: some View {
        Button(action: action) {
            PlayBarLabel(icon: icon, label: label, sub: sub, tint: tint, ink: ink)
        }
        .buttonStyle(NeonBarFocusStyle(tint: tint, ink: ink, progress: progress))
    }
}

/// The disc, the label and the sub-line. The disc carries the sonar rings
/// itself (it knows focus through the environment), so the style needs no
/// hook into the label.
private struct PlayBarLabel: View {
    let icon: String
    let label: String
    let sub: String
    let tint: Color
    let ink: Color

    @Environment(\.isFocused) private var focused: Bool
    @State private var focusedAt = Date()

    var body: some View {
        HStack(spacing: 18) {
            disc
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(Typography.font(26, .black)).tracking(2.2)
                    .foregroundStyle(ink)
                if !sub.isEmpty {
                    Text(sub)
                        .font(Mono.font(13, .bold)).tracking(1.6)
                        .foregroundStyle(ink.opacity(0.72))
                }
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 22)
        .frame(height: 84)
        .contentShape(Rectangle())
        .onChange(of: focused, initial: true) { _, isFocused in
            if isFocused { focusedAt = Date() }
        }
    }

    /// A white disc, the glyph in the film's colour, and — while focused —
    /// two rings a half-beat apart expanding out of it and fading, 1.6s per
    /// ring, never past the bar's edge.
    private var disc: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !focused)) { context in
            let t = focused ? context.date.timeIntervalSince(focusedAt) : 0
            ZStack {
                if focused {
                    ring(phase: (t / 1.6).truncatingRemainder(dividingBy: 1))
                    ring(phase: ((t + 0.8) / 1.6).truncatingRemainder(dividingBy: 1))
                }
                Circle().fill(ink)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(tint)
                    .offset(x: icon == "play.fill" ? 2 : 0)
            }
            .frame(width: 54, height: 54)
        }
    }

    private func ring(phase: Double) -> some View {
        Circle()
            .stroke(ink.opacity((1 - phase) * 0.75), lineWidth: 2.5)
            .scaleEffect(1 + phase * 0.5)
    }
}

/// The slab and its light. Focus: a 6% lift, the bloom breathing behind,
/// the streak crossing, the white edge coming up. Deliberately not
/// `FocusScaleStyle`: this bar is its own ring of light, and two rings on one
/// control fight.
private struct NeonBarFocusStyle: ButtonStyle {
    let tint: Color
    let ink: Color
    let progress: Double

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, tint: tint, ink: ink, progress: progress)
    }

    private struct Content: View {
        @Environment(\.isFocused) private var focused: Bool
        @State private var focusedAt = Date()
        let configuration: ButtonStyle.Configuration
        let tint: Color
        let ink: Color
        let progress: Double

        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }
        /// A near-black dominant colour would make a slab you can't see lit;
        /// lift it just enough to read as a surface.
        private var lift: Double { tint.luminance < 0.12 ? 0.22 : 0 }

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !focused)) { context in
                let t = focused ? context.date.timeIntervalSince(focusedAt) : 0
                configuration.label
                    .background { lamp(at: t) }
                    // A crisp white edge, not `NeonTube`: the tube's wide
                    // inner glow was designed for dark glass, and on a solid
                    // slab it washed the top and bottom into a milky band.
                    .overlay {
                        shape.strokeBorder(.white.opacity(focused ? 0.85 : 0.35), lineWidth: 1.5)
                            .shadow(color: .white.opacity(focused ? 0.5 : 0), radius: 9)
                    }
                    .scaleEffect(focused ? 1.06 : (configuration.isPressed ? 0.98 : 1))
                    .shadow(color: tint.opacity(focused ? 0.6 : 0.3), radius: focused ? 30 : 14, y: 10)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: focused)
            .onChange(of: focused, initial: true) { _, isFocused in
                if isFocused { focusedAt = Date() }
            }
        }

        private func lamp(at t: TimeInterval) -> some View {
            ZStack {
                // The bloom: the bar's own colour thrown onto the page behind
                // it, breathing while focused.
                shape.fill(tint)
                    .padding(-4)
                    .blur(radius: 26)
                    .opacity(focused ? 0.42 + 0.14 * sin(t * 2.4) : 0)

                ZStack(alignment: .leading) {
                    // A little more saturated than the poster's own average,
                    // which for a skin-toned poster is a pale peach — the slab
                    // has to read as colour, not as tinted glass.
                    shape.fill(tint).saturation(1.2).brightness(lift)
                    // Glass top, shaded foot.
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0.22), location: 0),
                        .init(color: .white.opacity(0.04), location: 0.48),
                        .init(color: .black.opacity(0.03), location: 0.52),
                        .init(color: .black.opacity(0.34), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    if progress > 0 { remainder }
                    if focused { streak(at: t) }
                }
                .clipShape(shape)
            }
        }

        /// RESUME: the unwatched stretch in shadow, a white filament where
        /// you stopped.
        private var remainder: some View {
            GeometryReader { geo in
                let edge = geo.size.width * min(max(progress, 0), 1)
                Rectangle().fill(.black.opacity(0.34))
                    .frame(width: max(0, geo.size.width - edge))
                    .offset(x: edge)
                Rectangle().fill(ink.opacity(0.95))
                    .frame(width: 2)
                    .offset(x: edge - 1)
                    .neonGlow(ink, intensity: 0.8)
            }
        }

        /// A band of light crossing the face every ~2.6s.
        private func streak(at t: TimeInterval) -> some View {
            GeometryReader { geo in
                let phase = (t * 0.38).truncatingRemainder(dividingBy: 1)
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.32), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 120, height: geo.size.height * 2.4)
                    .rotationEffect(.degrees(22))
                    .offset(x: (CGFloat(phase) * 2.2 - 1.1) * geo.size.width + geo.size.width / 2 - 60,
                            y: -geo.size.height * 0.7)
                    .blendMode(.screen)
            }
        }
    }
}
#endif
