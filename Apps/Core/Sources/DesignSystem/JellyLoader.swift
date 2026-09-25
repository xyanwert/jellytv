import SwiftUI

// MARK: - The mark, as paths

/// The app mark — the neon jellyfish on the icon (`AppMark`) — as vector paths in a
/// 100×100 unit box, so it can be *drawn* rather than shown: every stroke here can be
/// trimmed on the way SVG line art is animated with `stroke-dashoffset`.
///
/// Traced off the icon: a dome with a scalloped hem, two eyes and a smile, five cyan
/// tentacles in front and four violet ones between them.
enum JellyMarkPaths {
    static let hemY: CGFloat = 41

    /// The bell, one continuous stroke: up the left side, over the top, down the
    /// right, then the scalloped hem back to where it began — so a trim draws it
    /// the way a pen would.
    static var dome: Path {
        var p = Path()
        p.move(to: CGPoint(x: 27, y: hemY - 1))
        p.addCurve(to: CGPoint(x: 51, y: 12.5),
                   control1: CGPoint(x: 24, y: 24), control2: CGPoint(x: 36, y: 12.5))
        p.addCurve(to: CGPoint(x: 75, y: hemY - 1),
                   control1: CGPoint(x: 66, y: 12.5), control2: CGPoint(x: 78, y: 24))
        // Five scallops, right to left.
        let left: CGFloat = 27, right: CGFloat = 75
        let n = 5
        let step = (right - left) / CGFloat(n)
        for i in 0..<n {
            let x0 = right - CGFloat(i) * step
            let x1 = x0 - step
            p.addQuadCurve(to: CGPoint(x: x1, y: hemY - 1),
                           control: CGPoint(x: (x0 + x1) / 2, y: hemY + 2.6))
        }
        return p
    }

    static let eyes: [(center: CGPoint, radius: CGFloat)] = [
        (CGPoint(x: 42, y: 28.5), 2.7),
        (CGPoint(x: 57, y: 28.5), 2.7),
    ]

    static var smile: Path {
        var p = Path()
        p.move(to: CGPoint(x: 45.5, y: 33.2))
        p.addQuadCurve(to: CGPoint(x: 53.5, y: 33.2), control: CGPoint(x: 49.5, y: 37.4))
        return p
    }

    struct Tentacle {
        let x: CGFloat
        let length: CGFloat
        let phase: CGFloat
        let violet: Bool
    }

    /// Front (cyan) and back (violet) tentacles, left to right.
    static let tentacles: [Tentacle] = [
        .init(x: 31, length: 38, phase: 0.0, violet: false),
        .init(x: 35.5, length: 40, phase: 2.1, violet: true),
        .init(x: 40, length: 42, phase: 1.1, violet: false),
        .init(x: 44.5, length: 30, phase: 3.3, violet: true),
        .init(x: 49.5, length: 45, phase: 2.4, violet: false),
        .init(x: 55, length: 38, phase: 0.6, violet: true),
        .init(x: 59.5, length: 40, phase: 3.8, violet: false),
        .init(x: 64, length: 36, phase: 1.7, violet: true),
        .init(x: 69, length: 36, phase: 4.6, violet: false),
    ]

    /// A tentacle as a smooth wave hanging from the hem. `time` sways it: the wave
    /// travels down the tentacle, and it grows with distance from the hem so the
    /// root stays attached to the bell.
    static func tentacle(_ t: Tentacle, time: Double) -> Path {
        var p = Path()
        let segments = 36
        let splay = (t.x - 50) * 0.22
        for i in 0...segments {
            let u = CGFloat(i) / CGFloat(segments)
            let y = hemY + u * t.length
            let wave = sin(Double(u) * 7.2 + Double(t.phase) - time * 2.1)
            let x = t.x + splay * u + CGFloat(wave) * (0.6 + 2.6 * u)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

// MARK: - The animated mark

/// The jellyfish drawing itself in, then breathing, with a glint of light running
/// across its lines on a loop — the loading mark. Everything is one `Canvas` driven by
/// one clock, so the whole animation is a single layer the size of the mark: on a
/// 4K television that is a few percent of the frame, the budget the rest of this
/// app's tvOS motion is held to (see "Movie Night" in CLAUDE.md).
struct JellyLoaderMark: View {
    /// When the animation started; everything is a function of the time since.
    let start: Date
    var paused = false

    /// Seconds for the intro (strokes on, face, first glint begun) — the least a
    /// loading screen holds so the drawing is never cut off half-made.
    static let introDuration: Double = 1.9

    /// `JT_SPLASH_T` / `RT_SPLASH_T` = seconds freezes the mark at that moment, so a
    /// single frame of the draw-in or the glint can be screenshotted exactly —
    /// `simctl io screenshot` cannot be timed to a 60fps animation. Inert unless set.
    private static let frozenAt: Double? = {
        let env = ProcessInfo.processInfo.environment
        return (env["JT_SPLASH_T"] ?? env["RT_SPLASH_T"]).flatMap(Double.init)
    }()

    private static let cyan = Palette.jellyCyan
    private static let violet = Palette.jellyViolet

    var body: some View {
        TimelineView(.animation(paused: paused || Self.frozenAt != nil)) { context in
            let t = Self.frozenAt ?? context.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let side = min(size.width, size.height)
                ctx.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
                ctx.scaleBy(x: side / 100, y: side / 100)
                // Glow first (a blurred copy, wider and softer), then the crisp line.
                ctx.drawLayer { glow in
                    glow.addFilter(.blur(radius: 2.4))
                    glow.opacity = 0.85
                    draw(in: &glow, t: t, width: 3.4)
                }
                draw(in: &ctx, t: t, width: 1.55)
                drawGlint(in: &ctx, t: t)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(in ctx: inout GraphicsContext, t: Double, width: CGFloat) {
        let round = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        // A slow breath once drawn — brightness rides a sine, never below 85%.
        let breath = 0.925 + 0.075 * sin(t * 1.6)

        // Tentacles — back row first so the cyan front row crosses over it.
        for (i, tentacle) in JellyMarkPaths.tentacles.enumerated().sorted(by: { $0.1.violet && !$1.1.violet }) {
            let begin = 0.45 + Double(i) * 0.07
            let drawn = ease((t - begin) / 0.9)
            guard drawn > 0 else { continue }
            let path = JellyMarkPaths.tentacle(tentacle, time: t).trimmedPath(from: 0, to: drawn)
            let color = tentacle.violet ? Self.violet : Self.cyan
            ctx.stroke(path, with: .color(color.opacity((tentacle.violet ? 0.9 : 1) * breath)), style: round)
        }

        // The bell.
        let domeDrawn = ease(t / 1.1)
        if domeDrawn > 0 {
            ctx.stroke(JellyMarkPaths.dome.trimmedPath(from: 0, to: domeDrawn),
                       with: .color(Self.cyan.opacity(breath)), style: round)
        }

        // The face pops in once the bell has closed.
        let face = ease((t - 1.0) / 0.35)
        if face > 0 {
            for eye in JellyMarkPaths.eyes {
                let r = eye.radius * CGFloat(0.4 + 0.6 * face)
                let rect = CGRect(x: eye.center.x - r, y: eye.center.y - r, width: r * 2, height: r * 2)
                ctx.stroke(Path(ellipseIn: rect), with: .color(Self.cyan.opacity(face * breath)), style: round)
            }
            ctx.stroke(JellyMarkPaths.smile.trimmedPath(from: 0, to: face),
                       with: .color(Self.cyan.opacity(breath)), style: round)
        }

    }

    /// Where the glint's band is, across the 100-unit box, or nil while it rests. It
    /// crosses in the first half or so of each period and the mark sits lit for the rest.
    private func glintCenter(_ t: Double) -> CGFloat? {
        let first = 1.15, period = 2.8
        guard t > first else { return nil }
        let p = (t - first).truncatingRemainder(dividingBy: period) / period
        guard p < 0.55 else { return nil }
        return CGFloat(-25 + 150 * ease(p / 0.55))
    }

    /// The glint: a slanted band of white light run across the mark's own lines —
    /// light catching glass, not a thing flying past. The mark is drawn again into
    /// a layer and the band is filled `.sourceIn`, so the light exists only where
    /// the lines do; a blurred pass under it gives the band its bloom. As the band
    /// crosses the top of the bell a four-point twinkle flares there and goes out.
    private func drawGlint(in ctx: inout GraphicsContext, t: Double) {
        guard let c = glintCenter(t) else { return }
        let box = Path(CGRect(x: -10, y: -10, width: 120, height: 120))
        let band = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.55), location: 0.36),
                .init(color: .white, location: 0.5),
                .init(color: .white.opacity(0.55), location: 0.64),
                .init(color: .white.opacity(0), location: 1),
            ]),
            startPoint: CGPoint(x: c - 13, y: 45), endPoint: CGPoint(x: c + 13, y: 55))

        for (width, blur) in [(CGFloat(3.2), CGFloat(2.2)), (1.7, 0)] {
            ctx.drawLayer { layer in
                if blur > 0 {
                    layer.addFilter(.blur(radius: blur))
                    layer.opacity = 0.7
                }
                draw(in: &layer, t: t, width: width)
                layer.blendMode = .sourceIn
                layer.fill(box, with: band)
            }
        }

        // The twinkle, where the bell catches the light.
        let spot = CGPoint(x: 64.5, y: 16.5)
        let flare = max(0, 1 - abs(Double(c - spot.x)) / 16)
        guard flare > 0 else { return }
        let star = twinkle(at: spot, radius: 8 * CGFloat(flare), angle: .degrees(flare * 50))
        ctx.drawLayer { glow in
            glow.addFilter(.blur(radius: 1.8))
            glow.fill(star, with: .color(Self.cyan.opacity(flare)))
        }
        ctx.fill(star, with: .color(.white.opacity(flare)))
    }

    /// A four-point star: long thin rays, pinched hard at the middle.
    private func twinkle(at center: CGPoint, radius: CGFloat, angle: Angle) -> Path {
        var p = Path()
        let inner = radius * 0.16
        for i in 0..<8 {
            let r = i.isMultiple(of: 2) ? radius : inner
            let a = angle.radians + Double(i) * .pi / 4
            let pt = CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    /// Clamped ease-in-out.
    private func ease(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }
}

// MARK: - The launch splash

/// The screen the app opens on while it restores a saved session and loads Home —
/// the mark drawing itself, the wordmark under it, and nothing else, like the
/// streaming apps this one sits next to on the home screen. It holds for at least
/// the intro so the drawing is never cut off half-made, and a readout of what it is
/// waiting on appears only if the wait gets long.
struct LaunchSplash: View {
    /// True once there is something to show (Home loaded, or the reconnect failed
    /// and the form has something to say).
    let isReady: Bool
    /// What is being waited on, for the late readout ("REACHING SERVER").
    var status: String = ""
    let onFinished: () -> Void

    @EnvironmentObject private var theme: Theme
    @State private var start = Date()
    @State private var leaving = false
    @State private var showsStatus = false

    private var markSize: CGFloat {
        switch DeviceClass.current {
        case .tv: return 360
        case .pad: return 260
        case .phone: return 200
        }
    }

    private var wordmarkSize: CGFloat {
        switch DeviceClass.current {
        case .tv: return 54
        case .pad: return 38
        case .phone: return 30
        }
    }

    var body: some View {
        ZStack {
            Palette.page.ignoresSafeArea()
            // A faint pool of the mark's colour behind it, so the page isn't flat black.
            RadialGradient(colors: [Palette.jellyViolet.opacity(0.16), .clear],
                           center: .center, startRadius: 0, endRadius: markSize * 1.6)
                .ignoresSafeArea()

            VStack(spacing: markSize * 0.08) {
                JellyLoaderMark(start: start, paused: leaving)
                    .frame(width: markSize, height: markSize)
                wordmark
                    .opacity(wordmarkShown ? 1 : 0)
                Text(status.uppercased())
                    .font(Mono.font(DeviceClass.current == .tv ? 20 : 13))
                    .tracking(3)
                    .foregroundStyle(Palette.text(0.4))
                    .opacity(showsStatus && !status.isEmpty ? 1 : 0)
                    .animation(.easeOut(duration: 0.4), value: showsStatus)
            }
            .scaleEffect(leaving ? 1.06 : 1)
            .opacity(leaving ? 0 : 1)
        }
        .onAppear {
            // The clock starts on the first frame on screen, not when the view was
            // built — launch work in between would otherwise eat the draw-in.
            start = Date()
        }
        .task {
            // Only a slow wait earns words; a normal launch is the mark alone.
            try? await Task.sleep(for: .seconds(3.5))
            showsStatus = true
        }
        .task(id: isReady) {
            guard isReady else { return }
            let remaining = JellyLoaderMark.introDuration - Date().timeIntervalSince(start)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard !Task.isCancelled else { return }
            // The mark lifts and fades — a small layer, cheap even at 4K — and then the
            // splash is removed in one frame, the way pages cut on tvOS.
            withAnimation(.easeIn(duration: 0.32)) { leaving = true }
            try? await Task.sleep(for: .seconds(0.34))
            onFinished()
        }
    }

    /// The wordmark fades up as the face appears.
    @State private var wordmarkShown = false

    private var wordmark: some View {
        (
            Text("Why").foregroundColor(Palette.textPrimary)
            + Text(".").foregroundColor(theme.accent)
            + Text("So").foregroundColor(Palette.textPrimary)
            + Text(".").foregroundColor(theme.accent)
            + Text("Jelly?").foregroundColor(Palette.textPrimary)
        )
        .font(Typography.font(wordmarkSize, .black))
        .tracking(-1)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(1.1)) { wordmarkShown = true }
        }
    }
}
