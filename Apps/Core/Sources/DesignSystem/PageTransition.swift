import SwiftUI

/// How a page arrives over the screen that opened it, and what that screen
/// does while the page is up.
///
/// **This was a zoom, and the zoom is gone.** A poster's page grew out of the
/// poster while the shelf beneath pushed in toward the same point — two
/// full-screen SwiftUI hierarchies under an animating `scaleEffect` at once,
/// for 0.45s. It read well enough on the simulator, which is exactly what
/// this repo already knows the simulator cannot judge (see CLAUDE.md: a
/// recording of it drew a new frame every 150–180ms whatever the code did).
/// On a real Apple TV the verdict was that it looked horrible, and the reason
/// is structural rather than a matter of tuning: an Apple TV 4K draws this app
/// at 3840×2160, a `scaleEffect` on a subtree SwiftUI has not flattened is
/// applied per layer rather than once to a texture, and the movie page's own
/// two heavy layers — a 90pt blur of the poster at 1.3× the screen, and a
/// full-bleed backdrop — were being re-composited every frame of it. There is
/// no cheap version of that move. The zoom's own doc comment had already
/// walked one step down this road ("what makes it feel like a zoom is the
/// anchor, not the distance", after a 30% spring was cut to 6%); this is the
/// last step.
///
/// What is left is a dissolve: one alpha blend per layer, which is the
/// cheapest thing a compositor does, over 0.3s. Everything the zoom needed to
/// know about *where* a page came from went with it — `zoomOrigin`, an
/// `anchorPreference` that recomputed on every focus change across a grid of
/// forty posters, and `trackZoomOrigin`, the `GeometryReader` overlay that
/// read it. Nothing replaced them, because a dissolve has no origin.
///
/// The staggered `entrance(_:delay:)` that faded and raised each fold of the
/// movie page in turn went at the same time and for the same reason: five
/// overlapping animations on a page that was itself being scaled. The page
/// simply arrives now.
///
/// On iOS all of this is the plain crossfade the iPad screens always had.
extension View {
    /// A page presented over the screen that opened it.
    func pagePresented() -> some View {
        transition(.opacity)
    }

    /// The screen beneath a presented page.
    ///
    /// Two jobs, and the second is the one that matters most on a TV. It
    /// fades to 2% rather than 0 because the focus engine will not land on a
    /// view whose alpha is 0.01 or less, and focus is handed back on the
    /// first frame of the page's return, while this is still all but
    /// invisible — at 0 the poster you came from was skipped and focus fell
    /// to the first filter chip.
    ///
    /// And it marks the subtree **obscured**, which until now only the player
    /// did. Home's hero pill timer runs a `TimelineView(.animation)` — 60fps
    /// — and its dots row another at 12fps, and both of them kept running
    /// underneath an opened movie page, on top of everything that page was
    /// doing. `HomeView` stops the hero *rotation* off the same signal, which
    /// is what keeps the crumble shader — by this repo's own measure the most
    /// expensive thing in the app — from firing behind a film nobody can see
    /// it through.
    @ViewBuilder
    func pageBehind(_ presented: Bool) -> some View {
        #if os(tvOS)
        opacity(presented ? 0.02 : 1)
            .environment(\.isObscured, presented)
        #else
        self
        #endif
    }
}

extension Animation {
    /// One even ease, short enough that nothing has time to look laboured.
    static var pagePresentation: Animation {
        #if os(tvOS)
        .easeInOut(duration: 0.3)
        #else
        .easeOut(duration: 0.25)
        #endif
    }
}
