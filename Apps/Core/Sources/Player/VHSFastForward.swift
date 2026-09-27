import SwiftUI
import UIKit

/// One second of a VCR fast-forwarding: what a Skip intro / Skip credits
/// press plays while the real seek happens underneath.
///
/// The picture is the tape racing: the episode's own frames from where the
/// viewer was to where the skip lands, cut from the trickplay sheets
/// (`PlayerController.fastForwardFrames`) and flipped fifteen times a
/// second — the flip rate is constant, but *where the tape is* eases in and
/// out (`travel`): it pulls away slowly, races through the middle skipping
/// most of what it passes, and settles onto the landing. Each flip is knocked
/// sideways and rolled a little, the way a head
/// loses lock at speed. Over it, what makes it VHS rather than a slideshow:
/// a red/cyan fringe, fine scanlines, tracking bands sliding down the frame,
/// the jagged head-switching strip at the foot, and the deck's own on-screen
/// display — ▶▶, SP, and a counter racing to the landing time.
///
/// **Cheap on purpose, and only for a second.** No shader: two full-screen
/// copies of one small image, a few rectangles, a static scanline pattern
/// drawn once, and a bottom strip redrawn per frame. It never takes a touch
/// and it is gone as soon as the landing is.
struct VHSFastForward: View {
    let frames: [UIImage]
    let from: Double
    let to: Double
    /// The item's length, so the counter keeps one width (`formatPlayerClock`).
    let runtime: Double
    let started: Date

    /// One second (3 and 1.8 were tried and felt long). `JT_FF_SECONDS` / `RT_FF_SECONDS` overrides it (DEBUG
    /// only) so a simulator screenshot can catch it at all — the effect is
    /// judged frame by frame there and at speed on the Apple TV.
    static let duration: Double = {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let raw = env["JT_FF_SECONDS"] ?? env["RT_FF_SECONDS"], let seconds = Double(raw) { return seconds }
        #endif
        return 1.0
    }()

    /// How many frames to gather for a run: enough that the fast middle of
    /// the eased travel really does skip through the span.
    static let frameCount = 45

    /// Ease in, ease out (cubic): the deck winds up, races, and slows onto
    /// the landing — the counter and the picture both ride it.
    static func travel(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    /// Flips per second — the rate that reads as "very fast" rather than as
    /// a slideshow.
    private static let flipsPerSecond: Double = 15

    var body: some View {
        ZStack {
            TimelineView(.animation) { context in
                let t = min(1, max(0, context.date.timeIntervalSince(started) / Self.duration))
                let step = Int(t * Self.flipsPerSecond * Self.duration)
                ZStack {
                    tape(step: step, travel: Self.travel(t))
                    trackingBands(t: t)
                    headSwitchStrip(step: step)
                    osd(t: t, step: step)
                }
                .opacity(envelope(t))
            }
            Scanlines()
                .opacity(0.22)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// In fast, out fast: a hard deck-switch cut would read as a glitch.
    private func envelope(_ t: Double) -> Double {
        if t < 0.04 { return t / 0.04 }
        if t > 0.94 { return max(0, (1 - t) / 0.06) }
        return 1
    }

    // MARK: - The tape

    @ViewBuilder
    private func tape(step: Int, travel: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            if frames.isEmpty {
                // No trickplay: the live picture shows through, washed and
                // noisy, and the lines and OSD still say what is happening.
                Color.black.opacity(0.35)
            } else {
                let image = frames[min(frames.count - 1, Int((travel * Double(frames.count - 1)).rounded()))]
                // Each flip lands slightly off: sideways skew and a vertical
                // roll, seeded from the step so a flip holds still.
                let jx = (Self.noise(step, 1) - 0.5) * w * 0.025
                let roll = (Self.noise(step, 2) - 0.5) * h * 0.06
                let fringe = max(3, w * 0.004)
                ZStack {
                    Color.black
                    frame(image, w: w, h: h)
                        .saturation(0.75)
                        .contrast(1.18)
                    // The fringe: the same frame, tinted and shifted each
                    // way, screened on top — the colour smearing out of line.
                    frame(image, w: w, h: h)
                        .colorMultiply(Color(red: 1, green: 0.15, blue: 0.2))
                        .offset(x: fringe)
                        .blendMode(.screen)
                        .opacity(0.45)
                    frame(image, w: w, h: h)
                        .colorMultiply(Color(red: 0.1, green: 0.9, blue: 1))
                        .offset(x: -fringe)
                        .blendMode(.screen)
                        .opacity(0.35)
                }
                .offset(x: jx, y: roll)
                .frame(width: w, height: h)
                .clipped()
            }
        }
    }

    private func frame(_ image: UIImage, w: CGFloat, h: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.low)
            .scaledToFill()
            .frame(width: w * 1.04, height: h * 1.04)
            .frame(width: w, height: h)
    }

    // MARK: - Tracking

    /// Three bands sliding down the frame at different speeds — the tape's
    /// tracking noise, bright and thin inside a soft grey smear.
    private func trackingBands(t: Double) -> some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .top) {
                ForEach(0..<3, id: \.self) { i in
                    let speed = [2.4, 3.7, 1.6][i]
                    let height = h * [0.07, 0.025, 0.12][i]
                    let y = (t * speed + Double(i) * 0.37).truncatingRemainder(dividingBy: 1.1) - 0.05
                    band(height: height)
                        .offset(y: y * h)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func band(height: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [.clear, .white.opacity(0.22), .white.opacity(0.08), .clear],
                           startPoint: .top, endPoint: .bottom)
            Rectangle().fill(.white.opacity(0.55)).frame(height: max(1.5, height * 0.06))
                .offset(y: -height * 0.12)
        }
        .frame(height: height)
        .blendMode(.screen)
    }

    /// The strip at the foot where a VCR switches heads: torn sideways,
    /// flecked with white. The only per-frame drawing here, and it is a
    /// sliver of the screen.
    private func headSwitchStrip(step: Int) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let stripH = h * 0.075
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.55)))
                let rows = 9
                for r in 0..<rows {
                    let y = size.height * CGFloat(r) / CGFloat(rows)
                    let tear = CGFloat(Self.noise(step * 13 + r, 3)) * size.width * 0.3
                    let len = size.width * (0.2 + CGFloat(Self.noise(step * 7 + r, 4)) * 0.6)
                    ctx.fill(Path(CGRect(x: tear, y: y, width: len, height: size.height / CGFloat(rows) * 0.35)),
                             with: .color(.white.opacity(0.18 + Self.noise(r + step, 5) * 0.3)))
                }
            }
            .frame(width: w, height: stripH)
            .position(x: w / 2, y: h - stripH / 2)
        }
    }

    // MARK: - On-screen display

    /// The deck talking: ▶▶ top-left over the counter racing to the landing
    /// time, SP top-right. Chunky white with a hard shadow, the way a VCR's
    /// character generator drew it.
    private func osd(t: Double, step: Int) -> some View {
        GeometryReader { geo in
            let unit = geo.size.height / 1080
            let size = 64 * unit
            let now = from + (to - from) * Self.travel(t)
            let text = Font.system(size: size, weight: .heavy, design: .monospaced)
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 10 * unit) {
                    HStack(spacing: 18 * unit) {
                        Text("▶▶").font(text)
                        Text("FF").font(text)
                    }
                    // The glyph blinks, as they did.
                    .opacity(step % 4 < 3 ? 1 : 0.35)
                    Text(formatPlayerClock(now, matching: runtime))
                        .font(.system(size: size * 0.7, weight: .heavy, design: .monospaced))
                        .monospacedDigit()
                }
                .padding(.leading, 110 * unit)
                .padding(.top, 90 * unit)

                Text("SP")
                    .font(text)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 110 * unit)
                    .padding(.top, 90 * unit)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.85), radius: 0, x: 4 * unit, y: 4 * unit)
        }
    }

    /// Deterministic 0…1 noise, so a given step always jitters the same way
    /// (a flip holds still for its whole 1/15 s instead of shimmering).
    static func noise(_ n: Int, _ salt: Int) -> Double {
        let x = sin(Double(n) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }
}

/// Fine horizontal scanlines, drawn once — no state, so SwiftUI never asks
/// the `Canvas` to redraw it while the timeline ticks above.
private struct Scanlines: View {
    var body: some View {
        Canvas { ctx, size in
            let pitch: CGFloat = max(3, size.height / 360)
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: pitch * 0.45)),
                         with: .color(.black))
                y += pitch
            }
        }
        .drawingGroup()
    }
}
