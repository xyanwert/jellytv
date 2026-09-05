import Foundation
import Vision
import CoreImage
import AppKit

// Cuts the subject out of each headshot with the same Vision calls the app's
// `PortraitCutoutCache` makes, applying the same 8–95% coverage gate.
//
//   swift Scripts/segment-headshots.swift in1.jpg out1.png in2.jpg out2.png …
//
// Used by seed-simulator-cutouts.sh: the tvOS simulator cannot run this
// request ("Could not create inference context"), so the Mac does it and the
// results are dropped into the simulator app's cache.
func segment(_ path: String, to outPath: String) throws {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("\(path): no image"); return }
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    try handler.perform([request])
    guard let result = request.results?.first else { print("\(path): no instances"); return }
    let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
    CVPixelBufferLockBaseAddress(mask, .readOnly)
    let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
    let base = CVPixelBufferGetBaseAddress(mask)!
    let stride = CVPixelBufferGetBytesPerRow(mask) / 4
    var on = 0, total = 0
    for y in Swift.stride(from: 0, to: h, by: 4) {
        let row = base.advanced(by: y * stride * 4).assumingMemoryBound(to: Float.self)
        for x in Swift.stride(from: 0, to: w, by: 4) { total += 1; if row[x] > 0.5 { on += 1 } }
    }
    CVPixelBufferUnlockBaseAddress(mask, .readOnly)
    let coverage = Double(on) / Double(total)
    guard (0.08...0.95).contains(coverage) else { print("\(path): coverage \(Int(coverage * 100))% outside gate"); return }
    let masked = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
    let ci = CIImage(cvPixelBuffer: masked)
    guard let out = CIContext().createCGImage(ci, from: ci.extent) else { print("\(path): composite failed"); return }
    let rep = NSBitmapImageRep(cgImage: out)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
    print("\(path) → \(outPath) \(Int(coverage * 100))%")
}

let args = Array(CommandLine.arguments.dropFirst())
for i in Swift.stride(from: 0, to: args.count - 1, by: 2) {
    do { try segment(args[i], to: args[i + 1]) } catch { print("\(args[i]): \(error)") }
}
