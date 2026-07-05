#!/usr/bin/env swift
//
// generate-icons.swift
//
// Regenerates every branding asset for JellyTV from code — no external
// dependencies beyond macOS system frameworks. Deterministic and idempotent:
// running it twice produces byte-identical output.
//
//   Usage:  swift Scripts/generate-icons.swift        (run from the repo root)
//
// Produces, under each app's Assets.xcassets:
//   tvOS  (Apps/JellyTV/Resources/Assets.xcassets):
//     - "App Icon & Top Shelf Image.brandassets"
//         * App Icon - App Store.imagestack  (1280x768, layered)
//         * App Icon.imagestack              (400x240 @1x, 800x480 @2x, layered)
//         * Top Shelf Image Wide.imageset    (2320x720 @1x, 4640x1440 @2x)
//         * Top Shelf Image.imageset         (1920x720 @1x, 3840x1440 @2x)
//     - AccentColor.colorset
//   iOS   (Apps/Remote/Resources/Assets.xcassets):
//     - AppIcon.appiconset                   (1024x1024, no alpha)
//     - AccentColor.colorset
//
// Swap the drawing routines (or this whole script) for final artwork later;
// the asset-catalog layout it emits is what Xcode/App Review expect.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Brand palette

let bgTop    = (r: 0.16, g: 0.10, b: 0.29) // deep indigo
let bgBottom = (r: 0.43, g: 0.23, b: 0.82) // violet
let glyph    = (r: 0.95, g: 0.98, b: 1.00) // near-white

let accent   = (r: 0.431, g: 0.231, b: 0.820) // AccentColor (matches bgBottom)

// MARK: - Low-level rendering

/// Renders `draw` into an RGBA (or RGB when `opaque`) bitmap and returns PNG data.
func renderPNG(width: Int, height: Int, opaque: Bool, _ draw: (CGContext) -> Void) -> Data {
    let cs = CGColorSpaceCreateDeviceRGB()
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    guard let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: alpha.rawValue
    ) else { fatalError("Could not create CGContext \(width)x\(height)") }

    ctx.interpolationQuality = .high
    draw(ctx)

    guard let image = ctx.makeImage() else { fatalError("makeImage failed") }
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("CGImageDestination failed")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("PNG encode failed") }
    return out as Data
}

// MARK: - Drawing

func drawBackground(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(colorSpace: cs, components: [CGFloat(bgTop.r), CGFloat(bgTop.g), CGFloat(bgTop.b), 1])!,
        CGColor(colorSpace: cs, components: [CGFloat(bgBottom.r), CGFloat(bgBottom.g), CGFloat(bgBottom.b), 1])!,
    ] as CFArray
    let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
    // top (y = h) is the dark stop, bottom (y = 0) the light stop
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
}

/// A stylized jellyfish: a rounded bell dome with a wavy hem and trailing
/// tentacles — the "jelly" in JellyTV. Drawn in near-white on transparency.
func drawJellyfish(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let s = min(w, h)
    let cx = w / 2
    let cy = h * 0.56
    let R = s * 0.24
    let cs = CGColorSpaceCreateDeviceRGB()
    let fill = CGColor(colorSpace: cs, components: [CGFloat(glyph.r), CGFloat(glyph.g), CGFloat(glyph.b), 1])!

    ctx.saveGState()
    ctx.setFillColor(fill)
    ctx.setStrokeColor(fill)

    // Bell dome
    let dome = CGMutablePath()
    dome.move(to: CGPoint(x: cx - R, y: cy))
    dome.addQuadCurve(to: CGPoint(x: cx + R, y: cy),
                      control: CGPoint(x: cx, y: cy + R * 1.9))
    // wavy hem (3 scallops)
    let hemY = cy
    let step = (2 * R) / 3
    dome.addQuadCurve(to: CGPoint(x: cx + R - step, y: hemY),
                      control: CGPoint(x: cx + R - step * 0.5, y: hemY - R * 0.22))
    dome.addQuadCurve(to: CGPoint(x: cx + R - 2 * step, y: hemY),
                      control: CGPoint(x: cx + R - step * 1.5, y: hemY - R * 0.22))
    dome.addQuadCurve(to: CGPoint(x: cx - R, y: hemY),
                      control: CGPoint(x: cx - R + step * 0.5, y: hemY - R * 0.22))
    dome.closeSubpath()
    ctx.addPath(dome)
    ctx.fillPath()

    // Tentacles
    ctx.setLineWidth(s * 0.028)
    ctx.setLineCap(.round)
    let n = 5
    let amp = s * 0.032
    for i in 0..<n {
        let t = CGFloat(i) - CGFloat(n - 1) / 2   // -2 ... 2
        let x0 = cx + t * (R * 0.40)
        let topY = cy - R * 0.10
        let botY = cy - R * 1.7
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x0, y: topY))
        p.addCurve(to: CGPoint(x: x0, y: botY),
                   control1: CGPoint(x: x0 + amp, y: cy - R * 0.7),
                   control2: CGPoint(x: x0 - amp, y: cy - R * 1.2))
        ctx.addPath(p)
        ctx.strokePath()
    }
    ctx.restoreGState()
}

/// Full artwork (background + glyph) flattened onto one canvas.
func drawFlat(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    drawBackground(ctx, w, h)
    drawJellyfish(ctx, w, h)
}

// MARK: - Filesystem helpers

let fm = FileManager.default
let root = fm.currentDirectoryPath

func abspath(_ rel: String) -> String { (root as NSString).appendingPathComponent(rel) }

func resetDir(_ path: String) {
    if fm.fileExists(atPath: path) { try? fm.removeItem(atPath: path) }
    try! fm.createDirectory(atPath: path, withIntermediateDirectories: true)
}

func write(_ data: Data, to path: String) {
    let dir = (path as NSString).deletingLastPathComponent
    try! fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try! data.write(to: URL(fileURLWithPath: path))
}

func writeJSON(_ text: String, to path: String) {
    // Trailing newline; stable formatting → deterministic output.
    write(Data((text + "\n").utf8), to: path)
}

let catalogInfo = #"  "info" : { "author" : "xcode", "version" : 1 }"#

// MARK: - Asset builders

/// Writes a `.imageset` containing one flattened image per scale.
/// `scales` maps scale label ("1x"/"2x") to pixel size.
func writeImageset(dir: String, idiom: String, scales: [(label: String, w: Int, h: Int)]) {
    resetDir(dir)
    var entries: [String] = []
    for s in scales {
        let file = "content_\(s.label).png"
        write(renderPNG(width: s.w, height: s.h, opaque: true) { drawFlat($0, CGFloat(s.w), CGFloat(s.h)) },
              to: (dir as NSString).appendingPathComponent(file))
        entries.append("""
            {
              "filename" : "\(file)",
              "idiom" : "\(idiom)",
              "scale" : "\(s.label)"
            }
        """)
    }
    writeJSON("""
    {
      "images" : [
    \(entries.joined(separator: ",\n"))
      ],
    \(catalogInfo)
    }
    """, to: (dir as NSString).appendingPathComponent("Contents.json"))
}

/// Writes one `.imagestacklayer` (a single parallax layer) holding a Content.imageset.
/// `back == true` draws the gradient (opaque); otherwise the glyph (transparent).
func writeStackLayer(dir: String, idiom: String, back: Bool, scales: [(label: String, w: Int, h: Int)]) {
    resetDir(dir)
    // The layer itself just needs an info Contents.json.
    writeJSON("""
    {
    \(catalogInfo)
    }
    """, to: (dir as NSString).appendingPathComponent("Contents.json"))

    let content = (dir as NSString).appendingPathComponent("Content.imageset")
    try! fm.createDirectory(atPath: content, withIntermediateDirectories: true)
    var entries: [String] = []
    for s in scales {
        let file = "layer_\(s.label).png"
        let data = back
            ? renderPNG(width: s.w, height: s.h, opaque: true) { drawBackground($0, CGFloat(s.w), CGFloat(s.h)) }
            : renderPNG(width: s.w, height: s.h, opaque: false) { drawJellyfish($0, CGFloat(s.w), CGFloat(s.h)) }
        write(data, to: (content as NSString).appendingPathComponent(file))
        entries.append("""
            {
              "filename" : "\(file)",
              "idiom" : "\(idiom)",
              "scale" : "\(s.label)"
            }
        """)
    }
    writeJSON("""
    {
      "images" : [
    \(entries.joined(separator: ",\n"))
      ],
    \(catalogInfo)
    }
    """, to: (content as NSString).appendingPathComponent("Contents.json"))
}

/// Writes a two-layer `.imagestack` (Back gradient + Front glyph) for parallax.
func writeImagestack(dir: String, idiom: String, scales: [(label: String, w: Int, h: Int)]) {
    resetDir(dir)
    writeStackLayer(dir: (dir as NSString).appendingPathComponent("Front.imagestacklayer"),
                    idiom: idiom, back: false, scales: scales)
    writeStackLayer(dir: (dir as NSString).appendingPathComponent("Back.imagestacklayer"),
                    idiom: idiom, back: true, scales: scales)
    writeJSON("""
    {
    \(catalogInfo),
      "layers" : [
        { "filename" : "Front.imagestacklayer" },
        { "filename" : "Back.imagestacklayer" }
      ]
    }
    """, to: (dir as NSString).appendingPathComponent("Contents.json"))
}

func writeAccentColor(catalogDir: String) {
    let dir = (catalogDir as NSString).appendingPathComponent("AccentColor.colorset")
    resetDir(dir)
    writeJSON("""
    {
      "colors" : [
        {
          "color" : {
            "color-space" : "srgb",
            "components" : {
              "alpha" : "1.000",
              "blue" : "\(String(format: "%.3f", accent.b))",
              "green" : "\(String(format: "%.3f", accent.g))",
              "red" : "\(String(format: "%.3f", accent.r))"
            }
          },
          "idiom" : "universal"
        }
      ],
    \(catalogInfo)
    }
    """, to: (dir as NSString).appendingPathComponent("Contents.json"))
}

func writeCatalogRoot(_ catalogDir: String) {
    try! fm.createDirectory(atPath: catalogDir, withIntermediateDirectories: true)
    writeJSON("""
    {
    \(catalogInfo)
    }
    """, to: (catalogDir as NSString).appendingPathComponent("Contents.json"))
}

// MARK: - tvOS

func buildTVOS() {
    let catalog = abspath("Apps/JellyTV/Resources/Assets.xcassets")
    writeCatalogRoot(catalog)
    writeAccentColor(catalogDir: catalog)

    let brand = (catalog as NSString).appendingPathComponent("App Icon & Top Shelf Image.brandassets")
    resetDir(brand)

    // App Store icon: 1280x768, layered, 1x only.
    writeImagestack(dir: (brand as NSString).appendingPathComponent("App Icon - App Store.imagestack"),
                    idiom: "tv", scales: [("1x", 1280, 768)])

    // Home-screen icon: 400x240 @1x, 800x480 @2x, layered.
    writeImagestack(dir: (brand as NSString).appendingPathComponent("App Icon.imagestack"),
                    idiom: "tv", scales: [("1x", 400, 240), ("2x", 800, 480)])

    // Top Shelf Wide: 2320x720 @1x, 4640x1440 @2x.
    writeImageset(dir: (brand as NSString).appendingPathComponent("Top Shelf Image Wide.imageset"),
                  idiom: "tv", scales: [("1x", 2320, 720), ("2x", 4640, 1440)])

    // Top Shelf: 1920x720 @1x, 3840x1440 @2x.
    writeImageset(dir: (brand as NSString).appendingPathComponent("Top Shelf Image.imageset"),
                  idiom: "tv", scales: [("1x", 1920, 720), ("2x", 3840, 1440)])

    // Brand assets manifest.
    writeJSON("""
    {
      "assets" : [
        {
          "filename" : "App Icon - App Store.imagestack",
          "idiom" : "tv",
          "role" : "primary-app-icon",
          "size" : "1280x768"
        },
        {
          "filename" : "App Icon.imagestack",
          "idiom" : "tv",
          "role" : "primary-app-icon",
          "size" : "400x240"
        },
        {
          "filename" : "Top Shelf Image Wide.imageset",
          "idiom" : "tv",
          "role" : "top-shelf-image-wide",
          "size" : "2320x720"
        },
        {
          "filename" : "Top Shelf Image.imageset",
          "idiom" : "tv",
          "role" : "top-shelf-image",
          "size" : "1920x720"
        }
      ],
    \(catalogInfo)
    }
    """, to: (brand as NSString).appendingPathComponent("Contents.json"))
}

// MARK: - iOS

func buildIOS() {
    let catalog = abspath("Apps/Remote/Resources/Assets.xcassets")
    writeCatalogRoot(catalog)
    writeAccentColor(catalogDir: catalog)

    let appicon = (catalog as NSString).appendingPathComponent("AppIcon.appiconset")
    resetDir(appicon)
    // Single-size 1024x1024, no alpha.
    write(renderPNG(width: 1024, height: 1024, opaque: true) { drawFlat($0, 1024, 1024) },
          to: (appicon as NSString).appendingPathComponent("icon_1024.png"))
    writeJSON("""
    {
      "images" : [
        {
          "filename" : "icon_1024.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        }
      ],
    \(catalogInfo)
    }
    """, to: (appicon as NSString).appendingPathComponent("Contents.json"))
}

// MARK: - Main

buildTVOS()
buildIOS()
print("✓ Generated branding assets for JellyTV (tvOS) and Remote (iOS).")
