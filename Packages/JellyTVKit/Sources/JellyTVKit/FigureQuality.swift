import Foundation

/// What a segmentation mask measures like, reduced to the handful of numbers
/// that tell a *figure* — a character standing in the frame — apart from a
/// *scene*: a whole shot minus its sky. Vision cuts both equally happily and
/// reports both as "the foreground", so the app has to judge for itself.
///
/// Measured on the mask at whatever resolution Vision returns; every field is
/// resolution-free except `pixelHeight`, which is the one that says whether
/// the cut can stand 500pt tall on a 4K panel without going soft.
public struct FigureMeasure: Sendable, Equatable {
    /// Mask area over frame area.
    public var coverage: Double
    /// Mask area over its own bounding box's area. A standing figure fills
    /// about half its box; a scene fills nearly all of it.
    public var fill: Double
    /// Bounding-box height over width.
    public var aspect: Double
    /// Bounding-box height in source pixels.
    public var pixelHeight: Int
    /// The box reaches the frame's edge. The bottom is free — legs run off the
    /// bottom of nearly every key visual — but a cut spanning left *and* right
    /// is a scene, and a cropped head is the worst thing a mascot can have.
    public var touchesLeft: Bool
    public var touchesRight: Bool
    public var touchesTop: Bool
    /// The share of the bounding box under detected text: a title baked into
    /// the art and lying across the character comes out inside the cut, and
    /// three letters of a logo on someone's hip reads as a mistake.
    public var textOverlap: Double

    public init(coverage: Double, fill: Double, aspect: Double, pixelHeight: Int,
                touchesLeft: Bool = false, touchesRight: Bool = false, touchesTop: Bool = false,
                textOverlap: Double = 0) {
        self.coverage = coverage
        self.fill = fill
        self.aspect = aspect
        self.pixelHeight = pixelHeight
        self.touchesLeft = touchesLeft
        self.touchesRight = touchesRight
        self.touchesTop = touchesTop
        self.textOverlap = textOverlap
    }
}

/// The figure gate. Tuned against the real art on this server — nine anime
/// series and a sample of the adult library, three images each — where the
/// numbers separated cleanly: every thumb and poster that looked like a
/// character scored high, every backdrop that was a room with people in it
/// scored low, and the ones in between were the ones a person would also
/// hesitate over.
public enum FigureQuality {
    /// Below this the cut is not shown at all; the screen keeps its library
    /// layout rather than standing a blob on the stage.
    public static let pass = 0.72

    /// 0 for an outright rejection, else a weighted 0…1 across size, fill,
    /// shape, edge contact and resolution, less a penalty for text.
    public static func score(_ m: FigureMeasure) -> Double {
        // Hard rejections: nothing to weigh.
        if m.coverage < 0.03 || m.coverage > 0.72 { return 0 }
        if m.fill > 0.86 { return 0 }
        if m.touchesLeft && m.touchesRight { return 0 }
        if m.pixelHeight < 260 { return 0 }

        // Big enough to matter, not so big it is the whole frame.
        let size = ramp(m.coverage, from: 0.03, to: 0.10) * (1 - ramp(m.coverage, from: 0.45, to: 0.70))
        // Figures leave their box mostly empty.
        let fill = 1 - ramp(m.fill, from: 0.62, to: 0.85)
        // Taller than wide, or near enough.
        let shape = ramp(m.aspect, from: 0.45, to: 0.90)
        let edge = max(0, 1 - (m.touchesLeft ? 0.25 : 0) - (m.touchesRight ? 0.25 : 0) - (m.touchesTop ? 0.35 : 0))
        let resolution = ramp(Double(m.pixelHeight), from: 300, to: 700)
        let text = min(1, m.textOverlap / 0.05) * 0.35

        let weighted = 0.15 * size + 0.25 * fill + 0.15 * shape + 0.20 * edge + 0.25 * resolution
        return max(0, min(1, weighted - text))
    }

    /// Whether a cut with this score goes on screen.
    public static func passes(_ score: Double) -> Bool { score >= pass }

    /// The share of `box` covered by `text` rectangles, in one normalised
    /// coordinate space. Overlaps between text boxes are counted twice, which
    /// errs toward penalising — fine for a penalty.
    public static func textOverlap(box: CGRect, text: [CGRect]) -> Double {
        guard box.width > 0, box.height > 0 else { return 0 }
        let area = box.width * box.height
        let covered = text.reduce(0.0) { sum, t in
            let i = box.intersection(t)
            return i.isNull ? sum : sum + Double(i.width * i.height)
        }
        return min(1, covered / Double(area))
    }

    /// 0 at or below `from`, 1 at or above `to`, linear between.
    static func ramp(_ x: Double, from: Double, to: Double) -> Double {
        guard to > from else { return x >= to ? 1 : 0 }
        return min(1, max(0, (x - from) / (to - from)))
    }
}
