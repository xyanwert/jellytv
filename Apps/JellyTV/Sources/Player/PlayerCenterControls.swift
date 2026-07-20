import SwiftUI

/// Repeat-one toggle + the big play/pause circle. The circle swaps to a
/// spinner while `controller.isLoading` — the chrome's only loading
/// indicator, so a slow queue-advance doesn't leave the user staring at a
/// blank canvas wondering if anything is happening.
struct PlayerCenterControls: View {
    let controller: PlayerController
    let accent: Color
    let onInteract: () -> Void
    @FocusState.Binding var focus: PlayerFocusField?

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 26) {
            repeatButton
            playButton
        }
    }

    private var repeatButton: some View {
        let active = controller.repeatOne
        return Button {
            onInteract()
            controller.toggleRepeatOne()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "repeat")
                    .font(.system(size: 34, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if active {
                    Text("1")
                        .font(Mono.font(15, .bold))
                        .padding(6)
                }
            }
            .foregroundStyle(active ? Color(hex: "#FFD9DC") : Palette.text(0.75))
            .frame(width: 96, height: 96)
            .background(active ? accent.opacity(0.15) : Color.black.opacity(0.4), in: Circle())
            .overlay(Circle().stroke(active ? accent.opacity(0.44) : Palette.text(0.16), lineWidth: 1))
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: 48))
        .focused($focus, equals: .repeatOne)
    }

    private var playButton: some View {
        Button {
            onInteract()
            controller.togglePlay()
        } label: {
            ZStack {
                Circle().fill(accent)
                if controller.isLoading {
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: controller.isPlaying ? 0 : 3)
                }
            }
            .frame(width: 150, height: 150)
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .overlay {
                Circle()
                    .stroke(accent.opacity(0.5), lineWidth: 3)
                    .scaleEffect(pulse ? 1.35 : 1)
                    .opacity(pulse ? 0 : 1)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(FocusScaleStyle(cornerRadius: 75))
        .focused($focus, equals: .playPause)
        .onAppear {
            withAnimation(.easeOut(duration: 2.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
