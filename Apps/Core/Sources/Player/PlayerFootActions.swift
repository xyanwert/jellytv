import SwiftUI
import JellyTVKit

/// The foot: the two places you can *go* from here — the scene grid, and the
/// next video — centred under the transport on iPad/tvOS.
///
/// **The opinions left.** Thumbs-down and heart used to flank SCENES; they now
/// sit above the play button (`PlayerOpinionRow`), which leaves this row
/// meaning one thing only: leaving the moment you're in.
///
/// Centred rather than tucked into the bottom-right corner, so the whole
/// chrome stays one column down the middle of the screen — the same reason
/// the transport row holds an empty slot to keep play centred. A corner is
/// the furthest thing on screen from where the eye and the thumb already are.
/// **Phone is the exception** — see `PlayerChrome`'s phone layout, which puts
/// this row in the bottom-right corner on purpose (a one-handed "thumb rail"),
/// and this view's own `phoneRow` below.
///
/// PREV and NEXT flank SCENES rather than sitting side by side — a miss
/// between two adjacent queue buttons lands on the *wrong episode*, which is
/// the one mistake here that costs you your place. With the widest, brightest
/// target in the row between them, a slip lands on the scene grid instead,
/// and the scene grid is harmless.
///
/// Each appears only when the queue actually has something in that direction,
/// so a film shows SCENES alone and the first episode of a run has no PREV.
struct PlayerFootActions: View {
    let controller: PlayerController
    let accent: Color
    let onInteract: () -> Void
    let onOpenScenes: () -> Void
    @FocusState.Binding var focus: PlayerFocusField?

    private let violet = Color(OKLCH(l: 0.58, c: 0.19, h: 292))

    private var isPhone: Bool {
        #if os(iOS)
        DeviceClass.current == .phone
        #else
        false
        #endif
    }

    // iPad-only 25% reduction: this chrome's numbers were tuned for a
    // 10-foot tvOS remote (see `PlayerTransportRow`'s "reads from across the
    // room" reasoning) and just inherited as-is on iPad — fine at arm's
    // length on a TV, oversized on a tablet held in the hand. tvOS keeps the
    // original sizing. Phone runs this chrome in *landscape* on a screen
    // smaller than an iPad's, corner-anchored rather than centred under the
    // transport — its own smaller scale, straight off `Main.dc.html`'s
    // bottom-right pair (96/78pt wide, 64pt tall, 14pt gap).
    #if os(iOS)
    private enum Size {
        static let height: CGFloat = 96
        static let narrow: CGFloat = 129
        static let wide: CGFloat = 234
        static let gap: CGFloat = 19.5
        static let radius: CGFloat = 15
    }
    private enum PhoneSize {
        static let height: CGFloat = 64
        static let scenes: CGFloat = 96
        static let next: CGFloat = 78
        static let gap: CGFloat = 14
        static let radius: CGFloat = 14
    }
    private var height: CGFloat { isPhone ? PhoneSize.height : Size.height }
    private var narrow: CGFloat { Size.narrow }
    private var scenesWidth: CGFloat { isPhone ? PhoneSize.scenes : Size.wide }
    private var nextWidth: CGFloat { isPhone ? PhoneSize.next : Size.narrow }
    private var gap: CGFloat { isPhone ? PhoneSize.gap : Size.gap }
    private var radius: CGFloat { isPhone ? PhoneSize.radius : Size.radius }
    private var glyphSize: CGFloat { isPhone ? 22 : 30 }
    private var captionSize: CGFloat { isPhone ? 11 : 15 }
    private var captionTracking: CGFloat { 1.2 }
    private var labelSpacing: CGFloat { isPhone ? 7 : 9 }
    #else
    private enum Size {
        static let height: CGFloat = 128
        static let narrow: CGFloat = 172
        static let wide: CGFloat = 312
        static let gap: CGFloat = 26
        static let radius: CGFloat = 20
    }
    private let height: CGFloat = Size.height
    private let narrow: CGFloat = Size.narrow
    private let scenesWidth: CGFloat = Size.wide
    private let nextWidth: CGFloat = Size.narrow
    private let gap: CGFloat = Size.gap
    private let radius: CGFloat = Size.radius
    private let glyphSize: CGFloat = 40
    private let captionSize: CGFloat = 20
    private let captionTracking: CGFloat = 1.6
    private let labelSpacing: CGFloat = 12
    #endif

    var body: some View {
        #if os(iOS)
        if isPhone {
            phoneRow
        } else {
            standardRow
        }
        #else
        standardRow
        #endif
    }

    /// **No PREV, no phantom slot.** The task brief cuts PREV outright on
    /// phone (a corner-anchored pair reachable one-handed doesn't have room
    /// for a third target the way the centred iPad/tvOS row does), and
    /// without a centre line to protect there's nothing for a phantom slot
    /// to hold in place — SCENES simply sits nearest the thumb's natural
    /// resting point, NEXT one slot further out toward the corner, so an
    /// undershoot from the corner lands on the harmless scene grid rather
    /// than skipping an episode.
    #if os(iOS)
    private var phoneRow: some View {
        HStack(spacing: gap) {
            scenesButton
            if controller.hasNext {
                nextButton
            }
        }
    }
    #endif

    private var standardRow: some View {
        // Hidden rather than disabled at the ends of a queue: a permanently
        // dead button on a chrome this sparse reads as broken. But SCENES
        // still has to land in the same spot either way — a phantom slot
        // the width of the missing neighbour holds its place, the same
        // trick `PlayerTransportRow` uses for the deleted start-over
        // circle. Without it, the first episode of a run (no PREV) or the
        // last item in a queue (no NEXT) visibly shifts SCENES off the
        // centre line the rest of this chrome is built around.
        HStack(spacing: gap) {
            if controller.hasPrevious {
                previousButton
            } else {
                Color.clear.frame(width: narrow, height: 1)
            }
            scenesButton
            if controller.hasNext {
                nextButton
            } else {
                Color.clear.frame(width: narrow, height: 1)
            }
        }
    }

    private var scenesButton: some View {
        tile(field: .scenes, glyph: "square.grid.2x2.fill", caption: "SCENES",
             width: scenesWidth, fill: violet, glow: violet) {
            onOpenScenes()
        }
    }

    /// Both words *and* a glyph, unlike everything else here — ⏮/⏭ next to a
    /// row of seek circles is exactly the ambiguity this chrome exists to
    /// remove.
    ///
    /// Both route through `PlayerController`, which coalesces a mashed queue
    /// change into one advance (250ms leading edge, plus a re-entrancy guard)
    /// — pressing NEXT four times must not skip four episodes.
    private var previousButton: some View {
        tile(field: .previous, glyph: "backward.end.fill", caption: "PREV",
             width: narrow, fill: .black.opacity(0.46), glow: nil,
             stroke: Palette.text(0.16)) {
            Task { await controller.previous() }
        }
    }

    private var nextButton: some View {
        tile(field: .next, glyph: "forward.end.fill", caption: "NEXT",
             width: nextWidth, fill: .black.opacity(0.46), glow: nil,
             stroke: Palette.text(0.16)) {
            Task { await controller.next() }
        }
    }

    private func tile(field: PlayerFocusField, glyph: String, caption: String,
                      width: CGFloat, fill: Color, glow: Color?,
                      stroke: Color = .clear,
                      action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return Button {
            onInteract()
            action()
        } label: {
            VStack(spacing: labelSpacing) {
                Image(systemName: glyph)
                    .font(.system(size: glyphSize, weight: .semibold))
                Text(caption)
                    .font(Mono.font(captionSize, .bold))
                    .tracking(captionTracking)
            }
            .foregroundStyle(.white)
            .frame(width: width, height: height)
            .background(fill, in: shape)
            .overlay(shape.stroke(stroke, lineWidth: 1))
            .shadow(color: (glow ?? .black).opacity(glow == nil ? 0.35 : 0.32),
                    radius: 16, y: 8)
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: radius))
        .remoteFocus($focus, equals: field)
    }
}
