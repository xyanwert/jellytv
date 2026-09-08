import SwiftUI

/// Rail nav icons, hand-drawn to match the design reference's 24×24 stroke
/// paths (1.9pt stroke, round caps/joins, no fill). The Settings cog uses the
/// system gearshape glyph instead of replicating its bezier path by hand.
enum NavIcons {
    static func home(color: Color) -> some View {
        IconCanvas(color: color) { path in
            path.move(to: CGPoint(x: 3, y: 10.5))
            path.addLine(to: CGPoint(x: 12, y: 3))
            path.addLine(to: CGPoint(x: 21, y: 10.5))
            path.move(to: CGPoint(x: 5, y: 9.5))
            path.addLine(to: CGPoint(x: 5, y: 21))
            path.addLine(to: CGPoint(x: 19, y: 21))
            path.addLine(to: CGPoint(x: 19, y: 9.5))
        }
    }

    static func search(color: Color) -> some View {
        IconCanvas(color: color) { path in
            path.addEllipse(in: CGRect(x: 4, y: 4, width: 14, height: 14))
            path.move(to: CGPoint(x: 16.5, y: 16.5))
            path.addLine(to: CGPoint(x: 20, y: 20))
        }
    }

    static func movies(color: Color) -> some View {
        IconCanvas(color: color) { path in
            path.addRoundedRect(in: CGRect(x: 3, y: 3, width: 18, height: 18), cornerSize: CGSize(width: 3, height: 3))
            path.move(to: CGPoint(x: 7.5, y: 3)); path.addLine(to: CGPoint(x: 7.5, y: 21))
            path.move(to: CGPoint(x: 16.5, y: 3)); path.addLine(to: CGPoint(x: 16.5, y: 21))
            path.move(to: CGPoint(x: 3, y: 8)); path.addLine(to: CGPoint(x: 7.5, y: 8))
            path.move(to: CGPoint(x: 3, y: 16)); path.addLine(to: CGPoint(x: 7.5, y: 16))
            path.move(to: CGPoint(x: 16.5, y: 8)); path.addLine(to: CGPoint(x: 21, y: 8))
            path.move(to: CGPoint(x: 16.5, y: 16)); path.addLine(to: CGPoint(x: 21, y: 16))
        }
    }

    static func tv(color: Color) -> some View {
        IconCanvas(color: color) { path in
            path.addRoundedRect(in: CGRect(x: 2.5, y: 6, width: 19, height: 12.5), cornerSize: CGSize(width: 2.5, height: 2.5))
            path.move(to: CGPoint(x: 8, y: 2.5))
            path.addLine(to: CGPoint(x: 12, y: 6))
            path.addLine(to: CGPoint(x: 16, y: 2.5))
        }
    }

    /// 2×2 rounded-square grid with a `+` in place of the 4th square — reads as
    /// "your libraries, expandable" rather than a plain grid glyph.
    static func libraries(color: Color) -> some View {
        IconCanvas(color: color) { path in
            path.addRoundedRect(in: CGRect(x: 3, y: 3, width: 7.5, height: 7.5), cornerSize: CGSize(width: 1.6, height: 1.6))
            path.addRoundedRect(in: CGRect(x: 13.5, y: 3, width: 7.5, height: 7.5), cornerSize: CGSize(width: 1.6, height: 1.6))
            path.addRoundedRect(in: CGRect(x: 3, y: 13.5, width: 7.5, height: 7.5), cornerSize: CGSize(width: 1.6, height: 1.6))
            path.move(to: CGPoint(x: 17.25, y: 14.25)); path.addLine(to: CGPoint(x: 17.25, y: 20.25))
            path.move(to: CGPoint(x: 14.25, y: 17.25)); path.addLine(to: CGPoint(x: 20.25, y: 17.25))
        }
    }

    /// Discover — a compass rose. Deliberately *not* the magnifier: Search looks
    /// through what you already own, Discover looks outward at what you don't, and two
    /// glyphs that both mean "find" would make the rail ambiguous at a glance.
    static func discover(color: Color) -> some View {
        IconCanvas(color: color) { path in
            path.addEllipse(in: CGRect(x: 2.5, y: 2.5, width: 19, height: 19))
            // The needle: two triangles meeting at the centre, drawn as one closed kite
            // so it reads at rail size instead of turning to mush.
            path.move(to: CGPoint(x: 15.4, y: 8.6))
            path.addLine(to: CGPoint(x: 13.1, y: 13.1))
            path.addLine(to: CGPoint(x: 8.6, y: 15.4))
            path.addLine(to: CGPoint(x: 10.9, y: 10.9))
            path.closeSubpath()
        }
    }

    /// Downloads — an arrow into a tray. The tray matters: a bare down-arrow is the
    /// universal "scroll down" and would read as a rail affordance rather than a place.
    static func downloads(color: Color) -> some View {
        IconCanvas(color: color) { path in
            path.move(to: CGPoint(x: 12, y: 3))
            path.addLine(to: CGPoint(x: 12, y: 14.5))
            path.move(to: CGPoint(x: 7.5, y: 10.5))
            path.addLine(to: CGPoint(x: 12, y: 15))
            path.addLine(to: CGPoint(x: 16.5, y: 10.5))
            path.move(to: CGPoint(x: 4, y: 17))
            path.addLine(to: CGPoint(x: 4, y: 20))
            path.addLine(to: CGPoint(x: 20, y: 20))
            path.addLine(to: CGPoint(x: 20, y: 17))
        }
    }

    static func cog(color: Color) -> some View {
        Image(systemName: "gearshape")
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
    }
}

/// Strokes a hand-built 24×24 path with the design's stroke weight/caps.
private struct IconCanvas: View {
    let color: Color
    let build: (inout Path) -> Void

    var body: some View {
        Path(build)
            .stroke(color, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
            .frame(width: 24, height: 24)
    }
}
