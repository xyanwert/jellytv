import SwiftUI
import UIKit
import JellyTVKit

/// A VCR fast-forwarding: what a Skip intro / Skip credits press plays while
/// the real seek happens underneath.
///
/// The picture is the tape racing: the episode's own frames from where the
/// viewer was to where the skip lands, cut from the trickplay sheets
/// (`PlayerController.fastForwardFrames`). Where the tape *is* comes from
/// `VHSTapeTimeline` (kit, tested): it pulls away slowly, races through the
/// middle skipping most of what it passes, and slows onto the landing — and
/// everything that reads as speed rides that curve, so the deck audibly
/// winds up and winds down rather than running flat out for a second. The
/// flips (each one knocked sideways and rolled a little, the way a head
/// loses lock at speed) come slowly at the ends and fast in the middle; the
/// red/cyan fringe, the tracking bands sliding down the frame and the
/// head-switching strip at the foot all swell with the speed and calm as it
/// settles. Over it, the deck's own on-screen display — ▶▶ FF, SP, and a
/// counter racing to the landing time.
///
/// **It ends when the picture is back, not on a timer.** After
/// `tapeDuration` the tape is parked on the landing frame — a still with a
/// slow wobble, faint fringe, the OSD gone to ▶ PLAY — for as long as the
/// player needs to have that frame ready (`PlayerEngine.skipHolding`). A
/// seek can take several seconds, and a deck showing the frame it is about
/// to play is the honest picture for that wait; a black screen was what it
/// used to show. `PlayerChrome` removes this view the moment the hold is
/// released.
///
/// **Cheap on purpose.** No shader: two full-screen copies of one small
/// image, a few rectangles, a static scanline pattern drawn once, and a
/// bottom strip redrawn per flip. It never takes a touch.
struct VHSFastForward: View {
    let frames: [UIImage]
    let from: Double
    let to: Double
    /// The item's length, so the counter keeps one width (`formatPlayerClock`).
    let runtime: Double
    let started: Date
    /// The player's own decoded frame at the landing, once the held seek
    /// has it (`PlayerEngine.HeldSkip.landingFrame`): the still the tape
    /// settles and parks on, so the live picture the fade reveals is the
    /// same image. Until then, and without it, the last trickplay tile.
    var landingFrame: UIImage? = nil

    /// How long the travel takes; the hold after it is the seek's to fill.
    /// 1.6s: long enough for the slow ends to read as slow (a 1s run was
    /// all middle). `JT_FF_SECONDS` / `RT_FF_SECONDS` overrides it (DEBUG
    /// only) so a simulator screenshot can catch a phase at all — the run
    /// is judged frame by frame there and at speed on the Apple TV.
    static let tapeDuration: Double = {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let raw = env["JT_FF_SECONDS"] ?? env["RT_FF_SECONDS"], let seconds = Double(raw) { return seconds }
        #endif
        return 1.6
    }()

    /// How many frames to gather for a run: enough that the fast middle of
    /// the travel really does skip through the span.
    static let frameCount = 45

    /// Flips per second with the tape at rest, flips over the whole race
    /// (concentrated where the tape is fastest — around twenty a second at
    /// the peak), and flips per second while parked on the landing.
    private static let restFlipRate = 2.0
    private static let raceFlips = 6.0
    private static let holdFlipRate = 1.0

    var body: some View {
        ZStack {
            TimelineView(.animation) { context in
                let tape = VHSTapeTimeline(tapeDuration: Self.tapeDuration,
                                           elapsed: context.date.timeIntervalSince(started))
                let step = tape.flipStep(restRate: Self.restFlipRate, raceFlips: Self.raceFlips,
                                         holdRate: Self.holdFlipRate)
                ZStack {
                    picture(tape: tape, step: step)
                    trackingBands(tape: tape)
                    headSwitchStrip(tape: tape, step: step)
                    osd(tape: tape, step: step)
                }
                .opacity(min(1, tape.elapsed / 0.06))
            }
            Scanlines()
                .opacity(0.22)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// How hard the picture is being knocked about right now, 0…1: with the
    /// speed while travelling, a faint tremor while parked.
    private func turbulence(_ tape: VHSTapeTimeline) -> Double {
        tape.isHolding ? 0.12 : 0.15 + 0.85 * tape.speed
    }

    // MARK: - The tape

    @ViewBuilder
    private func picture(tape: VHSTapeTimeline, step: Int) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            if let image = pictureFrame(tape) {
                let knock = turbulence(tape)
                // Each flip lands slightly off: sideways skew and a vertical
                // roll, seeded from the step so a flip holds still.
                let jx = (Self.noise(step, 1) - 0.5) * w * 0.028 * knock
                let roll = (Self.noise(step, 2) - 0.5) * h * 0.07 * knock
                let fringe = max(1, w * 0.005) * knock
                let fringeOpacity = 0.3 + 0.7 * knock
                ZStack {
                    Color.black
                    frame(image, w: w, h: h)
                        .saturation(0.95 - 0.2 * knock)
                        .contrast(1.06 + 0.14 * knock)
                    // The fringe: the same frame, tinted and shifted each
                    // way, screened on top — the colour smearing out of line.
                    frame(image, w: w, h: h)
                        .colorMultiply(Color(red: 1, green: 0.15, blue: 0.2))
                        .offset(x: fringe)
                        .blendMode(.screen)
                        .opacity(0.45 * fringeOpacity)
                    frame(image, w: w, h: h)
                        .colorMultiply(Color(red: 0.1, green: 0.9, blue: 1))
                        .offset(x: -fringe)
                        .blendMode(.screen)
                        .opacity(0.35 * fringeOpacity)
                }
                .offset(x: jx, y: roll)
                .frame(width: w, height: h)
                .clipped()
            } else {
                // No trickplay and nothing from the player yet: the live
                // picture shows through, washed and noisy, and the lines and
                // OSD still say what is happening.
                Color.black.opacity(0.35)
            }
        }
    }

    /// The frame under the tape right now: the trickplay tile for where the
    /// tape is, the player's own frame once the tape reaches the landing.
    private func pictureFrame(_ tape: VHSTapeTimeline) -> UIImage? {
        guard !frames.isEmpty else { return tape.isHolding ? landingFrame : nil }
        let index = tape.frameIndex(count: frames.count)
        return (index == frames.count - 1 ? landingFrame : nil) ?? frames[index]
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
    /// tracking noise, bright and thin inside a soft grey smear. They move
    /// with the tape and creep while it is parked, and they are brightest
    /// at speed.
    private func trackingBands(tape: VHSTapeTimeline) -> some View {
        GeometryReader { geo in
            let h = geo.size.height
            let drift = tape.travel + tape.holdElapsed * 0.12
            ZStack(alignment: .top) {
                ForEach(0..<3, id: \.self) { i in
                    let speed = [2.4, 3.7, 1.6][i]
                    let height = h * [0.07, 0.025, 0.12][i]
                    let y = (drift * speed + Double(i) * 0.37).truncatingRemainder(dividingBy: 1.1) - 0.05
                    band(height: height)
                        .offset(y: y * h)
                }
            }
            .opacity(0.25 + 0.75 * turbulence(tape))
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
    /// flecked with white. The only per-flip drawing here, and it is a
    /// sliver of the screen.
    private func headSwitchStrip(tape: VHSTapeTimeline, step: Int) -> some View {
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
            .opacity(0.3 + 0.7 * turbulence(tape))
        }
    }

    // MARK: - On-screen display

    /// The deck talking: ▶▶ FF top-left over the counter racing to the
    /// landing time, SP top-right; once parked, ▶ PLAY blinking while the
    /// picture comes. Chunky white with a hard shadow, the way a VCR's
    /// character generator drew it.
    private func osd(tape: VHSTapeTimeline, step: Int) -> some View {
        GeometryReader { geo in
            let unit = geo.size.height / 1080
            let size = 64 * unit
            let text = Font.system(size: size, weight: .heavy, design: .monospaced)
            // FF blinks with the flips; PLAY blinks on its own slow clock,
            // as a deck's does while it finds the picture.
            let lit = tape.isHolding ? Int(tape.holdElapsed * 2) % 2 == 0 : step % 4 < 3
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 10 * unit) {
                    HStack(spacing: 18 * unit) {
                        Text(tape.isHolding ? "▶" : "▶▶").font(text)
                        Text(tape.isHolding ? "PLAY" : "FF").font(text)
                    }
                    .opacity(lit ? 1 : 0.35)
                    Text(formatPlayerClock(tape.position(from: from, to: to), matching: runtime))
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
    /// (a flip holds still between steps instead of shimmering).
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
