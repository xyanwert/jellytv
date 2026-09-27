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
actor StickerCut {
    static let shared = StickerCut()

    private var memory: [String: UIImage] = [:]
    private let context = CIContext(options: [.cacheIntermediates: false])

    /// `border` is in pixels of the (≤1400px) result.
    func sticker(_ image: UIImage, key: String, border: CGFloat = 16) -> UIImage? {
        if let cached = memory[key] { return cached }
        guard let made = Self.make(image, border: border, context: context) else { return nil }
        memory[key] = made
        return made
    }

    private static func make(_ image: UIImage, border: CGFloat, context: CIContext) -> UIImage? {
        guard let cg = image.cgImage, let box = alphaBounds(cg) else { return nil }
        var input = CIImage(cgImage: cg).cropped(to: box)
        input = input.transformed(by: CGAffineTransform(translationX: -box.minX, y: -box.minY))
        // At most 1400px on the long edge: plenty for a TV, and the morphology
        // pass costs per pixel.
        let long = max(input.extent.width, input.extent.height)
        if long > 1400 {
            let s = 1400 / long
            input = input.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        let pad = border + 6
        input = input.transformed(by: CGAffineTransform(translationX: pad, y: pad))
        let canvas = CGRect(x: 0, y: 0, width: input.extent.width + pad * 2, height: input.extent.height + pad * 2)

        func silhouette(_ color: CIColor, grow radius: CGFloat) -> CIImage {
            let fill = CIImage(color: color).cropped(to: canvas)
            let shape = fill.applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty().cropped(to: canvas),
                kCIInputMaskImageKey: input,
            ])
            return shape.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: canvas)
        }

        let ink = silhouette(CIColor(red: 0.07, green: 0.075, blue: 0.09), grow: border + 2)
        let white = silhouette(.white, grow: border)
        let composed = input.composited(over: white).composited(over: ink)
        guard let out = context.createCGImage(composed, from: canvas) else { return nil }
        return UIImage(cgImage: out)
    }

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
