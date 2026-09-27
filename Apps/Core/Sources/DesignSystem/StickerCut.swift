import SwiftUI
import CoreImage
#if canImport(UIKit)
import UIKit
#endif

/// A cut-out turned into a die-cut sticker: trimmed to its subject, a thick
/// white border grown around its own silhouette, a hairline of ink outside
/// that — the Zenless Zone Zero key-visual look the Anime library wears.
///
/// **Baked once, never drawn per frame.** The border is a morphology pass over
/// the alpha channel (`CIMorphologyMaximum`), done on a background thread when
/// the cut-out arrives and cached by key; the view then shows one flat image.
/// Twelve offset silhouettes in SwiftUI would do the same job and redraw a
/// full-size image twelve times on every layout pass.
///
/// **What makes it read as printed rather than pasted.** Vision's matte is
/// soft — a two-to-four pixel ramp that carries the background's colour with
/// it — so the alpha is *firmed* first (a short knee around 50%), eroded a
/// pixel to drop the fringe, and only then grown. A border dilated from a
/// soft mask is a blurry border; dilated from a firm one it is a crisp,
/// anti-aliased edge, like a plotter cut it. The border is proportional to
/// the figure — a fixed sixteen pixels was a thick rim on a bust and a
/// hairline on a full-length figure.
actor StickerCut {
    static let shared = StickerCut()

    /// How the border is struck.
    enum Style: Sendable {
        /// White paper around the subject, an ink keyline outside — a
        /// character sticker.
        case sticker
        /// Ink around the subject, a thin white keyline outside — for a logo,
        /// whose own type is often white and would vanish into white paper.
        case outline
    }

    private var memory: [String: UIImage] = [:]
    private let context = CIContext(options: [.cacheIntermediates: false])

    func sticker(_ image: UIImage, key: String, style: Style = .sticker) -> UIImage? {
        let cacheKey = "\(key)#\(style)"
        if let cached = memory[cacheKey] { return cached }
        guard let made = Self.make(image, style: style, context: context) else { return nil }
        memory[cacheKey] = made
        return made
    }

    private static func make(_ image: UIImage, style: Style, context: CIContext) -> UIImage? {
        guard let cg = image.cgImage, let box = alphaBounds(cg) else { return nil }
        var input = CIImage(cgImage: cg).cropped(to: box)
        input = input.transformed(by: CGAffineTransform(translationX: -box.minX, y: -box.minY))
        // At most 1600px on the long edge: plenty for a TV, and the morphology
        // pass costs per pixel.
        let long = max(input.extent.width, input.extent.height)
        if long > 1600 {
            let s = 1600 / long
            input = input.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        let height = input.extent.height
        let (inner, outer): (CGFloat, CGFloat)
        switch style {
        case .sticker: (inner, outer) = (clamp(height * 0.028, 10, 44), clamp(height * 0.007, 2.5, 10))
        case .outline: (inner, outer) = (clamp(height * 0.030, 5, 16), clamp(height * 0.012, 2, 8))
        }
        let pad = ceil(inner + outer + 4)
        input = input.transformed(by: CGAffineTransform(translationX: pad, y: pad))
        let canvas = CGRect(x: 0, y: 0, width: input.extent.width + pad * 2, height: input.extent.height + pad * 2)
            .integral
        let empty = CIImage.empty().cropped(to: canvas)

        // The alpha as a grey image, firmed around 50% and eroded a pixel.
        let alpha = input.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).composited(over: CIImage(color: .black).cropped(to: canvas))
        let knee: CGFloat = 1 / 0.3, foot: CGFloat = 0.35
        let firm = alpha.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: knee, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: knee, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: knee, w: 0),
            "inputBiasVector": CIVector(x: -foot * knee, y: -foot * knee, z: -foot * knee, w: 0),
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ])
        let core = firm.applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 1.2]).cropped(to: canvas)

        func silhouette(_ color: CIColor, grow radius: CGFloat) -> CIImage {
            let grown = core.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: canvas)
                .applyingFilter("CIMaskToAlpha")
            return CIImage(color: color).cropped(to: canvas).applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: empty,
                kCIInputMaskImageKey: grown,
            ])
        }

        let subject = input.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: empty,
            kCIInputMaskImageKey: core.applyingFilter("CIMaskToAlpha"),
        ])
        let ink = CIColor(red: 0.07, green: 0.075, blue: 0.09)
        let composed: CIImage
        switch style {
        case .sticker:
            composed = subject.composited(over: silhouette(.white, grow: inner))
                .composited(over: silhouette(ink, grow: inner + outer))
        case .outline:
            composed = subject.composited(over: silhouette(ink, grow: inner))
                .composited(over: silhouette(.white, grow: inner + outer))
        }
        guard let out = context.createCGImage(composed, from: canvas) else { return nil }
        return UIImage(cgImage: out)
    }

    private static func clamp(_ x: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(hi, max(lo, x)) }

    /// The box around every pixel with real alpha, found on a 160px-wide
    /// thumbnail and scaled back up — Vision keeps the source frame, so a
    /// cut-out is mostly empty space until it is trimmed.
    private static func alphaBounds(_ image: CGImage) -> CGRect? {
        let w = 160, h = max(1, Int(Double(image.height) / Double(image.width) * 160))
        var alpha = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &alpha, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where alpha[y * w + x] > 40 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let sx = CGFloat(image.width) / CGFloat(w), sy = CGFloat(image.height) / CGFloat(h)
        // The buffer's first row is the image's top; Core Image counts from the bottom.
        let top = CGFloat(minY) * sy, bottom = CGFloat(maxY + 1) * sy
        return CGRect(x: CGFloat(minX) * sx, y: CGFloat(image.height) - bottom,
                      width: CGFloat(maxX - minX + 1) * sx, height: bottom - top)
            .insetBy(dx: -sx, dy: -sy)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
}

/// A baked sticker on screen: the image plus the hard ink shadow every
/// Poster sticker casts. Decoration — never hit-testable, hidden from
/// VoiceOver.
struct DieCutSticker: View {
    let image: UIImage
    var height: CGFloat
    var tilt: Double = 0
    var shadow: CGFloat = 12

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: height)
            .shadow(color: Palette.posterInk.opacity(0.9), radius: 0, x: shadow, y: shadow)
            .rotationEffect(.degrees(tilt))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
