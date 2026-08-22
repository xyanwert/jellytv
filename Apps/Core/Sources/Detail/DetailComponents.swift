import SwiftUI
import JellyTVKit

// Shared "editorial dossier" chrome for the Show (2a) and Movie (1b) detail
// screens: the atmospheric backdrop, the left spine, spec-sheet cells, the
// framed key-art panel with its resume card, and the control pills.

/// The detail screen's atmospheric background: the item's art as a full-bleed,
/// blurred, dimmed wallpaper (adapted from the reference app's Backdrop +
/// blurred-wallpaper treatment), a soft accent radial, a sonar-ring motif, and
/// directional scrims fading into the page background for legibility.
struct DetailBackground: View {
    let image: String?
    let artwork: Artwork

    @EnvironmentObject private var theme: Theme
    @State private var sonarPulse = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Palette.screen

                // Blurred wallpaper of the key art, biased to the top-right
                // (away from the title text), fading into the background.
                backdrop
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blur(radius: 55)
                    .saturation(1.15)
                    .opacity(0.5)
                    .overlay(sonarRings.opacity(0.9))

                RadialGradient(
                    colors: [Color(OKLCH(l: 0.34, c: 0.10, h: 235)).opacity(0.5), .clear],
                    center: .init(x: 0.95, y: 0.05), startRadius: 0, endRadius: 1100
                )

                // Legibility scrims: opaque toward the left and bottom (where the
                // title/spec/controls live), clear toward the top-right art.
                LinearGradient(
                    stops: [
                        .init(color: Palette.screen, location: 0.0),
                        .init(color: Palette.screen.opacity(0.7), location: 0.34),
                        .init(color: .clear, location: 0.80),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.30),
                        .init(color: Palette.screen.opacity(0.6), location: 0.62),
                        .init(color: Palette.screen, location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 4).repeatForever(autoreverses: false)) { sonarPulse = true }
        }
    }

    @ViewBuilder private var backdrop: some View {
        if let image, image.hasPrefix("http"), let url = URL(string: image) {
            JellyfinAsyncImage(url: url, fallback: artwork.gradient)
        } else if let image {
            Image(image).resizable().scaledToFill()
        } else {
            artwork.gradient
        }
    }

    private var sonarRings: some View {
        ZStack {
            ForEach(0..<4) { i in
                Circle()
                    .stroke(Color(hex: "#78B4DC").opacity(0.16 - Double(i) * 0.03), lineWidth: 1)
                    .frame(width: 720 - CGFloat(i) * 180, height: 720 - CGFloat(i) * 180)
            }
            Circle()
                .stroke(theme.accent, lineWidth: 2)
                .frame(width: 180, height: 180)
                .scaleEffect(sonarPulse ? 2.2 : 0.7)
                .opacity(sonarPulse ? 0 : 0.6)
        }
        .frame(width: 720, height: 720)
        .position(x: 1720, y: 120)
        .allowsHitTesting(false)
    }
}

/// The detail screens' left spine: vertical genre label, a focusable back
/// control, and a small index marker (e.g. "EP 04" / "FILM 001").
struct DetailSpine: View {
    let genreLabel: String
    let markerTop: String
    let markerBottom: String
    let onBack: () -> Void

    @EnvironmentObject private var theme: Theme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(genreLabel.uppercased())
                .font(Typography.font(15, .semibold))
                .tracking(6)
                .foregroundStyle(Palette.text(0.32))
                .fixedSize()
                .rotationEffect(.degrees(90))
                .frame(height: 320)

            Spacer()

            VStack(spacing: 22) {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.text(0.85))
                        .frame(width: 54, height: 54)
                        .background(Palette.text(0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Palette.text(0.12), lineWidth: 1))
                }
                .buttonStyle(FocusScaleStyle(scale: 1.12, cornerRadius: 15))

                Text("\(markerTop)\n\(markerBottom)")
                    .font(Typography.font(13, .heavy))
                    .tracking(2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(.vertical, 40)
        .frame(width: 118)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.text(0.08)).frame(width: 1) }
    }
}

/// A "SIGNAL … | 4K · HDR · ATMOS"-style technical readout (top-right).
struct DetailTechReadout: View {
    let status: String
    let tech: String

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                Circle().fill(Palette.connected).frame(width: 8, height: 8)
                    .shadow(color: Palette.connected, radius: 6)
                Text(status)
            }
            Text("|").foregroundStyle(Palette.text(0.3))
            Text(tech)
        }
        .font(Typography.font(15, .medium))
        .tracking(1)
        .foregroundStyle(Palette.text(0.6))
    }
}

/// One cell of a 2×2 spec sheet: a mono-ish uppercase label over a value view.
struct SpecCell<Value: View>: View {
    let label: String
    @ViewBuilder var value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(Typography.font(13, .semibold))
                .tracking(2)
                .foregroundStyle(Palette.text(0.4))
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The tvOS vertical padding was generous relative to how little text
        // each cell actually holds (a short label + one line of value) — on
        // iPad's shorter screen that padding alone was most of what made the
        // whole 2×2 spec sheet read as taller than its content needed.
        #if os(iOS)
        .padding(.vertical, 4)
        #else
        .padding(.vertical, 6)
        #endif
        .padding(.horizontal, 20)
    }
}

/// A plain bold spec value.
struct SpecValue: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Typography.font(22, .bold)).foregroundStyle(Palette.textPrimary)
    }
}

/// A rating value: accent star + score + certification.
struct SpecRating: View {
    let rating: String
    let certification: String
    @EnvironmentObject private var theme: Theme
    var body: some View {
        HStack(spacing: 8) {
            Text("★").foregroundStyle(theme.accent)
            Text(rating)
            Text(certification)
                .font(Typography.font(16, .semibold))
                .foregroundStyle(Palette.text(0.4))
        }
        .font(Typography.font(24, .heavy))
        .foregroundStyle(Palette.textPrimary)
    }
}

/// The 2×2 spec-sheet frame (top border + inner dividers) wrapping four cells.
struct SpecSheet<TL: View, TR: View, BL: View, BR: View>: View {
    @ViewBuilder var topLeft: () -> TL
    @ViewBuilder var topRight: () -> TR
    @ViewBuilder var bottomLeft: () -> BL
    @ViewBuilder var bottomRight: () -> BR

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.text(0.12)).frame(height: 1)
            HStack(spacing: 0) { topLeft(); vDivider; topRight() }
            Rectangle().fill(Palette.text(0.08)).frame(height: 1)
            HStack(spacing: 0) { bottomLeft(); vDivider; bottomRight() }
        }
    }
    private var vDivider: some View { Rectangle().fill(Palette.text(0.08)).frame(width: 1) }
}

/// The framed key-art panel: art + accent corner ticks, with a floating resume
/// card overlapping its bottom-left.
struct KeyArtPanel<Resume: View>: View {
    let image: String?
    let artwork: Artwork
    @ViewBuilder var resume: () -> Resume

    @EnvironmentObject private var theme: Theme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            art
                .frame(width: 780, height: 439)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.text(0.1), lineWidth: 1))
                .overlay(alignment: .topLeading) { cornerTick(topLeading: true) }
                .overlay(alignment: .bottomTrailing) { cornerTick(topLeading: false) }
                .shadow(color: .black.opacity(0.6), radius: 40, y: 24)

            resume().offset(x: -32, y: 34)
        }
        .padding(.trailing, 4)
    }

    @ViewBuilder private var art: some View {
        if let image, image.hasPrefix("http"), let url = URL(string: image) {
            JellyfinAsyncImage(url: url, fallback: artwork.gradient)
        } else if let image {
            Image(image).resizable().scaledToFill()
        } else {
            artwork.gradient
        }
    }

    private func cornerTick(topLeading: Bool) -> some View {
        Path { p in
            if topLeading {
                p.move(to: CGPoint(x: 0, y: 24)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 24, y: 0))
            } else {
                p.move(to: CGPoint(x: 0, y: 24)); p.addLine(to: CGPoint(x: 24, y: 24)); p.addLine(to: CGPoint(x: 24, y: 0))
            }
        }
        .stroke(theme.accent, lineWidth: 2)
        .frame(width: 24, height: 24)
        .offset(x: topLeading ? -8 : 8, y: topLeading ? -8 : 8)
    }
}

/// Show-specific season art — bigger than the shared `KeyArtPanel` and
/// deliberately edge-less: a left + bottom fade dissolves it into the page
/// instead of a hard-bordered "TV screen" box, so it reads as an atmospheric
/// backdrop sitting behind the title rather than a discrete side panel.
struct SeasonBackdropPanel<Resume: View>: View {
    let image: String?
    let artwork: Artwork
    @ViewBuilder var resume: () -> Resume

    // tvOS's 1920pt-wide canvas has room for an 860pt art panel *and* a
    // 740pt title column side by side. An iPad landscape screen doesn't —
    // together they overflowed the available width, which is what was
    // squeezing the spec sheet's labels/values down to "RATI…"/"CREA…"/
    // "19…". Narrower (not the tvOS 860) keeps the title column's width back,
    // but *taller* than the first iPad pass — with the spec sheet/title
    // column now compacted (see `ShowView`'s tightened paddings and
    // `SpecCell`'s iOS padding), there's height to spare, and a panel this
    // much taller reads as a real background image behind the header rather
    // than a small corner thumbnail.
    #if os(iOS)
    private let width: CGFloat = 420
    private let height: CGFloat = 400
    #else
    private let width: CGFloat = 860
    private let height: CGFloat = 484
    #endif

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            art
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(fadeMask)
                .shadow(color: .black.opacity(0.5), radius: 50, y: 20)

            // The resume card is positioned relative to the panel's own
            // bounds, so it moves with it automatically as the panel
            // shrinks — only its own footprint/offset need scaling down too
            // so it doesn't dwarf the now-smaller art behind it.
            #if os(iOS)
            resume().offset(x: -18, y: 18)
            #else
            resume().offset(x: -32, y: 34)
            #endif
        }
    }

    @ViewBuilder private var art: some View {
        if let image, image.hasPrefix("http"), let url = URL(string: image) {
            JellyfinAsyncImage(url: url, fallback: artwork.gradient)
        } else if let image {
            Image(image).resizable().scaledToFill()
        } else {
            artwork.gradient
        }
    }

    /// Pre-darken toward the page background at the left/bottom edges
    /// (rather than an alpha cut) — the pre-darken is what makes the image
    /// dissolve into the page instead of hard-cutting.
    private var fadeMask: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Palette.screen, location: 0),
                .init(color: Palette.screen.opacity(0.5), location: 0.14),
                .init(color: .clear, location: 0.36),
            ], startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [
                .init(color: .clear, location: 0.66),
                .init(color: Palette.screen.opacity(0.55), location: 0.92),
                .init(color: Palette.screen, location: 1.0),
            ], startPoint: .top, endPoint: .bottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// The floating resume card (progress ring + play disc + labels) used by both
/// detail screens.
struct ResumeCard: View {
    let title: String
    let remaining: String
    let progress: Double
    /// Overrides the platform-default `cardWidth` — e.g. design 1b-iPad's
    /// resume card sits full-width under the key art panel (452pt) rather
    /// than at its usual fixed floating-card width.
    var width: CGFloat? = nil
    var action: () -> Void = {}

    @EnvironmentObject private var theme: Theme

    // Scaled down to match the now-smaller `SeasonBackdropPanel`/`KeyArtPanel`
    // on iOS — at the tvOS size this card would be nearly as wide as the
    // shrunk art it floats on.
    #if os(iOS)
    private static let ringSize: CGFloat = 58
    private static let playDiscSize: CGFloat = 34
    private static let playIconSize: CGFloat = 13
    private static let cardWidth: CGFloat = 290
    #else
    private static let ringSize: CGFloat = 78
    private static let playDiscSize: CGFloat = 44
    private static let playIconSize: CGFloat = 17
    private static let cardWidth: CGFloat = 410
    #endif

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Palette.text(0.14), lineWidth: 5)
                    Circle().trim(from: 0, to: progress)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle().fill(theme.accent).frame(width: Self.playDiscSize, height: Self.playDiscSize)
                        .overlay(Image(systemName: "play.fill").font(.system(size: Self.playIconSize)).foregroundStyle(.white))
                }
                .frame(width: Self.ringSize, height: Self.ringSize)

                VStack(alignment: .leading, spacing: 3) {
                    Text("RESUME").font(Typography.font(12, .heavy)).tracking(2).foregroundStyle(theme.accent)
                    Text(title).font(Typography.font(20, .heavy)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    Text(remaining).font(Typography.font(14, .medium)).foregroundStyle(Palette.text(0.55))
                }
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(width: width ?? Self.cardWidth)
            .background(Color(hex: "#0E1218").opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.text(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 18)
        }
        .buttonStyle(FocusScaleStyle(scale: 1.05, cornerRadius: 16))
    }
}

/// A secondary control-bar pill (icon + label), focusable.
struct DetailPill: View {
    var icon: String?
    let label: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.system(size: 18, weight: .semibold)) }
                Text(label).lineLimit(1).fixedSize()
            }
            .font(Typography.font(18, .semibold)).foregroundStyle(Palette.text(0.85))
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Palette.text(0.14), lineWidth: 1))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 13))
    }
}

#if os(iOS)
/// iPad's replacement for the tvOS `KeyArtPanel`/`SeasonBackdropPanel`:
/// instead of a small boxed thumbnail sharing a row with the title column,
/// the item's art covers the full screen height on the right, fading into
/// the page background (rather than a hard box edge) as it nears the
/// title/spec-sheet column — a full-bleed atmospheric layer, meant to sit
/// behind `DetailSpine`/`content` in the detail screen's outer `ZStack`
/// (declared after `DetailBackground` so it draws on top of that
/// screen-wide blurred wallpaper, but the spine/title/synopsis text still
/// draws after this and reads on top of it). Shared by `ShowView` (season
/// art) and `MovieDetailView` (key art) — both dossier screens use the same
/// canvas, so the same right-side treatment applies to either.
///
/// Ported directly from `HomeView`'s hero backdrop technique (`heroImage` /
/// `heroScrims` / `heroBottomFade`), just rotated 90° — left↔right here where
/// Home fades top↔bottom: the same 1.5×-then-clip zoom, the same *pre-darken
/// toward black before the alpha mask* trick (so the alpha cutoff dissolves
/// into page-background-colored art rather than cutting a still-vivid image
/// off sharply), and the same wide, multi-stop eased mask instead of a narrow
/// hard one.
///
/// `overlay` renders inside a full-height, trailing-aligned column — a
/// caller that only wants top-anchored content (`ShowView`'s resume card)
/// can just supply it directly; one that wants content pinned to both ends
/// (`MovieDetailView`'s meta panel up top, resume card at the bottom) can
/// wrap it in its own `VStack { top; Spacer(); bottom }`.
struct DetailRightBackdrop<Overlay: View>: View {
    let image: String?
    let artwork: Artwork
    @ViewBuilder var overlay: () -> Overlay

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                ZStack(alignment: .top) {
                    zoomedArt(size: geo.size)
                    leftPreDarken
                    topScrim
                    bottomScrim
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .mask(fadeMask)

                HStack(alignment: .top) {
                    Spacer()
                    overlay()
                }
                .padding(.top, 130)
                .padding(.bottom, 40)
                .padding(.trailing, 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var art: some View {
        if let image, image.hasPrefix("http"), let url = URL(string: image) {
            JellyfinAsyncImage(url: url, fallback: artwork.gradient)
        } else if let image {
            Image(image).resizable().scaledToFill()
        } else {
            artwork.gradient
        }
    }

    /// Rendered into a 1.5× box then clipped back to the frame — the same 50%
    /// zoom `HomeView.heroImage` applies, so the backdrop reads bigger/closer
    /// without changing its footprint.
    private func zoomedArt(size: CGSize) -> some View {
        art
            .frame(width: size.width * 1.5, height: size.height * 1.5)
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    private var topScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.55), location: 0.0),
                .init(color: .black.opacity(0.22), location: 0.07),
                .init(color: .clear, location: 0.16),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var bottomScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.82),
                .init(color: .black.opacity(0.3), location: 0.92),
                .init(color: .black.opacity(0.6), location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Pre-darkens the art toward black as it approaches the title column —
    /// both so that column's text stays legible over art that's still
    /// partway through the alpha fade (`fadeMask` below leaves a lot of the
    /// left half at partial, not zero, opacity), and so the alpha cutoff
    /// dissolves into art that's already near-black — matching the page
    /// background — instead of visibly cutting a still-bright image away.
    /// Same idea as `HomeView.heroScrims`'s bottom pre-darken, on the
    /// opposite axis.
    private var leftPreDarken: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.97), location: 0.0),
                .init(color: .black.opacity(0.93), location: 0.55),
                .init(color: .black.opacity(0.5), location: 0.65),
                .init(color: .black.opacity(0.15), location: 0.75),
                .init(color: .clear, location: 0.85),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    /// Wide, eased alpha fade — mirrors `HomeView.heroBottomFade`'s multi-stop
    /// falloff (several stops rather than one straight ramp so it eases out
    /// gently) rotated onto the horizontal axis. Ramping starts well behind
    /// the title column, but `leftPreDarken` above holds that zone almost
    /// fully black regardless — this curve is what shapes the *reveal* once
    /// the darken eases off past the title/spec-sheet column, not what
    /// protects it (a spec sheet's small text/thin divider lines turned out
    /// far less tolerant of a partially-visible image behind them than
    /// `HomeView`'s bold hero title is, so legibility there needed to come
    /// from the darken, not just from delaying the alpha ramp).
    private var fadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.30),
                .init(color: .white.opacity(0.2), location: 0.45),
                .init(color: .white.opacity(0.5), location: 0.58),
                .init(color: .white.opacity(0.85), location: 0.70),
                .init(color: .white, location: 0.82),
                .init(color: .white, location: 1.0),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }
}
#endif

extension View {
    /// Soft alpha fade at the leading/trailing edges of a horizontally
    /// scrolling strip — content dissolves as it nears the edge instead of
    /// hard-cutting at the scroll view's bounds.
    func horizontalEdgeFade(width: CGFloat = 36) -> some View {
        mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
            }
        )
    }
}
