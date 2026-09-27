import Foundation

/// Where a VCR's tape is during a fast-forward, moment by moment — the
/// arithmetic behind `VHSFastForward`, kept pure so the shape of the run can
/// be checked without a simulator.
///
/// A run has two parts. For `tapeDuration` seconds the tape **travels** from
/// the pressed moment to the landing on a quintic ease-in-out: it pulls
/// away slowly, races through the middle (most of the span goes by in the
/// middle third), and slows onto the landing frame. After that it is
/// **holding**: parked on the landing, waiting for the player to have the
/// picture there. The hold is what covers a slow seek — the deck shows the
/// frame it is about to play instead of a black screen — and it ends when
/// the player says the picture is back, not on a timer.
public struct VHSTapeTimeline: Equatable, Sendable {
    /// How long the travel takes. The hold after it is open-ended.
    public let tapeDuration: Double
    /// Seconds since the run began.
    public let elapsed: Double

    public init(tapeDuration: Double, elapsed: Double) {
        self.tapeDuration = tapeDuration
        self.elapsed = max(0, elapsed)
    }

    /// 0…1 through the travel; 1 for the whole hold.
    public var progress: Double {
        guard tapeDuration > 0 else { return 1 }
        return min(1, elapsed / tapeDuration)
    }

    /// Where the tape is between the pressed moment (0) and the landing (1).
    public var travel: Double { Self.travel(progress) }

    /// How fast the tape is moving, 0…1 — 0 at both ends, 1 at the middle.
    /// Everything that reads as "speed" on screen (flip rate, the sideways
    /// knock, the colour fringe, the tracking bands) scales with it.
    public var speed: Double { Self.speed(progress) }

    /// Settled on the landing, waiting for the picture.
    public var isHolding: Bool { elapsed >= tapeDuration }

    /// Seconds spent holding so far (0 while travelling).
    public var holdElapsed: Double { max(0, elapsed - tapeDuration) }

    /// Which of `count` frames, evenly spaced from the pressed moment to the
    /// landing, the tape is on.
    public func frameIndex(count: Int) -> Int {
        guard count > 1 else { return 0 }
        return min(count - 1, max(0, Int((travel * Double(count - 1)).rounded())))
    }

    /// A counter that advances once per "flip" — the moments the picture
    /// is knocked and re-seeded. A flip is a unit of tape distance plus a
    /// slow tick at rest, so flips come slowly at the ends of the travel
    /// and fast through the middle, and during the hold they come at
    /// `holdRate` per second: a parked deck's picture still wobbles.
    public func flipStep(restRate: Double, raceFlips: Double, holdRate: Double) -> Int {
        if isHolding {
            return Int(tapeDuration * restRate + raceFlips + holdElapsed * holdRate)
        }
        return Int(elapsed * restRate + travel * raceFlips)
    }

    /// Where the counter reads, in seconds of the item.
    public func position(from: Double, to: Double) -> Double {
        from + (to - from) * travel
    }

    /// Quintic ease-in-out. A cubic was too even to read as
    /// slow-fast-slow at this length; the quintic holds the ends back and
    /// spends the middle third on ~85% of the span.
    public static func travel(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        return t < 0.5 ? 16 * pow(t, 5) : 1 - pow(-2 * t + 2, 5) / 2
    }

    /// The derivative of `travel`, normalised so the peak (at t = 0.5) is 1.
    public static func speed(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        return t < 0.5 ? 16 * pow(t, 4) : pow(-2 * t + 2, 4)
    }
}
