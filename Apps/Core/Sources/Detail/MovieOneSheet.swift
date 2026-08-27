#if os(iOS)
import SwiftUI
import JellyTVKit

// iPad-only chrome for the Movie detail's "one sheet" layout (design
// 1b-onesheet): the poster is both the subject of the screen and the source
// of every colour on it.

/// The screen's colour field, thrown off the poster itself: the same image,
/// heavily defocused and desaturated back down by the scrims, plus two washes
/// in the poster's own dominant hue and a vignette to hold the edges.
///
/// Rendered 1.3× and clipped so the blur has pixels to sample past the frame
/// (blurring an exactly-sized image feathers its edges into the page).
struct PosterBloom: View {
    let image: String?
    let artwork: Artwork
    /// The poster's dominant colour — see `DominantColor`. Falls back to the
    /// app accent until the extraction lands.
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Palette.page
                art
                    .frame(width: geo.size.width * 1.3, height: geo.size.height * 1.3)
                    .clipped()
                    .blur(radius: 90, opaque: true)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .saturation(1.2)
                    .opacity(0.45)

                // A bright, saturated poster (animation, comedy) otherwise
                // shouts over the whole column; a dark one barely registers.
                // The veil levels both to the same ground.
                Palette.page.opacity(0.34)

                RadialGradient(colors: [tint.opacity(0.20), .clear],
                               center: .init(x: 0.76, y: 0.16), startRadius: 0, endRadius: 900)
                RadialGradient(colors: [tint.opacity(0.14), .clear],
                               center: .init(x: 0.08, y: 0.86), startRadius: 0, endRadius: 820)
                RadialGradient(colors: [.clear, Palette.page.opacity(0.86)],
                               center: .center, startRadius: 300, endRadius: 980)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var art: some View {
        if let image, image.hasPrefix("http"), let url = URL(string: image) {
            JellyfinAsyncImage(url: url, fallback: artwork.gradient)
        } else if let image {
            Image(image).resizable().scaledToFill()
        } else {
            artwork.gradient
        }
    }
}

/// The poster presented as a physical object rather than a panel: hard edge,
/// hairline, a raking sheen across it and a long shadow that lifts it off the
/// colour field behind. Sized by height — the width follows at 2:3 — so the
/// layout can shrink it to whatever the device leaves.
struct OneSheetPoster: View {
    let image: String?
    let artwork: Artwork
    let height: CGFloat

    static func width(for height: CGFloat) -> CGFloat { (height * 2 / 3).rounded() }
    private var width: CGFloat { Self.width(for: height) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }

    var body: some View {
        art
            .frame(width: width, height: height)
            .clipped()
            .clipShape(shape)
            .overlay { sheen }
            .overlay { shape.stroke(.white.opacity(0.11), lineWidth: 1) }
            .shadow(color: .black.opacity(0.80), radius: 46, y: 30)
            .shadow(color: .black.opacity(0.50), radius: 12, y: 6)
    }

    @ViewBuilder private var art: some View {
        if let image, image.hasPrefix("http"), let url = URL(string: image) {
            JellyfinAsyncImage(url: url, fallback: artwork.gradient)
        } else if let image {
            Image(image).resizable().scaledToFill()
        } else {
            artwork.gradient
        }
    }

    private var sheen: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.16), location: 0.0),
                .init(color: .white.opacity(0.02), location: 0.26),
                .init(color: .clear, location: 0.62),
                .init(color: .white.opacity(0.06), location: 1.0),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

/// One cell of the one-sheet's metadata rail.
struct RailCell<Value: View>: View {
    let label: String
    var first: Bool = false
    @ViewBuilder var value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Typography.font(12, .semibold)).tracking(2)
                .foregroundStyle(Palette.text(0.42))
            value()
        }
        .padding(.vertical, 13)
        .padding(.leading, first ? 0 : 24)
        .padding(.trailing, 24)
    }
}

/// The 2×2 `SpecSheet` folded into a single hairline row — the one-sheet
/// spends its height on the poster, so metadata gets one band and no more.
struct HairlineRail<A: View, B: View, C: View, D: View>: View {
    @ViewBuilder var first: () -> A
    @ViewBuilder var second: () -> B
    @ViewBuilder var third: () -> C
    @ViewBuilder var fourth: () -> D

    var body: some View {
        HStack(spacing: 0) {
            first(); divider; second(); divider; third(); divider; fourth()
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .top) { Rectangle().fill(Palette.text(0.14)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.text(0.09)).frame(height: 1) }
    }

    private var divider: some View {
        Rectangle().fill(Palette.text(0.09)).frame(width: 1, height: 48)
    }
}

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
                        Image(systemName: "play.fill")
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

/// The cast band across the foot of the one-sheet: full screen width, so names
/// and character names both fit without clipping. Scrolls on a narrower iPad
/// (or a long cast) rather than dropping anyone.
struct CastBand: View {
    let cast: [CastMember]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("CAST")
                    .font(Mono.font(11, .bold)).tracking(2)
                    .foregroundStyle(Palette.text(0.45))
                Spacer(minLength: 12)
                Text("\(cast.count) CREDITED")
                    .font(Mono.font(11, .bold)).tracking(1.5)
                    .foregroundStyle(Palette.text(0.38))
            }
            .padding(.top, 22)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(cast) { member in
                        CastAvatar(member: member, size: 64, labelWidth: 128)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 122)
            .padding(.top, 14)
            .horizontalEdgeFade()
        }
        .overlay(alignment: .top) { Rectangle().fill(Palette.text(0.12)).frame(height: 1) }
    }
}
#endif
