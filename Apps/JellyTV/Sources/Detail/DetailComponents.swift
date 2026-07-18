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

/// The detail screens' left spine: logo tile, vertical genre label, a focusable
/// back control, and a small index marker (e.g. "EP 04" / "FILM 001").
struct DetailSpine: View {
    let genreLabel: String
    let markerTop: String
    let markerBottom: String
    let onBack: () -> Void

    @EnvironmentObject private var theme: Theme

    var body: some View {
        VStack(spacing: 0) {
            Image("AppMark")
                .resizable()
                .scaledToFit()
                .padding(7)
                .frame(width: 54, height: 54)
                .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 6)

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
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(Typography.font(13, .semibold))
                .tracking(2)
                .foregroundStyle(Palette.text(0.4))
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
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
                .frame(width: 780, height: 460)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.text(0.1), lineWidth: 1))
                .overlay(alignment: .topLeading) { cornerTick(topLeading: true) }
                .overlay(alignment: .bottomTrailing) { cornerTick(topLeading: false) }
                .shadow(color: .black.opacity(0.6), radius: 40, y: 24)

            resume().offset(x: -32, y: 40)
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

/// The floating resume card (progress ring + play disc + labels) used by both
/// detail screens.
struct ResumeCard: View {
    let title: String
    let remaining: String
    let progress: Double
    var action: () -> Void = {}

    @EnvironmentObject private var theme: Theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Palette.text(0.14), lineWidth: 6)
                    Circle().trim(from: 0, to: progress)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle().fill(theme.accent).frame(width: 52, height: 52)
                        .overlay(Image(systemName: "play.fill").font(.system(size: 20)).foregroundStyle(.white))
                }
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 4) {
                    Text("RESUME").font(Typography.font(12, .heavy)).tracking(2).foregroundStyle(theme.accent)
                    Text(title).font(Typography.font(22, .heavy)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    Text(remaining).font(Typography.font(15, .medium)).foregroundStyle(Palette.text(0.55))
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(width: 430)
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
                Text(label)
            }
            .font(Typography.font(18, .semibold)).foregroundStyle(Palette.text(0.85))
            .padding(.horizontal, 22).padding(.vertical, 15)
            .background(Palette.text(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Palette.text(0.14), lineWidth: 1))
        }
        .buttonStyle(FocusScaleStyle(scale: 1.06, cornerRadius: 13))
    }
}
