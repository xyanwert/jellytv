import SwiftUI
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

    static let height: CGFloat = 296

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                art
                    .frame(width: geo.size.width * 1.3, height: Self.height * 1.3)
                    .frame(width: geo.size.width, height: Self.height)
                    .clipped()
                    .overlay { topScrim }
                    .mask(bottomFade)
            }
            .frame(height: Self.height)

            closeButton
                .padding(.top, 56)
                .padding(.trailing, 20)
        }
        .frame(height: Self.height)
        .ignoresSafeArea(edges: .top)
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
