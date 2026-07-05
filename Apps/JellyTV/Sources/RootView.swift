import SwiftUI
import JellyTVKit

/// Branded placeholder shown until the Jellyfin browsing/playback features land.
struct RootView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.10, blue: 0.29),
                    Color(red: 0.43, green: 0.23, blue: 0.82),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Text(JellyTVKit.displayName)
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Client for Jellyfin — v\(JellyTVKit.version)")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

#Preview {
    RootView()
}
