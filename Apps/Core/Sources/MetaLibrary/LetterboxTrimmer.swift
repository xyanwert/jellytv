import Foundation
import UIKit

/// Loads a thumbnail and trims the black bars baked into it.
///
/// **Why this exists.** Jellyfin's Screen Grabber captures whatever frame the
/// video actually contains — and a clip that was itself exported with pillarbox
/// or letterbox bars yields a thumbnail with those bars *inside the image*. No
/// amount of scaling fixes that: cropping a 16:9 picture to fill a 16:9 card
/// crops nothing, so the card ends up with black margins while its neighbours
/// are full-bleed. That inconsistency is what this removes.
///
/// The analysis runs on a downsampled copy — a few thousand pixels rather than
/// a few hundred thousand — so finding the bars costs far less than decoding
/// the image did in the first place.
actor LetterboxTrimmer {
    static let shared = LetterboxTrimmer()

    private var cache: [URL: UIImage] = [:]
    private var order: [URL] = []
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    /// Enough for several screenfuls of a scrolling grid without growing
    /// without bound.
    private static let maxCached = 120

    /// A row or column this dark counts as part of a bar. Not zero: video
    /// black is rarely pure black once it has been through an encoder.
    private static let blackThreshold: Double = 20 / 255

    /// Refuse to remove more than this in either axis. A frame that is almost
    /// entirely dark — a night scene, a fade to black — would otherwise be
    /// cropped down to whatever speck of light it contains.
    ///
    /// Generous on purpose: the real bars in this library are wide. A portrait
    /// clip pillarboxed into a 16:9 frame keeps only ~31% of its width, and
    /// that is a genuine bar, not a dark picture. What stops a dark *scene*
    /// being mangled is that its bounds are ragged — a real bar runs the full
    /// height or width of the frame, which is what the row/column scan
    /// requires.
    private static let maxTrimFraction: Double = 0.75

    func image(for url: URL) async -> UIImage? {
        if let cached = cache[url] {
            touch(url)
            return cached
        }
        if let existing = inFlight[url] { return await existing.value }

        let task = Task<UIImage?, Never> {
            guard let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 { return nil }
            guard let decoded = UIImage(data: data) else { return nil }
            return Self.trimmed(decoded)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight.removeValue(forKey: url)
        if let image { insert(url: url, image: image) }
        return image
    }

    private func insert(url: URL, image: UIImage) {
        cache[url] = image
        order.removeAll { $0 == url }
        order.append(url)
        while order.count > Self.maxCached { cache.removeValue(forKey: order.removeFirst()) }
    }

    private func touch(_ url: URL) {
        order.removeAll { $0 == url }
        order.append(url)
    }

    // MARK: - Trimming

    /// The image with any black border removed, or the original when there
    /// isn't one worth removing.
    nonisolated static func trimmed(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage,
              let map = luminanceMap(cg) else { return image }

        let (values, w, h) = map
        func rowIsBlack(_ y: Int) -> Bool {
            (0..<w).allSatisfy { values[y * w + $0] < blackThreshold }
        }
        func columnIsBlack(_ x: Int) -> Bool {
            (0..<h).allSatisfy { values[$0 * w + x] < blackThreshold }
        }

        var top = 0, bottom = h - 1, left = 0, right = w - 1
        while top < bottom, rowIsBlack(top) { top += 1 }
        while bottom > top, rowIsBlack(bottom) { bottom -= 1 }
        while left < right, columnIsBlack(left) { left += 1 }
        while right > left, columnIsBlack(right) { right -= 1 }

        // Nothing to do, or the frame is so dark that trimming would be
        // guessing rather than cropping.
        let keptWidth = Double(right - left + 1) / Double(w)
        let keptHeight = Double(bottom - top + 1) / Double(h)
        guard keptWidth < 0.995 || keptHeight < 0.995 else { return image }
        guard keptWidth >= (1 - maxTrimFraction), keptHeight >= (1 - maxTrimFraction) else { return image }

        // Map the fractions back onto the full-resolution image.
        let rect = CGRect(
            x: (Double(left) / Double(w)) * Double(cg.width),
            y: (Double(top) / Double(h)) * Double(cg.height),
            width: keptWidth * Double(cg.width),
            height: keptHeight * Double(cg.height)
        ).integral

        guard let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// A small greyscale sample of the image — 64px on its long edge, which is
    /// plenty to find a bar and cheap enough to do per card.
    private nonisolated static func luminanceMap(_ cg: CGImage) -> ([Double], Int, Int)? {
        let longEdge = 64.0
        let scale = longEdge / Double(max(cg.width, cg.height))
        let w = max(1, Int((Double(cg.width) * scale).rounded()))
        let h = max(1, Int((Double(cg.height) * scale).rounded()))

        var bytes = [UInt8](repeating: 0, count: w * h)
        guard let context = CGContext(
            data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (bytes.map { Double($0) / 255 }, w, h)
    }
}
