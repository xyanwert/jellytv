import SwiftUI
import JellyTVKit
import Vision
import CoreImage
import CryptoKit
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

/// A character cut out of a piece of key art — the figure that stands on the
/// Anime library's stage — as distinct from `PortraitCutoutCache`, which cuts
/// *whatever* Vision calls the foreground and keeps the source's framing.
///
/// This one judges. Vision finds one or more foreground instances; each
/// instance, and all of them together, is measured (`FigureMeasure`) and
/// scored (`FigureQuality`, kit, tested) as a figure rather than a scene, the
/// text on the art is detected so a cut with a title lying across it loses
/// points, and the best candidate comes back trimmed to itself with its score
/// — or nothing, when the art holds no figure worth standing up. A miss is
/// remembered on disk too, so a real Apple TV doesn't re-run Vision on the
/// same room-with-people backdrop every launch.
///
/// The simulator can't run Vision at all; `Scripts/seed-anime-figures.sh`
/// makes the same cuts on the Mac and drops them under the same names.
actor FigureCutoutCache {
    static let shared = FigureCutoutCache()

    struct Figure: Sendable {
        let image: UIImage
        let score: Double
    }

    private var memory: [String: Figure] = [:]
    private var misses: Set<String> = []
    private var inFlight: [String: Task<Figure?, Never>] = [:]
    private var permits = 2
    private var waiters: [CheckedContinuation<Void, Never>] = []

    static var isSupported: Bool { PortraitCutoutCache.isSupported }

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("cutouts", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// The cache file a figure for this URL lives under — `figure-<sha256>`,
    /// with `.png` beside a `.score`, or `.miss` when the art had no figure.
    /// Named so the Mac-side seeding script can write the same files.
    static func cacheStem(for urlString: String) -> String {
        "figure-" + SHA256.hash(data: Data(urlString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func figure(for urlString: String) async -> Figure? {
        if let hit = memory[urlString] { return hit }
        if misses.contains(urlString) { return nil }
        if let task = inFlight[urlString] { return await task.value }
        let stem = Self.directory.appendingPathComponent(Self.cacheStem(for: urlString))
        let task = Task.detached(priority: .utility) { () -> Figure? in
            await FigureCutoutCache.shared.acquire()
            defer { Task { await FigureCutoutCache.shared.release() } }
            return Self.render(urlString: urlString, stem: stem)
        }
        inFlight[urlString] = task
        let result = await task.value
        inFlight[urlString] = nil
        if let result { memory[urlString] = result } else { misses.insert(urlString) }
        return result
    }

    private func acquire() async {
        if permits > 0 { permits -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { permits += 1 } else { waiters.removeFirst().resume() }
    }

    // MARK: - Work

    private nonisolated static func render(urlString: String, stem: URL) -> Figure? {
        let png = stem.appendingPathExtension("png")
        let scoreFile = stem.appendingPathExtension("score")
        let miss = stem.appendingPathExtension("miss")
        if FileManager.default.fileExists(atPath: miss.path) { return nil }
        if let data = try? Data(contentsOf: png), let image = UIImage(data: data) {
            let score = (try? String(contentsOf: scoreFile, encoding: .utf8)).flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 1
            return Figure(image: image, score: score)
        }
        guard isSupported else { return nil }
        log("cutting figure \(urlString)")
        guard let url = URL(string: urlString), let data = try? Data(contentsOf: url) else {
            log("download failed \(urlString)")
            return nil
        }
        guard let source = downsampled(data, maxPixel: 1600) ?? UIImage(data: data)?.cgImage else {
            log("undecodable image \(urlString)")
            return nil
        }
        let figure: Figure
        switch segment(source) {
        case .figure(let found):
            figure = found
        case .nothing:
            // Vision ran and found no figure: remembered, so a real Apple TV
            // doesn't re-cut the same room-with-people backdrop every launch.
            // `Data().write` refuses an empty file; a marker needs no contents.
            FileManager.default.createFile(atPath: miss.path, contents: nil)
            return nil
        case .failed:
            // Vision could not run (the simulator, always) — not a verdict
            // on the art, so nothing is written and a seeded cut can land.
            return nil
        }
        if let out = figure.image.pngData() {
            try? out.write(to: png, options: .atomic)
            try? String(format: "%.3f", figure.score).write(to: scoreFile, atomically: true, encoding: .utf8)
        }
        return figure
    }

    private nonisolated static func downsampled(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }

    /// The best figure in the image, or nil. Every instance and the union of
    /// all of them are candidates; the one that scores highest as a figure
    /// wins, provided it clears `FigureQuality.pass`.
    private enum Verdict { case figure(Figure), nothing, failed }

    private nonisolated static func segment(_ image: CGImage) -> Verdict {
        guard #available(tvOS 17, iOS 17, *) else { return .failed }
        let masks = VNGenerateForegroundInstanceMaskRequest()
        let text = VNDetectTextRectanglesRequest()
        text.reportCharacterBoxes = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([masks, text])
        } catch {
            log("segmentation failed: \(error.localizedDescription)")
            return .failed
        }
        guard let result = masks.results?.first else {
            log("no foreground instances")
            return .nothing
        }
        // Vision's boxes are normalised with the origin at the bottom-left;
        // the measure's box is built the same way, so no flipping is needed.
        let textBoxes = (text.results ?? []).map(\.boundingBox)

        var candidates: [(IndexSet, Double)] = []
        var sets: [IndexSet] = [result.allInstances]
        if result.allInstances.count > 1 {
            sets += result.allInstances.map { IndexSet(integer: $0) }
        }
        for set in sets {
            guard let mask = try? result.generateScaledMaskForImage(forInstances: set, from: handler),
                  var measure = FigureMask.measure(mask) else { continue }
            measure.textOverlap = FigureQuality.textOverlap(box: FigureMask.box(mask, of: measure), text: textBoxes)
            candidates.append((set, FigureQuality.score(measure)))
        }
        guard let best = candidates.max(by: { $0.1 < $1.1 }), FigureQuality.passes(best.1) else {
            let scores = candidates.map { String(format: "%.2f", $0.1) }.joined(separator: " ")
            log("no figure — scores \(scores)")
            return .nothing
        }
        guard let masked = try? result.generateMaskedImage(ofInstances: best.0, from: handler,
                                                            croppedToInstancesExtent: true) else { return .failed }
        let ci = CIImage(cvPixelBuffer: masked)
        guard let cg = CIContext().createCGImage(ci, from: ci.extent) else { return .failed }
        log(String(format: "figure ok, score %.2f, %d of %d instances", best.1, best.0.count, result.allInstances.count))
        return .figure(Figure(image: UIImage(cgImage: cg), score: best.1))
    }

    private nonisolated static func log(_ message: String) {
        PlayerDiagnostics.log("figure: \(message)")
    }
}

/// Reads a Vision mask (one-component float, full image size) into the
/// numbers `FigureQuality` scores. Sampled every second pixel; the bounding
/// box is exact to that stride.
enum FigureMask {
    /// Bounding box in pixels, kept alongside the measure so the text overlap
    /// can be computed in the same normalised space Vision reports text in.
    private struct Box { var minX: Int, maxX: Int, minY: Int, maxY: Int }

    static func measure(_ mask: CVPixelBuffer) -> FigureMeasure? {
        guard let (box, on, w, h) = scan(mask) else { return nil }
        let step = 2
        let bw = box.maxX - box.minX + step, bh = box.maxY - box.minY + step
        let area = Double(on * step * step)
        return FigureMeasure(
            coverage: area / Double(w * h),
            fill: area / Double(bw * bh),
            aspect: Double(bh) / Double(bw),
            pixelHeight: bh,
            touchesLeft: box.minX <= Int(Double(w) * 0.01),
            touchesRight: box.maxX >= Int(Double(w) * 0.99) - step,
            touchesTop: box.minY <= Int(Double(h) * 0.01))
    }

    /// The measured box in Vision's normalised, bottom-left-origin space.
    static func box(_ mask: CVPixelBuffer, of measure: FigureMeasure) -> CGRect {
        guard let (box, _, w, h) = scan(mask) else { return .zero }
        let step = 2
        let x = CGFloat(box.minX) / CGFloat(w)
        let width = CGFloat(box.maxX - box.minX + step) / CGFloat(w)
        // Buffer rows count from the top; Vision's y from the bottom.
        let top = CGFloat(box.minY) / CGFloat(h), bottom = CGFloat(box.maxY + step) / CGFloat(h)
        return CGRect(x: x, y: 1 - bottom, width: width, height: bottom - top)
    }

    private static func scan(_ mask: CVPixelBuffer) -> (Box, Int, Int, Int)? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent32Float,
              let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
        let stride = CVPixelBufferGetBytesPerRow(mask) / MemoryLayout<Float>.size
        let step = 2
        var on = 0
        var box = Box(minX: w, maxX: -1, minY: h, maxY: -1)
        for y in Swift.stride(from: 0, to: h, by: step) {
            let row = base.advanced(by: y * stride * MemoryLayout<Float>.size).assumingMemoryBound(to: Float.self)
            for x in Swift.stride(from: 0, to: w, by: step) where row[x] > 0.5 {
                on += 1
                if x < box.minX { box.minX = x }
                if x > box.maxX { box.maxX = x }
                if y < box.minY { box.minY = y }
                if y > box.maxY { box.maxY = y }
            }
        }
        guard box.maxX >= box.minX else { return nil }
        return (box, on, w, h)
    }
}
