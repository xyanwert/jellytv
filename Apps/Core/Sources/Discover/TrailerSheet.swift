import SwiftUI
import JellyTVKit
#if os(iOS)
import WebKit
#endif

/// Opening a trailer, which is a **link** and not a stream.
///
/// This deliberately does not play video itself. Resolving a YouTube page into something
/// `AVPlayer` could open was built and then removed: it meant yt-dlp, a dependency that
/// breaks whenever YouTube changes something, for a video that is somebody else's either
/// way. TMDB gives us the link for free, so the app just opens it.
///
/// The two platforms differ because their capabilities differ, not by preference:
///
/// * **iOS** embeds YouTube's own player in a `WKWebView`, over the one-sheet.
/// * **tvOS** has no `WKWebView` and no browser. The only route is the YouTube tvOS app,
///   so `TrailerAvailability.canOpen` is asked *before* the button is drawn and the
///   control simply does not exist when nothing can answer it — the same rule the player
///   chrome follows about unlit glass.
enum TrailerAvailability {

    /// Can this device open this trailer at all? Asked before drawing the control.
    static func canOpen(_ trailer: YsojAPI.Trailer) -> Bool {
        #if os(tvOS)
        // No browser here: it is the YouTube app or nothing.
        guard let appURL = trailer.appURL else { return false }
        return UIApplication.shared.canOpenURL(appURL)
        #else
        return trailer.embedURL != nil || trailer.pageURL != nil
        #endif
    }

    /// Hand it to whoever claimed the scheme. tvOS's entire implementation.
    @MainActor
    static func open(_ trailer: YsojAPI.Trailer) {
        #if os(tvOS)
        guard let url = trailer.appURL else { return }
        UIApplication.shared.open(url)
        #else
        guard let url = trailer.pageURL else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

#if os(iOS)
/// The trailer, embedded over the one-sheet.
///
/// A same-`ZStack` overlay rather than a `.sheet`, matching the person sheet and the
/// download plan: a trailer is something that happens *on* this page, and a card sliding
/// up from the bottom would say it was a different screen.
struct TrailerSheet: View {
    let trailer: YsojAPI.Trailer
    let accent: Color
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 14) {
                header
                stage
            }
            .padding(padding)
            .frame(maxWidth: maxWidth)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(trailer.name.isEmpty ? "Trailer" : trailer.name)
                .font(Typography.font(titleSize, .bold))
                .foregroundStyle(Palette.text(0.9))
                .lineLimit(1)
            Spacer(minLength: 0)
            // An escape hatch to the real thing: the embed occasionally refuses to play
            // a video whose owner disabled embedding, and a dead rectangle with no way
            // out is worse than a link.
            Button {
                TrailerAvailability.open(trailer)
                onClose()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: closeGlyph, weight: .semibold))
                    .foregroundStyle(Palette.text(0.7))
                    .frame(width: closeSize, height: closeSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open in YouTube")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: closeGlyph, weight: .bold))
                    .foregroundStyle(Palette.text(0.85))
                    .frame(width: closeSize, height: closeSize)
                    .background(Circle().fill(Palette.text(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close trailer")
        }
    }

    @ViewBuilder
    private var stage: some View {
        if let embed = trailer.embedURL {
            WebVideo(url: embed)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Palette.text(0.12), lineWidth: 1)
                )
        } else {
            Button {
                TrailerAvailability.open(trailer)
                onClose()
            } label: {
                Label("Open in YouTube", systemImage: "arrow.up.forward.app")
                    .font(Typography.font(titleSize, .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 26).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(accent))
            }
            .buttonStyle(.plain)
        }
    }

    private var isPhone: Bool { DeviceClass.current == .phone }
    private var maxWidth: CGFloat { isPhone ? .infinity : 900 }
    private var padding: CGFloat { isPhone ? 16 : 28 }
    private var titleSize: CGFloat { isPhone ? 16 : 20 }
    private var closeSize: CGFloat { isPhone ? 34 : 38 }
    private var closeGlyph: CGFloat { isPhone ? 13 : 15 }
}

/// A `WKWebView` holding YouTube's embedded player.
///
/// Both configuration flags are load-bearing for `autoplay=1`: without inline playback
/// **and** without clearing the user-action requirement, the viewer gets a poster frame
/// and has to press play a second time inside a video they already asked for.
private struct WebVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard view.url != url else { return }
        view.load(URLRequest(url: url))
    }
}
#endif
