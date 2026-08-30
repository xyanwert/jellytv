import SwiftUI
import JellyTVKit

/// The three that earned their way back into the foot after the seven-tile
/// seek strip was removed: an opinion either way, and the one place you go
/// that is not a jump.
///
/// Only SCENES keeps a word. Four squares does not say "scenes" to anyone,
/// while a heart and a thumbs-down say themselves — so those two shrink to
/// the icon and SCENES stays the wide one. Both opinions are drawn hollow
/// when unset and fill in when set, which is the only way to see at a glance
/// whether you have already said something about this.
struct PlayerFootActions: View {
    let controller: PlayerController
    let accent: Color
    let onInteract: () -> Void
    let onOpenScenes: () -> Void
    @FocusState.Binding var focus: PlayerFocusField?

    private let violet = Color(OKLCH(l: 0.58, c: 0.19, h: 292))

    private enum Size {
        static let height: CGFloat = 128
        static let narrow: CGFloat = 172
        static let wide: CGFloat = 312
        static let gap: CGFloat = 26
        static let radius: CGFloat = 20
    }

    var body: some View {
        HStack(spacing: Size.gap) {
            dislikeButton
            scenesButton
            favoriteButton
        }
    }

    /// Local-only "not interested" — Jellyfin has no dislike endpoint, so this
    /// never leaves the device (see `PlayerController.toggleDislike`).
    private var dislikeButton: some View {
        let active = controller.isDisliked
        return iconButton(
            field: .dislike,
            glyph: active ? "hand.thumbsdown.fill" : "hand.thumbsdown",
            tint: active ? .white : Palette.text(0.82),
            fill: active ? accent.opacity(0.7) : .black.opacity(0.46),
            stroke: active ? accent : Palette.text(0.14),
            label: active ? "Undo not for me" : "Not for me"
        ) {
            controller.toggleDislike()
        }
    }

    /// Real Jellyfin favourite state, round-tripped through the server.
    private var favoriteButton: some View {
        let active = controller.isFavorite
        return iconButton(
            field: .favorite,
            glyph: active ? "heart.fill" : "heart",
            tint: active ? .white : Palette.text(0.82),
            fill: active ? accent : .black.opacity(0.46),
            stroke: active ? accent : Palette.text(0.14),
            label: active ? "Remove from favourites" : "I like it"
        ) {
            Task { await controller.toggleFavorite() }
        }
    }

    private var scenesButton: some View {
        let shape = RoundedRectangle(cornerRadius: Size.radius, style: .continuous)
        return Button {
            onInteract()
            onOpenScenes()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 40, weight: .semibold))
                Text("SCENES")
                    .font(Mono.font(20, .bold))
                    .tracking(1.6)
            }
            .foregroundStyle(.white)
            .frame(width: Size.wide, height: Size.height)
            .background(violet, in: shape)
            .shadow(color: violet.opacity(0.32), radius: 16, y: 8)
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: Size.radius))
        .remoteFocus($focus, equals: .scenes)
    }

    private func iconButton(field: PlayerFocusField, glyph: String, tint: Color,
                            fill: Color, stroke: Color, label: String,
                            action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: Size.radius, style: .continuous)
        return Button {
            onInteract()
            action()
        } label: {
            Image(systemName: glyph)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Size.narrow, height: Size.height)
                .background(fill, in: shape)
                .overlay(shape.stroke(stroke, lineWidth: 1))
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: Size.radius))
        .remoteFocus($focus, equals: field)
        .accessibilityLabel(label)
    }
}
