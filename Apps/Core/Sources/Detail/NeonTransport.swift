#if os(iOS)
import SwiftUI
import JellyTVKit

// The lit transport bar (design D2) and its readout — shared by both iPad
// detail screens. The Movie one fills it with how far you got; the Show one
// carries shuffle-everything and no fill, because a series has no single
// progress to draw.

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
                }
                // The label block is the only painted thing here, so the rest
                // of the button's footprint needs a shape to catch a touch.
                .contentShape(Rectangle())
            }
            .buttonStyle(FocusScaleStyle(scale: 1.03, cornerRadius: 7))

            Spacer(minLength: 12)

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
