import Foundation
import Vision
import CoreImage
import CryptoKit
import ImageIO
import AppKit

// Cuts the *figure* out of a piece of key art — the same judgement the app's
// `FigureCutoutCache` makes on a real Apple TV, run on the Mac for the
// simulator, which cannot run Vision at all.
//
//   swift Scripts/segment-figures.swift <cacheDir> <url1> <file1> <url2> <file2> …
//
// For each image: Vision's foreground instances and text rectangles; every
// instance and their union measured and scored as a figure rather than a
// scene (`FigureQuality` in JellyTVKit — the formula below is a copy and must
// stay one); the best passing candidate written to
// `<cacheDir>/figure-<sha256 of url>.png` beside a `.score`, or a `.miss`
// when the art holds no figure. Used by seed-anime-figures.sh.

// MARK: - FigureQuality (mirror of Packages/JellyTVKit/Sources/JellyTVKit/FigureQuality.swift)

struct FigureMeasure {
    var coverage: Double, fill: Double, aspect: Double, pixelHeight: Int
    var touchesLeft = false, touchesRight = false, touchesTop = false
    var textOverlap = 0.0
}

enum FigureQuality {
    static let pass = 0.72
    static func ramp(_ x: Double, from: Double, to: Double) -> Double {
        guard to > from else { return x >= to ? 1 : 0 }
        return min(1, max(0, (x - from) / (to - from)))
    }
    static func score(_ m: FigureMeasure) -> Double {
        if m.coverage < 0.03 || m.coverage > 0.72 { return 0 }
        if m.fill > 0.86 { return 0 }
        if m.touchesLeft && m.touchesRight { return 0 }
        if m.pixelHeight < 260 { return 0 }
        let size = ramp(m.coverage, from: 0.03, to: 0.10) * (1 - ramp(m.coverage, from: 0.45, to: 0.70))
        let fill = 1 - ramp(m.fill, from: 0.62, to: 0.85)
        let shape = ramp(m.aspect, from: 0.45, to: 0.90)
        let edge = max(0, 1 - (m.touchesLeft ? 0.25 : 0) - (m.touchesRight ? 0.25 : 0) - (m.touchesTop ? 0.35 : 0))
        let resolution = ramp(Double(m.pixelHeight), from: 300, to: 700)
        let text = min(1, m.textOverlap / 0.05) * 0.35
        let weighted = 0.15 * size + 0.25 * fill + 0.15 * shape + 0.20 * edge + 0.25 * resolution
        return max(0, min(1, weighted - text))
    }
    static func textOverlap(box: CGRect, text: [CGRect]) -> Double {
        guard box.width > 0, box.height > 0 else { return 0 }
        let area = box.width * box.height
        let covered = text.reduce(0.0) { sum, t in
            let i = box.intersection(t)
            return i.isNull ? sum : sum + Double(i.width * i.height)
        }
        return min(1, covered / Double(area))
    }
}

// MARK: - Mask measurement (mirror of FigureMask in Apps/Core/Sources/DesignSystem/FigureCutout.swift)

struct Scan { var minX: Int, maxX: Int, minY: Int, maxY: Int, on: Int, w: Int, h: Int }

func scan(_ mask: CVPixelBuffer) -> Scan? {
    CVPixelBufferLockBaseAddress(mask, .readOnly); defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
    let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
    let stride = CVPixelBufferGetBytesPerRow(mask) / 4
    var s = Scan(minX: w, maxX: -1, minY: h, maxY: -1, on: 0, w: w, h: h)
    for y in Swift.stride(from: 0, to: h, by: 2) {
        let row = base.advanced(by: y * stride * 4).assumingMemoryBound(to: Float.self)
        for x in Swift.stride(from: 0, to: w, by: 2) where row[x] > 0.5 {
            s.on += 1
            if x < s.minX { s.minX = x }; if x > s.maxX { s.maxX = x }
            if y < s.minY { s.minY = y }; if y > s.maxY { s.maxY = y }
        }
    }
    return s.maxX >= s.minX ? s : nil
}

func measure(_ s: Scan, text: [CGRect]) -> FigureMeasure {
    let step = 2
    let bw = s.maxX - s.minX + step, bh = s.maxY - s.minY + step
    let area = Double(s.on * step * step)
    var m = FigureMeasure(coverage: area / Double(s.w * s.h), fill: area / Double(bw * bh),
                          aspect: Double(bh) / Double(bw), pixelHeight: bh)
    m.touchesLeft = s.minX <= Int(Double(s.w) * 0.01)
    m.touchesRight = s.maxX >= Int(Double(s.w) * 0.99) - step
    m.touchesTop = s.minY <= Int(Double(s.h) * 0.01)
    let top = CGFloat(s.minY) / CGFloat(s.h), bottom = CGFloat(s.maxY + step) / CGFloat(s.h)
    let box = CGRect(x: CGFloat(s.minX) / CGFloat(s.w), y: 1 - bottom,
                     width: CGFloat(bw) / CGFloat(s.w), height: bottom - top)
    m.textOverlap = FigureQuality.textOverlap(box: box, text: text)
    return m
}

// MARK: - Work

func sha256(_ s: String) -> String {
    SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
}

func downsampled(_ path: String, maxPixel: Int) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
}

func cut(url: String, file: String, cacheDir: String) throws {
    let stem = "\(cacheDir)/figure-\(sha256(url))"
    let name = (file as NSString).lastPathComponent
    guard let cg = downsampled(file, maxPixel: 1600) else { print("\(name): undecodable"); return }
    let masks = VNGenerateForegroundInstanceMaskRequest()
    let text = VNDetectTextRectanglesRequest()
    text.reportCharacterBoxes = false
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    try handler.perform([masks, text])
    let textBoxes = (text.results ?? []).map(\.boundingBox)
    guard let result = masks.results?.first else {
        FileManager.default.createFile(atPath: stem + ".miss", contents: nil)
        print("\(name): no instances → miss"); return
    }
    var sets: [IndexSet] = [result.allInstances]
    if result.allInstances.count > 1 { sets += result.allInstances.map { IndexSet(integer: $0) } }
    var best: (IndexSet, Double)?
    var report: [String] = []
    for set in sets {
        guard let mask = try? result.generateScaledMaskForImage(forInstances: set, from: handler),
              let s = scan(mask) else { continue }
        let m = measure(s, text: textBoxes)
        let score = FigureQuality.score(m)
        if ProcessInfo.processInfo.environment["FIGURE_DEBUG"] != nil {
            print(String(format: "  %@ cov %.3f fill %.3f asp %.2f h %d L%d R%d T%d text %.3f → %.2f", set.count == result.allInstances.count ? "union" : "#\(set.first ?? 0)", m.coverage, m.fill, m.aspect, m.pixelHeight, m.touchesLeft ? 1 : 0, m.touchesRight ? 1 : 0, m.touchesTop ? 1 : 0, m.textOverlap, score))
        }
        report.append(String(format: "%.2f", score))
        if score > (best?.1 ?? -1) { best = (set, score) }
    }
    guard let best, best.1 >= FigureQuality.pass else {
        FileManager.default.createFile(atPath: stem + ".miss", contents: nil)
        print("\(name): no figure (\(report.joined(separator: " "))) → miss"); return
    }
    let masked = try result.generateMaskedImage(ofInstances: best.0, from: handler, croppedToInstancesExtent: true)
    let ci = CIImage(cvPixelBuffer: masked)
    guard let out = CIContext().createCGImage(ci, from: ci.extent) else { print("\(name): composite failed"); return }
    let rep = NSBitmapImageRep(cgImage: out)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: stem + ".png"))
    try String(format: "%.3f", best.1).write(toFile: stem + ".score", atomically: true, encoding: .utf8)
    print("\(name): figure \(String(format: "%.2f", best.1)) (\(best.0.count)/\(result.allInstances.count) instances, \(out.width)x\(out.height)) → png")
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3 else { print("usage: segment-figures.swift <cacheDir> <url> <file> …"); exit(1) }
let cacheDir = args[0]
for i in Swift.stride(from: 1, to: args.count - 1, by: 2) {
    do { try cut(url: args[i], file: args[i + 1], cacheDir: cacheDir) } catch { print("\(args[i + 1]): \(error)") }
}
