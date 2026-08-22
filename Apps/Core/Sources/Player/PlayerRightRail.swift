import SwiftUI

/// Favorite (real Jellyfin endpoint) / Next (queue advance, dimmed with no
/// next item) / Dislike (local-only) — vertically stacked on the trailing
/// edge.
struct PlayerRightRail: View {
    let controller: PlayerController
    let accent: Color
    let onInteract: () -> Void
    @FocusState.Binding var focus: PlayerFocusField?

    var body: some View {
        VStack(spacing: 22) {
            favoriteButton
            nextButton
            dislikeButton
        }
    }

    private var favoriteButton: some View {
        let active = controller.isFavorite
        return Button {
            onInteract()
            Task { await controller.toggleFavorite() }
        } label: {
            Image(systemName: active ? "heart.fill" : "heart")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(active ? .white : Palette.text(0.85))
                .frame(width: 78, height: 78)
                .background(active ? accent : Color.black.opacity(0.4), in: Circle())
                .overlay(Circle().stroke(active ? accent : Palette.text(0.16), lineWidth: 1))
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: 39))
        .remoteFocus($focus, equals: .favorite)
    }

    private var nextButton: some View {
        Button {
            onInteract()
            Task { await controller.next() }
        } label: {
            Image(systemName: "forward.end.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 104, height: 104)
                .background(accent, in: Circle())
                .shadow(color: accent.opacity(0.4), radius: 20, y: 8)
                .opacity(controller.hasNext ? 1 : 0.35)
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: 52))
        .remoteFocus($focus, equals: .next)
        .disabled(!controller.hasNext)
    }

    private var dislikeButton: some View {
        let active = controller.isDisliked
        return Button {
            onInteract()
            controller.toggleDislike()
        } label: {
            Image(systemName: active ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(active ? .white : Palette.text(0.7))
                .frame(width: 78, height: 78)
                .background(active ? accent.opacity(0.7) : Color.black.opacity(0.4), in: Circle())
                .overlay(Circle().stroke(active ? accent : Palette.text(0.16), lineWidth: 1))
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: 39))
        .remoteFocus($focus, equals: .dislike)
    }
}
