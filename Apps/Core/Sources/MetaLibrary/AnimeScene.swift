import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A character *staged* in the key visual rather than stuck on it.
///
/// What made the first figures read as cut-outs was the white paper around
/// them and a drop shadow that belonged to no light: a sticker on glass. So
/// the figure is inked (a thin manga line, `StickerCut.Style.inked`) and lit
/// by the scene it stands in — its silhouette in white a plate off register
/// up-left (the lit edge), and a halftone shadow thrown down-right onto the
/// ground. A `.softLight` wash of the palette over the art was tried and
/// dropped: it bleached the characters. Everything here is static once laid out; only the arrival
/// moves, and it moves figure-sized layers.
struct AnimeSceneFigure: View {
    let image: UIImage
    let height: CGFloat
    var arrived: Bool = true

    var body: some View {
        let ratio = image.size.width / max(1, image.size.height)
        let width = height * ratio
        ZStack {
            // The shadow the scene's light throws: halftone, like print.
            AnimeHalftone(color: Palette.posterInk.opacity(0.6), step: max(7, height * 0.017), falloff: false)
                .mask { silhouette(.black) }
                .offset(x: height * 0.05, y: height * 0.03)
            // The light: the silhouette in white, a plate off register up
            // and to the left — a lit edge on the side the scene is lit
            // from, which reads on the disc and on the ground alike. It
            // trails the figure in on arrival.
            silhouette(.white)
                .offset(x: arrived ? -height * 0.022 : height * 0.14, y: -height * 0.014)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.07), value: arrived)
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .compositingGroup()
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func silhouette(_ color: Color) -> some View {
        Image(uiImage: image)
            .renderingMode(.template)
            .resizable()
            .interpolation(.medium)
            .foregroundStyle(color)
    }
}

/// Manga speed lines bursting out from behind a figure: wedges from a ring
/// to the edge, thick outside and pointed inward, faded at both ends. One
/// `Canvas`, drawn once, seeded so a title always gets the same burst.
struct AnimeSpeedLines: View {
    let color: Color
    var seed: Int = 0

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            let n = 72
            var path = Path()
            for i in 0..<n {
                let jitter = (Self.noise(i + seed, 1) - 0.5) * 0.6
                let a = (Double(i) + jitter) / Double(n) * 2 * .pi
                let half = (0.25 + Self.noise(i + seed, 2) * 0.6) * (.pi / Double(n))
                let inner = r * (0.42 + Self.noise(i + seed, 3) * 0.2)
                path.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
                path.addLine(to: CGPoint(x: c.x + cos(a - half) * r, y: c.y + sin(a - half) * r))
                path.addLine(to: CGPoint(x: c.x + cos(a + half) * r, y: c.y + sin(a + half) * r))
                path.closeSubpath()
            }
            ctx.fill(path, with: .color(color))
        }
        .mask {
            EllipticalGradient(stops: [.init(color: .clear, location: 0.38), .init(color: .white, location: 0.6),
                                       .init(color: .white, location: 0.8), .init(color: .clear, location: 1)],
                               center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }

    static func noise(_ n: Int, _ salt: Int) -> Double {
        let x = sin(Double(n) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }
}

/// A field of print dots. With `falloff` the dots grow toward the bottom
/// right — a halftone gradient, the shading on the disc; without, an even
/// tone for a shadow.
struct AnimeHalftone: View {
    let color: Color
    let step: CGFloat
    var falloff: Bool = true

    var body: some View {
        Canvas { ctx, size in
            var dots = Path()
            var y = step / 2
            while y < size.height {
                var x = (Int(y / step) % 2 == 0) ? step / 2 : step
                while x < size.width {
                    let t = falloff ? min(1, max(0, (x / size.width + y / size.height) - 0.7)) : 1
                    let r = step * 0.42 * t
                    if r > 0.4 { dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }
                    x += step
                }
                y += step
            }
            ctx.fill(dots, with: .color(color))
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

/// The disc behind a figure's head and shoulders: flat colour, halftone
/// shading into its lower right, the hard ink offset every Poster shape casts.
struct AnimeHalftoneDisc: View {
    let color: Color
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(color)
            AnimeHalftone(color: Palette.posterInk.opacity(0.22), step: diameter * 0.032)
                .clipShape(Circle())
        }
        .frame(width: diameter, height: diameter)
        .compositingGroup()
        .shadow(color: Palette.posterInk.opacity(0.9), radius: 0, x: diameter * 0.022, y: diameter * 0.022)
    }
}

/// The sound effect lettered into the panel — ドドド, ドン! — die-cut in the
/// slash colour, overlapping the figure's shoulder the way a manga letters
/// its SFX *into* the drawing. Chosen per title, so a title always says the
/// same thing.
enum AnimeSFX {
    static func word(for id: String, variant: AnimeSkinVariant) -> String {
        let words = variant.isAdult ? ["ドキッ!", "ドキドキ", "ゾクッ", "キュン"] : ["ドドド", "ドン!", "ゴゴゴ", "バーン!", "ズバッ"]
        let n = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return words[abs(n) % words.count]
    }
}

/// The TV key visual's staging in a box of its own, for touch: the burst,
/// the halftone disc, the lit figure and its lettered SFX, sized to
/// `height` and laid out in a frame the figure's width plus room for the
/// burst. The TV keeps `AnimeKeyVisual`, which positions the same parts
/// against the screen's shelf line.
struct AnimeStagedFigure: View {
    let lead: AnimeLead
    let variant: AnimeSkinVariant
    let height: CGFloat

    var body: some View {
        let ratio = lead.figure.size.width / max(1, lead.figure.size.height)
        let h = min(height, height * 1.5 / max(ratio, 0.01))
        let w = h * ratio
        let disc = h * 0.86
        let box = CGSize(width: max(w, disc) * 1.35, height: height)
        ZStack {
            AnimeSpeedLines(color: lead.palette.slash.opacity(0.75), seed: lead.item.id.count)
                .frame(width: disc * 2, height: disc * 2)
                .position(x: box.width / 2 + h * 0.06, y: box.height - h + h * 0.38)
            AnimeHalftoneDisc(color: lead.palette.disc, diameter: disc)
                .position(x: box.width / 2 + h * 0.06, y: box.height - h + h * 0.38)
            AnimeSceneFigure(image: lead.figure, height: h)
                .position(x: box.width / 2, y: box.height - h / 2)
            DieCutText(text: AnimeSFX.word(for: lead.item.id, variant: variant),
                       font: .system(size: h * 0.17, weight: .black),
                       fill: lead.palette.slash, stroke: Palette.posterInk, width: h * 0.012,
                       shadow: h * 0.012)
                .rotationEffect(.degrees(-12))
                .position(x: box.width / 2 - w / 2 + h * 0.02, y: box.height - h + h * 0.16)
        }
        .frame(width: box.width, height: box.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
