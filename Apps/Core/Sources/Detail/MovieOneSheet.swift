import SwiftUI
import JellyTVKit

// Chrome for the Movie detail's "one sheet" layout (design 1b-onesheet), on
// iPad and — a size up — on tvOS: the poster is both the subject of the screen
// and the source of every colour on it.

/// The one-sheet's measurements that differ by viewing distance. A single
/// place, so the rail, the cast band and the info column stay in step.
enum OneSheetMetrics {
    #if os(tvOS)
    static let railLabelSize: CGFloat = 13
    static let railCellVerticalPadding: CGFloat = 16
    static let railCellGap: CGFloat = 28
    static let railDividerHeight: CGFloat = 58
    static let castHeaderSize: CGFloat = 13
    static let castPortrait: CGFloat = 84
    static let castLabelWidth: CGFloat = 156
    static let castSpacing: CGFloat = 28
    static let castStripHeight: CGFloat = 170
    #else
    static let railLabelSize: CGFloat = 12
    static let railCellVerticalPadding: CGFloat = 13
    static let railCellGap: CGFloat = 24
    static let railDividerHeight: CGFloat = 48
    static let castHeaderSize: CGFloat = 11
    static let castPortrait: CGFloat = 64
    static let castLabelWidth: CGFloat = 128
    static let castSpacing: CGFloat = 22
    static let castStripHeight: CGFloat = 122
    #endif
}

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
                .font(Typography.font(OneSheetMetrics.railLabelSize, .semibold)).tracking(2)
                .foregroundStyle(Palette.text(0.42))
            value()
        }
        .padding(.vertical, OneSheetMetrics.railCellVerticalPadding)
        .padding(.leading, first ? 0 : OneSheetMetrics.railCellGap)
        .padding(.trailing, OneSheetMetrics.railCellGap)
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
        Rectangle().fill(Palette.text(0.09)).frame(width: 1, height: OneSheetMetrics.railDividerHeight)
    }
}

/// The cast band across the foot of the one-sheet: full screen width, so names
/// and character names both fit without clipping. Scrolls on a narrower iPad
/// (or a long cast) rather than dropping anyone. Not focusable on tvOS — there
/// is no person page to go to, and a row of twelve focus stops between Play
/// and nothing would be twelve presses to get past.
struct CastBand: View {
    let cast: [CastMember]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("CAST")
                    .font(Mono.font(OneSheetMetrics.castHeaderSize, .bold)).tracking(2)
                    .foregroundStyle(Palette.text(0.45))
                Spacer(minLength: 12)
                Text("\(cast.count) CREDITED")
                    .font(Mono.font(OneSheetMetrics.castHeaderSize, .bold)).tracking(1.5)
                    .foregroundStyle(Palette.text(0.38))
            }
            .padding(.top, 22)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: OneSheetMetrics.castSpacing) {
                    ForEach(cast) { member in
                        CastAvatar(member: member, size: OneSheetMetrics.castPortrait,
                                   labelWidth: OneSheetMetrics.castLabelWidth)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: OneSheetMetrics.castStripHeight)
            .padding(.top, 14)
            .horizontalEdgeFade()
        }
        .overlay(alignment: .top) { Rectangle().fill(Palette.text(0.12)).frame(height: 1) }
    }
}
