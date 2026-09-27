import SwiftUI
import JellyTVKit
import Vision
import ImageIO
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

/// Experiments on the library hero's backdrop (`SelectedBackdrop`) — the
/// focused title's art behind the header, filters and hero text. Busy art
/// (a factory floor, a crowd cropped at the shoulders, a cartoon face the
/// size of the screen) fought the logo instead of lifting it. Selected with
/// `JT_HERO_STYLE` while the styles are being compared; `.classic` is what
/// shipped.
enum HeroArtStyle: String {
    /// The shipped look: the art at 1.5× zoom, nudged up, scrimmed.
    case classic
    /// The art graded to one colour — the poster's own hue — so a busy
    /// photograph turns into calm texture and the type pops.
    case duotone
    /// Duotone, with the art's subject cut out by Vision and laid back over
    /// it in full colour: the characters pop out of a toned scene.
    case cutout
    /// Smart framing only: faces (else the salient region) placed right of
    /// centre and never cut at the forehead, at a gentler zoom.
    case frame
    /// Framing, duotone and the cut-out together.
    case all
    /// No tint: framing, the scene softened (a shallow depth of field —
    /// blurred, a little dimmer and less saturated) and the cut-out subject
    /// laid back over it sharp and in full colour.
    case pop

    static let current: HeroArtStyle = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["JT_HERO_STYLE"] ?? ProcessInfo.processInfo.environment["RT_HERO_STYLE"],
           let style = HeroArtStyle(rawValue: raw) { return style }
        #endif
        return .classic
    }()

    var tints: Bool { self == .duotone || self == .cutout || self == .all }
    var cuts: Bool { self == .cutout || self == .all || self == .pop }
    var frames: Bool { self == .frame || self == .all || self == .pop }
    var softens: Bool { self == .pop }
}

/// What the analyser found in a backdrop: the decoded image, where its
/// subject is (faces first, else Vision's attention saliency; normalised,
/// top-left origin), and nothing else.
struct HeroArt: Sendable {
    let image: UIImage
    let focus: CGRect?
    /// The top of the highest face, when faces were found — the edge that
    /// must never be cropped.
    let faceTop: CGFloat?
}

actor HeroArtAnalyzer {
    static let shared = HeroArtAnalyzer()
    private var cache: [String: HeroArt] = [:]
    private var hues: [String: Double] = [:]

    func art(for urlString: String) async -> HeroArt? {
        if let hit = cache[urlString] { return hit }
        PlayerDiagnostics.log("hero: art \(urlString)")
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let cg = Self.downsample(data, max: 1600) else { return nil }
        // The verdict is kept on disk beside the cut-outs, so a backdrop is
        // analysed once per device — and the simulator, which cannot run
        // these requests, can be seeded from the Mac.
        let file = Self.directory.appendingPathComponent("hero-" + Self.key(urlString) + ".json")
        let analysed: (focus: CGRect?, faceTop: CGFloat?)
        if let saved = try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: file)) {
            analysed = (saved.focus.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }, saved.faceTop)
        } else if let fresh = Self.analyse(cg) {
            analysed = fresh
            let saved = Saved(focus: fresh.focus.map { [$0.minX, $0.minY, $0.width, $0.height] }, faceTop: fresh.faceTop)
            try? JSONEncoder().encode(saved).write(to: file)
        } else {
            analysed = (nil, nil)
        }
        let art = HeroArt(image: UIImage(cgImage: cg), focus: analysed.focus, faceTop: analysed.faceTop)
        cache[urlString] = art
        if cache.count > 40 { cache.removeAll() }
        return art
    }

    /// The dominant hue of a (small) image — the poster, whose palette is
    /// the title's brand.
    func hue(for urlString: String) async -> Double? {
        if let hit = hues[urlString] { return hit }
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let cg = Self.downsample(data, max: 200),
              let hue = DominantColor.hue(of: UIImage(cgImage: cg)) else { return nil }
        hues[urlString] = hue
        return hue
    }

    private static func downsample(_ data: Data, max: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }

    private struct Saved: Codable { var focus: [CGFloat]?; var faceTop: CGFloat? }

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("cutouts", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static func key(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Nil when Vision could not run at all (the simulator) — not a verdict,
    /// so nothing is saved.
    private static func analyse(_ image: CGImage) -> (focus: CGRect?, faceTop: CGFloat?)? {
        let faces = VNDetectFaceRectanglesRequest()
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([faces, saliency]) } catch {
            PlayerDiagnostics.log("hero: vision failed: \(error.localizedDescription)")
            return nil
        }
        // Vision is bottom-left origin; flip to top-left.
        func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height) }
        // Faces smaller than a sliver are crowd noise, not the subject.
        let found = (faces.results ?? []).map { flip($0.boundingBox) }.filter { $0.height > 0.06 }
        if !found.isEmpty {
            let union = found.dropFirst().reduce(found[0]) { $0.union($1) }
            PlayerDiagnostics.log(String(format: "hero: %d faces, union %.2f,%.2f %.2fx%.2f", found.count,
                                         union.minX, union.minY, union.width, union.height))
            return (union, union.minY)
        }
        if let salient = saliency.results?.first?.salientObjects?.first {
            let r = flip(salient.boundingBox)
            PlayerDiagnostics.log(String(format: "hero: saliency %.2f,%.2f %.2fx%.2f", r.minX, r.minY, r.width, r.height))
            return (r, nil)
        }
        PlayerDiagnostics.log("hero: no focus")
        return (nil, nil)
    }
}

/// The hero's art under one of the experimental styles, laid out in a frame
/// of `size`: the image placed (classic 1.5× framing, or smart framing),
/// optionally graded to the poster's hue, optionally with its subject cut
/// out and laid back over in full colour at the identical placement.
struct HeroArtLayer: View {
    let item: MediaItem
    let url: String?
    let size: CGSize
    let style: HeroArtStyle

    @State private var art: HeroArt?
    @State private var hue: Double?
    @State private var cutout: UIImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let art {
                let rect = placement(for: art)
                graded(Image(uiImage: art.image).resizable().interpolation(.high))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                if style.cuts, let cutout {
                    // A rim light (a white edge and a poster-coloured bloom
                    // behind the silhouette) was tried and turned down: it
                    // read as a cut-out glow, sloppy rather than lit.
                    Image(uiImage: cutout).resizable().interpolation(.high)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        // Never over the hero's text column.
                        .mask {
                            LinearGradient(stops: [.init(color: .clear, location: 0.34), .init(color: .white, location: 0.46)],
                                           startPoint: .leading, endPoint: .trailing)
                        }
                        .shadow(color: .black.opacity(0.6), radius: 24, x: -8, y: 8)
                        .transition(.opacity)
                }
            } else {
                item.artwork.gradient
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .task(id: url) {
            guard let url else { return }
            async let artTask = HeroArtAnalyzer.shared.art(for: url)
            async let hueTask: Double? = style.tints ? HeroArtAnalyzer.shared.hue(for: item.image ?? url) : nil
            let loaded = await artTask
            hue = await hueTask
            art = loaded
            if style.cuts, PortraitCutoutCache.isSupported {
                let cut = await PortraitCutoutCache.shared.cutout(for: url)
                PlayerDiagnostics.log("hero: cutout \(cut == nil ? "none" : "ok") for \(item.title)")
                withAnimation(.easeOut(duration: 0.3)) { cutout = cut }
            }
        }
    }

    @ViewBuilder private func graded(_ image: Image) -> some View {
        if style.tints {
            let tint = hue.map { Color(OKLCH(l: 0.62, c: 0.13, h: $0)) } ?? Palette.posterTeal
            image
                .grayscale(1)
                .contrast(1.12)
                .brightness(-0.04)
                .overlay { tint.blendMode(.color) }
                .compositingGroup()
        } else if style.softens {
            // Only once the subject is there to stand in front of it —
            // without a cut-out the scene stays as it is.
            image
                .blur(radius: cutout == nil ? 0 : 7)
                .saturation(cutout == nil ? 1 : 0.8)
                .brightness(cutout == nil ? 0 : -0.1)
        } else {
            image
        }
    }

    /// Where the image sits in the frame. Classic: the shipped 1.5× box,
    /// centred and nudged up 100pt. Smart framing: a gentler zoom, the
    /// subject's centre put right of the text column, and the top of the
    /// highest face kept below the header.
    private func placement(for art: HeroArt) -> CGRect {
        let iw = max(1, art.image.size.width), ih = max(1, art.image.size.height)
        let W = size.width, H = size.height
        if !style.frames {
            let s = max(1.5 * W / iw, 1.5 * H / ih)
            let dw = iw * s, dh = ih * s
            return CGRect(x: W / 2 - dw / 2, y: H / 2 - 100 - dh / 2, width: dw, height: dh)
        }
        // A subject that already fills the art (a cartoon face, a helmet)
        // gets no extra zoom, and is pinned from the top; a small one is
        // brought a little closer.
        let big = (art.focus?.height ?? 0) > 0.5
        let s = max(W / iw, H / ih) * (big ? 1.0 : 1.12)
        let dw = iw * s, dh = ih * s
        var x = (W - dw) / 2, y = (H - dh) * 0.3
        if let f = art.focus {
            x = 0.68 * W - f.midX * dw
            y = 0.32 * H - f.midY * dh
            if let top = art.faceTop { y = max(y, 0.12 * H - top * dh) }
        }
        x = min(0, max(W - dw, x))
        y = min(0, max(H - dh, y))
        return CGRect(x: x, y: y, width: dw, height: dh)
    }
}
