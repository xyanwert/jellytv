import SwiftUI

/// How a page arrives over the screen that opened it, and what that screen
/// does while the page is up.
///
/// **On tvOS: it does not animate. It is simply there.** That is the whole
/// design, arrived at by removing two attempts in a row.
///
/// The first was a zoom — the page grew out of the poster you selected while
/// the shelf beneath pushed in toward the same point. On a real Apple TV it
/// looked horrible, for a structural reason no amount of retiming addresses:
/// the box draws this app at 3840×2160, a `scaleEffect` on a subtree SwiftUI
/// has not flattened is applied per layer rather than once to a texture, and
/// **two** full-screen hierarchies were under one at the same time —
/// including the movie page's own 90pt poster blur.
///
/// The second was a plain 0.3s dissolve, which is the cheapest thing a
/// compositor does and still was not good enough. That is the useful finding:
/// the cost is not in *which* effect was chosen, it is that any cross-fade
/// has to keep two full-screen 4K layers alive and composited at once, and
/// one of them is a page whose background is a 90pt gaussian blur of a poster
/// scaled to 1.3× the screen. There is no version of "animate the whole
/// frame" this hardware does well.
///
/// So nothing animates. A cut costs one frame and cannot stutter, because
/// there is no second frame for it to stutter between. If motion comes back
/// here it will be motion on something *small* — see the note in
/// `MovieDetailView`.
///
/// On iOS the crossfade the iPad screens always had is untouched: a phone and
/// an iPad composite one screen's worth of pixels, not eight.
extension View {
    /// A page presented over the screen that opened it.
    @ViewBuilder
    func pagePresented() -> some View {
        #if os(tvOS)
        self
        #else
        transition(.opacity)
        #endif
    }

    /// The screen beneath a presented page.
    ///
    /// Two jobs, and the second is now the only one that costs anything. It
    /// drops to 2% rather than 0 because the focus engine will not land on a
    /// view whose alpha is 0.01 or less, and focus is handed back on the
    /// first frame of the page's return, while this is still all but
    /// invisible — at 0 the poster you came from was skipped and focus fell
    /// to the first filter chip. It does not *fade*; it changes in one frame,
    /// under an opaque page, where nobody can see it either way.
    ///
    /// And it marks the subtree **obscured**, which until recently only the
    /// player did. Home's hero pill timer runs a `TimelineView(.animation)` —
    /// 60fps — and its dots row another at 12fps, and both of them kept
    /// running underneath an opened movie page. `HomeView` stops the hero
    /// *rotation* off the same signal, which is what keeps the crumble shader
    /// — by this repo's own measure the most expensive thing in the app —
    /// from firing behind a film nobody can see it through. This is the part
    /// of this file that actually makes opening a page faster, and it stays
    /// however the presentation is styled.
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
    /// tvOS has nothing to time. iOS keeps the iPad's crossfade.
    ///
    /// Kept as a name rather than deleted so the presenting screens still
    /// read as making one deliberate choice in one place — and so putting
    /// motion back is an edit here, not an edit in seven screens.
    static var pagePresentation: Animation? {
        #if os(tvOS)
        nil
        #else
        .easeOut(duration: 0.25)
        #endif
    }
}
