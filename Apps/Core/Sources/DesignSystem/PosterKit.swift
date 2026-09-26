import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Poster Mode's parts (`AppStyle.poster`): the pieces an anime key visual is
// built from, kept here so every screen draws them the same way. None of them
// replaces a Classic foundation — backdrops, the hero crumble and the focus
// engine's behaviour are shared — they are drawn over and around it.
//
// Performance note for tvOS: everything here is static (no clocks), and the
// two full-screen textures (`PosterPaper`, `PosterStripeBand`) are one
// `Canvas` each, flattened with `drawingGroup()`, so they cost one layer
// rather than thousands of views.

// MARK: - Grounds

/// Dotted grid paper. `ink` draws the night version (dark dots on ink) used by
/// Search; the default is dark dots on a light ground, meant as a *texture*
/// over art at low opacity or as the full ground of a paper screen.
struct PosterPaper: View {
    var dotColor: Color = Palette.posterInk.opacity(0.14)
    var spacing: CGFloat = DeviceClass.current == .tv ? 30 : 22
    var radius: CGFloat = DeviceClass.current == .tv ? 1.6 : 1.2

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    x += spacing
                }
                y += spacing
            }
            ctx.fill(path, with: .color(dotColor))
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The ink band with fine diagonal hatching that rows and credits sit on.
struct PosterStripeBand: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "#111216")))
            var path = Path()
            let step: CGFloat = 14
            var x = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            ctx.stroke(path, with: .color(Color(hex: "#1B1C22")), lineWidth: 7)
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The paired teal/coral diagonal stripes that sit at an edge or corner —
/// never behind text.
struct PosterAccentStripes: View {
    var angle: Angle = .degrees(-32)
    var length: CGFloat = 900
    var scale: CGFloat = DeviceClass.current == .tv ? 1 : 0.62

    var body: some View {
        VStack(alignment: .leading, spacing: 14 * scale) {
            Rectangle().fill(Palette.posterTeal).frame(width: length, height: 24 * scale)
            Rectangle().fill(Color(hex: "#F0525F")).frame(width: length, height: 9 * scale)
        }
        .rotationEffect(angle)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Type

/// A title set enormous and faint behind the figure it names — the "EDGE
/// RUNNERS" behind Lucy. Pure decoration: hidden from accessibility and
/// hit-testing, one line, shrinking rather than wrapping.
///
/// Over art it is *blended*, not painted: `.overlay` lifts the lights and
/// deepens the darks of whatever is beneath, so the letters read as printed
/// into the picture — a flat translucent grey would sit on top of it instead.
/// A blend is plain compositing (no shader), so it is free on the TV.
struct PosterGhostTitle: View {
    let text: String
    var size: CGFloat
    var color: Color = .white.opacity(0.42)
    var blend: BlendMode = .overlay

    var body: some View {
        // Runs off the edge and is cut there, the way a poster crops its own
        // type — never an ellipsis. It sits in backgrounds and overlays, so
        // its natural width never widens a layout.
        Text(text.uppercased())
            .font(Display.font(size))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .blendMode(blend)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Stickers

/// The sticker name tag: the name in its own colour on white, the qualifier on
/// an ink bar beneath, the pair tilted like it was slapped on. Used for titles
/// on posters, people in lineups and the hero's eyebrow.
struct PosterStickerTag: View {
    let name: String
    var sub: String? = nil
    var nameColor: Color = Palette.posterInk
    var size: CGFloat = DeviceClass.current == .tv ? 40 : 24
    var tilt: Angle = .degrees(-3)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name.uppercased())
                .font(Display.font(size))
                .foregroundStyle(nameColor)
                .lineLimit(1)
                // A long name shrinks to its tag rather than running into the
                // neighbours' (the caller caps the width).
                .minimumScaleFactor(0.55)
                .padding(.horizontal, size * 0.34)
                .padding(.vertical, size * 0.1)
                .background(Color.white, in: UnevenRoundedRectangle(
                    topLeadingRadius: size * 0.2, bottomLeadingRadius: sub == nil ? size * 0.2 : 0,
                    bottomTrailingRadius: size * 0.2, topTrailingRadius: size * 0.2, style: .continuous))
            if let sub, !sub.isEmpty {
                Text(sub.uppercased())
                    .font(Display.font(size * 0.58))
                    .tracking(1)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, size * 0.34)
                    .padding(.vertical, size * 0.08)
                    .background(Palette.posterInk, in: UnevenRoundedRectangle(
                        topLeadingRadius: 0, bottomLeadingRadius: size * 0.2,
                        bottomTrailingRadius: size * 0.2, topTrailingRadius: 0, style: .continuous))
            }
        }
        .rotationEffect(tilt)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

/// A small ink chip: "PG-13", "2021", "4K". Poster Mode's metadata badge.
struct PosterChip: View {
    let text: String
    var inverted = false
    var size: CGFloat = DeviceClass.current == .tv ? 24 : 15

    var body: some View {
        Text(text.uppercased())
            .font(Display.font(size))
            .tracking(0.8)
            .foregroundStyle(inverted ? Palette.posterInk : Palette.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, size * 0.55)
            .padding(.vertical, size * 0.18)
            .background(inverted ? Color.white : Palette.posterInk.opacity(0.78),
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

// MARK: - Buttons

/// The arrow pill: a label in the display face with a round disc at its
/// trailing end. The primary action wears it white on ink art; `inverted`
/// gives the ink-on-paper version. The disc carries a play glyph or an arrow.
struct PosterArrowPill: View {
    let title: String
    var detail: String? = nil
    var systemImage = "play.fill"
    var inverted = false
    var discColor: Color? = nil
    var fullWidth = false

    private var height: CGFloat { DeviceClass.current == .tv ? 84 : 52 }
    private var fontSize: CGFloat { DeviceClass.current == .tv ? 34 : 20 }

    var body: some View {
        HStack(spacing: height * 0.24) {
            HStack(spacing: height * 0.16) {
                Text(title.uppercased()).font(Display.font(fontSize))
                if let detail, !detail.isEmpty {
                    Text(detail.uppercased())
                        .font(Display.font(fontSize * 0.7))
                        .opacity(0.6)
                }
            }
            .lineLimit(1)
            if fullWidth { Spacer(minLength: 0) }
            Image(systemName: systemImage)
                .font(.system(size: fontSize * 0.62, weight: .black))
                .foregroundStyle(inverted ? Palette.textPrimary : Palette.posterInk)
                .frame(width: height * 0.72, height: height * 0.72)
                .background(discColor ?? (inverted ? Palette.posterInk : Palette.posterTeal), in: Circle())
        }
        .foregroundStyle(inverted ? Palette.textPrimary : Palette.posterInk)
        .padding(.leading, height * 0.4)
        .padding(.trailing, height * 0.14)
        .frame(height: height)
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .background(inverted ? Palette.posterInk : Color.white, in: Capsule())
    }
}

/// The outlined pill for a secondary action ("DETAILS").
struct PosterOutlinePill: View {
    let title: String
    var ink = false

    private var height: CGFloat { DeviceClass.current == .tv ? 84 : 52 }

    var body: some View {
        Text(title.uppercased())
            .font(Display.font(DeviceClass.current == .tv ? 32 : 19))
            .foregroundStyle(ink ? Palette.posterInk : Palette.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, height * 0.42)
            .frame(height: height)
            .background(Capsule().fill(ink ? Color.clear : Palette.posterInk.opacity(0.35)))
            .overlay(Capsule().strokeBorder(ink ? Palette.posterInk : Color.white.opacity(0.85),
                                            lineWidth: DeviceClass.current == .tv ? 4 : 2.5))
    }
}

/// A round icon button in the same family ("♥").
struct PosterRoundButton: View {
    let systemImage: String
    var tint: Color = Palette.textPrimary

    private var side: CGFloat { DeviceClass.current == .tv ? 84 : 52 }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: side * 0.34, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(Circle().fill(Palette.posterInk.opacity(0.35)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: DeviceClass.current == .tv ? 4 : 2.5))
    }
}

// MARK: - Motion

/// A card at rest sits tilted like a sticker slapped on a wall, and snaps
/// straight when the remote lands on it — the one bit of game-feel every
/// shelf gets. Only the card itself moves (a few hundred points square), the
/// same area `CardFocusStyle`'s scale already animates, so it costs nothing a
/// TV would notice. Touch has no resting focus, so there it simply stays tilted.
struct PosterTilt: ViewModifier {
    let angle: Angle
    #if os(tvOS)
    @Environment(\.isFocused) private var focused
    #else
    private let focused = false
    #endif

    func body(content: Content) -> some View {
        content
            .rotationEffect(focused ? .zero : angle)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: focused)
    }
}

extension View {
    func posterTilt(_ angle: Angle) -> some View { modifier(PosterTilt(angle: angle)) }

    /// The alternating resting tilt for the `index`-th card on a shelf.
    func posterTilt(index: Int, degrees: Double = 2.2) -> some View {
        modifier(PosterTilt(angle: .degrees(index.isMultiple(of: 2) ? -degrees : degrees)))
    }
}

/// The sticker slap: a small element arrives oversized and rotated and lands
/// with a bounce. For eyebrows, chips and tags that change with a slide — never
/// for anything screen-sized.
extension AnyTransition {
    static var posterSlap: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: PosterSlapEffect(progress: 0), identity: PosterSlapEffect(progress: 1)),
            removal: .opacity
        )
    }
}

private struct PosterSlapEffect: ViewModifier {
    let progress: Double
    func body(content: Content) -> some View {
        content
            .scaleEffect(1 + 0.45 * (1 - progress))
            .rotationEffect(.degrees(-9 * (1 - progress)))
            .opacity(progress)
    }
}

/// The poster row header: "/// CONTINUE WATCHING" in the display face with a
/// rule running out to the edge.
struct PosterSectionHeader: View {
    let title: String
    var count: Int? = nil

    private var size: CGFloat { DeviceClass.current == .tv ? 38 : (DeviceClass.current == .phone ? 22 : 26) }

    var body: some View {
        HStack(spacing: size * 0.35) {
            Text("///")
                .font(Display.font(size))
                .tracking(-size * 0.12)
                .foregroundStyle(Palette.posterTeal)
            // The title wins every width fight; only the rule gives way.
            Text(title.uppercased())
                .font(Display.font(size))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
            Rectangle().fill(Palette.text(0.22)).frame(height: 3)
            if let count {
                Text(String(format: "%02d", count))
                    .font(Display.font(size * 0.7))
                    .foregroundStyle(Color(hex: "#F0525F"))
            }
        }
        .padding(.horizontal, DeviceClass.current == .phone ? 20 : 56)
    }
}

// MARK: - Library headers

/// A library screen's title in Poster Mode: the count as the headline in a
/// skewed number badge, the name beside it in the display face, the count's
/// words beneath — the "13 · NEW OUTFITS" banner. Adult libraries add an 18+
/// sticker. Classic keeps its own title block; screens branch on the style.
struct PosterLibraryTitle: View {
    let title: String
    let shown: Int
    let total: Int
    var noun = "titles"
    var badgeColor: Color = Color(hex: "#F0525F")
    var isAdult = false
    /// Hides the numbers until the first fetch lands, rather than badging a 0.
    var hasLoaded = true

    private var isTV: Bool { DeviceClass.current == .tv }
    private var badgeSide: CGFloat { isTV ? 96 : (DeviceClass.current == .phone ? 56 : 66) }

    var body: some View {
        HStack(alignment: .center, spacing: isTV ? 20 : 12) {
            Text(hasLoaded ? "\(shown)" : "··")
                .font(Display.font(badgeSide * 0.66))
                .foregroundStyle(Palette.posterInk)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, badgeSide * 0.12)
                .frame(minWidth: badgeSide, minHeight: badgeSide)
                .background(badgeColor, in: RoundedRectangle(cornerRadius: badgeSide * 0.16, style: .continuous))
                .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.14, d: 1, tx: badgeSide * 0.07, ty: 0))
                .contentTransition(.numericText())
                .animation(.snappy, value: shown)
            VStack(alignment: .leading, spacing: isTV ? 2 : 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text(title.uppercased())
                        .font(Display.font(isTV ? 64 : (DeviceClass.current == .phone ? 38 : 42)))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.14, d: 1, tx: 8, ty: 0))
                    if isAdult {
                        Text("18+")
                            .font(Display.font(isTV ? 22 : 14))
                            .foregroundStyle(Palette.posterInk)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Palette.posterBlush, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .rotationEffect(.degrees(-6))
                    }
                }
                if hasLoaded {
                    Text(LibraryChrome.countLabel(shown: shown, total: total, noun: noun).uppercased())
                        .font(Display.font(isTV ? 24 : 14))
                        .tracking(1)
                        .foregroundStyle(Palette.text(0.55))
                }
            }
        }
    }
}

// MARK: - Key visual

/// The key-visual title: enormous, printed in scanlines, blended into the art
/// behind the figure — "EDGERUNNERS" behind Lucy. One static `Canvas` of lines
/// masked by the text, so it costs a single flattened layer however big it is.
struct PosterScanlineTitle: View {
    let text: String
    var size: CGFloat
    var ink: Color = .white.opacity(0.55)
    var blend: BlendMode = .overlay

    var body: some View {
        let label = Text(text.uppercased()).font(Display.font(size))
        label
            .foregroundStyle(.clear)
            .lineLimit(1)
            .fixedSize()
            .overlay {
                Canvas { ctx, canvas in
                    var path = Path()
                    var y: CGFloat = 0
                    while y < canvas.height {
                        path.addRect(CGRect(x: 0, y: y, width: canvas.width, height: size * 0.018))
                        y += size * 0.028
                    }
                    ctx.fill(path, with: .color(ink))
                }
                .mask(label.lineLimit(1).fixedSize())
            }
            .drawingGroup()
            .blendMode(blend)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The subject of a full-screen backdrop, cut out by Vision
/// (`PortraitCutoutCache`, the same on-device pipeline as the cast busts) and
/// drawn over the backdrop at exactly its framing — the cut-out keeps the
/// source's dimensions, so a full-screen fill of each lands pixel on pixel.
/// With the scene behind it tinted, the characters stand out of it in full
/// colour, in front of the title the page printed behind them. Nothing at all
/// while there is no cut-out (or where Vision can't run), so it degrades to
/// the plain backdrop.
struct PosterSubjectCutout: View {
    let imageURL: String?
    /// Fades matching the backdrop's own scrims, so the figure never stands
    /// over the text column or the shelves below.
    var visibleFromX: CGFloat = 0.38
    var visibleToY: CGFloat = 0.66
    /// Where the subject starts, as a fraction of the image's height — reported
    /// once when the cut-out lands, so the page can lift backdrop and cut-out
    /// together and keep a face clear of whatever sits below.
    var onSubjectTop: (CGFloat) -> Void = { _ in }

    @State private var cutout: UIImage?

    var body: some View {
        GeometryReader { geo in
            if let cutout {
                Image(uiImage: cutout)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: visibleFromX - 0.12),
                                               .init(color: .white, location: visibleFromX)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                    .mask {
                        LinearGradient(stops: [.init(color: .white, location: visibleToY - 0.14),
                                               .init(color: .clear, location: visibleToY)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .shadow(color: .black.opacity(0.55), radius: 26, x: -10, y: 10)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: imageURL) {
            guard PortraitCutoutCache.isSupported, let imageURL else { return }
            let image = await PortraitCutoutCache.shared.cutout(for: imageURL)
            if let image, let top = Self.subjectTop(of: image) { onSubjectTop(top) }
            cutout = image
        }
    }

    /// The first row (as a fraction of the height) with any opaque pixel, read
    /// off a 96-pixel-tall thumbnail — an estimate a layout can act on, found
    /// once per cut-out.
    static func subjectTop(of image: UIImage) -> CGFloat? {
        guard let cg = image.cgImage else { return nil }
        let height = 96, width = max(1, Int(Double(cg.width) / Double(cg.height) * 96))
        var alpha = [UInt8](repeating: 0, count: width * height)
        guard let ctx = CGContext(data: &alpha, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        for row in 0..<height {
            // CoreGraphics' origin is bottom-left; the buffer's first row is the top.
            let start = row * width
            if alpha[start..<(start + width)].contains(where: { $0 > 128 }) {
                return CGFloat(row) / CGFloat(height)
            }
        }
        return nil
    }
}
