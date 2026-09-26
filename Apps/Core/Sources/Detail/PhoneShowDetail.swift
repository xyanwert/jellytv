import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import JellyTVKit

#if os(iOS)
/// The Show screen's three phone tabs (`Detail.dc.html`) — EPISODES/DETAILS/
/// CAST replace the iPad drawer's always-visible episode list plus the
/// tvOS/iPad title block's always-visible spec sheet and cast row. A phone
/// column doesn't have room for all three sections at once the way a wide
/// drawer or a tall tvOS canvas does, so they fold into tabs instead.
enum PhoneShowTab: CaseIterable {
    case episodes, details, cast

    var label: String {
        switch self {
        case .episodes: return "EPISODES"
        case .details: return "DETAILS"
        case .cast: return "CAST"
        }
    }
}

/// The Show screen's phone key art: a **contained block that ends** at a
/// fixed height, not a full-bleed banner the whole page lives inside (that's
/// `ShowFullBackdrop`, iPad's own treatment) — see `Detail.dc.html`. Fades
/// into the page's own flat background at the bottom rather than running
/// the art the full height of the screen, and carries its own close button
/// (top-right, clear of the thumb's reading path and of the system's
/// leading-edge swipe-back gesture — deliberately not `DetailSpine`'s
/// leading-edge back arrow, which sits exactly where that gesture lives).
struct PhoneShowKeyArt: View {
    let image: String?
    let artwork: Artwork
    let onClose: () -> Void
    /// Poster Mode: the title printed in scanlines across the art, with the
    /// art's subject cut out and laid back over it in front of the title.
    var posterTitle: String? = nil

    @EnvironmentObject private var theme: Theme
    @State private var cutout: UIImage?

    static let height: CGFloat = 296

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                art
                    .frame(width: geo.size.width * 1.3, height: Self.height * 1.3)
                    .frame(width: geo.size.width, height: Self.height)
                    .clipped()
                    .overlay { topScrim }
                    // Poster Mode draws *over* the art's fixed frame, never
                    // beside it in a stack: the scanlined title is far wider
                    // than the phone (a long title is ~2000pt), and as a stack
                    // sibling it widened the stack and slid the picture off
                    // the left edge — the key art showed as a flat teal block
                    // (verified on The Marvelous Mrs. Maisel).
                    .overlay(alignment: .bottomLeading) {
                        if theme.isPoster, let posterTitle {
                            posterDressing(title: posterTitle, width: geo.size.width)
                        }
                    }
                    .clipped()
                    .mask(bottomFade)
            }
            .frame(height: Self.height)
            .task(id: image) {
                guard theme.isPoster, posterTitle != nil, PortraitCutoutCache.isSupported,
                      let image, image.hasPrefix("http") else { return }
                cutout = await PortraitCutoutCache.shared.cutout(for: image)
            }

            closeButton
                .padding(.top, 56)
                .padding(.trailing, 20)
        }
        .frame(height: Self.height)
        .ignoresSafeArea(edges: .top)
    }

    private func posterDressing(title: String, width: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Palette.posterTeal.opacity(0.3).blendMode(.color)
            PosterPaper(dotColor: .white.opacity(0.08), spacing: 16, radius: 1)
            PosterScanlineTitle(text: title, size: 120)
                .padding(.leading, 12)
                .padding(.bottom, 64)
                .frame(width: width, height: Self.height, alignment: .bottomLeading)
                .clipped()
            // The subject, at the art's exact framing (the cut-out keeps the
            // source's size), in front of its title.
            if let cutout {
                Image(uiImage: cutout)
                    .resizable().scaledToFill()
                    .frame(width: width * 1.3, height: Self.height * 1.3)
                    .frame(width: width, height: Self.height)
                    .clipped()
                    .shadow(color: .black.opacity(0.5), radius: 16, x: -6, y: 6)
            }
            PosterAccentStripes(angle: .degrees(58), length: 320, scale: 0.5)
                .frame(width: width, height: Self.height, alignment: .topTrailing)
                .offset(x: 110, y: -30)
        }
        .frame(width: width, height: Self.height)
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

    private var topScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.34), location: 0.0),
                .init(color: .clear, location: 0.26),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Fades to fully transparent well before the block's own bottom edge,
    /// so the page's flat background (not a hard image edge) is what the
    /// identity block below actually sits on.
    private var bottomFade: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white, location: 0.5),
                .init(color: .white.opacity(0.6), location: 0.72),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.5), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}
#endif
