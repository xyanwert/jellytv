import SwiftUI

/// The rail's Jellyfin-connectivity indicator, pinned to the app-mark tile's
/// top-left corner. Connected renders a green glowing dot with a looping pulse;
/// disconnected renders a static, desaturated dot of the same geometry.
struct StatusDot: View {
    let isConnected: Bool

    @State private var pulsing = false

    private static let liveColor = Color(hex: "#58D399")

    var body: some View {
        Circle()
            .fill(isConnected ? Self.liveColor : Palette.text(0.3))
            .frame(width: 13, height: 13)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: isConnected ? Self.liveColor.opacity(pulsing ? 0.95 : 0.55) : .clear,
                    radius: isConnected ? (pulsing ? 9 : 4) : 0)
            .onAppear {
                guard isConnected else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
