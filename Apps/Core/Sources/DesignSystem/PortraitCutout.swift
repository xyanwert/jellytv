import SwiftUI
import JellyTVKit
import Vision
import CoreImage
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

/// Cast headshots with the background lifted off — the bust that stands in
/// relief on the movie page's `CastCoin`s, its head rising above the rim.
///
/// **On device, once, cached.** `VNGenerateForegroundInstanceMaskRequest`
/// (tvOS 17+) finds the subject of the photo and hands back an alpha-matted
/// copy; that takes ~100–200ms per headshot on an Apple TV 4K, so every result
/// is kept in memory and as a PNG under `Caches/cutouts/`, and at most two run
/// at a time. A cut-out is never redone for the same URL.
///
/// **Honest failures.** Vision will happily return *something* for any image
/// — a mask covering the whole frame, or a sliver. Coverage outside 8–95% is
/// treated as "no usable cut-out" and the caller falls back to the plain
/// portrait, which is what the lineup shows in the meantime anyway, so a
/// failure looks like nothing happened rather than like a bug.
actor PortraitCutoutCache {
    static let shared = PortraitCutoutCache()

    private var memory: [String: UIImage] = [:]
    private var failed: Set<String> = []
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var permits = 2
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("cutouts", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Whether this device can cut anything out at all.
    static var isSupported: Bool {
        if #available(tvOS 17, iOS 17, *) { return true }
        return false
    }

    func cutout(for urlString: String) async -> UIImage? {
        if let image = memory[urlString] { return image }
        if failed.contains(urlString) { return nil }
        if let task = inFlight[urlString] { return await task.value }

        let diskURL = Self.directory.appendingPathComponent(Self.key(for: urlString)).appendingPathExtension("png")
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            await PortraitCutoutCache.shared.acquire()
            defer { Task { await PortraitCutoutCache.shared.release() } }
            return Self.render(urlString: urlString, diskURL: diskURL)
        }
        inFlight[urlString] = task
        let result = await task.value
        inFlight[urlString] = nil
        if let result { memory[urlString] = result } else { failed.insert(urlString) }
        return result
    }

    // MARK: - Concurrency permit (two segmentations at a time)

    private func acquire() async {
        if permits > 0 { permits -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { permits += 1 } else { waiters.removeFirst().resume() }
    }

    // MARK: - Work

    private static func key(for urlString: String) -> String {
        SHA256.hash(data: Data(urlString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func render(urlString: String, diskURL: URL) -> UIImage? {
        if let data = try? Data(contentsOf: diskURL), let image = UIImage(data: data) {
            return image
        }
        guard let url = URL(string: urlString), let data = try? Data(contentsOf: url) else {
            log("download failed \(urlString)")
            return nil
        }
        guard let source = UIImage(data: data)?.cgImage else {
            log("undecodable image (\(data.count) bytes) \(urlString)")
            return nil
        }
        guard let cutout = segment(source) else { return nil }
        if let png = cutout.pngData() {
            try? png.write(to: diskURL, options: .atomic)
        }
        return cutout
    }

    private nonisolated static func segment(_ image: CGImage) -> UIImage? {
        guard #available(tvOS 17, iOS 17, *) else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            log("segmentation failed: \(error.localizedDescription)")
            return nil
        }
        guard let result = request.results?.first else {
            log("no foreground instances found")
            return nil
        }

        // Quality gate on the scaled mask before paying for the composite.
        guard let mask = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler),
              let covered = coverage(of: mask) else {
            log("could not read the mask")
            return nil
        }
        guard (0.08...0.95).contains(covered) else {
            log("mask covers \(Int(covered * 100))% of the frame — not a cut-out")
            return nil
        }

        guard let masked = try? result.generateMaskedImage(ofInstances: result.allInstances, from: handler,
                                                            croppedToInstancesExtent: false) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: masked)
        guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return nil }
        log("cut-out ok, mask covers \(Int(covered * 100))%")
        return UIImage(cgImage: cgImage)
    }

    /// `JT_PLAYER_LOG=1` turns these on, same switch (and same line-buffered
    /// stdout) as the player's own diagnostics — the segmentation path fails
    /// silently by design, and this is the one way to see why on a given box.
    private nonisolated static func log(_ message: String) {
        PlayerDiagnostics.log("cutout: \(message)")
    }

    /// The share of the mask that is "subject" — a one-component float buffer,
    /// sampled every fourth pixel; precision is not the point.
    private nonisolated static func coverage(of mask: CVPixelBuffer) -> Double? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent32Float,
              let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask)
        let stride = CVPixelBufferGetBytesPerRow(mask) / MemoryLayout<Float>.size
        var on = 0, total = 0
        for y in Swift.stride(from: 0, to: height, by: 4) {
            let row = base.advanced(by: y * stride * MemoryLayout<Float>.size).assumingMemoryBound(to: Float.self)
            for x in Swift.stride(from: 0, to: width, by: 4) {
                total += 1
                if row[x] > 0.5 { on += 1 }
            }
        }
        return total == 0 ? nil : Double(on) / Double(total)
    }
}

