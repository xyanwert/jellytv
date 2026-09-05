import SwiftUI
import JellyTVKit

/// The two opinions — thumbs-down and heart — sitting directly above the play
/// button.
///
/// **They moved here out of the foot.** The foot is where you go to *do*
/// something else (open scenes, move to the next video); saying whether you
/// liked this is a different kind of act, and having it share a row with those
/// meant a mis-aimed press for SCENES landed on a permanent opinion instead.
/// Above the play button they're still dead centre — the one place on this
/// chrome that needs no aiming — but they're a size down from every transport
/// circle, which is the visual statement that they're not part of the
/// transport.
///
/// Both are drawn hollow when unset and fill in when set. That's the only way
/// to see at a glance whether you've already said something about this item,
/// and it matters more here than it did in the foot: these are the two
/// controls a stray press can silently change.
struct PlayerOpinionRow: View {
    let controller: PlayerController
    let accent: Color
    let onInteract: () -> Void
    @FocusState.Binding var focus: PlayerFocusField?

    // iPad-only 25% reduction: this chrome's numbers were tuned for a
    // 10-foot tvOS remote (see `PlayerTransportRow`'s "reads from across the
    // room" reasoning) and just inherited as-is on iPad — fine at arm's
    // length on a TV, oversized on a tablet held in the hand. tvOS keeps the
    // original sizing.
    #if os(iOS)
    // Phone runs this chrome in *landscape* on a screen much smaller than an
    // iPad's — see `PlayerTransportRow`'s identical note. Sized to
    // `Main.dc.html`'s bottom-left pair: 52pt circles, 14pt gap.
    private enum Size {
        static let diameter: CGFloat = DeviceClass.current == .phone ? 52 : 81
        static let gap: CGFloat = DeviceClass.current == .phone ? 14 : 22.5
    }
    private static let glyphSize: CGFloat = DeviceClass.current == .phone ? 21 : 31.5
    #else
    private enum Size {
        /// Smaller than the smallest transport circle (152pt) and still far
        /// past the 88pt floor this chrome holds itself to.
        static let diameter: CGFloat = 108
        static let gap: CGFloat = 30
    }
    private static let glyphSize: CGFloat = 42
    #endif

    var body: some View {
        HStack(spacing: Size.gap) {
            dislikeButton
            favoriteButton
        }
    }

    /// Local-only "not interested" — Jellyfin has no dislike endpoint, so this
    /// never leaves the device (see `PlayerController.toggleDislike`).
    private var dislikeButton: some View {
        let active = controller.isDisliked
        return circle(
            field: .dislike,
            glyph: active ? "hand.thumbsdown.fill" : "hand.thumbsdown",
            tint: active ? .white : Palette.text(0.82),
            fill: active ? accent.opacity(0.7) : .black.opacity(0.46),
            stroke: active ? accent : Palette.text(0.16),
            label: active ? "Undo not for me" : "Not for me"
        ) {
            controller.toggleDislike()
        }
    }

    /// Real Jellyfin favourite state, round-tripped through the server.
    private var favoriteButton: some View {
        let active = controller.isFavorite
        return circle(
            field: .favorite,
            glyph: active ? "heart.fill" : "heart",
            tint: active ? .white : Palette.text(0.82),
            fill: active ? accent : .black.opacity(0.46),
            stroke: active ? accent : Palette.text(0.16),
            label: active ? "Remove from favourites" : "I like it"
        ) {
            Task { await controller.toggleFavorite() }
        }
    }

    private func circle(field: PlayerFocusField, glyph: String, tint: Color,
                        fill: Color, stroke: Color, label: String,
                        action: @escaping () -> Void) -> some View {
        Button {
            onInteract()
            action()
        } label: {
            Image(systemName: glyph)
                .font(.system(size: Self.glyphSize, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Size.diameter, height: Size.diameter)
                .background(fill, in: Circle())
                .overlay(Circle().stroke(stroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.38), radius: 18, y: 8)
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: Size.diameter / 2))
        .remoteFocus($focus, equals: field)
        .accessibilityLabel(label)
    }
}
