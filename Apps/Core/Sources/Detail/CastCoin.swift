import SwiftUI
import JellyTVKit

#if os(tvOS)
/// A cast member struck as a coin.
///
/// The headshot sits recessed in a milled metal rim — gold for an Academy
/// Award winner, silver for everyone else — with the coin's thickness showing
/// on the side turned toward you. Where Vision cut a bust out of the headshot
/// (`PortraitCutoutCache`), it stands on the coin's field in relief, its head
/// rising above the top of the rim the way a head breaks the edge of a
/// commemorative coin; until then, and wherever the cut-out isn't possible,
/// the photo itself fills the field.
///
/// **The coin under the remote is live.** It spins in on arrival — one full
/// turn, easing out, showing its tails side (a star struck in the same metal)
/// on the way round — then rocks a few degrees and a light travels its rim, so
/// it catches the light the way a coin held up to a lamp does. Coins at rest
/// lean alternately, like a row standing on a table.
///
/// All of it is transforms and gradients: `rotation3DEffect` for the turn and
/// the lean, an `AngularGradient` whose angle moves for the sweep, offset discs
/// for the thickness. Only the live coin ticks (its `TimelineView` is paused
/// otherwise), so eight of these cost what one does.
struct CastCoin: View {
    let member: CastMember
    let tint: Color
    /// Diameter. The view is taller than this by `reliefOverflow`, to make
    /// room for the bust above the rim.
    let size: CGFloat
    /// Spinning in, rocking, rim light travelling. The lineup passes focus;
    /// the person sheet's hero coin is always live.
    let live: Bool
    /// Degrees of lean about the vertical axis for a coin at rest.
    var restingLean: Double = 0

    @State private var cutout: UIImage?
    @State private var liveSince: Date?

    /// How far the relief bust may rise above the rim, as a share of the diameter.
    static let reliefOverflow: CGFloat = 0.17

    static func height(for size: CGFloat) -> CGFloat { size * (1 + reliefOverflow) }

    private var metal: CoinMetal { member.wonOscar ? .gold : .silver }
    private var rim: CGFloat { max(6, (size * 0.055).rounded()) }
    private var overflow: CGFloat { size * Self.reliefOverflow }
    /// The coin's centre within the taller frame — what the 3D turn pivots on.
    private var pivot: UnitPoint { UnitPoint(x: 0.5, y: (Self.reliefOverflow + 0.5) / (1 + Self.reliefOverflow)) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !live)) { context in
            let elapsed = liveSince.map { context.date.timeIntervalSince($0) }
            coin(pose: pose(at: live ? elapsed : nil))
        }
        .frame(width: size, height: Self.height(for: size), alignment: .bottom)
        .onChange(of: live, initial: true) { _, isLive in liveSince = isLive ? Date() : nil }
        .animation(.easeOut(duration: 0.35), value: cutout != nil)
        .task(id: member.imageURL) {
            guard PortraitCutoutCache.isSupported, let url = member.imageURL else { return }
            cutout = await PortraitCutoutCache.shared.cutout(for: url)
        }
    }

    // MARK: - Pose

    private struct Pose {
        var yaw: Double      // about the vertical axis, degrees
        var pitch: Double    // about the horizontal axis, degrees
        var sweep: Double    // where the rim light is, degrees
        var glint: Double    // strength of the surface highlight, 0…1
        var streak: Double?  // 0…1 position of the light passing over the face; nil at rest
        var live: Bool
        var facingFront: Bool { cos(yaw * .pi / 180) >= 0 }
        var yawSine: CGFloat { CGFloat(sin(yaw * .pi / 180)) }
    }

    /// One full turn on arrival, easing out over 0.85s, then a slow rock and
    /// nod that fade in as the turn settles, with a light passing over the
    /// face every couple of seconds. At rest: the given lean, no motion.
    private func pose(at elapsed: TimeInterval?) -> Pose {
        guard let t = elapsed else {
            return Pose(yaw: restingLean, pitch: 0, sweep: -35, glint: 0.32, streak: nil, live: false)
        }
        let progress = min(1, t / 0.85)
        let turn = 360 * (1 - pow(1 - progress, 3))
        let settle = min(1, max(0, (t - 0.65) / 0.8))
        let rock = sin(t * 1.35) * 10 * settle
        let nod = sin(t * 0.9 + 1.2) * 4 * settle
        let streak = settle > 0 ? ((t - 0.65) * 0.42).truncatingRemainder(dividingBy: 1) : nil
        return Pose(yaw: turn + rock, pitch: nod, sweep: -35 + t * 70, glint: 0.7, streak: streak, live: true)
    }

    // MARK: - Assembly

    private func coin(pose: Pose) -> some View {
        ZStack(alignment: .bottom) {
            disc(pose)
                .frame(width: size, height: size)
            if pose.facingFront, let cutout {
                relief(cutout)
            }
        }
        .frame(width: size, height: Self.height(for: size), alignment: .bottom)
        .rotation3DEffect(.degrees(pose.yaw), axis: (x: 0, y: 1, z: 0), anchor: pivot, perspective: 0.6)
        .rotation3DEffect(.degrees(pose.pitch), axis: (x: 1, y: 0, z: 0), anchor: pivot, perspective: 0.6)
        .shadow(color: pose.live ? tint.opacity(0.55) : .black.opacity(0.5),
                radius: pose.live ? 30 : 16, y: 12)
    }

    /// The disc itself: thickness, base metal, the face (heads or tails), the
    /// rim, and the highlight sliding across it as it turns.
    private func disc(_ pose: Pose) -> some View {
        ZStack {
            // Thickness: darker discs stepped out on the side turned toward
            // us, so the coin reads as a slab rather than a sticker.
            ForEach(0..<5, id: \.self) { step in
                Circle().fill(metal.edge)
                    .offset(x: -pose.yawSine * CGFloat(step + 1) * size * 0.02)
            }
            Circle().fill(metal.body)
            if pose.facingFront { heads } else { tails }
            rimRing(pose)
            glint(pose)
            if let streak = pose.streak { self.streak(at: streak) }
        }
        .frame(width: size, height: size)
    }

    /// A band of light crossing the face, the way a lamp crosses a coin
    /// turned in the hand. Clipped to the coin so it never spills.
    private func streak(at phase: Double) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [.clear, .white.opacity(0.30), .clear],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: size * 0.34, height: size * 1.7)
            .rotationEffect(.degrees(28))
            .offset(x: (CGFloat(phase) * 2.0 - 1.0) * size)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .blendMode(.screen)
    }

    // MARK: - Faces

    private var fieldDiameter: CGFloat { size - 2 * rim }

    /// The front: the photo in the recess — or, once the bust stands on the
    /// coin, the bare field it stands against.
    private var heads: some View {
        ZStack {
            Circle().fill(metal.field)
            if cutout == nil {
                headshot
                    .frame(width: fieldDiameter, height: fieldDiameter)
                    .clipShape(Circle())
                Circle().fill(RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center,
                                             startRadius: fieldDiameter * 0.30, endRadius: fieldDiameter * 0.52))
            } else {
                etchedRings
            }
            recess
        }
        .frame(width: fieldDiameter, height: fieldDiameter)
        .clipShape(Circle())
    }

    /// The back, seen only mid-turn: rings and a star struck in the metal,
    /// with a hairline of the film's own colour.
    private var tails: some View {
        ZStack {
            Circle().fill(metal.field)
            etchedRings
            Circle().inset(by: fieldDiameter * 0.17)
                .strokeBorder(tint.opacity(0.75), lineWidth: 2)
            Image(systemName: "star.fill")
                .font(.system(size: fieldDiameter * 0.34, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [metal.stops[0], metal.stops[1]],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.6), radius: 2, y: 2)
            recess
        }
        .frame(width: fieldDiameter, height: fieldDiameter)
        .clipShape(Circle())
    }

    /// The inner shadow where the field drops below the rim.
    private var recess: some View {
        Circle().strokeBorder(.black.opacity(0.6), lineWidth: rim * 0.9)
            .blur(radius: rim * 0.5)
    }

    private var etchedRings: some View {
        ForEach(0..<4, id: \.self) { ring in
            Circle().inset(by: size * 0.06 + CGFloat(ring) * size * 0.075)
                .strokeBorder(metal.etch.opacity(0.35), lineWidth: 1)
        }
    }

    @ViewBuilder private var headshot: some View {
        if let string = member.imageURL, let url = URL(string: string) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                case .empty, .failure: monogram
                @unknown default: monogram
                }
            }
        } else {
            monogram
        }
    }

    /// Same deterministic two-tone monogram as `CastPortrait`, so a person
    /// with no headshot is the same colour here as on every other screen.
    private var monogram: some View {
        let hue = Double(abs(member.id.hashValue) % 360)
        return ZStack {
            LinearGradient(
                colors: [Color(OKLCH(l: 0.56, c: 0.13, h: hue)),
                         Color(OKLCH(l: 0.38, c: 0.11, h: hue + 26))],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(member.initials)
                .font(Typography.font(fieldDiameter * 0.34, .heavy))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    // MARK: - Rim and light

    /// Brushed metal (an angular gradient of light and dark stops, its angle
    /// carrying the travelling light), milled reeding, a dark outer edge and
    /// a bright inner lip. Live: the film's colour burns at the edge; the lead
    /// at rest keeps a hairline of it.
    private func rimRing(_ pose: Pose) -> some View {
        ZStack {
            Circle().strokeBorder(
                AngularGradient(colors: metal.stops, center: .center, angle: .degrees(pose.sweep)),
                lineWidth: rim)
            Circle().strokeBorder(.black.opacity(0.28), style: StrokeStyle(lineWidth: rim, dash: [1.5, 2.6]))
            // The chamfer: an inner bevel lit from a different angle than the
            // flat of the rim, which is what makes the rim read as raised.
            Circle().inset(by: rim * 0.55).strokeBorder(
                AngularGradient(colors: [.white.opacity(0.55), .black.opacity(0.45), .white.opacity(0.4),
                                         .black.opacity(0.5), .white.opacity(0.55)],
                                center: .center, angle: .degrees(pose.sweep + 50)),
                lineWidth: rim * 0.45)
            Circle().strokeBorder(.black.opacity(0.7), lineWidth: 1)
            Circle().inset(by: rim - 1).strokeBorder(.white.opacity(0.45), lineWidth: 1)
            if pose.live {
                Circle().strokeBorder(tint.opacity(0.9), lineWidth: 2.5).blur(radius: 1)
            } else if member.isLead {
                Circle().strokeBorder(tint.opacity(0.7), lineWidth: 1.5)
            }
        }
    }

    /// A soft highlight on the surface that slides with the turn.
    private func glint(_ pose: Pose) -> some View {
        Circle()
            .fill(RadialGradient(colors: [.white.opacity(0.55 * pose.glint), .clear],
                                 center: .center, startRadius: 0, endRadius: size * 0.34))
            .frame(width: size * 0.7, height: size * 0.7)
            .offset(x: -pose.yawSine * size * 0.22 - size * 0.08, y: -size * 0.2)
            .blendMode(.screen)
    }

    // MARK: - Relief

    /// The cut-out bust standing on the field: clipped to the field below the
    /// coin's centre line so the shoulders end at the rim, free above it so
    /// the head rises past the edge.
    ///
    /// The photo's own straight edges must never show. Its bottom sits on the
    /// coin's bottom, below the field, so the circle always does the cutting
    /// there; its sides are feathered, so hair or a shoulder that reaches the
    /// photo's edge fades rather than stopping on a hard vertical line.
    private func relief(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: size * Self.bustWidthShare, height: Self.height(for: size), alignment: .bottom)
            .mask { sideFeather }
            .frame(width: size, height: Self.height(for: size), alignment: .bottom)
            .mask { reliefMask }
            .shadow(color: .black.opacity(0.55), radius: 6, y: 5)
            .transition(.opacity)
    }

    private static let bustWidthShare: CGFloat = 0.80

    private var sideFeather: some View {
        Rectangle().fill(LinearGradient(
            stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.15),
                    .init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
            startPoint: .leading, endPoint: .trailing))
    }

    private var reliefMask: some View {
        ZStack(alignment: .bottom) {
            Circle().inset(by: rim).frame(width: size, height: size)
            Rectangle()
                .frame(width: size, height: overflow + size * 0.5)
                .frame(width: size, height: Self.height(for: size), alignment: .top)
        }
        .frame(width: size, height: Self.height(for: size))
    }
}

/// The two metals a coin is struck in.
private enum CoinMetal {
    case silver, gold

    /// Light and dark alternating around the rim — brushed metal under a lamp.
    var stops: [Color] {
        switch self {
        case .silver: return ["#F7F9FC", "#9FA8B5", "#E6EAF0", "#707A88", "#F7F9FC"].map { Color(hex: $0) }
        case .gold: return ["#FFF1BF", "#C79A2E", "#FFE58F", "#916814", "#FFF1BF"].map { Color(hex: $0) }
        }
    }
    var body: Color { Color(hex: self == .gold ? "#D4AC45" : "#B9C1CC") }
    var field: Color { Color(hex: self == .gold ? "#3A2C0F" : "#1E232C") }
    var edge: Color { Color(hex: self == .gold ? "#7A5A14" : "#5C6470") }
    var etch: Color { Color(hex: self == .gold ? "#F1D27A" : "#DCE2EA") }
}
#endif
