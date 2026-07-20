import SwiftUI

/// Retry / Skip (queue has a next item) / Close, over a translucent card —
/// shown when `PlayerEngine.phase` is `.failed`. Retry re-resolves via a
/// fresh PlaybackInfo POST and clears the engine's failure streak; Skip
/// advances the queue even past the 3-strike auto-skip cap; Close dismisses.
struct PlayerFailureOverlay: View {
    let message: String
    let hasNext: Bool
    let accent: Color
    let onRetry: () -> Void
    let onSkip: () -> Void
    let onClose: () -> Void
    @FocusState.Binding var focus: PlayerFocusField?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Circle().fill(Color(hex: "#E8544A")).frame(width: 10, height: 10)
                Text("PLAYBACK FAILED")
                    .font(Mono.font(16, .bold))
                    .tracking(2)
                    .foregroundStyle(Color(hex: "#E8544A"))
            }
            Text(message)
                .font(Typography.font(20, .medium))
                .foregroundStyle(Palette.text(0.85))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                pillButton("Retry", bg: accent, action: onRetry)
                    .focused($focus, equals: .failureRetry)
                if hasNext {
                    pillButton("Skip", bg: Palette.text(0.14), action: onSkip)
                        .focused($focus, equals: .failureSkip)
                }
                pillButton("Close", bg: Palette.text(0.14), action: onClose)
                    .focused($focus, equals: .failureClose)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Palette.text(0.12), lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pillButton(_ title: String, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.font(20, .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(bg, in: Capsule())
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: 24))
    }
}
