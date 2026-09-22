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

// MARK: - The one thing that does move

/// **The press lands on the card, and then the page is there.**
///
/// With the page itself cutting in (above), pressing a poster produced no
/// acknowledgement of any kind: the shelf was simply replaced between one
/// frame and the next. A cut with nothing confirming the press reads as a
/// glitch — as though the remote had skipped a beat and something else
/// happened. A cut *immediately after the thing you pressed visibly reacted*
/// reads as instant, which is what it is.
///
/// So the card dips and brightens for `beat`, and then the page replaces it.
/// This is the whole of the motion, and it is deliberately on the smallest
/// thing on screen: the rule the zoom and the dissolve both taught is that
/// **the area being animated is what costs, not the effect**. A poster is
/// ~200×300pt, well under 1% of a 3840×2160 frame, and `CardFocusStyle`
/// already scales one 1.18× on every focus move at 60fps with nothing to show
/// for it on the profiler. Anything proposed here in future should be able to
/// answer "how many pixels change per frame" with a number this small.
///
/// The dip is never released on screen — the page arrives on top of it. That
/// is the right reading rather than a shortcut: you push the card in and it
/// becomes the page, so the card is the door rather than a button that
/// happens to sit next to one.
///
/// iOS does none of this. A finger already gets `CardFocusStyle`'s own press
/// dip under it, and the iPad keeps its crossfade, so there is nothing
/// missing to stand in for.
enum PageLaunch {
    /// How long the acknowledgement runs before the page replaces it.
    /// Comfortably under the ~150ms at which an added delay starts to read as
    /// lag, and long enough that the dip is seen rather than inferred.
    static let beat: Duration = .milliseconds(130)

    /// Runs `action` once the card's beat has played. Immediate on iOS.
    ///
    /// Call it *with* bumping the card's own tick — the two halves are
    /// deliberately separate, because the visual belongs to the card and the
    /// timing belongs to whatever the press opens.
    @MainActor
    static func then(_ action: @escaping () -> Void) {
        #if os(tvOS)
        Task { @MainActor in
            try? await Task.sleep(for: beat)
            action()
        }
        #else
        action()
        #endif
    }
}

extension View {
    /// Plays `PageLaunch`'s beat each time `tick` changes. Put it on the
    /// button, outside its `buttonStyle`, so the dip multiplies with the
    /// focus scale already there rather than replacing it.
    @ViewBuilder
    func pageLaunchBeat(_ tick: Int) -> some View {
        #if os(tvOS)
        modifier(PageLaunchBeat(tick: tick))
        #else
        self
        #endif
    }
}

#if os(tvOS)
private struct PageLaunchBeat: ViewModifier {
    let tick: Int
    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.94 : 1)
            // A dip alone is ~12×18pt on a poster, which is real motion but
            // small from across a room; the lift is what makes it land. Kept
            // well under a flash — this is a poster, and washing the art out
            // to acknowledge a press would be a strange trade.
            .brightness(pressed ? 0.10 : 0)
            .animation(.easeOut(duration: 0.06), value: pressed)
            .onChange(of: tick) { _, _ in
                pressed = true
                // Released after the page has had time to cover it, so a
                // press that opens nothing (a failed fetch, a guard that
                // returns early) still returns the card to rest instead of
                // leaving it pushed in.
                Task { @MainActor in
                    try? await Task.sleep(for: PageLaunch.beat + .milliseconds(60))
                    pressed = false
                }
            }
    }
}
#endif
