import SwiftUI

/// The tvOS way from a poster to its page: the page **zooms out of the thing
/// you selected** and the screen beneath pushes in toward that same spot and
/// fades — a camera move into the poster — then reverses on Menu, the page
/// shrinking back into its poster as the shelf returns. The same mechanism
/// takes the movie page to a person's sheet (out of the coin) and back.
///
/// Three parts, all compositor work (scale and opacity, no shaders):
///
/// - `zoomOrigin(_:)` on any focusable card marks *where* a zoom would start
///   while the card is focused (an anchor preference).
/// - `trackZoomOrigin(_:)` on the screen that presents reads that mark into a
///   `UnitPoint` of its own frame, and stops the mark travelling further up —
///   a coin focused inside the movie page must not become the library's idea
///   of where the page came from.
/// - `zoomPresented(from:)` on the presented page and `zoomedBehind(_:origin:)`
///   on the screen beneath do the moves, driven by the same `.animation(
///   .zoomPresentation, value:)` the presenting screen already carries.
///
/// On iOS every one of these is a no-op or the plain crossfade the iPad
/// screens had, so the shared call sites read the same on both platforms.
extension View {
    /// While `active`, this view is where a zoom presentation starts.
    @ViewBuilder
    func zoomOrigin(_ active: Bool) -> some View {
        #if os(tvOS)
        anchorPreference(key: ZoomOriginKey.self, value: .bounds) { active ? $0 : nil }
        #else
        self
        #endif
    }

    /// Reads the focused `zoomOrigin` beneath this view into `origin`, as a
    /// point in this view's own frame. Keeps the last known point when nothing
    /// is marked, so a Select that lands right after focus moved still has
    /// somewhere to zoom from.
    @ViewBuilder
    func trackZoomOrigin(_ origin: Binding<UnitPoint>) -> some View {
        #if os(tvOS)
        overlayPreferenceValue(ZoomOriginKey.self) { anchor in
            GeometryReader { geo in
                Color.clear.preference(key: ZoomOriginPointKey.self, value: anchor.map { anchor -> UnitPoint in
                    let rect = geo[anchor]
                    guard geo.size.width > 0, geo.size.height > 0 else { return .center }
                    return UnitPoint(x: min(max(rect.midX / geo.size.width, 0), 1),
                                     y: min(max(rect.midY / geo.size.height, 0), 1))
                })
            }
            .allowsHitTesting(false)
        }
        .onPreferenceChange(ZoomOriginPointKey.self) { point in
            if let point { origin.wrappedValue = point }
        }
        .transformPreference(ZoomOriginPointKey.self) { $0 = nil }
        .transformPreference(ZoomOriginKey.self) { $0 = nil }
        #else
        self
        #endif
    }

    /// A page presented by zoom: it grows out of `origin` and, on dismissal,
    /// settles back toward it.
    ///
    /// Subtle on purpose — 6% in, 3% out. A first cut flew the page in from
    /// 30% of its size on a spring, and on a TV that read as lurching, not
    /// smooth: a big scale range moves every pixel of a 4K frame a long way
    /// per frame, and the spring's settle added a wobble on top. What makes
    /// it feel like a zoom is the anchor, not the distance.
    @ViewBuilder
    func zoomPresented(from origin: UnitPoint) -> some View {
        #if os(tvOS)
        transition(.asymmetric(
            insertion: .scale(scale: 0.94, anchor: origin).combined(with: .opacity),
            removal: .scale(scale: 0.97, anchor: origin).combined(with: .opacity)))
        #else
        transition(.opacity)
        #endif
    }

    /// The screen beneath a zoom presentation: pushes in toward `origin` and
    /// fades out while `presented`, and comes back the same way.
    ///
    /// It fades to 2%, not 0: the focus engine will not land on a view whose
    /// alpha is 0.01 or less, and focus is handed back to this screen at the
    /// first frame of its return, while it is still all but invisible — at 0
    /// the poster you came from was skipped and focus fell to the first
    /// filter chip. Under an opaque page 2% cannot be seen.
    @ViewBuilder
    func zoomedBehind(_ presented: Bool, origin: UnitPoint) -> some View {
        #if os(tvOS)
        scaleEffect(presented ? 1.04 : 1, anchor: origin)
            .opacity(presented ? 0.02 : 1)
        #else
        self
        #endif
    }
}

extension View {
    /// A page's content arriving in order: fades in and rises `rise` points,
    /// `delay` seconds after `shown` flips, so the folds of a page land one
    /// after another instead of all at once. A few points, not a leap — the
    /// page is already moving. tvOS only — the iPad's pages were built
    /// without it and stay that way.
    @ViewBuilder
    func entrance(_ shown: Bool, delay: Double, rise: CGFloat = 14) -> some View {
        #if os(tvOS)
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : rise)
            .animation(.easeOut(duration: 0.5).delay(delay), value: shown)
        #else
        self
        #endif
    }
}

extension Animation {
    /// The zoom's timing: one even ease on tvOS — no spring, nothing to
    /// settle — and the iPad's plain crossfade elsewhere.
    static var zoomPresentation: Animation {
        #if os(tvOS)
        .easeInOut(duration: 0.45)
        #else
        .easeOut(duration: 0.25)
        #endif
    }
}

#if os(tvOS)
private struct ZoomOriginKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() { value = next }
    }
}

private struct ZoomOriginPointKey: PreferenceKey {
    static let defaultValue: UnitPoint? = nil
    static func reduce(value: inout UnitPoint?, nextValue: () -> UnitPoint?) {
        if let next = nextValue() { value = next }
    }
}
#endif
